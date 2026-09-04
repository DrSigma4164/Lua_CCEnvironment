local instrList_Name = "Instructions.txt"
local localSettingsList_Name = "settings.txt"
local deploySettingsFileName = "deploysettings.txt"
local prefix = "https://raw.githubusercontent.com/"
local defaultFolderName = "CCEnv/"

local expect = require "cc.expect"

--TODO: Нотатка: local modem = peripheral.find("modem") or error("No modem attached", 0)

-- Функція завантаження даних
local function _GET(path) --> content, nil | nil, isError(string) -- Читає дані з GitHub
    local handle = http.get(prefix .. path)
	
    if (handle == nil) or (handle.getResponseCode() ~= 200) then
        return nil, '"' .. path .. '" not responding'
    end
	
    local content = handle.readAll()
    handle.close()
    return content, nil
end

--Функція зчитування даних з клавіатури за n секунд, або повернення значення за замовчуванням
local function fReadData(defaultValue, nTimerTime) -->  --> content(string) | nil, nil | isError(string)
	expect.expect(1, defaultValue, "string", "nil")
	expect.expect(2, nTimerTime, "number", "nil")

	if ((nTimerTime == nil) or (nTimerTime < 0)) then nTimerTime = 3 end

	local nTimerId = os.startTimer(nTimerTime)--запускаємо таймер на 3 секунди і зберігаємо його ID
	while true do
		local sEventName, eventArgs = os.pullEvent()
		if ((sEventName == "timer") and (eventArgs == nTimerId) and (defaultValue ~= nil)) then -- Якщо таймер вже вийшов і є значення за замовчуванням
			return defaultValue
		elseif ((sEventName == "char") and (eventArgs == ' ') and (defaultValue ~= nil)) then -- Або ми натиснули на пробіл і є значення за замовчуванням
			return defaultValue
		elseif ((sEventName == "char") and (eventArgs ~= ' ')) then -- Або ввели щось інше
			write(">")
			return read(nil, nil, nil, eventArgs)
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
	fout.write(textutils.serialise(obj))
	fout.close()
	return nil
end

-- Функція запису списку файлів, які потрібно стягнути з репозиторію. Кожен елемент tFileList — це
-- {sGitPath=<шлях у репозиторії>, sLocalPath=<куди записати>}. Проходить по всьому списку одним разом,
-- замість того щоб тягнути й писати файл одразу в тому місці, де про нього дізнались.
local function writeFilesList(tFileList, repoPath) --> nil | isError(bool), tStatus(table), errorMsg(string)
	local tStatus = {} -- По кожному індексу: true, якщо файл записано, false, якщо ні
	local bHasError = false
	local sErrorMsg = ""

	for i, tFileEntry in ipairs(tFileList) do -- Проходимось по кожному запису зі списку
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

	-- Перевіряємо чи є папка для видалення, яку не видалили минулого разу, та видаляємо її
	if fs.exists("deleteFolder_" .. defaultFolderName) then shell.run("delete", "deleteFolder_" .. defaultFolderName) end
	-- Перейменовуємо стару папку для подальшого її видалення
	local renameStatus
	if fs.exists(defaultFolderName) then renameStatus = shell.run("rename", defaultFolderName, "deleteFolder_" .. defaultFolderName) end

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
			local instalDir = ((fTag == "!") and ("") or (defaultFolderName)) -- "Тернарний оператор", конструкція:(s = condition ? "true" : "false"), пояснення: оператор "and" повертає перше хибне значення серед своїх операндів; якщо обидва операнди істинні, повертається останній з них, а оператор "or" повертає перше істинне значення серед своїх операндів; якщо обидва операнди хибні, повертається останній з них
																			  -- Якщо "!", то не потрібно переміщати файл у підпапку, але якщо "Service", то потрібно перемістити в папку за замовчуванням
			table.insert(tFileList, {sGitPath = fName, sLocalPath = curdir .. instalDir .. fName}) -- Додаємо файл у список на завантаження, самого завантаження тут ще не відбувається
		elseif fTag == "User" then -- Якщо після ключового символу "#" є ("User"), то це користувацькі програми, тобто
			local _, _, fPath = string.find(fName, "sPath='(.-)'") -- Дізнаємось шлях, куди встановлювати програму
			local _, _, fstartupArgs = string.find(fName, "sStartupArgs='(.-)'") -- Дізнаємось, які аргументи потрібно вказувати у файлику зі стартапом
			--TODO: переробити систему аргументів запуску, або зчитувати, ну і відповідно записати, глобальні інструкції як таблицю з json файлу, або щось інше
			local _, _, progName = string.find(fPath, "/(.-).lua") -- Витягуємо назву програми
			table.insert(userProgTable, {kProgName = progName, kPath = fPath, kStartupArgs = fstartupArgs})
			if (tDeploySettings ~= nil) and (progName == tDeploySettings.S_pinProgramm) then existingProgIndex = #userProgTable end -- Якщо це та сама програма, що вже стояла на цьому ПК раніше — запам'ятовуємо її індекс
		else -- Неправильно складений або невідомий тег

		end
    end

	 ---Вивід списку програм
	print((existingProgIndex and (' - The selected program for this PC is: "' .. tDeploySettings.S_pinProgramm .. '".')) or ' - Select a program number from the list below, or 0 to skip:')
	local _, nDisplayHight = term.getSize()
	for k, v in pairs(userProgTable) do
		local _, nCursPosY = term.getCursorPos() -- Позиція, де курсор БУДЕ ДРУКУВАТИ
		if nCursPosY == (nDisplayHight) then --Якщо курсор уже на останньому рядку
			term.scroll(1) -- Піднімаємо весь текст вгору
			term.setCursorPos(1, nDisplayHight) -- Ставимо курсор на початок останнього рядка
			term.write("Wait or press any key") -- Пишемо підказку
			 -- чекаємо пів секунди або запуску функції, в якій, якщо функція поверне true, тоді значення "aSkipAnsw" повернеться як результат першої функції "fWaitOrSkip()"
			fWaitOrSkip(0.5, true, true, function(eventTbl)  if ((eventTbl[1] == "key")) then print("TEST1111") return true end end)
			term.clearLine() -- Очищаємо рядок, на якому була підказка
			term.setCursorPos(1, nDisplayHight) -- Ставимо курсор на початок останнього рядка
		end
		print(" ["..k.."] ".."Name: "..v.kProgName)
	end

		---Очікуємо вводу користувача, або значення за замовчуванням
		local bHasExistingProgram = fs.exists("/startup.lua") -- Якщо на ПК вже є startup.lua, то якась програма вже налаштована — можна безпечно взяти "0" за замовчуванням; якщо немає, це "чистий" ПК, і чекаємо явний вибір без обмеження часу

		local inputValue
		repeat -- Цикл з післяумовою для перевірки введеного значення
			write("\n> ")
			inputValue = tonumber(fReadData((bHasExistingProgram and "0" or nil), 3))
			if ((inputValue > #userProgTable) or (inputValue < 0)) then print("Please enter again: ") end
		until ((inputValue <= #userProgTable) and (inputValue >= 0))
		print() -- Переносимо рядок: якщо ввід стався за замовчуванням (тайм-аут, без жодного натискання), курсор лишається одразу після "> ", і наступний текст в'їжджав би в той самий рядок
	-- Виконання вибраних користувачем дій
	local chosenProgram -- Таблиця з даними обраної user-програми, якщо користувач її обрав
	local chosenProgramFileIndex -- Індекс запису обраної програми в tFileList, щоб потім перевірити саме її статус завантаження
	if inputValue > 0 then -- Ввели номер програми зі списку
		chosenProgram = {S_pinProgramm = userProgTable[inputValue].kProgName, S_pinPathGit = userProgTable[inputValue].kPath, S_pinStartArgs = userProgTable[inputValue].kStartupArgs} -- Нова таблиця з даними, S означає сервісні дані
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

	-- Завантаження всього, що назбиралось у tFileList, одним проходом — і службові файли, і обрана user-програма
	local isDownloadError, tDownloadStatus, downloadErrorMsg = writeFilesList(tFileList, repoPath)
	if isDownloadError then
		print(downloadErrorMsg)
		errorFlag = true
	end

	if chosenProgram ~= nil then -- Якщо ми обирали user-програму — settings.txt і startup.lua пишемо лише якщо сама програма реально завантажилась
		if (not isDownloadError) or (tDownloadStatus[chosenProgramFileIndex]) then
			local writeSettErr = writeProgramSettings(chosenProgram, curdir)
			local writeDeployStateErr = serialToFile(curdir .. deploySettingsFileName, {Repository = repo, Branch = branch, S_pinProgramm = chosenProgram.S_pinProgramm, S_pinPathGit = chosenProgram.S_pinPathGit, S_pinStartArgs = chosenProgram.S_pinStartArgs}) -- Запам'ятовуємо для наступного запуску deploy.lua, що саме тут стоїть
			if writeSettErr or writeDeployStateErr then
				if writeSettErr then print(writeSettErr) end
				if writeDeployStateErr then print(writeDeployStateErr) end
				errorFlag = true
			else print('\nProgramm "'..chosenProgram.S_pinProgramm..'" was connected to "'..os.getComputerLabel()..'" label.') end
		else
			print('\nProgramm "'..chosenProgram.S_pinProgramm..'" was NOT connected: could not download the program file.')
			errorFlag = true
		end
	end

	--TODO: подумати, що робити з "deleteFolder_", якщо isDownloadError — зараз вона просто лишається на диску як резервна копія,
	--      але наступний запуск deploy.lua одразу видалить її на самому початку (крок з "Перевіряємо чи є папка для видалення"),
	--      навіть якщо той наступний запуск теж не вдасться. Треба або зберігати ознаку невдалого запуску окремо, або якось інакше.

	-- Видалення старої папки (лишаємо її на диску, якщо під час завантаження була помилка — про всяк випадок)
	if renameStatus and not isDownloadError then shell.run("delete", "deleteFolder_" .. defaultFolderName) end -- Видаляємо стару папку, якщо вона існувала і все завантажилось без помилок
	return true, ""
end


-- Безпосередній запуск "розпаковки" середовища з GitHub
local args = {...}
print("#Name: deploy.lua# || #Version: 2.3.0#\n")
clone(args[1], args[2])