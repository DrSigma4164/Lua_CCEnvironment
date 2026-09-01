local instrList_Name = "Instructions.txt"
local localSettingsList_Name = "settings.txt"
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

-- Функція десеріалізації даних
local function unserelObj(pathToFile) --> content(Any) | nil, nil | isError(string) -- Читає дані з файлу і проводить десеріалізацію
    if fs.exists(pathToFile) == true then -- Якщо є стара папка, і файл з налаштуваннями відкрився, то пробуємо шукати налаштування в ній
		local fin = fs.open(pathToFile, "r") -- Пробуємо відкрити локальний файл з інструкціями
		if fin ~= nil then -- Якщо файл старих локальних налаштувань відкрився
			local unserializeObj = textutils.unserialize(fin.readAll()) -- Пробуємо читати з файлу з налаштуваннями
			fin.close()
			if unserializeObj ~= nil then
				return unserializeObj, nil
			else return nil, 'Cannot unserialize data into object ("'..pathToFile..'")' end -- Помилка: не змогли десеріалізувати дані
		else return nil, 'Cannot open a file ("'..pathToFile..'")' end -- Помилка: не змогли відкрити файл
	else return nil, 'Folder or file ("'..pathToFile..'") does not exists' end -- Помилка: не змогли знайти файл або папку
end

-- Функція запису даних
local function writeFileandObj(settingTable, curdir, repoPath) --> nil | isError(string) -- Записує файл програми, файл з гітхаба, та стартап
    if settingTable.S_pinPathGit == nil then return "userProgError: cannot get file from repository." end
	print("\nReceiving user programm: ", settingTable.S_pinPathGit)
	local userFile, isError = _GET(repoPath .. settingTable.S_pinPathGit)
	if isError then
		print(" ..unexisted")
		return 'userProgError: cannot get file ("'..settingTable.S_pinPathGit..'") from repository.'
	else
		local fout = fs.open(curdir .. defaultFolderName .. settingTable.S_pinProgramm .. ".lua", "w") -- Записуємо файл програми
		if fout ~= nil then 
			fout.write(userFile)
			fout.close()

			local foutSett = fs.open(curdir .. defaultFolderName .. localSettingsList_Name, "w") -- Записуємо в файл налаштувань самі налаштування
			foutSett.write(textutils.serialise(settingTable))
			foutSett.close()

			local foutStartup = fs.open("/startup.lua", "w") -- Записуємо в файл стартапу потрібні дані
			foutStartup.write('shell.run("'..curdir..defaultFolderName..settingTable.S_pinProgramm..'.lua"'..settingTable.S_pinStartArgs..')')
			foutStartup.close()
		else return "userProgError: table error in key: S_pinProgramm." end
	end
	
	return nil
end

-- Функція клонування репозиторію
local function clone(repo, branch) -->  isError(bool), isError(string) -- Клонує дані з GitHub
	local errorFlag = false
    local curdir = shell.dir() .. "/"
	local compLabel = os.getComputerLabel()
	local userProgTable = {}

	if branch == nil then -- Якщо в аргументах не була вказана гілка, то встановлюється значення за замовчуванням, "master"
        branch = "master"
    end

	-- Якщо в аргументах не був вказаний репозиторій
    if repo == nil then 
	    local fin = fs.open(curdir .. instrList_Name, "r") -- Пробуємо відкрити файл
        if fin ~= nil then -- Якщо у файлах на ПК є файл інструкцій, тобто ця програма вже успішно виконувалась            
			local _, _, r = string.find(fin.readLine(), '!Repository="(.-)"') -- Читаємо перший рядок, в якому має знаходитись ім'я репозиторію
			local _, _, b = string.find(fin.readLine(), '!Branch="(.-)"') -- Читаємо наступний рядок, в якому має знаходитись гілка
            fin.close()
            return clone(r, b)
        else -- Не вдалось знайти локальний файл попереднього запуску
            print("Please specify repository in arguments")
			errorFlag = true
            return false, "No repository name"
        end
    end

	-- Відкриваємо репозиторій
    local repoPath = repo .. "/" .. branch .. "/" -- Шлях у репозиторії
    local instrList_File, instrList_isError = _GET(repoPath .. instrList_Name) -- Спроба завантажити файл з інструкціями

    if instrList_isError then -- Якщо не вдалось завантажити інструкції
		errorFlag = true
        return (print(' Repository "' .. repo .. '" does not contain the following file: ' .. instrList_Name) and false), (' Repository "' .. repo .. '" does not contain the following file: ' .. instrList_Name)
    end                               
									  
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

	local isUserProg = false
	-- Клонування потрібних файлів з репозиторію на ПК
	for fTag, fName in string.gmatch(instrList_File, '#(.-)="(.-)"') do -- Читання інструкцій з файлу згідно з патерном, та обробка цих інструкцій далі
		if (fTag == "!") or (fTag == "Service") or (fTag == "File") then -- Якщо після ключового символу "#" є ("!" або "Service" або "File"), то це службові програми, і вони мають бути встановлені всюди
			--TODO: використати функцію, яка буде надсилати дані в консоль, і відправляти на базу, і на КПК
			print("Receiving: ", fName)
            local content, isError = _GET(repoPath .. fName)
            if isError then print(" ..unexisted") else
				local instalDir = ((fTag == "!") and ("") or (defaultFolderName)) -- "Тернарний оператор", конструкція:(s = condition ? "true" : "false"), пояснення: оператор "and" повертає перше хибне значення серед своїх операндів; якщо обидва операнди істинні, повертається останній з них, а оператор "or" повертає перше істинне значення серед своїх операндів; якщо обидва операнди хибні, повертається останній з них
																				  -- Якщо "!", то не потрібно переміщати файл у підпапку, але якщо "Service", то потрібно перемістити в папку за замовчуванням
				local fout = fs.open(curdir .. instalDir .. fName, "w")
                fout.write(content)
                fout.close()
			end
		elseif fTag == "User" then -- Якщо після ключового символу "#" є ("User"), то це користувацькі програми, тобто
			if not isUserProg then -- Немає встановленої користувацької програми
				local _, _, fPath = string.find(fName, "sPath='(.-)'") -- Дізнаємось шлях, куди встановлювати програму
				local _, _, fstartupArgs = string.find(fName, "sStartupArgs='(.-)'") -- Дізнаємось, які аргументи потрібно вказувати у файлику зі стартапом
				--TODO: переробити систему аргументів запуску, або зчитувати, ну і відповідно записати, глобальні інструкції як таблицю з json файлу, або щось інше
				local _, _, progName = string.find(fPath, "/(.-).lua") -- Витягуємо назву програми
				table.insert(userProgTable, {kProgName = progName, kPath = fPath, kStartupArgs = fstartupArgs})

				if progName == compLabel and false then -- Якщо є програма з такою ж назвою, як і мітка ПК, то ..
					print("\nReceiving user programm: ", fPath)
					local content, isError = _GET(repoPath .. fPath)
					if isError then print(" ..unexisted") else
						local fout = fs.open(curdir .. defaultFolderName .. progName .. ".lua", "w")
						fout.write(content)
						fout.close()
					end
					isUserProg = true -- Робимо позначку, що програму знайдено
					userProgTable = {} -- Видаляємо вже непотрібну таблицю
				end

			end
		else -- Неправильно складений або невідомий тег

		end
    end

	-- Обробка таблиці з користувацькими програмами, якщо потрібно
	if not isUserProg then -- Якщо ми не знайшли потрібної програми
		local sDefaultProgramm -- Змінна для того, щоб задати значення за замовчуванням в залежності від ситуації.

		os.queueEvent("settings_driver_in", nil, "stop") -- Призупиняємо роботу драйвера налаштувань, якщо він працює, і
		sleep(1) -- чекаємо 1 секунду, щоб він завершився
		print("Test after STOP")  --DEBUG

		local tSettings, errMsg = unserelObj(curdir .. "deleteFolder_" .. defaultFolderName .. localSettingsList_Name) -- Пробуємо десеріалізувати дані з файлу налаштувань

		if ((tSettings ~= nil) and (tSettings.S_pinProgramm ~= nil) and false) then -- Якщо дані десеріалізувались і в таблиці є дані програми, то ...
			print(' - The selected program for this PC is: "' .. tSettings.S_pinProgramm .. '".')
			sDefaultProgramm = tSettings.S_pinProgramm
			--TODO: зробити перенесення локальних налаштувань
		else -- Якщо ні, то робимо новий файл налаштувань
			--TODO: зробити створення нового файлу для локальних налаштувань
			if errMsg == nil then errMsg = "" end
			print(' - Error: "' .. errMsg .. '". Select a program number from the list below, or 0 to skip:')
		end

		 ---Вивід списку програм
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
		local inputValue
		repeat -- Цикл з післяумовою для перевірки введеного значення
			write("\n> ")
			inputValue = tonumber(fReadData("0", 3))
			if ((inputValue > #userProgTable) or (inputValue < 0)) then print("Please enter again: ") end
		until ((inputValue <= #userProgTable) and (inputValue >= 0))

		-- Виконання вибраних користувачем дій
		if inputValue > 0 then
			local content = {S_pinProgramm = userProgTable[inputValue].kProgName, S_pinPathGit = userProgTable[inputValue].kPath, S_pinStartArgs = userProgTable[inputValue].kStartupArgs} -- Нова таблиця з даними, S означає сервісні дані

			local writeSIsError= writeFileandObj(content, curdir, repoPath) -- Запис у файли
			if writeSIsError then print(writeSIsError) errorFlag = true
			else print('\nProgramm "'..content.S_pinProgramm..'" was connected to "'..os.getComputerLabel()..'" label.') end
		elseif inputValue == 0 then
			print("No user programm has been downloaded.") -- Якщо ми не хочемо завантажувати програми
		end
	end

	-- Видалення старої папки
	if renameStatus then shell.run("delete", "deleteFolder_" .. defaultFolderName) end -- Видаляємо стару папку, якщо вона існувала
	return true, ""
end


-- Безпосередній запуск "розпаковки" середовища з GitHub
local args = {...}
print("#Name: deploy.lua# || #Version: 2.2.5#\n")
clone(args[1], args[2])