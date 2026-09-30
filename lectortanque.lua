-- ============================================================
-- LECTOR DE DEPOSITO MULTI-ID / MULTI-GRUPO
-- Advanced Peripherals + CC:Tweaked
--
-- Cada deposito tiene:
--   group_id
--   tank_id
--
-- Varios surtidores pueden apuntar al mismo deposito.
-- Solo uno puede bloquearlo/repostar a la vez.
-- ============================================================

local CONFIG_FILE = "/tanque.cfg"
local ADMIN_PIN = "2050"
local NETWORK_VERSION = "fuelnet1"

local defaults = {
    group_id = "GRUPO1",
    tank_id = "T" .. tostring(os.getComputerID()),

    -- "auto" o nombre exacto del periferico
    tank_peripheral = "auto",

    -- Si un surtidor desaparece sin liberar el deposito,
    -- el bloqueo caduca automaticamente.
    lock_timeout = 30.0,
}

local cfg = {}

local tank = nil
local tankName = nil

local lockOwner = nil
local lockComputerID = nil
local lockLastSeen = 0

local lastData = nil
local hostError = nil

-- ============================================================
-- TERMINAL
-- ============================================================

local function hasColor()
    return term.isColor()
end

local function resetColors()
    if hasColor() then
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
    end
end

local function clear()
    resetColors()
    term.clear()
    term.setCursorPos(1, 1)
end

local function writeAt(x, y, text, fg, bg)
    local w, h = term.getSize()

    if y < 1 or y > h or x > w then return end
    if x < 1 then x = 1 end

    text = tostring(text or "")
    if #text > (w - x + 1) then
        text = text:sub(1, w - x + 1)
    end

    if hasColor() then
        if bg then term.setBackgroundColor(bg) end
        if fg then term.setTextColor(fg) end
    end

    term.setCursorPos(x, y)
    term.write(text)
    resetColors()
end

local function centerText(y, text, fg, bg)
    local w = select(1, term.getSize())
    text = tostring(text or "")

    local x = math.floor((w - #text) / 2) + 1
    if x < 1 then x = 1 end

    writeAt(x, y, text, fg, bg)
end

local function fillLine(y, bg)
    local w = select(1, term.getSize())

    if hasColor() then term.setBackgroundColor(bg) end

    term.setCursorPos(1, y)
    term.write(string.rep(" ", w))
    resetColors()
end

-- ============================================================
-- IDENTIDAD / RED
-- ============================================================

local function cleanID(value)
    value = tostring(value or "")
    value = value:gsub("^%s+", ""):gsub("%s+$", "")

    if value == "" then return "SIN_ID" end
    return value
end

local function networkSafe(value)
    value = cleanID(value):lower()
    value = value:gsub("[^%w_%-]", "_")
    return value
end

local function protocolName()
    return "fuelnet_" .. networkSafe(cfg.group_id)
end

local function hostname()
    return "tank_" ..
        networkSafe(cfg.group_id) .. "_" ..
        networkSafe(cfg.tank_id)
end

-- ============================================================
-- CONFIG
-- ============================================================

local function copyDefaults()
    cfg = {}
    for k, v in pairs(defaults) do cfg[k] = v end
end

local function saveConfig()
    local f = fs.open(CONFIG_FILE, "w")
    if not f then error("No se pudo guardar " .. CONFIG_FILE) end

    f.write(textutils.serialize(cfg))
    f.close()
end

local function loadConfig()
    copyDefaults()

    if fs.exists(CONFIG_FILE) then
        local f = fs.open(CONFIG_FILE, "r")

        if f then
            local data = textutils.unserialize(f.readAll())
            f.close()

            if type(data) == "table" then
                for k, v in pairs(data) do
                    if defaults[k] ~= nil then cfg[k] = v end
                end
            end
        end
    end

    cfg.group_id = cleanID(cfg.group_id)
    cfg.tank_id = cleanID(cfg.tank_id)

    saveConfig()
end

-- ============================================================
-- MODEM
-- ============================================================

local function openModems()
    for _, name in ipairs(peripheral.getNames()) do
        local types = {peripheral.getType(name)}

        for _, t in ipairs(types) do
            if t == "modem" then
                pcall(rednet.open, name)
            end
        end
    end
end

-- ============================================================
-- DEPOSITO
-- ============================================================

local function hasMethod(obj, method)
    return obj and type(obj[method]) == "function"
end

local function findTank()
    tank = nil
    tankName = nil

    if cfg.tank_peripheral ~= "" and
       cfg.tank_peripheral ~= "auto" then

        local p = peripheral.wrap(cfg.tank_peripheral)

        if p and (
            hasMethod(p, "info") or
            hasMethod(p, "getInfo") or
            hasMethod(p, "tanks")
        ) then
            tank = p
            tankName = peripheral.getName(p)
            return true
        end

        return false
    end

    local foundName = nil

    local p = peripheral.find(
        "fluid_tank",
        function(name)
            foundName = name
            return true
        end
    )

    if p then
        tank = p
        tankName = foundName or peripheral.getName(p)
        return true
    end

    p = peripheral.find(
        "fluidTank",
        function(name)
            foundName = name
            return true
        end
    )

    if p then
        tank = p
        tankName = foundName or peripheral.getName(p)
        return true
    end

    for _, name in ipairs(peripheral.getNames()) do
        local obj = peripheral.wrap(name)

        if obj and (
            hasMethod(obj, "getInfo") or
            hasMethod(obj, "tanks")
        ) then
            tank = obj
            tankName = name
            return true
        end
    end

    return false
end

local function fluidName(fluid)
    if type(fluid) == "string" then return fluid end
    if type(fluid) ~= "table" then return "vacio" end

    return fluid.name or
           fluid.id or
           fluid.registryName or
           fluid.displayName or
           "desconocido"
end

local function fluidAmount(fluid)
    if type(fluid) ~= "table" then return 0 end

    return tonumber(
        fluid.amount or
        fluid.count or
        fluid.quantity or
        0
    ) or 0
end

local function readTank()
    if not tank and not findTank() then
        return nil, "No encuentro el deposito/periferico"
    end

    if hasMethod(tank, "info") then
        local ok, info = pcall(tank.info)

        if not ok or type(info) ~= "table" then
            return nil, "Fallo tank.info()"
        end

        local amount = 0
        local name = "vacio"

        if info.fluid ~= nil then
            amount = fluidAmount(info.fluid)
            name = fluidName(info.fluid)
        end

        if amount == 0 and tonumber(info.amount) then
            amount = tonumber(info.amount)
        end

        return {
            amount = amount,
            capacity = tonumber(info.capacity or 0) or 0,
            fluid = name,
            peripheral = tankName,
        }
    end

    if hasMethod(tank, "getInfo") then
        local ok, info = pcall(tank.getInfo)

        if not ok or type(info) ~= "table" then
            return nil, "Fallo tank.getInfo()"
        end

        return {
            amount = tonumber(info.amount or 0) or 0,
            capacity = tonumber(info.capacity or 0) or 0,
            fluid = fluidName(info.fluid),
            peripheral = tankName,
        }
    end

    if hasMethod(tank, "tanks") then
        local ok, tanks = pcall(tank.tanks)

        if not ok or type(tanks) ~= "table" then
            return nil, "Fallo tank.tanks()"
        end

        local amount = 0
        local capacity = 0
        local name = "vacio"

        for _, entry in pairs(tanks) do
            if type(entry) == "table" then
                amount = amount +
                    (tonumber(entry.amount or entry.count or 0) or 0)

                capacity = capacity +
                    (tonumber(entry.capacity or 0) or 0)

                if name == "vacio" and (entry.name or entry.id) then
                    name = entry.name or entry.id
                end
            end
        end

        return {
            amount = amount,
            capacity = capacity,
            fluid = name,
            peripheral = tankName,
        }
    end

    tank = nil
    tankName = nil

    return nil, "API del deposito no reconocida"
end

-- ============================================================
-- HOST REDNET
-- ============================================================

local hostedProtocol = nil

local function registerHost()
    hostError = nil

    if hostedProtocol then
        pcall(rednet.unhost, hostedProtocol)
        hostedProtocol = nil
    end

    local protocol = protocolName()

    local ok, err = pcall(
        rednet.host,
        protocol,
        hostname()
    )

    if ok then
        hostedProtocol = protocol
    else
        hostError = tostring(err)
    end

    return ok
end

-- ============================================================
-- BLOQUEO
-- ============================================================

local function clearLock()
    lockOwner = nil
    lockComputerID = nil
    lockLastSeen = 0
end

local function lockExpired()
    if not lockOwner then return false end
    return (os.clock() - lockLastSeen) > cfg.lock_timeout
end

local function refreshLock()
    if lockExpired() then clearLock() end
end

local function isOwner(sender, stationID)
    refreshLock()

    return lockOwner ~= nil and
           sender == lockComputerID and
           cleanID(stationID) == cleanID(lockOwner)
end

-- ============================================================
-- UI
-- ============================================================

local function drawStatus(message)
    local _, h = term.getSize()

    clear()

    if hasColor() then
        fillLine(1, colors.blue)
        centerText(1, "LECTOR DEPOSITO", colors.white, colors.blue)
    else
        centerText(1, "LECTOR DEPOSITO")
    end

    centerText(2, cleanID(cfg.group_id) .. " / " .. cleanID(cfg.tank_id))

    writeAt(2, 4, "Host:")
    writeAt(9, 4, hostname())

    writeAt(2, 5, "Tanque:")
    writeAt(10, 5, tostring(tankName or "NO DETECTADO"))

    writeAt(2, 7, "Estado:")

    if lockOwner then
        writeAt(10, 7, "OCUPADO", colors.yellow)
        writeAt(2, 8, "Surtidor:")
        writeAt(12, 8, tostring(lockOwner))
    else
        writeAt(10, 7, "LIBRE", colors.lime)
    end

    if lastData then
        writeAt(2, 10, "Cantidad:")
        writeAt(13, 10, tostring(lastData.amount) .. " mB")

        writeAt(2, 11, "Capacidad:")
        writeAt(13, 11, tostring(lastData.capacity) .. " mB")

        writeAt(2, 12, "Fluido:")
        writeAt(11, 12, tostring(lastData.fluid))
    end

    if hostError then
        writeAt(2, h - 3, "HOST ERROR:", colors.red)
        writeAt(2, h - 2, hostError, colors.red)
    elseif message then
        writeAt(2, h - 2, tostring(message))
    end
end

-- ============================================================
-- ADMIN
-- ============================================================

local function promptText(title, current)
    clear()
    centerText(1, title)

    print("")
    print("Actual:")
    print(tostring(current))
    print("")
    write("> ")

    local value = read()
    if value == "" then return current end
    return value
end

local function promptNumber(title, current, minimum)
    local text = promptText(title, current)
    if tostring(text) == tostring(current) then return current end

    local number = tonumber(text)

    if not number or (minimum and number < minimum) then
        clear()
        centerText(5, "VALOR INVALIDO", colors.red)
        sleep(1)
        return current
    end

    return number
end

local function adminOptions()
    return {
        {
            label="Grupo",
            value=function() return cfg.group_id end,
            edit=function()
                cfg.group_id = cleanID(promptText("ID DEL GRUPO", cfg.group_id))
            end
        },

        {
            label="ID deposito",
            value=function() return cfg.tank_id end,
            edit=function()
                cfg.tank_id = cleanID(promptText("ID DEL DEPOSITO", cfg.tank_id))
            end
        },

        {
            label="Periferico",
            value=function() return cfg.tank_peripheral end,
            edit=function()
                cfg.tank_peripheral = promptText(
                    "Periferico o auto",
                    cfg.tank_peripheral
                )
                findTank()
            end
        },

        {
            label="Timeout bloqueo",
            value=function() return cfg.lock_timeout end,
            edit=function()
                cfg.lock_timeout = promptNumber(
                    "Timeout bloqueo",
                    cfg.lock_timeout,
                    5
                )
            end
        },

        {
            label="Buscar deposito",
            value=function() return "EJECUTAR" end,
            edit=function()
                cfg.tank_peripheral = "auto"
                findTank()
                drawStatus(
                    tankName and
                    ("Detectado: " .. tostring(tankName)) or
                    "No encontrado"
                )
                sleep(1.5)
            end
        },

        {
            label="Liberar bloqueo",
            value=function() return lockOwner or "LIBRE" end,
            edit=clearLock
        },

        {
            label="GUARDAR Y SALIR",
            value=function() return "" end,
            exit=true
        }
    }
end

local function drawAdmin(selected, firstVisible)
    local options = adminOptions()
    local w, h = term.getSize()
    local visible = math.max(4, h - 6)

    clear()

    if hasColor() then
        fillLine(1, colors.blue)
        centerText(1, "CONFIG DEPOSITO", colors.white, colors.blue)
    else
        centerText(1, "CONFIG DEPOSITO")
    end

    centerText(2, "FLECHAS + ENTER")

    local last = math.min(#options, firstVisible + visible - 1)
    local y = 4

    for i = firstVisible, last do
        local option = options[i]
        local prefix = i == selected and "> " or "  "
        local value = tostring(option.value())

        local text = option.exit
            and (prefix .. option.label)
            or (prefix .. option.label .. ": " .. value)

        if #text > w then text = text:sub(1, w) end

        local fg, bg = colors.white, colors.black

        if i == selected and hasColor() then
            fg, bg = colors.black, colors.lightGray
            fillLine(y, bg)
        end

        writeAt(1, y, text, fg, bg)
        y = y + 1
    end

    if firstVisible > 1 then
        writeAt(w, 3, "^", colors.yellow)
    end

    if last < #options then
        writeAt(w, h - 1, "v", colors.yellow)
    end

    centerText(h, "BACKSPACE = GUARDAR/SALIR", colors.lightGray)
    return visible
end

local function adminMenu()
    clear()
    centerText(2, "ACCESO RESTRINGIDO")
    centerText(4, "Introduce codigo")
    term.setCursorPos(2, 6)
    write("PIN: ")

    if read("*") ~= ADMIN_PIN then
        clear()
        centerText(5, "CODIGO INCORRECTO", colors.red)
        sleep(1.5)
        return
    end

    local selected = 1
    local firstVisible = 1

    while true do
        local options = adminOptions()
        local visible = drawAdmin(selected, firstVisible)

        local event, a = os.pullEvent()

        if event == "key" then
            if a == keys.up then
                selected = selected - 1
                if selected < 1 then selected = #options end

            elseif a == keys.down then
                selected = selected + 1
                if selected > #options then selected = 1 end

            elseif a == keys.enter then
                local option = options[selected]

                if option.exit then
                    saveConfig()
                    findTank()
                    clearLock()
                    registerHost()
                    return
                end

                if option.edit then
                    option.edit()
                    saveConfig()
                end

            elseif a == keys.backspace then
                saveConfig()
                findTank()
                clearLock()
                registerHost()
                return
            end

        elseif event == "mouse_scroll" then
            if a > 0 then
                selected = math.min(#options, selected + 1)
            else
                selected = math.max(1, selected - 1)
            end
        end

        if selected < firstVisible then firstVisible = selected end

        if selected >= firstVisible + visible then
            firstVisible = selected - visible + 1
        end

        if selected == 1 then firstVisible = 1 end
    end
end

-- ============================================================
-- FUELNET
-- ============================================================

local function validPacket(message)
    return type(message) == "table" and
           message.system == NETWORK_VERSION and
           cleanID(message.group_id) == cleanID(cfg.group_id) and
           cleanID(message.tank_id) == cleanID(cfg.tank_id)
end

local function reply(target, data)
    data = data or {}

    data.system = NETWORK_VERSION
    data.group_id = cleanID(cfg.group_id)
    data.tank_id = cleanID(cfg.tank_id)

    rednet.send(
        target,
        data,
        protocolName()
    )
end

local function handleMessage(sender, message)
    if not validPacket(message) then return end

    refreshLock()

    local command = message.command
    local stationID = cleanID(message.station_id)

    if command == "begin" then
        if not lockOwner or isOwner(sender, stationID) then
            lockOwner = stationID
            lockComputerID = sender
            lockLastSeen = os.clock()

            reply(sender, {
                ok=true,
                owner=lockOwner
            })

            drawStatus("Sesion iniciada")
        else
            reply(sender, {
                ok=false,
                error="BUSY",
                owner=lockOwner
            })
        end

    elseif command == "read" then
        if lockOwner and not isOwner(sender, stationID) then
            reply(sender, {
                ok=false,
                error="BUSY",
                owner=lockOwner
            })
            return
        end

        if lockOwner then
            lockLastSeen = os.clock()
        end

        local data, err = readTank()

        if data then
            lastData = data

            reply(sender, {
                ok=true,
                amount=data.amount,
                capacity=data.capacity,
                fluid=data.fluid,
                peripheral=data.peripheral,
                owner=lockOwner
            })

            drawStatus("Lectura para " .. stationID)
        else
            reply(sender, {
                ok=false,
                error=err
            })

            drawStatus("ERROR: " .. tostring(err))
        end

    elseif command == "end" then
        if not lockOwner or isOwner(sender, stationID) then
            clearLock()

            reply(sender, {
                ok=true
            })

            drawStatus("Deposito liberado")
        else
            reply(sender, {
                ok=false,
                error="NOT_OWNER",
                owner=lockOwner
            })
        end
    end
end

-- ============================================================
-- MAIN
-- ============================================================

local function main()
    loadConfig()
    openModems()

    if not rednet.isOpen() then
        error("No hay modem conectado")
    end

    findTank()
    registerHost()
    drawStatus("Esperando surtidores...")

    local timer = os.startTimer(1)

    while true do
        local event, a, b, c = os.pullEvent()

        if event == "key" and a == keys.c then
            adminMenu()
            drawStatus("Esperando surtidores...")

        elseif event == "rednet_message" and c == protocolName() then
            handleMessage(a, b)

        elseif event == "timer" and a == timer then
            local wasLocked = lockOwner ~= nil

            refreshLock()

            if wasLocked and not lockOwner then
                drawStatus("Bloqueo caducado")
            end

            timer = os.startTimer(1)
        end
    end
end

local ok, err = pcall(main)

if not ok then
    clear()

    if hasColor() then term.setTextColor(colors.red) end
    print("ERROR FATAL DEL LECTOR")
    resetColors()

    print("")
    print(tostring(err))
end
