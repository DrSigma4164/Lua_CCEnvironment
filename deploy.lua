local instrList_Name = "Instructions.txt"
local localSettingsList_Name = "settings.txt"
local deploySettingsFileName = "deploysettings.txt"
local deployFailedMarkerName = "deployfailed.marker"
local prefix = "https://raw.githubusercontent.com/"
local apiPrefix = "https://api.github.com/repos/"
local defaultFolderName = "CCEnv/"

local expect = require "cc.expect"

--TODO: Нотатка: local modem = peripheral.find("modem") or error("No modem attached", 0)

-- Функція завантаження даних
local function _GET(path) --> content, nil | nil, isError(string) -- Читає дані з GitHub, максимум 3 спроби при мережевій помилці
	local isError
	for i = 1, 3 do
		local handle = http.get(prefix .. path)
		if (handle ~= nil) and (handle.getResponseCode() == 200) then
			local content = handle.readAll()
			handle.close()
			return content, nil
		end
		isError = '"' .. path .. '" not responding'
		print(isError)
	end
	return nil, isError
end

--Функція зчитування даних з клавіатури за n секунд, або повернення значення за замовчуванням.
--sEnteredChar — опційно: якщо символ уже відомий заздалегідь (наприклад, натиснутий під час прокрутки списку вище),
--одразу читаємо його як введений, не чекаючи нової події "char"
local function fReadData(defaultValue, nTimerTime, sEnteredChar) --> content(string) | nil, nil | isError(string)
	expect.expect(1, defaultValue, "string", "nil")
	expect.expect(2, nTimerTime, "number", "nil")
	expect.expect(3, sEnteredChar, "string", "nil")

	if ((nTimerTime == nil) or (nTimerTime < 0)) then nTimerTime = 3 end

	local nTimerId = os.startTimer(nTimerTime)--запускаємо таймер на 3 секунди і зберігаємо його ID
	while true do
		local sEventName, eventArgs
		if sEnteredChar == nil then sEventName, eventArgs = os.pullEvent() end -- Якщо символ уже відомий — не чекаємо нову подію, одразу йдемо в гілку читання нижче
		if ((sEventName == "timer") and (eventArgs == nTimerId) and (defaultValue ~= nil)) then -- Якщо таймер вже вийшов і є значення за замовчуванням
			return defaultValue
		elseif ((sEventName == "char") and (eventArgs == ' ') and (defaultValue ~= nil)) then -- Або ми натиснули на пробіл і є значення за замовчуванням
			return defaultValue
		elseif (sEnteredChar ~= nil) or ((sEventName == "char") and (eventArgs ~= ' ')) then -- Або вже маємо символ заздалегідь, або ввели щось інше зараз
			write(">")
			return read(nil, nil, nil, sEnteredChar or eventArgs)
		end
	end
	return nil, "EoF"
end

--Функція
local function fWaitOrSkip(nTimerTime, aTimerAnsw, aSkipAnsw, fEventCher) -->  content(Any) | nil, nil | isError(string)
	expect.expect(1, nTimerTime, "number")
	--expect.expect(2, aTimerAnsw, "string", "nil")
	--expect.expect(3, aSkipAnsw, "string", "nil")
	expect.expect(4, fEventCher, "function", "nil")

	if (nTimerTime < 0) then nTimerTime = 1.5 end
	if (fEventCher == nil) then fEventCher = function() return false end end

	local nTimerId = os.startTimer(nTimerTime)--запускаємо таймер і зберігаємо його ID
	while true do
		local tEventReturn = {os.pullEvent()}
		if ((tEventReturn[1] == "timer") and (tEventReturn[2] == nTimerId)) then -- Якщо таймер вже вийшов
			return aTimerAnsw
		elseif fEventCher(tEventReturn) then -- Або ми отримали відповідь
			return aSkipAnsw
		end
	end
end

-- Функція десеріалізації даних з файлу
local function unserialFromFile(pathToFile) --> content(Any) | nil, nil | isError(string) -- Читає дані з файлу і проводить десеріалізацію
    if fs.exists(pathToFile) == true then -- Якщо файл існує, то пробуємо читати дані з нього
		local fin = fs.open(pathToFile, "r") -- Пробуємо відкрити локальний файл
		if fin ~= nil then -- Якщо файл відкрився
			local unserializeObj = textutils.unserialize(fin.readAll()) -- Пробуємо читати з файлу
			fin.close()
			if unserializeObj ~= nil then
				return unserializeObj, nil
			else return nil, 'Cannot unserialize data into object ("'..pathToFile..'")' end -- Помилка: не змогли десеріалізувати дані
		else return nil, 'Cannot open a file ("'..pathToFile..'")' end -- Помилка: не змогли відкрити файл
	else return nil, 'Folder or file ("'..pathToFile..'") does not exists' end -- Помилка: не змогли знайти файл або папку
end

-- Функція серіалізації даних у файл
local function serialToFile(pathToFile, obj) --> nil | isError(string) -- Серіалізує таблицю і записує її у вказаний файл
	local fout = fs.open(pathToFile, "w") -- Пробуємо відкрити локальний файл для запису
	if fout == nil then return 'Cannot open a file ("'..pathToFile..'") for writing' end
	fout.write(textutils.serialize(obj))
	fout.close()
	return nil
end

-- Функція отримання git-хешів усіх файлів репозиторію одним запитом до GitHub API (Git Trees), щоб потім
-- порівняти їх зі збереженими з минулого разу й не перезавантажувати те, що не змінилось. Якщо API з якоїсь
-- причини недоступне (інший домен, ліміт запитів, немає textutils.unserialiseJSON тощо) — просто повертає помилку,
-- а виклик знає, що тоді треба качати все, як і раніше.
local function getRepoFileHashes(repo, branch) --> tHashes(table), nil | nil, isError(string)
	local bOk, result = pcall(function()
		local handle = http.get(apiPrefix .. repo .. "/git/trees/" .. branch .. "?recursive=1")
		if (handle == nil) or (handle.getResponseCode() ~= 200) then
			error('GitHub API did not respond for "'..repo..'/'..branch..'"')
		end
		local body = handle.readAll()
		handle.close()
		local tJson = textutils.unserialiseJSON(body)
		if (tJson == nil) or (tJson.tree == nil) then
			error("Could not parse GitHub tree response")
		end
		local tHashes = {}
		for _, v in ipairs(tJson.tree) do
			if v.type == "blob" then tHashes[v.path] = v.sha end
		end
		return tHashes
	end)
	if not bOk then return nil, tostring(result) end
	return result, nil
end

-- Функція запису списку файлів, які потрібно стягнути з репозиторію. Кожен елемент tFileList — це
-- {sGitPath=<шлях у репозиторії>, sLocalPath=<куди записати>}. Проходить по всьому списку одним разом,
-- замість того щоб тягнути й писати файл одразу в тому місці, де про нього дізнались.
-- tOldHashes і tNewHashes — опційні (можуть бути nil): якщо для файлу відомий і старий, і новий git-хеш,
-- і вони збігаються, і локальний файл усе ще існує — файл пропускається без завантаження.
local function writeFilesList(tFileList, repoPath, tOldHashes, tNewHashes) --> nil | isError(bool), tStatus(table), errorMsg(string)
	local tStatus = {} -- По кожному індексу: true, якщо файл записано (або пропущено як незмінений), false, якщо ні
	local bHasError = false
	local sErrorMsg = ""

	for i, tFileEntry in ipairs(tFileList) do -- Проходимось по кожному запису зі списку
		local sNewHash = tNewHashes and tNewHashes[tFileEntry.sGitPath]
		local sOldHash = tOldHashes and tOldHashes[tFileEntry.sGitPath]
		if (sNewHash ~= nil) and (sNewHash == sOldHash) and fs.exists(tFileEntry.sLocalPath) then -- Файл не змінювався з минулого разу і вже є на диску
			tStatus[i] = true
		else
			print("Receiving: ", tFileEntry.sGitPath)
			local content, isError = _GET(repoPath .. tFileEntry.sGitPath)
			if isError then -- Якщо не вдалось стягнути файл з репозиторію
				print(" ..unexisted")
				tStatus[i] = false
				bHasError = true
				sErrorMsg = sErrorMsg .. 'Cannot get file ("'..tFileEntry.sGitPath..'") from repository.\n'
			else
				local fout = fs.open(tFileEntry.sLocalPath, "w") -- Пробуємо відкрити локальний файл для запису
				if fout ~= nil then
					fout.write(content)
					fout.close()
					tStatus[i] = true
				else -- Якщо не вдалось відкрити локальний файл
					tStatus[i] = false
					bHasError = true
					sErrorMsg = sErrorMsg .. 'Cannot open a local file ("'..tFileEntry.sLocalPath..'") for writing.\n'
				end
			end
		end
	end

	if bHasError then return true, tStatus, sErrorMsg end -- Якщо була хоча б одна помилка
	return nil -- Всі файли зі списку записані без помилок
end

-- Функція запису локальних файлів для обраної user-програми (settings.txt і startup.lua). Це не завантаження
-- з гіта, тому й окрема функція — сама програма (.lua) тягнеться і пишеться через writeFilesList.
local function writeProgramSettings(settingTable, curdir) --> nil | isError(string)
	local sSettErr = serialToFile(curdir .. defaultFolderName .. localSettingsList_Name, settingTable) -- Записуємо в файл налаштувань самі налаштування
	if sSettErr then return sSettErr end

	local foutStartup = fs.open("/startup.lua", "w") -- Записуємо в файл стартапу потрібні дані
	if foutStartup == nil then return "userProgError: cannot open startup file for writing." end
	foutStartup.write('shell.run("'..curdir..defaultFolderName..settingTable.S_pinProgramm..'.lua"'..settingTable.S_pinStartArgs..')')
	foutStartup.close()

	return nil
end

-- Функція побудови масиву індексів userProgTable для показу списку. Якщо sTag не заданий (nil) — звичайний тотожний
-- порядок 1..n (весь список); якщо заданий — ті самі індекси, але записи з цим тегом переставлені на початок.
-- userProgTable сам не змінюється — лише повертається новий масив індексів і кількість записів з тегом на початку
-- (дорівнює довжині всього масиву, якщо sTag nil).
local function sortIndexByTag(userProgTable, sTag) --> tIndex(table), nCount(number)
	expect.expect(1, userProgTable, "table")
	expect.expect(2, sTag, "string", "nil")

	local n = #userProgTable
	if sTag == nil then
		local tIndex = {}
		for i = 1, n do tIndex[i] = i end
		return tIndex, n
	end

	local tMatched, tRest = {}, {}
	for i = 1, n do
		local bHasTag = false
		for _, sProgTag in ipairs(userProgTable[i].kTags) do
			if sProgTag == sTag then bHasTag = true break end
		end
		table.insert(bHasTag and tMatched or tRest, i)
	end
	local nCount = #tMatched
	for _, i in ipairs(tRest) do table.insert(tMatched, i) end
	return tMatched, nCount
end

-- Функція друку списку програм за масивом індексів (з прокруткою, якщо список не влазить на екран).
-- Повертає символ, натиснутий під час прокрутки, якщо такий був (щоб одразу передати його в подальше зчитування вводу)
local function printProgramList(tIndex, nCount, userProgTable) --> sEnteredChar(string) | nil
	local sEnteredChar
	local _, nDisplayHight = term.getSize()
	for i = 1, nCount do
		local _, nCursPosY = term.getCursorPos() -- Позиція, де курсор БУДЕ ДРУКУВАТИ
		if nCursPosY == (nDisplayHight) then --Якщо курсор уже на останньому рядку
			term.scroll(1) -- Піднімаємо весь текст вгору
			term.setCursorPos(1, nDisplayHight) -- Ставимо курсор на початок останнього рядка
			term.write("Wait or press any key") -- Пишемо підказку
			 -- чекаємо пів секунди або натискання, яке одразу зберігаємо як sEnteredChar, щоб не загубити
			fWaitOrSkip(0.5, true, true, function(eventTbl) if (eventTbl[1] == "char") then sEnteredChar = eventTbl[2] return true end end)
			term.clearLine() -- Очищаємо рядок, на якому була підказка
			term.setCursorPos(1, nDisplayHight) -- Ставимо курсор на початок останнього рядка
			if sEnteredChar ~= nil then break end -- Символ уже отримано — решту списку не друкуємо
		end
		print(" ["..i.."] ".."Name: "..userProgTable[tIndex[i]].kProgName)
	end
	return sEnteredChar
end

-- Функція очікування вводу номера в діапазоні [nMin, nMax], з повтором при некоректному значенні.
-- sEnteredChar (опційно) використовується лише при першій спробі — символ, натиснутий ще під час прокрутки списку.
local function readMenuChoice(nMin, nMax, sDefaultInput, sEnteredChar) --> inputValue(number)
	local inputValue
	local bFirstTry = true
	repeat -- Цикл з післяумовою для перевірки введеного значення
		write("\n> ")
		inputValue = tonumber(fReadData(sDefaultInput, 3, bFirstTry and sEnteredChar or nil))
		bFirstTry = false
		if ((inputValue > nMax) or (inputValue < nMin)) then print("Please enter again: ") end
	until ((inputValue <= nMax) and (inputValue >= nMin))
	return inputValue
end

-- Функція клонування репозиторію
local function clone(repo, branch) -->  isError(bool), isError(string) -- Клонує дані з GitHub
	local errorFlag = false
    local curdir = shell.dir() .. "/"
	local compLabel = os.getComputerLabel()
	local userProgTable = {}
	local tFileList = {} -- Список усіх файлів, які треба стягнути з репозиторію і куди їх покласти; заповнюється нижче, а стягується одним проходом перед видаленням старої папки

	if branch == nil then -- Якщо в аргументах не була вказана гілка, то встановлюється значення за замовчуванням, "master"
        branch = "master"
    end

	-- Якщо в аргументах не був вказаний репозиторій
    if repo == nil then
		local tDeploySettings, dsErr = unserialFromFile(curdir .. deploySettingsFileName) -- Пробуємо прочитати файл стану деплою з минулого запуску
        if (tDeploySettings ~= nil) and (tDeploySettings.Repository ~= nil) then -- Якщо файл є і в ньому вказано репозиторій, тобто ця програма вже успішно виконувалась
            return clone(tDeploySettings.Repository, tDeploySettings.Branch)
        else -- Не вдалось знайти файл стану деплою з попереднього запуску
            print("Please specify repository in arguments")
			errorFlag = true
            return false, "No repository name"
        end
    end

	-- Відкриваємо репозиторій
    local repoPath = repo .. "/" .. branch .. "/" -- Шлях у репозиторії
    local instrList_File, instrList_isError = _GET(repoPath .. instrList_Name) -- Спроба завантажити файл з інструкціями
	local tDeploySettings = unserialFromFile(curdir .. deploySettingsFileName) -- Пробуємо прочитати файл стану деплою з минулого запуску (може повернути nil, якщо його ще нема)

    if instrList_isError then -- Якщо не вдалось завантажити інструкції
		errorFlag = true
        return (print(' Repository "' .. repo .. '" does not contain the following file: ' .. instrList_Name) and false), (' Repository "' .. repo .. '" does not contain the following file: ' .. instrList_Name)
    end                               
									  
	os.queueEvent("settings_driver_in", nil, "stop") -- Призупиняємо роботу драйвера налаштувань, якщо він працює, і
	sleep(1) -- чекаємо 1 секунду, щоб він завершився

	-- Перевіряємо, чи минулий запуск лишив позначку невдалого завантаження — якщо так, стара папка є єдиною робочою копією,
	-- і перейменування тут небезпечне: пишемо файли прямо в наявну CCEnv/, не змінюючи deleteFolder_
	local bPreviousRunFailed = fs.exists(curdir .. deployFailedMarkerName)
	local renameStatus
	if bPreviousRunFailed then
		print(" - Previous run did not finish cleanly, working in place to avoid touching the last known-good backup.")
	else
		-- Перевіряємо чи є папка для видалення, яку не видалили минулого разу, та видаляємо її
		if fs.exists("deleteFolder_" .. defaultFolderName) then shell.run("delete", "deleteFolder_" .. defaultFolderName) end
		-- Перейменовуємо стару папку для подальшого її видалення
		if fs.exists(defaultFolderName) then renameStatus = shell.run("rename", defaultFolderName, "deleteFolder_" .. defaultFolderName) end
	end

	-- Призначення мітки для ПК, якщо потрібно
	if compLabel == nil then -- Якщо у ПК немає мітки, то ...
		print(" - Your PC does not have a label, please enter it below:")
	else --Пропозиція змінити мітку
		print(" - Your PC already has a label, but if you want to change it, you can enter it below within 3 seconds (to skip faster, press \"space\"):")
	end
	repeat -- Цикл з післяумовою для перевірки введеного значення
		local tempCompLabel = fReadData(compLabel)
		if tempCompLabel == nil then print("Incorrect label name, please enter again: ") else compLabel = tempCompLabel end
	until tempCompLabel ~= nil
	os.setComputerLabel(compLabel)

	local existingProgIndex -- Індекс в userProgTable, якщо раніше обрана програма й досі є серед того, що зараз реально є в репозиторії
	-- Клонування потрібних файлів з репозиторію на ПК
	for fTag, fName in string.gmatch(instrList_File, '#(.-)="(.-)"') do -- Читання інструкцій з файлу згідно з патерном, та обробка цих інструкцій далі
		if (fTag == "!") or (fTag == "Service") or (fTag == "File") then -- Якщо після ключового символу "#" є ("!" або "Service" або "File"), то це службові програми, і вони мають бути встановлені всюди
			--TODO: використати функцію, яка буде надсилати дані в консоль, і відправляти на базу, і на КПК
			if fName ~= "" then
				local instalDir = ((fTag == "!") and ("") or (defaultFolderName)) -- "Тернарний оператор", конструкція:(s = condition ? "true" : "false"), пояснення: оператор "and" повертає перше хибне значення серед своїх операндів; якщо обидва операнди істинні, повертається останній з них, а оператор "or" повертає перше істинне значення серед своїх операндів; якщо обидва операнди хибні, повертається останній з них
																				  -- Якщо "!", то не потрібно переміщати файл у підпапку, але якщо "Service", то потрібно перемістити в папку за замовчуванням
				table.insert(tFileList, {sGitPath = fName, sLocalPath = curdir .. instalDir .. fName}) -- Додаємо файл у список на завантаження, самого завантаження тут ще не відбувається
			else
				print('Warning: empty path for tag "'..fTag..'" in Instructions.txt, skipping')
			end
		elseif fTag == "User" then -- Якщо після ключового символу "#" є ("User"), то це користувацькі програми, тобто
			local _, _, fPath = string.find(fName, "sPath='(.-)'") -- Дізнаємось шлях, куди встановлювати програму
			if fPath ~= nil then
				local _, _, fstartupArgs = string.find(fName, "sStartupArgs='(.-)'") -- Дізнаємось, які аргументи потрібно вказувати у файлику зі стартапом
				local _, _, sTags = string.find(fName, "sTags='(.-)'") -- Дізнаємось теги програми
				--TODO: переробити систему аргументів запуску, або зчитувати, ну і відповідно записати, глобальні інструкції як таблицю з json файлу, або щось інше
				local _, _, progName = string.find(fPath, "/(.-).lua") -- Витягуємо назву програми
				if progName ~= nil then
					local kTags = {} -- Розбиваємо "sTags='Tag1,Tag2'" на масив; якщо sTags nil або порожній — масив лишається порожнім
					if sTags ~= nil then
						for sTag in string.gmatch(sTags, "[^,]+") do table.insert(kTags, sTag) end
					end
					table.insert(userProgTable, {kProgName = progName, kPath = fPath, kStartupArgs = fstartupArgs or "", kTags = kTags})
					if (tDeploySettings ~= nil) and (progName == tDeploySettings.S_pinProgramm) then existingProgIndex = #userProgTable end -- Якщо це та сама програма, що вже стояла на цьому ПК раніше — запам'ятовуємо її індекс
				else
					print('Warning: could not extract program name from sPath "'..fPath..'", skipping')
				end
			else
				print('Warning: malformed User entry (missing sPath), skipping: '..fName)
			end
		else -- Неправильно складений або невідомий тег
			print('Warning: unknown tag "'..fTag..'" in Instructions.txt, skipping: '..fName)
		end
    end

	local tIndex, nCount = sortIndexByTag(userProgTable, nil) -- Поточний масив індексів для показу: спершу повний, без фільтру за тегом
	local bFirstPrompt = true -- Тайм-аут з дефолтом діє лише на першому показі списку; після будь-якої взаємодії чекаємо без обмеження
	local realChoice -- Реальний індекс у userProgTable для обраної програми, якщо ввели номер зі списку (nil, якщо ввели "0")

	while true do
		---Вивід списку програм
		print((existingProgIndex and (' - The selected program for this PC is: "' .. tDeploySettings.S_pinProgramm .. '".')) or ' - Select a program number from the list below, or 0 to skip:')
		print(" [-1] By tag\n")
		local sEnteredChar = printProgramList(tIndex, nCount, userProgTable)

		---Очікуємо вводу користувача, або значення за замовчуванням
		local inputValue = readMenuChoice(-1, nCount, (bFirstPrompt and existingProgIndex and "0" or nil), sEnteredChar) -- Тайм-аут з дефолтом лише при першому показі; далі — без обмеження
		bFirstPrompt = false
		print() -- Переносимо рядок: якщо ввід стався за замовчуванням (тайм-аут, без жодного натискання), курсор лишається одразу після "> ", і наступний текст в'їжджав би в той самий рядок

		if inputValue == -1 then -- Показуємо список тегів для вибору
			-- tIndex і nCount тут не змінюємо: якщо в пікері оберуть "Cancel", список повернеться до того, що був до цього
			local tTagList, tSeenTags = {}, {}
			for i = 1, #userProgTable do
				for _, sTag in ipairs(userProgTable[i].kTags) do
					if not tSeenTags[sTag] then tSeenTags[sTag] = true table.insert(tTagList, sTag) end
				end
			end

			if #tTagList == 0 then
				print("No tags defined for any program.")
			else
				print(' - Select a tag, -1 to cancel, -2 to show all programs' .. (existingProgIndex and ', or 0 to keep the current program:' or ':'))
				for i, sTag in ipairs(tTagList) do print(" ["..i.."] "..sTag) end
				local tagChoice = readMenuChoice(-2, #tTagList, nil) -- Сюди потрапляємо лише після взаємодії — тайм-ауту тут немає
				print()
				if tagChoice > 0 then
					tIndex, nCount = sortIndexByTag(userProgTable, tTagList[tagChoice])
				elseif tagChoice == -2 then
					tIndex, nCount = sortIndexByTag(userProgTable, nil)
				elseif tagChoice == 0 then
					break -- "0" працює однаково на будь-якому рівні: одразу лишаємо прив'язану програму
				end
				-- tagChoice == -1: нічого не робимо, tIndex/nCount лишаються як були — повертаємось на попередній рівень
			end
		elseif inputValue == 0 then
			break -- Пропускаємо вибір; що робити далі — вирішиться нижче
		else
			realChoice = tIndex[inputValue]
			break
		end
	end

	-- Виконання вибраних користувачем дій
	local chosenProgram -- Таблиця з даними обраної user-програми, якщо користувач її обрав
	local chosenProgramFileIndex -- Індекс запису обраної програми в tFileList, щоб потім перевірити саме її статус завантаження
	if realChoice ~= nil then -- Ввели номер програми зі списку (повного або відфільтрованого за тегом)
		local v = userProgTable[realChoice]
		chosenProgram = {S_pinProgramm = v.kProgName, S_pinPathGit = v.kPath, S_pinStartArgs = v.kStartupArgs} -- Нова таблиця з даними, S означає сервісні дані
		table.insert(tFileList, {sGitPath = chosenProgram.S_pinPathGit, sLocalPath = curdir .. defaultFolderName .. chosenProgram.S_pinProgramm .. ".lua"}) -- Додаємо обрану програму в той самий загальний список
		chosenProgramFileIndex = #tFileList -- Запам'ятовуємо, під яким індексом вона в списку, щоб потім перевірити саме її статус
	elseif existingProgIndex ~= nil then -- Пропустили вибір ("0"), але раніше обрана програма й досі є в списку з гіта — лишаємо її
		local v = userProgTable[existingProgIndex]
		chosenProgram = {S_pinProgramm = v.kProgName, S_pinPathGit = v.kPath, S_pinStartArgs = v.kStartupArgs}
		table.insert(tFileList, {sGitPath = chosenProgram.S_pinPathGit, sLocalPath = curdir .. defaultFolderName .. chosenProgram.S_pinProgramm .. ".lua"})
		chosenProgramFileIndex = #tFileList
	else -- "0" і раніше обраної програми немає
		print("No user programm has been selected.") -- Якщо ми не хочемо обирати програму
	end

	-- Отримуємо хеші файлів у репозиторії одним запитом, щоб не перезавантажувати те, що не змінилось.
	-- Якщо GitHub API з якоїсь причини недоступне — просто качаємо все, як і раніше.
	local tRepoHashes, hashErr = getRepoFileHashes(repo, branch)
	if hashErr then print("Skip-detection unavailable (" .. hashErr .. "), downloading everything.") end

	-- Завантаження всього, що назбиралось у tFileList, одним проходом — і службові файли, і обрана user-програма
	local isDownloadError, tDownloadStatus, downloadErrorMsg = writeFilesList(tFileList, repoPath, tDeploySettings and tDeploySettings.tFileHashes, tRepoHashes)
	if isDownloadError then
		print(downloadErrorMsg)
		errorFlag = true
		if not bPreviousRunFailed then -- Позначаємо, що цей запуск не вдався, щоб наступний запуск не видалив резервну копію, не розібравшись
			local fout = fs.open(curdir .. deployFailedMarkerName, "w")
			if fout ~= nil then fout.write("1") fout.close() end
		end
	end

	if chosenProgram ~= nil then -- Якщо ми обирали user-програму — settings.txt і startup.lua пишемо лише якщо сама програма реально завантажилась
		if (not isDownloadError) or (tDownloadStatus[chosenProgramFileIndex]) then
			local writeSettErr = writeProgramSettings(chosenProgram, curdir)
			if writeSettErr then
				print(writeSettErr)
				errorFlag = true
			elseif chosenProgram.S_pinProgramm == nil then
				print("Warning: chosenProgram.S_pinProgramm is nil after selection — this should not happen, please report it.")
				errorFlag = true
			else
				print('\nProgramm "'..chosenProgram.S_pinProgramm..'" was connected to "'..os.getComputerLabel()..'" label.')
			end
		else
			print('\nProgramm "'..chosenProgram.S_pinProgramm..'" was NOT connected: could not download the program file.')
			errorFlag = true
		end
	end

	if not isDownloadError then -- Запам'ятовуємо стан для наступного запуску: репозиторій, гілку, хеші файлів, і (якщо є) обрану програму
		local tFinalDeploySettings = {Repository = repo, Branch = branch, tFileHashes = tRepoHashes}
		local tProgSource = chosenProgram or tDeploySettings -- Якщо цього разу нічого не обирали — лишаємо те, що вже було записано раніше
		if tProgSource ~= nil then
			tFinalDeploySettings.S_pinProgramm = tProgSource.S_pinProgramm
			tFinalDeploySettings.S_pinPathGit = tProgSource.S_pinPathGit
			tFinalDeploySettings.S_pinStartArgs = tProgSource.S_pinStartArgs
		end
		local writeDeployStateErr = serialToFile(curdir .. deploySettingsFileName, tFinalDeploySettings)
		if writeDeployStateErr then print(writeDeployStateErr) errorFlag = true end
	end

	-- Видалення старої папки та позначки невдалого запуску (лишаємо все на диску, якщо під час завантаження була помилка — про всяк випадок)
	if not isDownloadError then
		if renameStatus or bPreviousRunFailed then shell.run("delete", "deleteFolder_" .. defaultFolderName) end -- Видаляємо стару папку, якщо вона існувала (перейменували цього разу, або лишилась з невдалого минулого запуску) і все завантажилось без помилок
		if bPreviousRunFailed then shell.run("delete", curdir .. deployFailedMarkerName) end -- Успішно відновились після невдалого запуску — прибираємо позначку
	end
	return true, ""
end


-- Безпосередній запуск "розпаковки" середовища з GitHub
local args = {...}
print("#Name: deploy.lua# || #Version: 2.5.1#\n")
clone(args[1], args[2])