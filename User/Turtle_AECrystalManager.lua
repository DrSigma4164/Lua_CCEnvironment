if not turtle then
    printError("Error: requires a Turtle")
end

local fService = require("ServicePrograms")
local pickaxePeri = peripheral.wrap("right")
local tArgs = { ... }

print("#Version: 1.1.1# || #Name: Turtle_AECrystalManager.lua#\n")

if #tArgs >= 6 then
    if tArgs[7] == "nil" then tArgs[2] = nil end
    if pickaxePeri ~= nil  then -- Якщо в правій руці немає кірки
        --- Йдемо на початкову точку, яка вказана в стартапі
        --TODO: зробити локальні файли конфігів, і перемістити параметри зі стартапу туди і додати перший запуск.
        local vDir = fService.goToGPS(vector.new(tArgs[1], tArgs[2], tArgs[3]), nil, false, nil) -- йдемо на стартову позицію
        vDir = fService.setTurtleDirection(vDir, vector.new(tArgs[4], tArgs[5], tArgs[6])) -- розвертаємося в правильну сторону

        --- Операції з сховищем навпроти
        if tArgs[7] == nil then tArgs[7] = "ae2:flawed_budding_quartz" end
        for i = 1, 16 do -- Чистимо інвентар черепашки
            turtle.select(i)
            turtle.drop()
        end


        while true do -- Операції
            turtle.select(16)
            if turtle.getItemDetail() == nil then -- Якщо в 16 слоті немає потрібного предмету, то ...
                turtle.suck(1) -- Пробуємо взяти предмет зі сховища
                if turtle.getItemDetail().name ~= tArgs[7] then printError("The corresponding item in the front chest, namely:" .. tArgs[7]) else
                    sleep(16) os.reboot() -- Якщо в сундуці немає предмета, то чекаємо 16 сек і перезапускаємось
                end
            end





        end
        else printError("No pickaxe in right hand")
        end
    else
    print('Usage:\n - x, y, z - Coordinate start\n - x, y, z - Direction after moving\n - [CrystalBudding](default when \"nil\": "ae2:flawed_budding_quartz")')
end