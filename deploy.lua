local instrList_Name = "Instructions.txt"
local localSettingsList_Name = "settings.txt"
local prefix = "https://raw.githubusercontent.com/"
local defaultFolderName = "CCEnv/"

local expect = require "cc.expect"

--TODO: Заметка: local modem = peripheral.find("modem") or error("No modem attached", 0)

-- Функция загрузки данных
function _GET(path) --> content, nil | nil, isError(string) -- Читает данные с GitHub
    local handle = http.get(prefix .. path)
	
    if (handle == nil) or (handle.getResponseCode() ~= 200) then
        return nil, '"' .. path .. '" not responding'
    end
	
    local content = handle.readAll()
    handle.close()
    return content, nil
end

--Функция считывание данных с клавиатуры за n секунд, или возвращения значение по умолчанию
function fReadData(defaultValue, nTimerTime) -->  --> content(string) | nil, nil | isError(string)
	expect.expect(1, defaultValue, "string", "nil")
	expect.expect(2, nTimerTime, "number", "nil")

	if ((nTimerTime == nil) or (nTimerTime < 0)) then nTimerTime = 3 end

	local nTimerId = os.startTimer(nTimerTime)--запускаем таймер на 3 секунды и сохраняем его ИД
	while true do
		local sEventName, eventArgs = os.pullEvent()
		if ((sEventName == "timer") and (eventArgs == nTimerId) and (defaultValue ~= nil)) then -- Если таймер уже вышел и есть значение по умолчанию
			return defaultValue
		elseif ((sEventName == "char") and (eventArgs == ' ') and (defaultValue ~= nil)) then -- Или мы нажали на пробел и есть значение по умолчанию
			return defaultValue
		elseif ((sEventName == "char") and (eventArgs ~= ' ')) then -- Или ввели что-то другое
			write(">")
			return read(nil, nil, nil, eventArgs)
		end
	end
	return nil, "EoF"
end

--Функция
function fWaitOrSkip(nTimerTime, aTimerAnsw, aSkipAnsw, fEventCher) -->  content(Any) | nil, nil | isError(string)
	expect.expect(1, nTimerTime, "number")
	--expect.expect(2, aTimerAnsw, "string", "nil")
	--expect.expect(3, aSkipAnsw, "string", "nil")
	expect.expect(4, fEventCher, "function", "nil")

	if (nTimerTime < 0) then nTimerTime = 1.5 end
	if (fEventCher == nil) then fEventCher = function() return false end end

	local nTimerId = os.startTimer(nTimerTime)--запускаем таймер и сохраняем его ИД
	while true do
		local tEventReturn = {os.pullEvent()}
		if ((tEventReturn[1] == "timer") and (tEventReturn[2] == nTimerId)) then -- Если таймер уже вышел
			return aTimerAnsw
		elseif fEventCher(tEventReturn) then -- Или мы получили ответ
			return aSkipAnsw
		end
	end
end

-- Функция десерилизации данных
function unserelObj(pathToFile) --> content(Any) | nil, nil | isError(string) -- Читает данные с файла и проводит десерилизацию
    if fs.exists(pathToFile) == true then -- Если есть старая папка, и файл с настройками открылся, то пробуем искать с настройками в ней
		local fin = fs.open(pathToFile, "r") -- Пробуем открыть локальный файл с инструкциями
		if fin ~= nil then -- Если файл старых локальных настроек открылся
			local unserializeObj = textutils.unserialize(fin.readAll()) -- Пробуем читать из файла с настройками
			fin.close()
			if unserializeObj ~= nil then
				return unserializeObj, nil
			else return nil, 'Cannot unserialize data into object ("'..pathToFile..'")' end -- Ошибка: не смогли десерелизировать данные
		else return nil, 'Cannot open a file ("'..pathToFile..'")' end -- Ошибка: не смогли открыть файл
	else return nil, 'Folder or file ("'..pathToFile..'") does not exists' end -- Ошибка: не смогли найти файл или папку
end

-- Функция записи данных
function writeFileandObj(settingTable, curdir, repoPath) --> nil | isError(string) -- Записывает файл настройки, файл с гибхаба,
    if settingTable.S_pinPathGit == nil then return "userProgError: cannot get file from repository." end
	print("\nReceiving user programm: ", settingTable.S_pinPathGit)
	local userFile, isError = _GET(repoPath .. settingTable.S_pinPathGit)
	if isError then
		print(" ..unexisted")
		return 'userProgError: cannot get file ("'..settingTable.S_pinPathGit..'") from repository.'
	else
		local fout = fs.open(curdir .. defaultFolderName .. settingTable.S_pinProgramm .. ".lua", "w") -- Записываем файл программы
		if fout ~= nil then 
			fout.write(userFile)
			fout.close()

			local foutSett = fs.open(curdir .. defaultFolderName .. localSettingsList_Name, "w") -- Записываем в файл настроек настройки)
			foutSett.write(textutils.serialise(settingTable))
			foutSett.close()

			local foutStartup = fs.open("/startup.lua", "w") -- Записываем в файл стартапу настройки)
			foutStartup.write('shell.run("'..curdir..defaultFolderName..settingTable.S_pinProgramm..'.lua"'..settingTable.S_pinStartArgs..')')
			foutStartup.close()
		else return "userProgError: table error in key: S_pinProgramm." end
	end
	
	return nil
end

-- Функция клонирования репозитория
function clone(repo, branch) -->  isError(bool), isError(string) -- Клонирует данные с GitHub
	local errorFlag = false
    local curdir = shell.dir() .. "/"
	local compLabel = os.getComputerLabel()
	local userProgTable = {}

	if branch == nil then -- Если в аргументах не была указана ветка, то устанавливается значение по умолчанию, "master"
        branch = "master"
    end

	-- Если в аргументах не был указан репозиторий
    if repo == nil then 
	    local fin = fs.open(curdir .. instrList_Name, "r") -- Пробуем открыть файл
        if fin ~= nil then -- Если в файлах на ПК есть файл инструкций, тоесть данная программа уже успешно выполнялась            
			_, _, r = string.find(fin.readLine(), '!Repository="(.-)"') -- Читаем первую строку, в которой должно находится имя репозитория
			_, _, b = string.find(fin.readLine(), '!Branch="(.-)"') -- Читаем следующую строку, в которой должна находится ветка
            fin.close()
            return clone(r, b)
        else -- Не удалось найти локальный файл предыдущего запуска
            print("Please specify repository in arguments")
			errorFlag = true
            return false, "No repository name"
        end
    end

	-- Открываем репозиторий
    local repoPath = repo .. "/" .. branch .. "/" -- Путь в репозитории
    local instrList_File, instrList_isError = _GET(repoPath .. instrList_Name) -- Попытка загрузить файл с инструкциями

    if instrList_isError then -- Если не удалось загрузить инструкции
		errorFlag = true
        return (print(' Repository "' .. repo .. '" does not contain the following file: ' .. instrList_Name) and false), (' Repository "' .. repo .. '" does not contain the following file: ' .. instrList_Name)
    end                               

	-- Перевіряємо чи є папка для видаленя, яку не видалили минулий раз, та видаляємо її
	if fs.exists("deleteFolder_" .. defaultFolderName) then shell.run("delete", "deleteFolder_" .. defaultFolderName) end
	-- Прейменовуємо стару папку для подальшого в її видалення
	local renameStatus
	if fs.exists(defaultFolderName) then renameStatus = shell.run("rename", defaultFolderName, "deleteFolder_" .. defaultFolderName) end

	-- Назначение метки для ПК, если нужно
	if compLabel == nil then -- Если в пк нет метки, то ...
		print(" - Your PC does not have a label, please enter it below:")
	else --Предложение сменить метку
		print(" - Your PC already has a label, but if you want to change it, you can enter it below within 3 seconds (to skip faster, press \"space\"):")
	end
	repeat -- Цыкли с после-условием для проверки введеного значения
		local tempCompLabel = fReadData(compLabel)
		if tempCompLabel == nil then print("Incorrect label name, please enter again: ") else compLabel = tempCompLabel end
	until tempCompLabel ~= nil
	os.setComputerLabel(compLabel)

	local isUserProg = false
	-- Клонирование нужных файлов с репозитория на ПК
	for fTag, fName in string.gmatch(instrList_File, '#(.-)="(.-)"') do -- Читання інструкцій з файла згідно патерну, та обробка далі цих інстрйкцій
		if (fTag == "!") or (fTag == "Service") or (fTag == "File") then -- Если после ключевого символа "#" есть ("!" или "Service" или "File") то это служебные прогаммы и должны быть установлены везде
			--TODO: использовать функцию, которая будет посылать данные в консоль, и откправлять на базу, и на КПК
			print("Receiving: ", fName)
            local content, isError = _GET(repoPath .. fName)
            if isError then print(" ..unexisted") else
				local instalDir = ((fTag == "!") and ("") or (defaultFolderName)) -- "Тернарный оператор", конструктция:(s = condition ? "true" : "false"), пояснение: оператор "and" возвращает первое ложное значение среди сових операндов; если оба операнда истинны, возвращается последний из них, а оператор "or" возвращает первое истинное значение среди своих операндов; если оба операнда ложны, возвращается последний из них
																				  -- Если "!", то не нужно перемещать файл в подпапку, но если "Service", то нужно переместить в папку по умолчанию
				local fout = fs.open(curdir .. instalDir .. fName, "w")
                fout.write(content)
                fout.close()
			end
		elseif fTag == "User" then -- Если после ключевого символа "#" есть ("User") то это пользовательские программы, тоисть
			if not isUserProg then -- Нет установленой пользовательской программы
				local _, _, fPath = string.find(fName, "sPath='(.-)'") -- Узнаем путь куда устанавливать программу
				local _, _, fstartupArgs = string.find(fName, "sStartupArgs='(.-)'") -- Узнаем какие аргументы нужно вказывать в файлике с стартапом
				--TODO: переробити систему аргументів запуску, або зчитувати, ну і відповідно записати, глобальні інструкції як таблицю з json файлу, або шось інше
				local _, _, progName = string.find(fPath, "/(.-).lua") -- Извлекаем название программы
				table.insert(userProgTable, {kProgName = progName, kPath = fPath, kStartupArgs = fstartupArgs})

				if progName == compLabel and false then -- Если есть приложение с таким же названием как и пк, то ..
					print("\nReceiving user programm: ", fPath)
					local content, isError = _GET(repoPath .. fPath)
					if isError then print(" ..unexisted") else
						local fout = fs.open(curdir .. defaultFolderName .. progName .. ".lua", "w")
						fout.write(content)
						fout.close()
					end
					isUserProg = true -- Делаем пометку, что программу найдено
					userProgTable = {} -- Удаляем ненужную уже таблицу
				end

			end
		else -- Не верно составленый или неизвестный Тэг

		end
    end

	-- Обработка таблицы с пользовательскими программами, если нужна
	if not isUserProg then -- Если мы не нашли нужной программы
		local sDefaultProgramm -- Переменная для того, чтобы задать значение по умолчанию в зависимости от ситуации.

		os.queueEvent("settings_driver_in", nil, "stop") -- Приостанавливаем роботу драйвера настроек, если он работает, и
		sleep(1) -- ждём 1 секунду, чтобы он завершился
		print("Test after STOP")  --DEBUG

		local tSettings, errMsg = unserelObj(curdir .. "deleteFolder_" .. defaultFolderName .. localSettingsList_Name) -- Пробуем десерилизировать данные с файла настройки

		if ((tSettings ~= nil) and (tSettings.S_pinProgramm ~= nil) and false) then -- Если данные серилизировались и в таблице есть данные программы, то ...
			print(' - The selected program for this PC is: "' .. tSettings.S_pinProgramm .. '".')
			sDefaultProgramm = tSettings.S_pinProgramm
			--TODO: зробити перенесення локальних налаштувань
		else -- Если нет, то делаем новый настроечный файл
			--TODO: зробити створення нового файлу для локальних налаштувань
			if errMsg == nil then errMsg = "" end
			print(' - Error: "' .. errMsg .. '". Select a program number from the list below, or 0 to skip:')
		end

		 ---Вивід списку програм
		local _, nDisplayHight = term.getSize()
		for k, v in pairs(userProgTable) do
			local _, nCursPosY = term.getCursorPos() -- Позиция где курсор БУДЕТ ПЕЧАТАТЬ
			if nCursPosY == (nDisplayHight) then --Если курсор уже на последней строке
				term.scroll(1) -- Поднимаем весь текст вверх
				term.setCursorPos(1, nDisplayHight) -- Ставим курсов в начало последней строки
				term.write("Wait or press any key") -- Пишем подсказку
				 -- ждём пол секкунды или запуск функции, в которой, если функция вернет true, тогда значение "aSkipAnsw" вернётся как результат первой функций "fWaitOrSkip()"
				fWaitOrSkip(0.5, true, true, function(eventTbl)  if ((eventTbl[1] == "key")) then print("TEST1111") return true end end)
				term.clearLine() -- Очищаем строку на которой біла подсказка
				term.setCursorPos(1, nDisplayHight) -- Ставим курсов в начало последней строки
			end
			print(" ["..k.."] ".."Name: "..v.kProgName)
		end

		---Очікуємо вводу користувача, або значення за замовчуванням
		local inputValue
		repeat -- Цыкли с после-условием для проверки введеного значения
			write("\n> ")
			inputValue = tonumber(fReadData("0", 3))
			if ((inputValue > #userProgTable) and (inputValue < 0)) then print("Please enter again: ") end
		until ((inputValue <= #userProgTable) and (inputValue >= 0))

		-- Виконання вибраних користувачем дій
		if inputValue > 0 then
			local content = {S_pinProgramm = userProgTable[inputValue].kProgName, S_pinPathGit = userProgTable[inputValue].kPath, S_pinStartArgs = userProgTable[inputValue].kStartupArgs} -- Новая таблица с данными, S - значить сервисные данные

			local writeSIsError= writeFileandObj(content, curdir, repoPath) -- Запись в файлы
			if writeSIsError then print(writeSIsError) errorFlag = true
			else print('\nProgramm "'..content.S_pinProgramm..'" was connected to "'..os.getComputerLabel()..'" label.') end
		elseif inputValue == 0 then
			print("No user programm has been downloaded.") -- Если мы не хотим загружать программы
		end
	end

	-- Удаление старой папки
	if renameStatus then shell.run("delete", "deleteFolder_" .. defaultFolderName) end -- Удаляем старую папку, если она существовала
	return true, ""
end


-- Непосредственный запуск "распаковки" среды с GitHub
local args = {...}
print("#Name: deploy.lua# || #Version: 2.2.5#\n")
clone(args[1], args[2])