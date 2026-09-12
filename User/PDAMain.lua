local tArgs = {...}
local sMode = tArgs[1] -- nil чи "" = меню додатків; "app" = виконати конкретний додаток (другий аргумент — його назва)
local sAppName = tArgs[2]

local fService = require("ServicePrograms")

-- Внутрішній сигнал зупинки власних підпрограм (вкладок multishell), окремий від зовнішнього монітор-
-- протоколу. Лише головне меню говорить із зовнішнім монітором — якщо кожна вкладка відповідала б йому
-- самостійно, зовнішній монітор зарахував би зупинку, щойно відповіла перша-ліпша, а не всі.
local function checkPDAStop() --> bShouldStop(boolean)
	local bGot = false
	local nTimerId = os.startTimer(0)
	repeat
		local sEvent = os.pullEvent()
		if sEvent == "pda_stop_signal" then bGot = true end
	until bGot or (sEvent == "timer")
	if bGot then os.queueEvent("pda_stop_ack") end
	return bGot
end

-- Функція зупинки для checkMonitorCommand — викликається лише в головному меню. Розсилає внутрішній сигнал
-- усім власним вкладкам (multishell.getCount() - 1, бо одна з них — саме це меню), чекає підтвердження від
-- кожної до 10 секунд; хто не встиг — вважається завислою, як і в зовнішньому протоколі. Для зовнішнього
-- монітора байдуже, чи це головна програма, чи підпрограма — це розмежування суто внутрішнє, тут.
local function stopPDA() --> isOk(boolean), errorMsg(string)|nil
	if multishell == nil then return true end
	local nSubApps = multishell.getCount() - 1
	if nSubApps <= 0 then return true end

	os.queueEvent("pda_stop_signal")
	local nAcked = 0
	local nTimerId = os.startTimer(10)
	while nAcked < nSubApps do
		local sEvent = os.pullEvent()
		if sEvent == "pda_stop_ack" then nAcked = nAcked + 1
		elseif sEvent == "timer" then break end
	end
	return true
end

-- ==================== Func for Monitor ====================

-- Пінгує мережу і за nTimeout секунд збирає мітки й ID усіх, хто відповів (дедуп за міткою)
local function pingForPCs(nTimeout) --> tPCs(table) -- масив {sLabel, nId}
	local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
	if modem == nil then return {} end
	if not rednet.isOpen(peripheral.getName(modem)) then rednet.open(peripheral.getName(modem)) end
	rednet.broadcast({sType = "ping"}, fService.sMonitorProtocol)

	local tPCs, tSeen = {}, {}
	local nTimerId = os.startTimer(nTimeout)
	repeat
		local sEvent, a, b, c = os.pullEvent()
		if (sEvent == "rednet_message") and (c == fService.sMonitorProtocol) and (type(b) == "table") and (b.sType == "pong") and (not tSeen[b.sLabel]) then
			tSeen[b.sLabel] = true
			table.insert(tPCs, {sLabel = b.sLabel, nId = a})
		end
	until (sEvent == "timer") and (a == nTimerId)
	return tPCs
end

-- Шле команду sType з аргументами tArgs конкретному ПК (nId) і чекає відповідь із тим самим nReqId, до nTimeout секунд
local function sendCommand(nId, sType, tArgs, nTimeout) --> tResponse(table) | nil, sError(string) | nil
	local nReqId = os.startTimer(0) -- Лише унікальний ID запиту, не реальний таймер
	local tMsg = {sType = sType, nReqId = nReqId}
	for sKey, vValue in pairs(tArgs) do tMsg[sKey] = vValue end
	rednet.send(nId, tMsg, fService.sMonitorProtocol)

	local nTimerId = os.startTimer(nTimeout)
	while true do
		local sEvent, a, b, c = os.pullEvent()
		if (sEvent == "timer") and (a == nTimerId) then return nil, "Timeout waiting for response" end
		if (sEvent == "rednet_message") and (a == nId) and (c == fService.sMonitorProtocol) and (type(b) == "table") and (b.nReqId == nReqId) then return b end
	end
end

-- Перетворює введений текст аргументу на потрібний тип за угорською нотацією в назві: "n..." — число,
-- "b..." — логічне значення, інакше лишається рядком
local function coerceArgValue(sArgName, sRawValue) --> value(any)
	local sPrefix = sArgName:sub(1, 1)
	if sPrefix == "n" then return tonumber(sRawValue)
	elseif sPrefix == "b" then return (sRawValue == "true") or (sRawValue == "1")
	else return sRawValue end
end

-- Додаток "Monitor": пошук живих ПК мережі, вибір одного, перегляд і виконання його команд.
-- checkPDAStop — реакція на внутрішній сигнал від головного меню (не зовнішній монітор-протокол, тим
-- опікується лише меню). waitForFocus — призупиняє ввід/вивід, поки ця вкладка не в фокусі.
--
-- Команди беруться з локального монітора КПК (той, що в фоні на самому КПК, не з якогось конкретного
-- цільового ПК) — припускаємо, що всі цілі мають той самий набір команд. Якщо конкретний ПК її не
-- підтримує чи не відповів — помилка виводиться червоним і йде в журнал, решта цілей це не зупиняє.
local function runMonitorClient()
	while true do
		fService.waitForFocus()
		if checkPDAStop() then return end

		print("Pinging network...")
		local tPCs = pingForPCs(3)
		if #tPCs == 0 then print("No PCs found.") return end

		local tNames, tSelected = {}, {}
		for i, tPC in ipairs(tPCs) do
			tNames[i] = tPC.sLabel
			tSelected[i] = true
		end

		local tPicked = fService.fReadScrollMenu("Select target PCs:", tNames, tSelected)
		if tPicked == nil then return end -- Cancel

		local tTargets = {}
		for i, bSel in ipairs(tPicked) do
			if bSel then table.insert(tTargets, tPCs[i]) end
		end
		if #tTargets == 0 then print("No targets selected.")
		else
			while true do -- Цикл команд для цієї ж групи цілей
				fService.waitForFocus()
				if checkPDAStop() then return end

				local tListResp, sListErr = sendCommand(os.getComputerID(), "list_commands", {}, 5) -- Локальний монітор КПК
				if tListResp == nil then print("Error: "..sListErr) break end

				local tCmdLines = {}
				for i, tCmd in ipairs(tListResp.tCommands) do tCmdLines[i] = tCmd.sName.." - "..tCmd.sDescription end

				local nCmdChoice = fService.fReadScrollMenu("Select command for "..#tTargets.." target(s):", tCmdLines, nil)
				if nCmdChoice == nil then break end -- Назад до вибору ПК

				local tCmd = tListResp.tCommands[nCmdChoice]
				local tCmdArgs = {}
				for _, sArgName in ipairs(tCmd.tArgs) do
					write(sArgName..": ")
					tCmdArgs[sArgName] = coerceArgValue(sArgName, fService.fReadData("", 5))
				end

				for _, tTarget in ipairs(tTargets) do
					local tResult, sSendErr = sendCommand(tTarget.nId, tCmd.sName, tCmdArgs, 5)
					if tResult ~= nil then print(tTarget.sLabel..": "..textutils.serialize(tResult))
					else fService.logPrint("PDA", colors.red, true, tTarget.sLabel..": "..tostring(sSendErr)) end
				end
			end
		end
	end
end

-- ==================== End func for Monitor ====================

-- Реєстр додатків: назва → опис і функція реалізації. Новий додаток — новий запис тут, більше нічого міняти не треба
local tApps = {
	Monitor = {sDescription = "Send commands to a PC's monitor", fnRun = runMonitorClient},
}

if sMode == "app" then
	if tApps[sAppName] ~= nil then tApps[sAppName].fnRun() end
else
	print("#Name: PDAMain.lua# || #Version: 1.2.0#\n")
	while true do
		print(" - Select an app:")
		local tNames = {}
		for sName, tApp in pairs(tApps) do
			table.insert(tNames, sName)
			print(" ["..#tNames.."] "..sName.." - "..tApp.sDescription)
		end

		write("> ")
		local nChoice = tonumber(fService.fReadData("0", 5))
		fService.checkMonitorCommand(stopPDA)

		if (nChoice ~= nil) and (nChoice >= 1) and (nChoice <= #tNames) then
			if multishell ~= nil then multishell.launch({}, shell.getRunningProgram(), "app", tNames[nChoice])
			else print("multishell unavailable (requires Advanced Computer) — cannot open as a tab.") end
		end
	end
end