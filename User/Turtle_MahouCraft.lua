if not turtle then
    printError("Requires a Turtle")
    return
end

if not turtle.craft then
    print("Requires a Crafty Turtle")
    return
end

local inputChest = peripheral.wrap("front")
local outputChest = peripheral.wrap("bottom")
local tArgs = { ... }
if tArgs[1] == nil then tArgs[1] = "1" end  --TODO: Встановлення значення за замовчуванням, якщо користувач не ввів кількість крафту
local nLimit = tonumber(tArgs[1])

print("#Version: 1.2.6# || #Name: TestTurtle.lua#\n")

print("Craft count at once: " .. tostring(nLimit))
if nLimit > 0 and nLimit <= 8 then
    if tArgs[2] == nil then tArgs[2] = "minecraft:oak_log" end --TODO: Встановлення значення за замовчуванням, якщо користувач не ввів тип дерева
    if inputChest ~= nil then
        if outputChest ~= nil then
            -- Очищення інвентаря черепахи
            for i = 1, 16 do
                turtle.select(i)
                turtle.dropUp()
            end

            while true do
                sleep(0.2)
                local outChestCount = 0
                outChestCount = 0
                for _, _ in pairs(outputChest.list()) do outChestCount = outChestCount + 1 end
                if (outputChest.size() - outChestCount >= 2 * nLimit) then -- Якщо в вихідному сундуку є місце для предметів, то ...
                    -- Початок процесу крафту
                    turtle.select(1)
                    local itemToCraft = 0
                    repeat
                        nLimit = 1 --TODO: Визначення кількості предметів для крафту
                        local isEmpty = 0
                        for _, _ in pairs(inputChest.list()) do isEmpty = isEmpty + 1 end -- Перевіряємо, чи є предмети у вхідному сундуку
                        if isEmpty == 0 then -- Якщо сундук порожній
                            if itemToCraft > 0 then nLimit = itemToCraft print("\nCraft count at now: " .. tostring(itemToCraft)) -- Якщо вже були предмети, продовжуємо
                            else print("InputChest is empty") return "InputChest is empty" end -- Якщо ні, виводимо помилку
                        end
                        turtle.suck(1) -- Беремо предмет із вхідного сундука
                        itemToCraft = itemToCraft + 1
                        local collectItem = turtle.getItemDetail().name
                        if collectItem ~= tArgs[2] then turtle.dropUp() itemToCraft = itemToCraft - 1 end -- Відкидаємо зайві предмети
                    until collectItem == tArgs[2] and itemToCraft >= nLimit  -- Повторюємо, поки не наберемо потрібну кількість потрібного ресурсу

                    -- Виконуємо крафт
                    turtle.craft(nLimit) -- Крафтимо 4 * nLimit предметів
                    turtle.transferTo(2, 3 * nLimit) -- Переміщуємо 3 * nLimit предметів у слот 2
                    turtle.transferTo(6, 1 * nLimit) -- Переміщуємо 1 * nLimit предметів у слот 6
                    turtle.craft(nLimit) -- Крафтимо ще 4 * nLimit предметів
                    turtle.transferTo(6, 2 * nLimit) -- Переміщуємо 2 * nLimit предметів у слот 6
                    turtle.transferTo(10, 2 * nLimit) -- Переміщуємо 2 * nLimit предметів у слот 10
                    turtle.craft(2 * nLimit) -- Крафтимо 2 * nLimit фінальних предметів

                    -- Переміщення предметів у вихідний сундук
                    for i = 1, (2 * nLimit) do
                        turtle.select(i)
                        turtle.dropDown()
                    end
                    turtle.select(1)
                end
            end
        else printError("No output chest under the turtle") end
    else printError("No input chest on front of turtle") end
else print('Usage:\n - count to craft (0 < NUM <= 8)\n - [WoodTypeTOCraft](default:"minecraft:oak_log")') end
