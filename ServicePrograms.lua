local tFunctionLists = {} -- Таблица в которую будут добавлены функции, чтобы добавить напише TABLE_NAME.FUNC_NAME() возле имени функции.
local expect = require "cc.expect"
local defaultFolderName = "CCEnv/"

--TODO: сделать функцию, которая будет посылать данные в консоль, и отправлять на базу, и на КПК
--TODO: сделать функцию для ввода команд, которая запускается паралельно с основной программой И команды можна будет ввести как вручную, так и при помощи предложеных блоков, к примеру: на экране будет показыватся Список возможных ПК, далее при выборе будет показыватся команда, а дальше в зависимости от команды аргументы
--TODO: зробити набір функцій для звязку з модом IntegratedDynamics
--TODO: зробити функцыъ для управлыння інвентарем черепашки

--Функция драйвера настроек, которая последовательно будет исполнять команды
function tFunctionLists.fSettingsDriver() --> funcStatus(boolean), returnMsg(string)
    local tSettingTable = {}
    local localSettingsList_Name = "settings.txt"

    -- Считывание предыдущих сохраненных настроек
    local fin, _ = fs.open(defaultFolderName .. localSettingsList_Name, "r") -- Пробуем открыть файл c настройками
    if fin ~= nil then -- если файл открылся
        local sContent = fin.readAll() -- Читаем таблицу с файла
        fin.close()
        if sContent ~= nil then -- если что-то есть в файле
            tSettingTable = textutils.unserialize(sContent) -- Пробуем десирилизировать вместимое файла
            if tSettingTable == nil then tSettingTable = {} end --если мы смогли десирилизировать данные с файла
        end
    end

    -- Последовательная обработка команд
    while true do
        local _, nRecvId, eventCommand, eventTableId, eventArgs = os.pullEvent("settings_driver_in")
        if ((eventCommand == "get")) then -- Если нужно считать данные
            if tSettingTable[eventTableId] ~= nil then -- Если есть такое поле и там есть значение
                os.queueEvent("settings_driver_out", nRecvId, tSettingTable[eventTableId], "")
            else
                os.queueEvent("settings_driver_out", nRecvId, nil, "no field")
            end
        elseif ((eventCommand == "set")) then -- Или нужно установить данные
            tSettingTable[eventTableId] = eventArgs
            local bErrorFlag = false
            local fout, _ = fs.open(defaultFolderName .. "temp" .. localSettingsList_Name, "w") -- Пробуем открыть файл c настройками
            if fout ~= nil then --Если файл открылся
                local seriObj = textutils.serialize(tSettingTable)
                if seriObj ~= nil then
                    fout.write(seriObj)
                    fout.close()
                    shell.run("delete", defaultFolderName .. localSettingsList_Name)
                    if shell.run("rename", defaultFolderName .. "temp" .. localSettingsList_Name, defaultFolderName .. localSettingsList_Name) then bErrorFlag = true end
                else
                    fout.close()
                end
            end
            os.queueEvent("settings_driver_out", nRecvId, bErrorFlag, "save error")
        elseif ((eventCommand == "stop")) then -- Или команда "стоп"
            return true, 'Command: "stop"'
        end
    end

    return false, 'Error: EoF'
end

--Функция получения указаной настройки за указаное время (по умолчанию 5 секунд)
function tFunctionLists.getSettings(sTableLabel, nDefaultTime) --> operResContent(string), nil | nil, errorMsg(string)
    expect.expect(1, sTableLabel, "string")
    expect.expect(2, nDefaultTime, "number", "nil")

    if ((nDefaultTime == nil) or (nDefaultTime < 0)) then nDefaultTime = 3 end -- Если пользователь не указал максимальное время, то оно равно значению по умолчанию

    local nRequestId = os.startTimer(nDefaultTime) -- Запускаем таймер, который будет служить ID, и непосредственно таймером

    --Отдача команды и ожидание ответа
    os.queueEvent("settings_driver_in", nRequestId, "get", sTableLabel)
    while true do
        local sEventName, nEventID, sOperContent, sOperErr = os.pullEvent()
        if ((sEventName == "timer") and (nEventID == nRequestId)) then -- Если таймер уже вышел
            return nil, "Timer out (get)"
        elseif ((sEventName == "settings_driver_out") and (nEventID == nRequestId)) then -- Или мы получили ответ
            return sOperContent, sOperErr
        end
    end
    return nil, 'Error: EoF'
end

--Функция установки указаной настройки за указаное время (по умолчанию 5 секунд)
function tFunctionLists.setSettings(sTableLabel, sTableValue, nDefaultTime) --> operStatus(boolean), nil | errorMsg(string)
    expect.expect(1, sTableLabel, "string")
    expect.expect(2, sTableValue, "string")
    expect.expect(3, nDefaultTime, "number", "nil")

    if ((nDefaultTime == nil) or (nDefaultTime < 0)) then nDefaultTime = 3 end -- Если пользователь не указал максимальное время, то оно равно значению по умолчанию

    local nRequestId = os.startTimer(nDefaultTime) -- Запускаем таймер, который будет служить ID, и непосредственно таймером

    --Отдача команды и ожидание ответа
    os.queueEvent("settings_driver_in", nRequestId, "set", sTableLabel, sTableValue)
    while true do
        local sEventName, nEventID, sOperContent, sOperErr = os.pullEvent()
        if ((sEventName == "timer") and (nEventID == nRequestId)) then -- Если таймер уже вышел
            return false, "Timer out (set)"
        elseif ((sEventName == "settings_driver_out") and (nEventID == nRequestId)) then -- Или мы получили ответ
            return sOperContent, sOperErr
        end
    end
    return false, 'Error: EoF'
end

--Функция считывание данных с клавиатуры за n секунд, или возвращения значение по умолчанию
function tFunctionLists.fReadData(defaultValue, nTimerTime) --> content(string), nil | nil, errorMsg(string)
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

-- Функція отримання двох найменшу і найбільшу точки області
function tFunctionLists.getAreaCoord(vPos1, vPos2) --> vMinPos(vector), vMaxPos(vector), nil, errorMsg(string)
    expect.expect(1, vPos1, "table")
    expect.expect(2, vPos2, "table")
    local vMinPos = vector.new(math.min(vPos1.x, vPos2.x), math.min(vPos1.y, vPos2.y), math.min(vPos1.z, vPos2.z))
    local vMaxPos = vector.new(math.max(vPos1.x, vPos2.x), math.max(vPos1.y, vPos2.y), math.max(vPos1.z, vPos2.z))
    return vMinPos, vMaxPos, nil
end

-- Функція отримання напрямку черепахи
function tFunctionLists.getTurtleDirection(allowDig) --> direction(vector) | nil, nil | errorMsg(string) -- No change position
    expect.expect(1, allowDig, "boolean", "nil")
    if not turtle then return nil, "Error: requires a Turtle" end -- Якщо функцією користується не "черепашка"
	local i = 1 -- Счётчик цыкла
	local h = 0 -- Счётчик относительной высоты
	
    -- Определяем наши координаты
	local xPos, _, zPos = gps.locate(1)
	if xPos == nil then return nil, "I can't find gps!!!(start)" end -- Если не смогли определить местоположение
    -- Пробуем двигатся вперёд
	while not turtle.forward() do -- Если черепах не смогла двинуться вперёд, то ...
        if allowDig then -- якщо є дозвіл, то копаємо перед собою блок
            turtle.dig()
        else
            if math.fmod(i, 4) == 0 then -- Если мы пробовали пройти вперёд уже 4 раза, то ..
                i = 1 -- "обнуляем" счётчик
                if turtle.up() then -- Если мы сможем поднятся вверх, то..
                    h = h + 1
                elseif turtle.down() then -- Если мы не смогли поднятся вверх, но можем вниз, то ..
                    h = h - 1
                else -- Мы не смогли никуда повернутся, ошибка
                    return nil, "I can't move anywhere!!"
                end
            else -- Если ещё не повернулись 4 раза, то ..
                turtle.turnRight()
                i = i + 1
            end
        end
	end
	
    -- Определям новое местоположение
	local xRel, _, zRel = gps.locate(1)
	if xRel == nil then return nil, "I can't find gps!!!(final)" end -- Если не смогли определить местоположение
	
    -- "Обнуляем" набраную позицию
	if not turtle.back() then return nil, "I can't move back!!" end -- Возвращаемся назад, так как двигались вперёд
	while h ~= 0 do -- Если мы двигались по вертикале, то пробуем обнулить набраную высоту
		if h < 0 then 
			if not turtle.up() then return nil, "I can't move up!!"
			else h = h + 1 end
		elseif h > 0 then
			if not turtle.down() then return nil, "I can't move down!!"
			else h = h - 1 end
		end
	end
	
    -- Возвращаем направление
	local vDir = vector.new(xRel, 0, zRel) - vector.new(xPos, 0, zPos)
	return vDir:normalize(), nil
end

-- Фунція встановлення напрямку черепахи
function tFunctionLists.setTurtleDirection(vDirection, vDirToDest) --> newDirection(vector), nil | dontChangeDirection(vector), errorMsg(string) -- No change position
    expect.expect(1, vDirection, "table")
    expect.expect(2, vDirToDest, "table")
    if not turtle then return vDirection, "Error: requires a Turtle" end -- Якщо функцією користується не "черепашка"

    if not vDirection:equals(vDirToDest) then -- Якщо ми дивимось не в правильному напрямку, то крутимо "черепашку" в правильний напрямок
        if (vDirection:cross(vDirToDest)).y < 0 then -- Якщо верктор дивиться вниз, то повертаємо вправо
            vDirection = tFunctionLists.goTurtleRight(vDirection)
        elseif (vDirection:cross(vDirToDest)).y > 0 then -- Якщо верктор дивиться вверх, то повертаємо вліво
            vDirection = tFunctionLists.goTurtleLeft(vDirection)
        else -- Інакше, якщо вектор нульвоий, і ми дивись в не тому напрямку, то потрібно повернутися на 180
            vDirection = tFunctionLists.goTurtleRight(vDirection)
            vDirection = tFunctionLists.goTurtleRight(vDirection)
        end
    end

    return vDirection, nil
end

-- Фунція повороту праворуч
function tFunctionLists.goTurtleRight(vDirection) --> NowDirection(vector), nil | dontChangeDirection(vector), errorMsg(string)
    expect.expect(1, vDirection, "table")
    if not turtle then return vDirection, "Error: requires a Turtle" end -- Якщо функцією користується не "черепашка"
    if turtle.turnRight() then return vDirection:cross(vector.new(0, 1, 0)), nil
    else return vDirection, "Can't turn right" end
end

-- Фунція повороту ліворуч
function tFunctionLists.goTurtleLeft(vDirection) --> NowDirection(vector), nil | dontChangeDirection(vector), errorMsg(string)
    expect.expect(1, vDirection, "table")
    if not turtle then return vDirection, "Error: requires a Turtle" end -- Якщо функцією користується не "черепашка"
    if turtle.turnLeft() then return vDirection:cross(vector.new(0, -1, 0)), nil
    else return vDirection, "Can't turn left" end
end

-- Функція руху черепахи в певному напрямку
function tFunctionLists.goInDirection(vDirection, vDirToDest, allowDig) --> direction(vector), nil | dontChangeDirection(vector), errorMessage(string) -- No change position
    expect.expect(1, vDirection, "table")
    expect.expect(2, vDirToDest, "table")
    expect.expect(3, allowDig, "boolean", "nil")
    if not turtle then return vDirection, "Error: requires a Turtle" end -- Якщо функцією користується не "черепашка"

    -- Рухаємось у вказаному напрямку
    if vDirToDest.y > 0 then -- Якщо потрібно рухатись вверх
        if not turtle.up() then if allowDig then turtle.digUp() end end --Якщо не вдалось пройти вверх, то якщо є дозвіл на копання, то копаємо вверх
    elseif vDirToDest.y < 0 then -- Якщо потрібно рухатись вниз
        if not turtle.down() then if allowDig then turtle.digDown() end end --Якщо не вдалось пройти вниз, то якщо є дозвіл на копання, то копаємо вниз
    else
        if math.abs(vDirToDest.x) == math.abs(vDirToDest.z) then vDirToDest.z = 0 end -- якщо потрібно рухатись по діагоналі, то пріоритетом є вісь X
        vDirection = tFunctionLists.setTurtleDirection(vDirection, vDirToDest) -- крутимо "черепашку" в правильний напрямок
        if not turtle.forward() then if allowDig then turtle.dig() end end --Якщо не вдалось пройти вперед, то якщо є дозвіл на копання, то копаємо вперед
    end

    return vDirection, nil
end

-- Функция поиска пути к определенным координатам
function tFunctionLists.goToGPS(vDestPos, vDirection, allowDig, fFuncAftMove) -- fFuncAftMove(vDirection) return vDirection end --> NowDirection(vector), nil | dontChangeDirection(vector), errorMsg(string)
    expect.expect(1, vDestPos, "table")
    expect.expect(2, vDirection, "table", "nil")
    expect.expect(3, allowDig, "boolean", "nil")
    expect.expect(4, fFuncAftMove, "function", "nil")
    if not turtle then return vDirection, "Error: requires a Turtle" end -- Якщо функцією користується не "черепашка"

    if (vDirection == nil) then --Якщо не надано напрямок руху, то ...
        local vDir, isError = tFunctionLists.getTurtleDirection(allowDig) -- пробуємо знайти це напрямок
        if isError then return vDirection, "Can't get direction: " .. isError end -- якщо ми його не знайшли, то завершуємо функцію
        vDirection = vDir -- інакше присвоюємо отриманий напрямок руху
    end

    local vCurPos
    while (true) do
        if true then -- Визначаємо наші координати
            local xPos, yPos, zPos = gps.locate(1)
            if xPos == nil then return vDirection, "I can't find gps!!!" end -- Якщо не змогли отримати координати
            vCurPos = vector.new(xPos, yPos, zPos)
        end

        if (vCurPos:equals(vDestPos)) or ((math.abs((vDestPos - vCurPos).x) + math.abs((vDestPos - vCurPos).y) + math.abs((vDestPos - vCurPos).z)) == 1 and not allowDig) then return vDirection, nil end --Якщо ми в точці призначення, або біля цієї точки і немає дозволу на копання.

        local vDirToDest = vDestPos - vCurPos -- Визначаємо напрямок для руху
        vDirToDest = vDirToDest:normalize() -- Нормалізовуємо вектор
        vDirToDest = vDirToDest:round() -- Та заокруглюємо його

        vDirection = tFunctionLists.goInDirection(vDirection, vDirToDest, allowDig) -- Рухаємось в відповідну сторону
        if fFuncAftMove ~= nil then vDirection = fFuncAftMove(vDirection) end -- Якщо є функція, то запустимо її
    end
end

print("#Name: ServicePrograms.lua# || #Version: 2.4.6#\n")
return tFunctionLists -- Возвращает таблицу, в которой находятся функции