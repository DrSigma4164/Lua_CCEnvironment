local tFunctionLists = {} -- Таблиця, в яку будуть додані функції; щоб додати, напишіть TABLE_NAME.FUNC_NAME() біля імені функції.
local expect = require "cc.expect"
local defaultFolderName = "CCEnv/"
local sMonitorProtocol = "cc-monitor" -- Назва протоколу rednet для зв'язку монітора з КПК

--TODO: зробити функцію, яка буде надсилати дані в консоль, і відправляти на базу, і на КПК
--TODO: зробити функцію для вводу команд, яка запускається паралельно з основною програмою, і команди можна буде вводити як вручну, так і за допомогою запропонованих блоків, наприклад: на екрані буде показуватись список можливих ПК, далі при виборі буде показуватись команда, а далі в залежності від команди аргументи
--TODO: зробити набір функцій для звязку з модом IntegratedDynamics
--TODO: зробити функцію для управління інвентарем черепашки

-- Локальна функція очікування конкретної події з тайм-аутом. Не додається в tFunctionLists — внутрішня допоміжна.
local function waitForEvent(nTimerTime, fEventCher) --> bFound(boolean)
	local nTimerId = os.startTimer(nTimerTime)
	while true do
		local tEvent = {os.pullEvent()}
		if (tEvent[1] == "timer") and (tEvent[2] == nTimerId) then return false end
		if fEventCher(tEvent) then return true end
	end
end

-- Функція друку з тегом джерела і кольором (як у docker compose: "ConfEngine | текст"). Якщо термінал
-- не кольоровий — просто тег без кольору. Відсутність тегу означає, що пише незмінена стара user-програма.
function tFunctionLists.logPrint(sSource, nColor, ...) --> nil
	expect.expect(1, sSource, "string")
	expect.expect(2, nColor, "number", "nil")
	local tArgs = {...}
	for i = 1, #tArgs do tArgs[i] = tostring(tArgs[i]) end
	if term.isColor() and (nColor ~= nil) then term.setTextColor(nColor) end
	print(sSource .. " | " .. table.concat(tArgs, " "))
	if term.isColor() then term.setTextColor(colors.white) end
end

--Функція драйвера налаштувань, яка послідовно буде виконувати команди
function tFunctionLists.fSettingsDriver() --> funcStatus(boolean), returnMsg(string)
    local tSettingTable = {}
    local localSettingsList_Name = "settings.txt"

    -- Зчитування попередньо збережених налаштувань
    local fin, _ = fs.open("/" .. defaultFolderName .. localSettingsList_Name, "r") -- Пробуємо відкрити файл з налаштуваннями (абсолютний шлях, щоб не залежати від поточної робочої директорії програми)
    if fin ~= nil then -- якщо файл відкрився
        local sContent = fin.readAll() -- Читаємо таблицю з файлу
        fin.close()
        if sContent ~= nil then -- якщо щось є у файлі
            tSettingTable = textutils.unserialize(sContent) -- Пробуємо десеріалізувати вміст файлу
            if tSettingTable == nil then tSettingTable = {} end --якщо ми не змогли десеріалізувати дані з файлу
        end
    end

    -- Послідовна обробка команд
    while true do
        local _, nRecvId, eventCommand, eventTableId, eventArgs = os.pullEvent("settings_driver_in")
        if ((eventCommand == "get")) then -- Якщо потрібно зчитати дані
            if tSettingTable[eventTableId] ~= nil then -- Якщо є таке поле і там є значення
                os.queueEvent("settings_driver_out", nRecvId, tSettingTable[eventTableId], "")
            else
                os.queueEvent("settings_driver_out", nRecvId, nil, "no field")
            end
        elseif ((eventCommand == "set")) then -- Або потрібно встановити дані
            tSettingTable[eventTableId] = eventArgs
            local bErrorFlag = false
            local fout, _ = fs.open("/" .. defaultFolderName .. "temp" .. localSettingsList_Name, "w") -- Пробуємо відкрити файл з налаштуваннями
            if fout ~= nil then --Якщо файл відкрився
                local seriObj = textutils.serialize(tSettingTable)
                if seriObj ~= nil then
                    fout.write(seriObj)
                    fout.close()
                    shell.run("delete", "/" .. defaultFolderName .. localSettingsList_Name)
                    if shell.run("rename", "/" .. defaultFolderName .. "temp" .. localSettingsList_Name, "/" .. defaultFolderName .. localSettingsList_Name) then bErrorFlag = true end
                else
                    fout.close()
                end
            end
            os.queueEvent("settings_driver_out", nRecvId, bErrorFlag, "save error")
        elseif ((eventCommand == "stop")) then -- Або команда "стоп"
            if nRecvId ~= nil then os.queueEvent("settings_driver_out", nRecvId, "ack", nil) end -- Підтверджуємо отримання команди
            if nRecvId ~= nil then os.queueEvent("settings_driver_out", nRecvId, "done", nil) end -- Зупинка тут миттєва (налаштування вже збережені на кожен "set"), тому done одразу після ack
            return true, 'Command: "stop"'
        end
    end

    return false, 'Error: EoF'
end

--Функція отримання вказаного налаштування за вказаний час (за замовчуванням 5 секунд)
function tFunctionLists.getSettings(sTableLabel, nDefaultTime) --> operResContent(string), nil | nil, errorMsg(string)
    expect.expect(1, sTableLabel, "string")
    expect.expect(2, nDefaultTime, "number", "nil")

    if ((nDefaultTime == nil) or (nDefaultTime < 0)) then nDefaultTime = 3 end -- Якщо користувач не вказав максимальний час, то він дорівнює значенню за замовчуванням

    local nRequestId = os.startTimer(nDefaultTime) -- Запускаємо таймер, який буде слугувати ID, і безпосередньо таймером

    --Відправка команди та очікування відповіді
    os.queueEvent("settings_driver_in", nRequestId, "get", sTableLabel)
    while true do
        local sEventName, nEventID, sOperContent, sOperErr = os.pullEvent()
        if ((sEventName == "timer") and (nEventID == nRequestId)) then -- Якщо таймер уже вийшов
            return nil, "Timer out (get)"
        elseif ((sEventName == "settings_driver_out") and (nEventID == nRequestId)) then -- Або ми отримали відповідь
            return sOperContent, sOperErr
        end
    end
    return nil, 'Error: EoF'
end

--Функція встановлення вказаного налаштування за вказаний час (за замовчуванням 5 секунд)
function tFunctionLists.setSettings(sTableLabel, sTableValue, nDefaultTime) --> operStatus(boolean), nil | errorMsg(string)
    expect.expect(1, sTableLabel, "string")
    expect.expect(2, sTableValue, "string")
    expect.expect(3, nDefaultTime, "number", "nil")

    if ((nDefaultTime == nil) or (nDefaultTime < 0)) then nDefaultTime = 3 end -- Якщо користувач не вказав максимальний час, то він дорівнює значенню за замовчуванням

    local nRequestId = os.startTimer(nDefaultTime) -- Запускаємо таймер, який буде слугувати ID, і безпосередньо таймером

    --Відправка команди та очікування відповіді
    os.queueEvent("settings_driver_in", nRequestId, "set", sTableLabel, sTableValue)
    while true do
        local sEventName, nEventID, sOperContent, sOperErr = os.pullEvent()
        if ((sEventName == "timer") and (nEventID == nRequestId)) then -- Якщо таймер уже вийшов
            return false, "Timer out (set)"
        elseif ((sEventName == "settings_driver_out") and (nEventID == nRequestId)) then -- Або ми отримали відповідь
            return sOperContent, sOperErr
        end
    end
    return false, 'Error: EoF'
end

-- Функція для вставки в цикл user-програми: неблокуюче перевіряє, чи прийшла команда від монітора.
-- {sType="heartbeat_ping"} — монітор перевіряє, чи програма жива; одразу відповідаємо {sType="heartbeat_pong"}
-- і повертаємо false (це не зупинка, цикл програми триває далі як звичайно).
-- {sType="stop_request"} — монітор просить зупинитись. Шлемо {sType="stop_ack"} (отримав, починаю), викликаємо
-- fnStop (унікальну для програми функцію зупинки, яка повертає isOk(boolean), errorMsg(string)|nil), шлемо
-- {sType="stop_done"} з результатом, і повертаємо true.
-- Якщо жодної команди немає — повертає false майже миттєво, не блокуючи цикл програми.
function tFunctionLists.checkMonitorCommand(fnStop) --> bWasStopped(boolean)
    expect.expect(1, fnStop, "function")
    local tMsg
    local bGotSignal = waitForEvent(0, function(t)
        if (t[1] == sMonitorProtocol) and (type(t[2]) == "table") and ((t[2].sType == "stop_request") or (t[2].sType == "heartbeat_ping")) then tMsg = t[2] return true end
    end)
    if not bGotSignal then return false end
    if tMsg.sType == "heartbeat_ping" then
        os.queueEvent(sMonitorProtocol, {sType = "heartbeat_pong", nReqId = tMsg.nReqId})
        return false
    end
    os.queueEvent(sMonitorProtocol, {sType = "stop_ack", nReqId = tMsg.nReqId})
    local bOk, sErr = fnStop()
    os.queueEvent(sMonitorProtocol, {sType = "stop_done", nReqId = tMsg.nReqId, bOk = bOk, sErrorMsg = sErr})
    return true
end

-- Функція моніторинг-двигуна. Піднімає мережу (якщо є бездротовий модем) під протоколом sMonitorProtocol.
-- Локальні команди (для тестування, напряму через os.queueEvent) і мережеві команди від КПК обробляються
-- через одну диспетчер-таблицю (tCommands) — додати нову команду означає лише додати новий запис туди,
-- більше нічого міняти не треба.
--
-- Команди:
--   stop          - зупиняє user-програму (до 10с на stop_ack, ще до 10с на stop_done, інакше вважає її
--                    завислою і йде далі), потім конфіг-двигун (так само, до 5с на кожен крок) через наявний
--                    "settings_driver_in"/"stop", надсилає в мережу {sStatus="stopped"} і перезавантажує ПК.
--   list_commands - повертає список команд, які підтримує цей ПК, напряму тому, хто запитав.
--   dummyCommand  - тестова команда: через nSeconds друкує sMessage. Виконується як окрема паралельна
--                   гілка через "spawn" (дивись нижче), тому не блокує цикл диспетчеризації, поки спить.
--
-- Окремо, теж через "spawn" — вартовий цикл: раз на 10 секунд шле "heartbeat_ping" user-програмі й чекає
-- "heartbeat_pong". Не відповіла 3 рази поспіль (тобто 30 секунд без жодної відповіді) — вважаємо її
-- завислою чи завершеною без циклу (як стара програма без "checkMonitorCommand") і викликаємо ту саму
-- команду "stop", що й за зовнішнім запитом.
function tFunctionLists.fMonitoringDriver(spawn) --> funcStatus(boolean), returnMsg(string)
    local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
    local bNetworked = (modem ~= nil)
    if bNetworked then
        rednet.open(peripheral.getName(modem))
        rednet.host(sMonitorProtocol, os.getComputerLabel())
    end

    local tCommands
    tCommands = {
        stop = {
            sDescription = "Stop the user program and config engine, then reboot the PC",
            tArgs = {},
            fnHandler = function(tMsg, nSenderId)
                local nReqId = os.startTimer(0) -- Використовуємо лише як унікальний ID запиту, не як реальний таймер
                os.queueEvent(sMonitorProtocol, {sType = "stop_request", nReqId = nReqId})
                if waitForEvent(10, function(t) return (t[1] == sMonitorProtocol) and (type(t[2]) == "table") and (t[2].sType == "stop_ack") and (t[2].nReqId == nReqId) end) then
                    waitForEvent(10, function(t) return (t[1] == sMonitorProtocol) and (type(t[2]) == "table") and (t[2].sType == "stop_done") and (t[2].nReqId == nReqId) end)
                end -- Якщо не було навіть stop_ack — вважаємо user-програму завислою і йдемо далі, не чекаючи на неї більше

                local nSettReqId = os.startTimer(0)
                os.queueEvent("settings_driver_in", nSettReqId, "stop")
                if waitForEvent(5, function(t) return (t[1] == "settings_driver_out") and (t[2] == nSettReqId) and (t[3] == "ack") end) then
                    waitForEvent(5, function(t) return (t[1] == "settings_driver_out") and (t[2] == nSettReqId) and (t[3] == "done") end)
                end

                if bNetworked then rednet.broadcast({sStatus = "stopped", sLabel = os.getComputerLabel()}, sMonitorProtocol) end
                os.reboot()
            end
        },
        list_commands = {
            sDescription = "Return the list of commands this PC supports",
            tArgs = {},
            fnHandler = function(tMsg, nSenderId)
                local tList = {}
                for sName, tCmd in pairs(tCommands) do
                    table.insert(tList, {sName = sName, sDescription = tCmd.sDescription, tArgs = tCmd.tArgs})
                end
                rednet.send(nSenderId, {sType = "command_list", nReqId = tMsg.nReqId, tCommands = tList}, sMonitorProtocol)
            end
        },
        dummyCommand = {
            sDescription = "Test command: prints sMessage after nSeconds",
            tArgs = {"nSeconds", "sMessage"},
            fnHandler = function(tMsg, nSenderId)
                spawn(function() -- Окрема паралельна гілка, тому sleep тут не блокує цикл диспетчеризації нижче
                    sleep(tMsg.nSeconds)
                    tFunctionLists.logPrint("Dummy", colors.yellow, tMsg.sMessage)
                end)
            end
        },
    }

    spawn(function() -- Вартовий цикл heartbeat — окрема паралельна гілка, не блокує диспетчеризацію нижче
        local nMissed = 0
        while true do
            sleep(10)
            local nReqId = os.startTimer(0) -- Використовуємо лише як унікальний ID запиту, не як реальний таймер
            os.queueEvent(sMonitorProtocol, {sType = "heartbeat_ping", nReqId = nReqId})
            local bGotPong = waitForEvent(10, function(t) return (t[1] == sMonitorProtocol) and (type(t[2]) == "table") and (t[2].sType == "heartbeat_pong") and (t[2].nReqId == nReqId) end)
            if bGotPong then
                nMissed = 0
            else
                nMissed = nMissed + 1
                tFunctionLists.logPrint("Monitor", colors.orange, "User program did not respond to heartbeat (" .. nMissed .. "/3)")
                if nMissed >= 3 then
                    tFunctionLists.logPrint("Monitor", colors.red, "User program appears unresponsive, stopping")
                    tCommands.stop.fnHandler({}, nil) -- Та сама команда "stop", що й за зовнішнім запитом; вона й перезавантажить ПК
                end
            end
        end
    end)

    local function dispatch(tMsg, nSenderId)
        if (type(tMsg) == "table") and (tCommands[tMsg.sType] ~= nil) then
            tCommands[tMsg.sType].fnHandler(tMsg, nSenderId)
        end
    end

    while true do
        local sEventName, a, b, c = os.pullEvent()
        if bNetworked and (sEventName == "rednet_message") and (c == sMonitorProtocol) and (type(b) == "table") then
            dispatch(b, a) -- b = саме повідомлення, a = ID відправника
        elseif (sEventName == sMonitorProtocol) and (type(a) == "table") then
            dispatch(a, nil) -- Локальна подія (для тестування) — немає мережевого відправника, щоб відповідати
        end
    end

    return false, "Error: EoF"
end

--Функція зчитування даних з клавіатури за n секунд, або повернення значення за замовчуванням
function tFunctionLists.fReadData(defaultValue, nTimerTime) --> content(string), nil | nil, errorMsg(string)
    expect.expect(1, defaultValue, "string", "nil")
    expect.expect(2, nTimerTime, "number", "nil")

    if ((nTimerTime == nil) or (nTimerTime < 0)) then nTimerTime = 3 end -- Якщо користувач не вказав максимальний час, то він дорівнює значенню за замовчуванням

    local nTimerId = os.startTimer(nTimerTime)--запускаємо таймер на 3 секунди і зберігаємо його ID
    while true do
        local sEventName, eventArgs = os.pullEvent()
        if ((sEventName == "timer") and (eventArgs == nTimerId) and (defaultValue ~= nil)) then -- Якщо таймер уже вийшов і є значення за замовчуванням
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

-- Функція отримання двох найменшої і найбільшої точки області
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
	local i = 1 -- Лічильник циклу
	local h = 0 -- Лічильник відносної висоти
	
    -- Визначаємо наші координати
	local xPos, _, zPos = gps.locate(1)
	if xPos == nil then return nil, "I can't find gps!!!(start)" end -- Якщо не змогли визначити місцезнаходження
    -- Пробуємо рухатись вперед
	while not turtle.forward() do -- Якщо черепашка не змогла рухатись вперед, то ...
        if allowDig then -- якщо є дозвіл, то копаємо перед собою блок
            turtle.dig()
        else
            if math.fmod(i, 4) == 0 then -- Якщо ми пробували пройти вперед уже 4 рази, то ..
                i = 1 -- "обнуляємо" лічильник
                if turtle.up() then -- Якщо ми зможемо піднятись вгору, то..
                    h = h + 1
                elseif turtle.down() then -- Якщо ми не змогли піднятись вгору, але можемо вниз, то ..
                    h = h - 1
                else -- Ми не змогли нікуди повернутись, помилка
                    return nil, "I can't move anywhere!!"
                end
            else -- Якщо ще не повернулись 4 рази, то ..
                turtle.turnRight()
                i = i + 1
            end
        end
	end
	
    -- Визначаємо нове місцезнаходження
	local xRel, _, zRel = gps.locate(1)
	if xRel == nil then return nil, "I can't find gps!!!(final)" end -- Якщо не змогли визначити місцезнаходження
	
    -- "Обнуляємо" набрану позицію
	if not turtle.back() then return nil, "I can't move back!!" end -- Повертаємось назад, оскільки рухались вперед
	while h ~= 0 do -- Якщо ми рухались по вертикалі, то пробуємо обнулити набрану висоту
		if h < 0 then 
			if not turtle.up() then return nil, "I can't move up!!"
			else h = h + 1 end
		elseif h > 0 then
			if not turtle.down() then return nil, "I can't move down!!"
			else h = h - 1 end
		end
	end
	
    -- Повертаємо напрямок
	local vDir = vector.new(xRel, 0, zRel) - vector.new(xPos, 0, zPos)
	return vDir:normalize(), nil
end

-- Функція встановлення напрямку черепахи
function tFunctionLists.setTurtleDirection(vDirection, vDirToDest) --> newDirection(vector), nil | dontChangeDirection(vector), errorMsg(string) -- No change position
    expect.expect(1, vDirection, "table")
    expect.expect(2, vDirToDest, "table")
    if not turtle then return vDirection, "Error: requires a Turtle" end -- Якщо функцією користується не "черепашка"

    if not vDirection:equals(vDirToDest) then -- Якщо ми дивимось не в правильному напрямку, то крутимо "черепашку" в правильний напрямок
        if (vDirection:cross(vDirToDest)).y < 0 then -- Якщо вектор дивиться вниз, то повертаємо вправо
            vDirection = tFunctionLists.goTurtleRight(vDirection)
        elseif (vDirection:cross(vDirToDest)).y > 0 then -- Якщо вектор дивиться вгору, то повертаємо вліво
            vDirection = tFunctionLists.goTurtleLeft(vDirection)
        else -- Інакше, якщо вектор нульовий, і ми дивимось не в той бік, то потрібно повернутися на 180
            vDirection = tFunctionLists.goTurtleRight(vDirection)
            vDirection = tFunctionLists.goTurtleRight(vDirection)
        end
    end

    return vDirection, nil
end

-- Функція повороту праворуч
function tFunctionLists.goTurtleRight(vDirection) --> NowDirection(vector), nil | dontChangeDirection(vector), errorMsg(string)
    expect.expect(1, vDirection, "table")
    if not turtle then return vDirection, "Error: requires a Turtle" end -- Якщо функцією користується не "черепашка"
    if turtle.turnRight() then return vDirection:cross(vector.new(0, 1, 0)), nil
    else return vDirection, "Can't turn right" end
end

-- Функція повороту ліворуч
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
    if vDirToDest.y > 0 then -- Якщо потрібно рухатись вгору
        if not turtle.up() then if allowDig then turtle.digUp() end end --Якщо не вдалось пройти вгору, то якщо є дозвіл на копання, то копаємо вгору
    elseif vDirToDest.y < 0 then -- Якщо потрібно рухатись вниз
        if not turtle.down() then if allowDig then turtle.digDown() end end --Якщо не вдалось пройти вниз, то якщо є дозвіл на копання, то копаємо вниз
    else
        if math.abs(vDirToDest.x) == math.abs(vDirToDest.z) then vDirToDest.z = 0 end -- якщо потрібно рухатись по діагоналі, то пріоритетом є вісь X
        vDirection = tFunctionLists.setTurtleDirection(vDirection, vDirToDest) -- крутимо "черепашку" в правильний напрямок
        if not turtle.forward() then if allowDig then turtle.dig() end end --Якщо не вдалось пройти вперед, то якщо є дозвіл на копання, то копаємо вперед
    end

    return vDirection, nil
end

-- Функція пошуку шляху до вказаних координат
function tFunctionLists.goToGPS(vDestPos, vDirection, allowDig, fFuncAftMove) -- fFuncAftMove(vDirection) return vDirection end --> NowDirection(vector), nil | dontChangeDirection(vector), errorMsg(string)
    expect.expect(1, vDestPos, "table")
    expect.expect(2, vDirection, "table", "nil")
    expect.expect(3, allowDig, "boolean", "nil")
    expect.expect(4, fFuncAftMove, "function", "nil")
    if not turtle then return vDirection, "Error: requires a Turtle" end -- Якщо функцією користується не "черепашка"

    if (vDirection == nil) then --Якщо не надано напрямок руху, то ...
        local vDir, isError = tFunctionLists.getTurtleDirection(allowDig) -- пробуємо знайти цей напрямок
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

        vDirection = tFunctionLists.goInDirection(vDirection, vDirToDest, allowDig) -- Рухаємось у відповідну сторону
        if fFuncAftMove ~= nil then vDirection = fFuncAftMove(vDirection) end -- Якщо є функція, то запустимо її
    end
end

print("#Name: ServicePrograms.lua# || #Version: 2.7.0#\n")
return tFunctionLists -- Повертає таблицю, в якій знаходяться функції