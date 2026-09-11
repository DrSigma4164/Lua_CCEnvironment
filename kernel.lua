local tArgs = {...}
local sProgramPath = tArgs[1]

local fService = require("ServicePrograms")

if sProgramPath == nil then
	printError("Usage: kernel <programPath> [args...]")
	return
end

local tProgramArgs = {}
for i = 2, #tArgs do table.insert(tProgramArgs, tArgs[i]) end

-- Функція запуску самої user-програми. Якщо це стара, незмінена програма — вона просто виконається і вийде,
-- ніяк не реагуючи на команди монітора; для неї монітор і передбачає тайм-аут і вважає її завислою.
local function runProgram()
	shell.run(sProgramPath, table.unpack(tProgramArgs))
end

print("#Name: kernel.lua# || #Version: 1.0.0#\n")

local bOk, sErr = pcall(parallel.waitForAll, runProgram, fService.fSettingsDriver, fService.fMonitoringDriver)
if not bOk then -- Якщо будь-яка з трьох гілок впала з необробленою помилкою (не за штатною командою "стоп")
	fService.logPrint("Kernel", colors.red, "Fatal: " .. tostring(sErr))
	os.reboot()
end