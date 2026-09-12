local tFunctionLists = {} -- Таблиця, в яку будуть додані функції; щоб додати, напишіть TABLE_NAME.FUNC_NAME() біля імені функції.
local expect = require "cc.expect"
local defaultFolderName = "CCEnv/"
local sMonitorProtocol = "cc-monitor" -- Назва протоколу rednet для зв'язку монітора з КПК
local journalFileName = "journal.txt" -- Файл спільного журналу логів між моніторами мережі
local nJournalLimit = 100 -- Скільки останніх записів журналу зберігати
local nAliveAnnounceIntervalMs = 5000 -- Мінімальний проміжок між проактивними alive_announce в checkMonitorCommand (мс)

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
-- bJournal — чи додатково зберегти цей рядок у спільний журнал мережі (подія до монітора, він може бути
-- в іншій паралельній гілці). Типово true (nil теж рахується як true) — вимикати явним false, коли не треба.
function tFunctionLists.logPrint(sSource, nColor, bJournal, ...) --> nil
	expect.expect(1, sSource, "string")
	expect.expect(2, nColor, "number", "nil")
	expect.expect(3, bJournal, "boolean", "nil")
	local tArgs = {...}
	for i = 1, #tArgs do tArgs[i] = tostring(tArgs[i]) end
	local sLine = table.concat(tArgs, " ")
	if term.isColor() and (nColor ~= nil) then term.setTextColor(nColor) end
	print(sSource .. " | " .. sLine)
	if term.isColor() then term.setTextColor(colors.white) end
	if bJournal ~= false then
		os.queueEvent(sMonitorProtocol, {sType = "journal", sAction = "new", tEntry = {nTime = os.epoch("utc"), sLabel = os.getComputerLabel(), sSource = sSource, sMessage = sLine}})
	end
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
                os.queueEvent("settings_driver_out", nRecvId, tSettingTable[eventTableId], nil)
            else
                os.queueEvent("settings_driver_out", nRecvId, nil, "no field")
            end
        elseif ((eventCommand == "set")) then -- Або потрібно встановити дані
            tSettingTable[eventTableId] = eventArgs
            local bErrorFlag = false -- true, якщо справді сталась помилка запису
            local sErrMsg
            local fout, _ = fs.open("/" .. defaultFolderName .. "temp" .. localSettingsList_Name, "w") -- Пробуємо відкрити файл з налаштуваннями
            if fout ~= nil then --Якщо файл відкрився
                local seriObj = textutils.serialize(tSettingTable)
                if seriObj ~= nil then
                    fout.write(seriObj)
                    fout.close()
                    shell.run("delete", "/" .. defaultFolderName .. localSettingsList_Name)
                    if not shell.run("rename", "/" .. defaultFolderName .. "temp" .. localSettingsList_Name, "/" .. defaultFolderName .. localSettingsList_Name) then
                        bErrorFlag = true
                        sErrMsg = "save error"
                    end
                else
                    fout.close()
                    bErrorFlag = true
                    sErrMsg = "serialize error"
                end
            else
                bErrorFlag = true
                sErrMsg = "cannot open temp file for writing"
            end
            os.queueEvent("settings_driver_out", nRecvId, bErrorFlag, sErrMsg)
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
function tFunctionLists.setSettings(sTableLabel, sTableValue, nDefaultTime) --> bErrorFlag(boolean), errorMsg(string) | false, nil
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
            return true, "Timer out (set)"
        elseif ((sEventName == "settings_driver_out") and (nEventID == nRequestId)) then -- Або ми отримали відповідь
            return sOperContent, sOperErr
        end
    end
    return false, 'Error: EoF'
end

-- Функція для вставки в цикл user-програми: неблокуюче перевіряє, чи прийшла команда від монітора, і заразом
-- сама проактивно повідомляє "я жива" раз на nAliveAnnounceIntervalMs — без sleep, порівнянням системного
-- часу з часом попереднього повідомлення (nLastAliveAnnounce — змінна рівня файлу, не в user-програмі, тож
-- викликати цю функцію в циклі можна одним рядком, нічого додатково не оголошуючи).
-- {sType="heartbeat_ping"} — монітор перевіряє, чи програма жива; одразу відповідаємо {sType="heartbeat_pong"}
-- і повертаємо false (це не зупинка, цикл програми триває далі як звичайно).
-- {sType="stop_request"} — монітор просить зупинитись. Шлемо {sType="stop_ack"} (отримав, починаю), викликаємо
-- fnStop (унікальну для програми функцію зупинки, яка повертає isOk(boolean), errorMsg(string)|nil), шлемо
-- {sType="stop_done"} з результатом, і повертаємо true.
-- Якщо жодної команди немає — повертає false майже миттєво, не блокуючи цикл програми.
local nLastAliveAnnounce = 0
function tFunctionLists.checkMonitorCommand(fnStop) --> bWasStopped(boolean)
    expect.expect(1, fnStop, "function")
    if (os.epoch("utc") - nLastAliveAnnounce) > nAliveAnnounceIntervalMs then
        nLastAliveAnnounce = os.epoch("utc")
        os.queueEvent(sMonitorProtocol, {sType = "alive_announce"})
    end

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

-- Функція для вставки в цикл програми, що працює у власній вкладці multishell: якщо вкладка зараз не в
-- фокусі — призупиняє виконання (не блокуючи диспетчеризацію в інших вкладках, лише цю саму гілку), поки
-- фокус не повернеться, перевіряючи це раз на секунду. Якщо multishell недоступний — нічого не робить.
function tFunctionLists.waitForFocus() --> nil
    if multishell == nil then return end
    while multishell.getFocus() ~= multishell.getCurrent() do
        sleep(1)
    end
end

-- Прокручуваний список із ручним вводом номера (не read(), щоб стрілки лишались вільними для прокрутки, а не
-- йшли в історію вводу). Довгі рядки, що переносяться на кілька рядків терміналу, враховані — прокрутка йде
-- в рядках терміналу, не в пунктах списку, щоб не стрибала нерівномірно на суміші коротких і довгих пунктів.
--
-- sHeader (може бути nil) — заголовок над органами керування, теж завжди на місці при перемальовці.
-- tItems — масив готових рядків для показу.
-- tSelected (може бути nil):
--   nil — режим одиночного вибору. Лише "[-1] Cancel". Enter на номері одразу повертає це число.
--         Повертає nSingleChoice(number) | nil (при -1).
--   масив boolean розміром #tItems (типово всі true) — режим множинного вибору. "[-1] Cancel",
--         "[-2] Confirm", "[-3] Invert selection", "[0] Select/deselect all" (перемикає всі одразу,
--         залежно від того, чи зараз усі позначені). Enter на номері перемикає позначку цього пункту.
--         Повертає tSelected(table) | nil (при -1).
--
-- ^/v — прокрутка на половину видимої висоти списку. Список коротший за екран — стрілки просто нічого
-- не роблять. Один пункт, довший за всю видиму висоту сам по собі — теоретично можливо, спеціально не
-- обробляється, просто виведеться повністю, трохи витіснивши межу видимої області за той кадр.
function tFunctionLists.fReadScrollMenu(sHeader, tItems, tSelected) --> tSelected(table) | nSingleChoice(number) | nil
    expect.expect(1, sHeader, "string", "nil")
    expect.expect(2, tItems, "table")
    expect.expect(3, tSelected, "table", "nil")

    local bMultiSelect = (tSelected ~= nil)
    local nWidth, nHeight = term.getSize()
    local tItemRows = {} -- Скільки рядків терміналу займає кожен пункт (перенесення довгих рядків)
    for i, sItem in ipairs(tItems) do
        tItemRows[i] = math.max(1, math.ceil(#sItem / nWidth))
    end
    local tHeaderLines = {} -- Заповнюється нижче, після локальних функцій; redraw() уже посилається на неї як на своє замикання
    local nListHeight
    local nScrollOffset = 0 -- В рядках терміналу, не в пунктах списку
    local sInputBuffer = ""

    -- ==================== Локальні функції ====================

    -- Додає пару органів керування одним рядком, якщо вистачає ширини екрана, інакше кожен на своєму рядку
    local function addControlPair(sLeft, sRight)
        if nWidth >= 40 then
            table.insert(tHeaderLines, sLeft .. string.rep(" ", math.max(1, 20 - #sLeft)) .. sRight)
        else
            table.insert(tHeaderLines, sLeft)
            table.insert(tHeaderLines, sRight)
        end
    end

    local function redraw()
        term.clear()
        term.setCursorPos(1, 1)
        for _, sLine in ipairs(tHeaderLines) do print(sLine) end

        local nRow, nSkipped = 0, 0
        for i, sItem in ipairs(tItems) do
            if nSkipped + tItemRows[i] > nScrollOffset then
                if nRow >= nListHeight then break end
                local sMark = bMultiSelect and (tSelected[i] and "[*] " or "[ ] ") or ""
                print(" ["..i.."] "..sMark..sItem)
                nRow = nRow + tItemRows[i]
            end
            nSkipped = nSkipped + tItemRows[i]
        end

        term.setCursorPos(1, nHeight)
        write("> "..sInputBuffer)
    end

    -- ==================== Кінець локальних функцій ====================

    if sHeader ~= nil then table.insert(tHeaderLines, sHeader) end
    if bMultiSelect then
        addControlPair("[-1] Cancel", "[-2] Confirm")
        addControlPair("[-3] Invert", "[0] Select All")
    else table.insert(tHeaderLines, "[-1] Cancel") end
    table.insert(tHeaderLines, "-")
    nListHeight = nHeight - #tHeaderLines - 1 -- -1 для рядка вводу знизу

    redraw()
    while true do
        local sEvent, a = os.pullEvent()
        if (sEvent == "key") and (a == keys.up) then
            nScrollOffset = math.max(0, nScrollOffset - math.ceil(nListHeight / 2))
            redraw()
        elseif (sEvent == "key") and (a == keys.down) then
            local nTotalRows = 0
            for _, r in ipairs(tItemRows) do nTotalRows = nTotalRows + r end
            nScrollOffset = math.min(math.max(0, nTotalRows - nListHeight), nScrollOffset + math.ceil(nListHeight / 2))
            redraw()
        elseif (sEvent == "key") and (a == keys.backspace) then
            sInputBuffer = sInputBuffer:sub(1, -2)
            redraw()
        elseif (sEvent == "key") and (a == keys.enter) then
            local nValue = tonumber(sInputBuffer)
            sInputBuffer = ""
            if nValue == -1 then return nil
            elseif bMultiSelect and (nValue == -2) then return tSelected
            elseif bMultiSelect and (nValue == -3) then
                for i = 1, #tSelected do tSelected[i] = not tSelected[i] end
            elseif bMultiSelect and (nValue == 0) then
                local bAllSelected = true
                for i = 1, #tSelected do if not tSelected[i] then bAllSelected = false break end end
                for i = 1, #tSelected do tSelected[i] = not bAllSelected end
            elseif (nValue ~= nil) and (nValue >= 1) and (nValue <= #tItems) then
                if bMultiSelect then tSelected[nValue] = not tSelected[nValue]
                else return nValue end
            end
            redraw()
        elseif (sEvent == "char") and a:match("^[%d%-]$") then
            sInputBuffer = sInputBuffer .. a
            redraw()
        end
    end
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
--   update        - те саме, що stop, для user-програми й конфіг-двигуна (спільна функція), але замість
--                    негайного перезавантаження двічі запускає "/deploy.lua" (другий прогін уже новою версією,
--                    якщо перший її оновив) і лише тоді перезавантажує. Одразу шле {sType="ack"} у відповідь
--                    і пише в журнал на початку й наприкінці — якщо запис "фінішу" не з'явився за розумний
--                    час, це і є сигнал, що щось на цьому ПК зависло (найімовірніше — сам deploy.lua чекає
--                    вводу без дефолту, бо прив'язана програма зникла з маніфесту) і треба перевірити вручну.
--   list_commands - повертає список команд, які підтримує цей ПК, напряму тому, хто запитав.
--   ping          - відповідає {sType="pong", sLabel=...} напряму запитувачу; призначено для пошуку живих
--                   ПК мережі (широкомовний ping, кожен живий відповідає своєю міткою).
--   dummyCommand  - тестова команда: через nSeconds друкує sMessage. Виконується як окрема паралельна
--                   гілка через "spawn" (дивись нижче), тому не блокує цикл диспетчеризації, поки спить.
--   journal       - спільний журнал логів між усіма моніторами мережі (останні nJournalLimit записів,
--                   відсортовані за часом). "sAction" визначає, що саме — див. чотири фази в коментарі над
--                   syncIntent нижче: sync_intent (перегони за право ініціювати), want_request/want_response
--                   (об'єднання бажаних зрізів співініціаторів), sync_request/sync_manifest (широкомовний
--                   запит і збір відповідей "у мене є стільки"), pull_request/transfer_start/transfer_done
--                   (сама передача записів по одному, через "new", з чіткими межами початку й кінця).
--                   "new" і "already_syncing" — окремо: "new" завжди означає новий запис журналу (дедуп,
--                   транслюється, лише якщо джерело локальне), "already_syncing" — відповідь запізнілому ПК.
--
-- Окремо, теж через "spawn" — вартовий цикл: раз на 10 секунд шле "heartbeat_ping" user-програмі й чекає
-- "heartbeat_pong". Не відповіла 3 рази поспіль (тобто 30 секунд без жодної відповіді) — вважаємо її
-- завислою чи завершеною без циклу (як стара програма без "checkMonitorCommand") і викликаємо ту саму
-- команду "stop", що й за зовнішнім запитом.
--
-- Ще одна спавн-гілка — syncIntent: запускається одразу при старті, і повторно, коли після чужого
-- sync_request з'ясовується наявність прогалини у власному журналі.
function tFunctionLists.fMonitoringDriver(spawn) --> funcStatus(boolean), returnMsg(string)
    local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
    local bNetworked = (modem ~= nil)
    if bNetworked then
        rednet.open(peripheral.getName(modem))
        rednet.host(sMonitorProtocol, os.getComputerLabel())
    end

    -- Спільний стан для tCommands і всіх spawn-гілок нижче
    local tCommands -- Наперед оголошено, бо посилається сама на себе (list_commands) і на неї посилаються spawn-гілки
    local tJournal = {} -- Масив записів журналу {nTime, sLabel, sSource, sMessage}, відсортований за nTime
    local nLatestIntentTime = 0 -- Час (os.epoch) останнього побаченого наміру синхронізації журналу, від будь-кого
    local bTransferInProgress = false -- Глобально: чи триває зараз реальна передача журналу. Змінює лише той, хто передає дані за pull_request
    local bDeferToOtherInitiator = false -- true, якщо надійшло want_request або already_syncing: раунд координується кимось іншим, лише очікування його завершення
    local bIsRoundInitiator = false -- true після перемоги в перегонах цього раунду — координація фаз 2-4
    local tRoundSnapshot = nil -- Під час координації головним ініціатором: об'єднаний (мінімум по кожній мітці) бажаний зріз
    local tChosenProvider = {nMissingCount = -1, nSenderId = nil} -- Найбагатша відповідь на sync_request у поточному раунді
    local nInitiatorId = nil -- ID головного ініціатора поточного раунду (відомий лише після відповіді на want_request) — для перевірки живучості

    -- ==================== Локальні функції ====================

    local function saveJournal()
        local sPath = "/" .. defaultFolderName .. journalFileName
        local fout = fs.open(sPath .. ".tmp", "w")
        if fout == nil then return end
        fout.write(textutils.serialize(tJournal))
        fout.close()
        fs.delete(sPath)
        fs.move(sPath .. ".tmp", sPath)
    end

    local function buildSnapshot() --> tSnapshot(table) -- По кожній мітці ПК — час найновішого наявного запису
        local tSnapshot = {}
        for i = 1, #tJournal do
            local e = tJournal[i]
            if (tSnapshot[e.sLabel] == nil) or (e.nTime > tSnapshot[e.sLabel]) then tSnapshot[e.sLabel] = e.nTime end
        end
        return tSnapshot
    end

    -- Додає запис, якщо його ще нема (дедуп за парою nTime+sLabel), сортує, обрізає до nJournalLimit, зберігає.
    -- bBroadcast — чи розсилати цей запис мережею: true лише для власних щойно створених записів. Ender-модем
    -- має необмежену досяжність, тому все, хто міг почути оригінальну розсилку, вже почув — ретранслювати
    -- отримане з мережі не потрібно.
    local function mergeEntry(tEntry, bBroadcast) --> bWasNew(boolean)
        for i = 1, #tJournal do
            if (tJournal[i].nTime == tEntry.nTime) and (tJournal[i].sLabel == tEntry.sLabel) then return false end
        end
        table.insert(tJournal, tEntry)
        table.sort(tJournal, function(a, b) return a.nTime < b.nTime end)
        while #tJournal > nJournalLimit do table.remove(tJournal, 1) end
        saveJournal()
        if bBroadcast and bNetworked then rednet.broadcast({sType = "journal", sAction = "new", tEntry = tEntry}, sMonitorProtocol) end
        return true
    end

    -- Перегони намірів синхронізації та, у разі перемоги, координація раунду.
    -- Фаза 1 (перегони): випадкова пауза 1-2с, оголошення наміру, вікно тиші 5с. Хтось новіший заявив намір
    -- за цей час — повтор циклу. Ніхто не заявився — перехід до ролі головного ініціатора і фази 2.
    -- Фаза 2 (опитування співініціаторів): широкомовний "want_request", коротке вікно 2с на відповіді —
    -- кожен, хто теж хотів синхронізуватись, надсилає свій зріз журналу; об'єднання через мінімум по кожній
    -- мітці (для покриття найглибшої прогалини серед усіх, хто хотів синхронізуватись, а не лише власної).
    -- Фаза 3 (широкомовний запит): sync_request з об'єднаним зрізом на всю мережу, 4с на маніфести-відповіді,
    -- вибір того, хто має строго найбільше.
    -- Фаза 4 (запит даних): pull_request обраному; сама передача — в обробнику pull_request, окремою гілкою.
    -- Поки координація (фази 2-4) ще триває, а не сама передача (bTransferInProgress ще false) — той, хто
    -- поставлений на паузу чужим раундом, раз на ~5с перевіряє, чи головний ініціатор ще живий (ping/pong).
    -- Немає відповіді — ініціатор вважається зниклим, повернення до власних перегонів (фаза 1), як після рестарту.
    -- Щойно bTransferInProgress стає true, ця перевірка вже не потрібна — роль головного ініціатора виконана,
    -- далі все тримається на постачальнику даних, і цикл нижче просто чекає завершення передачі.
    local function syncIntent()
        while not bTransferInProgress do
            if bDeferToOtherInitiator then
                if (nInitiatorId ~= nil) and bNetworked then
                    rednet.send(nInitiatorId, {sType = "journal", sAction = "initiator_ping"}, sMonitorProtocol)
                    local bGotPong = waitForEvent(2, function(t) return (t[1] == sMonitorProtocol) and (type(t[2]) == "table") and (t[2].sType == "initiator_pong") end)
                    if not bGotPong then
                        bDeferToOtherInitiator = false -- Головний ініціатор не відповідає — повернення до власних перегонів
                        nInitiatorId = nil
                    end
                end
                sleep(5)
            else
                sleep(1 + math.random())
                if bTransferInProgress or bDeferToOtherInitiator then break end

                local nMyTime = os.epoch("utc")
                nLatestIntentTime = nMyTime
                if bNetworked then rednet.broadcast({sType = "journal", sAction = "sync_intent", sLabel = os.getComputerLabel()}, sMonitorProtocol) end

                sleep(5)
                if bTransferInProgress or bDeferToOtherInitiator then break end
                if nLatestIntentTime <= nMyTime then -- Ніхто новіший не заявив про намір за ці 5 секунд — перехід до ролі головного ініціатора
                    bIsRoundInitiator = true
                    tRoundSnapshot = buildSnapshot()
                    if bNetworked then rednet.broadcast({sType = "journal", sAction = "want_request", sLabel = os.getComputerLabel()}, sMonitorProtocol) end
                    sleep(2) -- Коротке вікно: відповіді співініціаторів локальні й майже миттєві

                    tChosenProvider = {nMissingCount = -1, nSenderId = nil}
                    if bNetworked then rednet.broadcast({sType = "journal", sAction = "sync_request", sLabel = os.getComputerLabel(), tSnapshot = tRoundSnapshot}, sMonitorProtocol) end
                    sleep(4) -- Вікно збору маніфестів

                    if (tChosenProvider.nSenderId ~= nil) and bNetworked then
                        rednet.send(tChosenProvider.nSenderId, {sType = "journal", sAction = "pull_request", sLabel = os.getComputerLabel(), tSnapshot = tRoundSnapshot}, sMonitorProtocol)
                    end
                    break
                end
                -- Інакше хтось новіший заявив намір — цикл почнеться знову з нової випадкової паузи
            end
        end

        if bDeferToOtherInitiator or bIsRoundInitiator then -- Ми долучились до якогось раунду — чекаємо, поки він реально завершиться
            while not bTransferInProgress do sleep(0.5) end
            while bTransferInProgress do sleep(0.5) end
        end
    end

    -- Спільна для "stop" і "update": зупиняє user-програму (до 10с на stop_ack, ще до 10с на stop_done,
    -- інакше вважає завислою і йде далі), потім конфіг-двигун (так само, до 5с на кожен крок). Не займає
    -- монітор і нічого не робить після зупинки — це вирішує вже кожна команда сама.
    local function stopUserProgramAndConfig()
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
    end

    -- ==================== Кінець локальних функцій ====================

    do -- Завантажуємо журнал з диска (якщо ПК перезавантажувався)
        local fin = fs.open("/" .. defaultFolderName .. journalFileName, "r")
        if fin ~= nil then
            local tLoaded = textutils.unserialize(fin.readAll())
            fin.close()
            if tLoaded ~= nil then tJournal = tLoaded end
        end
    end

    spawn(syncIntent)

    tCommands = {
        stop = {
            sDescription = "Stop the user program and config engine, then reboot the PC",
            tArgs = {},
            fnHandler = function(tMsg, nSenderId)
                stopUserProgramAndConfig()
                if bNetworked then rednet.broadcast({sStatus = "stopped", sLabel = os.getComputerLabel()}, sMonitorProtocol) end
                os.reboot()
            end
        },
        update = {
            sDescription = "Stop everything, run /deploy.lua twice (in case deploy.lua itself changes on the first run), then reboot",
            tArgs = {},
            fnHandler = function(tMsg, nSenderId)
                if bNetworked and (nSenderId ~= nil) then rednet.send(nSenderId, {sType = "ack", nReqId = tMsg.nReqId}, sMonitorProtocol) end -- Негайне підтвердження, до початку довгої операції
                tFunctionLists.logPrint("Monitor", colors.cyan, true, "Update requested, stopping and running deploy.lua")
                spawn(function() -- Окрема гілка — довга операція не має блокувати диспетчеризацію інших команд
                    stopUserProgramAndConfig()
                    shell.run("/deploy.lua")
                    shell.run("/deploy.lua") -- Другий прогін — уже новим deploy.lua з диска, якщо перший прогін його оновив
                    tFunctionLists.logPrint("Monitor", colors.cyan, true, "Update finished, rebooting")
                    if bNetworked then rednet.broadcast({sStatus = "updated", sLabel = os.getComputerLabel()}, sMonitorProtocol) end
                    os.reboot()
                end)
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
        ping = {
            sDescription = "Reply with this PC's label (used to discover live PCs on the network)",
            tArgs = {},
            fnHandler = function(tMsg, nSenderId)
                if bNetworked and (nSenderId ~= nil) then rednet.send(nSenderId, {sType = "pong", sLabel = os.getComputerLabel()}, sMonitorProtocol) end
            end
        },
        dummyCommand = {
            sDescription = "Test command: prints sMessage after nSeconds",
            tArgs = {"nSeconds", "sMessage"},
            fnHandler = function(tMsg, nSenderId)
                spawn(function() -- Окрема паралельна гілка, тому sleep тут не блокує цикл диспетчеризації нижче
                    sleep(tMsg.nSeconds)
                    tFunctionLists.logPrint("Dummy", colors.yellow, false, tMsg.sMessage)
                end)
            end
        },
        journal = {
            sDescription = "Shared log between all monitors on the network (sAction: new, sync_intent, want_request, want_response, already_syncing, sync_request, sync_manifest, pull_request, transfer_start, transfer_done, initiator_ping, initiator_pong)",
            tArgs = {"sAction", "..."},
            fnHandler = function(tMsg, nSenderId)
                if tMsg.sAction == "new" then -- Новий запис журналу: дедуп і збереження завжди; ретрансляція лише за локального походження
                    mergeEntry(tMsg.tEntry, nSenderId == nil) -- nSenderId == nil означає локальне джерело (виклик logPrint на цьому ПК) — ретрансляція лише в цьому випадку
                elseif tMsg.sAction == "sync_intent" then -- Оголошення наміру синхронізуватись (локальне чи мережеве)
                    nLatestIntentTime = os.epoch("utc") -- Перегони побачать це на наступній перевірці
                    if (bIsRoundInitiator or bDeferToOtherInitiator) and bNetworked and (tMsg.sLabel ~= os.getComputerLabel()) then
                        rednet.send(nSenderId, {sType = "journal", sAction = "already_syncing"}, sMonitorProtocol) -- Запізніле оголошення — цей раунд уже координується (будь-ким з учасників, не лише головним)
                    end
                elseif tMsg.sAction == "already_syncing" then -- Повідомлення про раунд, що вже координується кимось іншим — власні перегони припиняються
                    bDeferToOtherInitiator = true
                elseif tMsg.sAction == "want_request" then -- Запит головного ініціатора на бажаний зріз журналу
                    bDeferToOtherInitiator = true -- Перегони вже виграні кимось іншим — власна ініціація припиняється
                    nInitiatorId = nSenderId -- Ідентифікатор для подальшої перевірки живучості, поки координація триває
                    if bNetworked and (tMsg.sLabel ~= os.getComputerLabel()) then
                        rednet.send(nSenderId, {sType = "journal", sAction = "want_response", tSnapshot = buildSnapshot()}, sMonitorProtocol)
                    end
                elseif tMsg.sAction == "want_response" then -- Відповідь співініціатора на want_request — об'єднання з уже зібраними даними
                    if tRoundSnapshot ~= nil then -- Об'єднання через мінімум по кожній мітці — покриття найглибшої прогалини серед усіх
                        for sLabel, nTime in pairs(tMsg.tSnapshot) do
                            if (tRoundSnapshot[sLabel] == nil) or (nTime < tRoundSnapshot[sLabel]) then tRoundSnapshot[sLabel] = nTime end
                        end
                    end
                elseif tMsg.sAction == "sync_request" then -- Широкомовний запит з об'єднаним зрізом: порівняння журналу зі зрізом, відповідь кількістю зайвих записів, перевірка власної прогалини
                    local tMissing = {}
                    for i = 1, #tJournal do
                        local e = tJournal[i]
                        local nTheirLatest = tMsg.tSnapshot[e.sLabel]
                        if (nTheirLatest == nil) or (e.nTime > nTheirLatest) then table.insert(tMissing, {nTime = e.nTime, sLabel = e.sLabel}) end
                    end
                    if (#tMissing > 0) and bNetworked then
                        rednet.broadcast({sType = "journal", sAction = "sync_manifest", nMissingCount = #tMissing}, sMonitorProtocol) -- Бродкаст, а не напряму — щоб і решта мережі бачила, в кого чого бракує
                    end
                    local tMySnapshot = buildSnapshot()
                    local bIHaveGap = false
                    for sLabel, nTheirTime in pairs(tMsg.tSnapshot) do
                        if (tMySnapshot[sLabel] == nil) or (nTheirTime > tMySnapshot[sLabel]) then bIHaveGap = true break end
                    end
                    if bIHaveGap and not (bDeferToOtherInitiator or bIsRoundInitiator or bTransferInProgress) then spawn(syncIntent) end -- Виявлена власна прогалина за відсутності участі в іншому раунді — запуск нового раунду
                elseif tMsg.sAction == "sync_manifest" then -- Відповідь на sync_request із кількістю зайвих записів — запис, якщо це поки найбільше значення
                    if (tMsg.nMissingCount ~= nil) and (tMsg.nMissingCount > tChosenProvider.nMissingCount) then
                        tChosenProvider = {nMissingCount = tMsg.nMissingCount, nSenderId = nSenderId}
                    end
                elseif (tMsg.sAction == "pull_request") and bNetworked then -- Запит на передачу журналу — надсилання запитаного діапазону окремою паралельною гілкою
                    local tSnapshot = tMsg.tSnapshot
                    spawn(function() -- Окрема гілка — сама передача не має блокувати диспетчеризацію інших команд
                        rednet.broadcast({sType = "journal", sAction = "transfer_start"}, sMonitorProtocol)
                        local tSentMarks = {}
                        for i = 1, #tJournal do
                            local e = tJournal[i]
                            local nTheirLatest = tSnapshot[e.sLabel]
                            if (nTheirLatest == nil) or (e.nTime > nTheirLatest) then
                                rednet.broadcast({sType = "journal", sAction = "new", tEntry = e}, sMonitorProtocol) -- Той самий канал "new" — кожен, хто ще не має, збереже собі, дедуп сам відсіє дублікати
                                table.insert(tSentMarks, {nTime = e.nTime, sLabel = e.sLabel})
                            end
                        end
                        rednet.broadcast({sType = "journal", sAction = "transfer_done", tSentMarks = tSentMarks}, sMonitorProtocol)
                    end)
                elseif tMsg.sAction == "transfer_start" then -- Початок передачі журналу постачальником — глобальний стан змінюється лише тут
                    bTransferInProgress = true
                elseif tMsg.sAction == "transfer_done" then -- Завершення передачі журналу постачальником — повне завершення раунду і скидання стану
                    bTransferInProgress = false
                    bDeferToOtherInitiator = false
                    bIsRoundInitiator = false
                    nInitiatorId = nil
                elseif (tMsg.sAction == "initiator_ping") and bIsRoundInitiator and bNetworked then -- Перевірка живучості головного ініціатора
                    rednet.send(nSenderId, {sType = "journal", sAction = "initiator_pong"}, sMonitorProtocol)
                elseif tMsg.sAction == "initiator_pong" then -- Відповідь на initiator_ping; сама перевірка відбувається окремим очікуванням у syncIntent, обробки тут не потребує
                end
            end
        },
    }

    spawn(function() -- Вартовий цикл heartbeat — окрема паралельна гілка, не блокує диспетчеризацію нижче
        local nMissed = 0
        while true do
            sleep(10)
            local nReqId = os.startTimer(0) -- Використовуємо лише як унікальний ID запиту, не як реальний таймер
            os.queueEvent(sMonitorProtocol, {sType = "heartbeat_ping", nReqId = nReqId})
            local bAlive = waitForEvent(10, function(t) -- Зараховується або відповідь саме на цей пінг, або проактивний alive_announce від checkMonitorCommand
                if (t[1] ~= sMonitorProtocol) or (type(t[2]) ~= "table") then return false end
                return ((t[2].sType == "heartbeat_pong") and (t[2].nReqId == nReqId)) or (t[2].sType == "alive_announce")
            end)
            if bAlive then
                nMissed = 0
            else
                nMissed = nMissed + 1
                tFunctionLists.logPrint("Monitor", colors.orange, false, "User program did not respond to heartbeat (" .. nMissed .. "/3)") -- Проміжні промахи не варті журналу — лише останній, значущий випадок
                if nMissed >= 3 then
                    tFunctionLists.logPrint("Monitor", colors.red, true, "User program appears unresponsive, stopping")
                    tCommands.stop.fnHandler({}, nil) -- Та сама команда "stop", що й за зовнішнім запитом; вона й перезавантажить ПК
                end
            end
        end
    end)

    while true do
        local sEventName, a, b, c = os.pullEvent()
        if bNetworked and (sEventName == "rednet_message") and (c == sMonitorProtocol) and (type(b) == "table") and (tCommands[b.sType] ~= nil) then
            tCommands[b.sType].fnHandler(b, a) -- b = саме повідомлення, a = ID відправника
        elseif (sEventName == sMonitorProtocol) and (type(a) == "table") and (tCommands[a.sType] ~= nil) then
            tCommands[a.sType].fnHandler(a, nil) -- Локальна подія (для тестування) — немає мережевого відправника, щоб відповідати
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

print("#Name: ServicePrograms.lua# || #Version: 2.17.0#\n")
tFunctionLists.sMonitorProtocol = sMonitorProtocol -- Назва протоколу rednet монітора, для програм, що самі спілкуються мережею (наприклад, КПК)
return tFunctionLists -- Повертає таблицю, в якій знаходяться функції