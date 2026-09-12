local tArgs = {...}
local sLaunchMode = tArgs[1] or ""
local sProgramPath = tArgs[2]

local fService = require("ServicePrograms")

if sProgramPath == nil then
	printError("Usage: kernel <launchMode> <programPath> [args...]")
	return
end

local tProgramArgs = {}
for i = 3, #tArgs do table.insert(tProgramArgs, tArgs[i]) end

-- Функція запуску самої user-програми. Якщо це стара, незмінена програма — вона просто виконається і вийде,
-- ніяк не реагуючи на команди монітора; для неї монітор і передбачає тайм-аут і вважає її завислою.
-- sLaunchMode — "" (звичайно, через shell.run у складі waitForAll) чи "multishell" (окремою вкладкою, для
-- програм із власним інтерфейсом, що самі керують іншими підпрограмами). Конфіг-двигун і монітор завжди
-- йдуть через waitForAll — їм вкладки не потрібні, це фонові сервіси.
local function runProgram()
	if (sLaunchMode == "multishell") and (multishell ~= nil) then
		multishell.launch({}, sProgramPath, table.unpack(tProgramArgs)) -- Повертається одразу після відкриття вкладки — waitForAll це не порушує, бо все одно далі чекає конфіг-двигун і монітор
	else
		if (sLaunchMode == "multishell") then fService.logPrint("Kernel", colors.red, true, "multishell requested but unavailable (requires Advanced Computer) — launching normally") end
		shell.run(sProgramPath, table.unpack(tProgramArgs))
	end
end

print("#Name: kernel.lua# || #Version: 1.4.0#\n")

local bOk, sErr = pcall(parallel.waitForAll, runProgram, fService.fSettingsDriver, fService.fMonitoringDriver)
if not bOk then -- Якщо будь-яка з трьох гілок впала з необробленою помилкою (не за штатною командою "стоп")
	fService.logPrint("Kernel", colors.red, true, "Fatal: " .. tostring(sErr))
	sleep(10) -- Даємо час прочитати повідомлення на екрані перед перезавантаженням
	os.reboot()
end