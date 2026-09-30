-- ============================================================
-- SURTIDOR MULTI-ID / MULTI-GRUPO
-- CC:Tweaked + Lightman's Currency
--
-- 1 FuelToken = 1 Netherite Coin
-- Item: lightmanscurrency:coin_netherite
--
-- Cliente:
--   F / click = iniciar o parar
--
-- Administracion:
--   acceso oculto
--   PIN: 2050
--   flechas = navegar
--   ENTER = editar
--   BACKSPACE = guardar y salir
--
-- Red FuelNet:
--   Grupo + ID surtidor + ID deposito
-- ============================================================

local CONFIG_FILE = "/surtidor.cfg"
local ADMIN_PIN = "2050"
local NETWORK_VERSION = "fuelnet1"
local NETHERITE_COIN_ID = "lightmanscurrency:coin_netherite"

local defaults = {
    station_name = "SURTIDOR",
    out_of_service = false,

    -- Identidad de red
    group_id = "GRUPO1",
    station_id = "S" .. tostring(os.getComputerID()),
    tank_id = "T1",

    token_name = "FuelToken",
    token_item_id = NETHERITE_COIN_ID,
    mb_per_token = 1000,

    payment_side = "right",
    storage_side = "bottom",

    open_side = "back",
    close_side = "left",
    pulse_time = 0.15,

    sample_time = 0.20,
    no_flow_limit = 8,
    flow_epsilon_mb = 1,
    flow_grace_time = 1.0,

    tank_timeout = 2.0,
    change_retry_time = 0.5,
}

local cfg = {}
local tankComputerID = nil

local payment, storage = nil, nil
local paymentName, storageName = nil, nil

local buttonBounds = {x1=1, x2=1, y1=1, y2=1}

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

local function tankHostname()
    return "tank_" ..
        networkSafe(cfg.group_id) .. "_" ..
        networkSafe(cfg.tank_id)
end

-- ============================================================
-- CONFIGURACION
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
                if data.coin_id then cfg.token_item_id = data.coin_id end
                if data.currency_name then cfg.token_name = data.currency_name end
                if data.mb_per_coin then cfg.mb_per_token = data.mb_per_coin end

                for k, v in pairs(data) do
                    if defaults[k] ~= nil then cfg[k] = v end
                end
            end
        end
    end

    cfg.group_id = cleanID(cfg.group_id)
    cfg.station_id = cleanID(cfg.station_id)
    cfg.tank_id = cleanID(cfg.tank_id)

    if cfg.token_item_id == "" or cfg.token_item_id == "CAMBIAR_ESTO" then
        cfg.token_item_id = NETHERITE_COIN_ID
    end

    if cfg.token_name == "" or cfg.token_name == "monedas" then
        cfg.token_name = "FuelToken"
    end

    saveConfig()
end

-- ============================================================
-- MODEM / INVENTARIOS
-- ============================================================

local function openModems()
    for _, name in ipairs(peripheral.getNames()) do
        local types = {peripheral.getType(name)}
        for _, t in ipairs(types) do
            if t == "modem" then pcall(rednet.open, name) end
        end
    end
end

local function refreshInventories()
    payment = peripheral.wrap(cfg.payment_side)
    storage = peripheral.wrap(cfg.storage_side)

    paymentName = payment and peripheral.getName(payment) or nil
    storageName = storage and peripheral.getName(storage) or nil

    if payment and
       (type(payment.list) ~= "function" or
        type(payment.pushItems) ~= "function") then
        payment, paymentName = nil, nil
    end

    if storage and
       (type(storage.list) ~= "function" or
        type(storage.pushItems) ~= "function") then
        storage, storageName = nil, nil
    end
end

-- ============================================================
-- MONEDAS
-- ============================================================

local function normalizeItemID(value)
    if type(value) ~= "string" then return "" end
    return value:gsub("^%s+", ""):gsub("%s+$", ""):lower()
end

local function isFuelToken(item)
    if type(item) ~= "table" then return false end

    local id = normalizeItemID(item.name)
    if id == normalizeItemID(cfg.token_item_id) then return true end
    return id == NETHERITE_COIN_ID
end

local function autoRepairTokenID()
    if not payment then return end

    for _, item in pairs(payment.list()) do
        if normalizeItemID(item.name) == NETHERITE_COIN_ID then
            if normalizeItemID(cfg.token_item_id) ~= NETHERITE_COIN_ID then
                cfg.token_item_id = NETHERITE_COIN_ID
                cfg.token_name = "FuelToken"
                saveConfig()
            end
            return
        end
    end
end

local function countTokens(inv)
    if not inv then return 0 end

    local total = 0
    for _, item in pairs(inv.list()) do
        if isFuelToken(item) then
            total = total + item.count
        end
    end
    return total
end

local function countInvalidItems()
    if not payment then return 0 end

    local total = 0
    for _, item in pairs(payment.list()) do
        if not isFuelToken(item) then
            total = total + item.count
        end
    end
    return total
end

local function moveTokens(source, destinationName, amount)
    if not source or not destinationName or amount <= 0 then return 0 end

    local moved = 0

    for slot, item in pairs(source.list()) do
        if isFuelToken(item) then
            local remaining = amount - moved
            if remaining <= 0 then break end

            local wanted = math.min(item.count, remaining)
            local ok, quantity = pcall(
                source.pushItems,
                destinationName,
                slot,
                wanted
            )

            if not ok then return moved end
            moved = moved + (quantity or 0)
        end
    end

    return moved
end

local function reserveCredit(amount)
    refreshInventories()

    if not payment or not storage then return false end

    local moved = moveTokens(payment, storageName, amount)
    if moved == amount then return true end

    if moved > 0 then
        moveTokens(storage, paymentName, moved)
    end

    return false
end

local function returnChange(amount)
    refreshInventories()
    if not payment or not storage then return 0 end
    return moveTokens(storage, paymentName, amount)
end

-- ============================================================
-- VALVULA
-- ============================================================

local function pulse(side)
    redstone.setOutput(side, true)
    sleep(cfg.pulse_time)
    redstone.setOutput(side, false)
end

local function openValve()
    pulse(cfg.open_side)
end

local function closeValve()
    pulse(cfg.close_side)
end

-- ============================================================
-- INTERFAZ
-- ============================================================

local function drawButton(running, enabled)
    local w, h = term.getSize()

    local label = running and " [ F ]  PARAR " or " [ F ]  COMENZAR "
    local x = math.floor((w - #label) / 2) + 1
    local y = h - 1

    buttonBounds = {
        x1=x,
        x2=x + #label - 1,
        y1=y,
        y2=y
    }

    local bg = colors.gray
    if hasColor() then
        if running then
            bg = colors.red
        elseif enabled then
            bg = colors.green
        end
    end

    writeAt(x, y, label, colors.white, bg)
end

local function buttonClicked(x, y)
    return x >= buttonBounds.x1 and
           x <= buttonBounds.x2 and
           y >= buttonBounds.y1 and
           y <= buttonBounds.y2
end

local function drawOutOfService()
    local _, h = term.getSize()
    clear()

    if hasColor() then
        fillLine(1, colors.red)
        centerText(1, cfg.station_name, colors.white, colors.red)
    else
        centerText(1, cfg.station_name)
    end

    centerText(math.floor(h / 2) - 1, "FUERA DE SERVICIO", colors.red)
    centerText(math.floor(h / 2) + 1, "Disculpe las molestias")
end

local function drawMain(state)
    state = state or {}

    if cfg.out_of_service then
        drawOutOfService()
        return
    end

    local w, h = term.getSize()
    clear()

    if hasColor() then
        fillLine(1, colors.blue)
        centerText(1, cfg.station_name, colors.white, colors.blue)
    else
        centerText(1, cfg.station_name)
    end

    centerText(2, cleanID(cfg.station_id) .. " | " .. cleanID(cfg.group_id))

    local status = state.status or "ESPERANDO"
    local statusColor = colors.white

    if hasColor() then
        if state.running then
            statusColor = colors.lime
        elseif status:find("ERROR") or status:find("OCUPADO") then
            statusColor = colors.red
        elseif status == "LISTO" then
            statusColor = colors.yellow
        end
    end

    centerText(3, status, statusColor)

    local credit = state.credit or 0
    local served = state.served or 0
    local cost = state.cost or 0
    local remaining = math.max(0, credit - cost)

    writeAt(2, 5, "CREDITO")
    writeAt(16, 5, tostring(credit) .. " FT", colors.yellow)

    writeAt(2, 6, "SUMINISTRADO")
    writeAt(16, 6, tostring(served) .. " mB", colors.cyan)

    writeAt(2, 7, "COSTE")
    writeAt(16, 7, tostring(cost) .. " FT", colors.orange)

    writeAt(2, 8, "RESTANTE")
    writeAt(16, 8, tostring(remaining) .. " FT", colors.lime)

    if state.tankAmount ~= nil then
        writeAt(2, 10, "DEPOSITO " .. cleanID(cfg.tank_id))

        local text = tostring(state.tankAmount) .. " mB"
        if state.tankCapacity and state.tankCapacity > 0 then
            text = text .. "/" .. tostring(state.tankCapacity)
        end

        writeAt(16, 10, text)
    end

    writeAt(2, 12, "PRECIO")
    writeAt(10, 12, "1 FT = " .. tostring(cfg.mb_per_token) .. " mB")

    if state.message then
        local msg = tostring(state.message)
        local maxLen = math.max(1, w - 4)

        writeAt(2, h - 4, msg:sub(1, maxLen))
        if #msg > maxLen then
            writeAt(2, h - 3, msg:sub(maxLen + 1, maxLen * 2))
        end
    end

    drawButton(state.running == true, credit > 0)
end

-- ============================================================
-- ADMIN
-- ============================================================

local validSides = {
    left=true, right=true, top=true,
    bottom=true, front=true, back=true
}

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

local function promptSide(title, current)
    local value = promptText(title, current):lower()
    if validSides[value] then return value end

    clear()
    print("Lado invalido.")
    print("left/right/top/bottom/front/back")
    sleep(2)
    return current
end

local function diagnosticCoins()
    refreshInventories()
    clear()

    print("DIAGNOSTICO MONEDAS")
    print("-------------------")
    print("")

    if not payment then
        print("No encuentro barril.")
    else
        local found = false

        for slot, item in pairs(payment.list()) do
            found = true
            print("Slot " .. tostring(slot))
            print(tostring(item.count) .. "x " .. tostring(item.name))
            print(isFuelToken(item) and "FUELTOKEN VALIDO" or "NO VALIDO")
            print("")
        end

        if not found then print("Barril vacio.") end
    end

    print("")
    print("Pulsa una tecla...")
    os.pullEvent("key")
end

local function adminOptions()
    return {
        {
            label="Estado surtidor",
            value=function()
                return cfg.out_of_service and "FUERA DE SERVICIO" or "OPERATIVO"
            end,
            edit=function()
                cfg.out_of_service = not cfg.out_of_service
                if cfg.out_of_service then closeValve() end
            end
        },

        {
            label="Grupo",
            value=function() return cfg.group_id end,
            edit=function()
                cfg.group_id = cleanID(promptText("ID DEL GRUPO", cfg.group_id))
                tankComputerID = nil
            end
        },

        {
            label="ID surtidor",
            value=function() return cfg.station_id end,
            edit=function()
                cfg.station_id = cleanID(promptText("ID DEL SURTIDOR", cfg.station_id))
            end
        },

        {
            label="ID deposito",
            value=function() return cfg.tank_id end,
            edit=function()
                cfg.tank_id = cleanID(promptText("ID DEL DEPOSITO", cfg.tank_id))
                tankComputerID = nil
            end
        },

        {
            label="Nombre surtidor",
            value=function() return cfg.station_name end,
            edit=function()
                cfg.station_name = promptText("Nombre surtidor", cfg.station_name)
            end
        },

        {
            label="mB por FuelToken",
            value=function() return cfg.mb_per_token end,
            edit=function()
                cfg.mb_per_token = promptNumber("mB por FuelToken", cfg.mb_per_token, 1)
            end
        },

        {
            label="Barril pago",
            value=function() return cfg.payment_side end,
            edit=function()
                cfg.payment_side = promptSide("Barril pago", cfg.payment_side)
            end
        },

        {
            label="Barril almacen",
            value=function() return cfg.storage_side end,
            edit=function()
                cfg.storage_side = promptSide("Barril almacen", cfg.storage_side)
            end
        },

        {
            label="Abrir valvula",
            value=function() return cfg.open_side end,
            edit=function()
                cfg.open_side = promptSide("Abrir valvula", cfg.open_side)
            end
        },

        {
            label="Cerrar valvula",
            value=function() return cfg.close_side end,
            edit=function()
                cfg.close_side = promptSide("Cerrar valvula", cfg.close_side)
            end
        },

        {
            label="Tiempo pulso",
            value=function() return cfg.pulse_time end,
            edit=function()
                cfg.pulse_time = promptNumber("Tiempo pulso", cfg.pulse_time, 0.05)
            end
        },

        {
            label="Intervalo lectura",
            value=function() return cfg.sample_time end,
            edit=function()
                cfg.sample_time = promptNumber("Intervalo lectura", cfg.sample_time, 0.05)
            end
        },

        {
            label="Lecturas sin flujo",
            value=function() return cfg.no_flow_limit end,
            edit=function()
                cfg.no_flow_limit = math.floor(
                    promptNumber("Lecturas sin flujo", cfg.no_flow_limit, 1)
                )
            end
        },

        {
            label="Tolerancia mB",
            value=function() return cfg.flow_epsilon_mb end,
            edit=function()
                cfg.flow_epsilon_mb = promptNumber(
                    "Tolerancia mB",
                    cfg.flow_epsilon_mb,
                    0
                )
            end
        },

        {
            label="Gracia inicial",
            value=function() return cfg.flow_grace_time end,
            edit=function()
                cfg.flow_grace_time = promptNumber(
                    "Gracia inicial",
                    cfg.flow_grace_time,
                    0
                )
            end
        },

        {
            label="Timeout deposito",
            value=function() return cfg.tank_timeout end,
            edit=function()
                cfg.tank_timeout = promptNumber(
                    "Timeout deposito",
                    cfg.tank_timeout,
                    0.2
                )
            end
        },

        {
            label="Diagnostico monedas",
            value=function() return "ABRIR" end,
            edit=diagnosticCoins
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
        centerText(1, "CONFIGURACION", colors.white, colors.blue)
    else
        centerText(1, "CONFIGURACION")
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

            elseif a == keys.pageUp then
                selected = math.max(1, selected - visible)

            elseif a == keys.pageDown then
                selected = math.min(#options, selected + visible)

            elseif a == keys.enter then
                local option = options[selected]

                if option.exit then
                    saveConfig()
                    refreshInventories()
                    autoRepairTokenID()
                    tankComputerID = nil
                    return
                end

                if option.edit then
                    option.edit()
                    saveConfig()
                end

            elseif a == keys.backspace then
                saveConfig()
                refreshInventories()
                autoRepairTokenID()
                tankComputerID = nil
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

local function makePacket(command)
    return {
        system = NETWORK_VERSION,
        command = command,
        group_id = cleanID(cfg.group_id),
        station_id = cleanID(cfg.station_id),
        tank_id = cleanID(cfg.tank_id),
    }
end

local function findTankComputer()
    tankComputerID = rednet.lookup(
        protocolName(),
        tankHostname()
    )

    return tankComputerID ~= nil
end

local function isStopInput(event, a, b, c)
    if event == "key" and a == keys.f then return true end

    if event == "mouse_click" and buttonClicked(b, c) then
        return true
    end

    return false
end

local function tankRequest(command, waitReply, allowStop)
    if not tankComputerID and not findTankComputer() then
        return nil, "DEPOSITO_NO_ENCONTRADO"
    end

    rednet.send(
        tankComputerID,
        makePacket(command),
        protocolName()
    )

    if not waitReply then return true end

    local timer = os.startTimer(cfg.tank_timeout)

    while true do
        local event, a, b, c = os.pullEvent()

        if event == "rednet_message" then
            if a == tankComputerID and c == protocolName() then
                if type(b) == "table" and
                   b.system == NETWORK_VERSION and
                   cleanID(b.group_id) == cleanID(cfg.group_id) and
                   cleanID(b.tank_id) == cleanID(cfg.tank_id) then
                    return b
                end
            end

        elseif event == "timer" and a == timer then
            tankComputerID = nil
            return nil, "TIMEOUT"

        elseif allowStop and isStopInput(event, a, b, c) then
            return nil, "USER_STOP"
        end
    end
end

local function beginTankSession()
    local reply, err = tankRequest("begin", true, false)

    if not reply then return false, err end

    if reply.ok == false then
        if reply.error == "BUSY" then
            return false, "BUSY:" .. tostring(reply.owner or "?")
        end

        return false, reply.error or "ERROR_DEPOSITO"
    end

    return true
end

local function endTankSession()
    tankRequest("end", false, false)
end

local function readTank(allowStop)
    local reply, err = tankRequest("read", true, allowStop)

    if not reply then return nil, err end

    if reply.ok == false then
        if reply.error == "BUSY" then
            return nil, "BUSY:" .. tostring(reply.owner or "?")
        end

        return nil, reply.error or "ERROR_DEPOSITO"
    end

    if type(reply.amount) ~= "number" then
        return nil, "BAD_AMOUNT"
    end

    return reply
end

-- ============================================================
-- CAMBIO / REPOSTAJE
-- ============================================================

local function finishChange(amount)
    local pending = amount

    while pending > 0 do
        local returned = returnChange(pending)
        pending = pending - returned

        if pending > 0 then
            drawMain({
                status="CAMBIO PENDIENTE",
                credit=0,
                served=0,
                cost=0,
                message="Libera espacio en el barril derecho."
            })

            sleep(cfg.change_retry_time)
        end
    end
end

local function waitForSampleOrStop()
    local timer = os.startTimer(cfg.sample_time)

    while true do
        local event, a, b, c = os.pullEvent()

        if event == "timer" and a == timer then
            return "sample"
        end

        if isStopInput(event, a, b, c) then
            return "stop"
        end
    end
end

local function refuel(credit)
    if cfg.out_of_service then
        closeValve()
        return
    end

    closeValve()

    -- Reserva exclusiva del deposito.
    local locked, lockError = beginTankSession()

    if not locked then
        local message = tostring(lockError)

        if message:sub(1, 5) == "BUSY:" then
            message = "Usado por " .. message:sub(6)
        end

        drawMain({
            status="DEPOSITO OCUPADO",
            credit=credit,
            message=message
        })

        sleep(2.5)
        return
    end

    -- Solo cogemos las monedas cuando el deposito ya es nuestro.
    if not reserveCredit(credit) then
        endTankSession()

        drawMain({
            status="ERROR PAGO",
            credit=credit,
            message="No puedo mover las monedas."
        })

        sleep(3)
        return
    end

    local first, firstError = readTank(true)

    if firstError == "USER_STOP" then
        closeValve()
        endTankSession()
        finishChange(credit)
        return
    end

    if not first then
        closeValve()
        endTankSession()
        finishChange(credit)

        drawMain({
            status="ERROR DEPOSITO",
            message=tostring(firstError)
        })

        sleep(3)
        return
    end

    local initial = first.amount
    local previous = initial
    local lowest = initial
    local capacity = first.capacity or 0
    local noFlow = 0
    local maxFuel = credit * cfg.mb_per_token
    local reason = "FINALIZADO"
    local startedAt = os.clock()

    drawMain({
        status="REPOSTANDO",
        credit=credit,
        served=0,
        cost=0,
        tankAmount=initial,
        tankCapacity=capacity,
        running=true,
        message="F o boton para detener."
    })

    openValve()

    while true do
        if waitForSampleOrStop() == "stop" then
            reason = "PARADO"
            break
        end

        local data, readError = readTank(true)

        if readError == "USER_STOP" then
            reason = "PARADO"
            break
        end

        if not data then
            reason = "ERROR COMUNICACION"
            break
        end

        local current = data.amount
        capacity = data.capacity or capacity

        -- Se cobra exactamente la bajada del deposito de gasolina.
        if current > previous + cfg.flow_epsilon_mb then
            reason = "DEPOSITO RELLENANDOSE"
            break
        end

        if current < lowest then lowest = current end

        local served = math.max(0, initial - lowest)
        local cost = math.ceil(served / cfg.mb_per_token)

        if cost > credit then cost = credit end

        drawMain({
            status="REPOSTANDO",
            credit=credit,
            served=served,
            cost=cost,
            tankAmount=current,
            tankCapacity=capacity,
            running=true,
            message="F o boton para detener."
        })

        if served >= maxFuel then
            reason = "CREDITO AGOTADO"
            break
        end

        if current <= 0 then
            reason = "DEPOSITO VACIO"
            break
        end

        local difference = previous - current
        local elapsed = os.clock() - startedAt

        if elapsed >= cfg.flow_grace_time then
            if difference > cfg.flow_epsilon_mb then
                noFlow = 0
            else
                noFlow = noFlow + 1
            end
        end

        if noFlow >= cfg.no_flow_limit then
            reason = "REPOSTAJE COMPLETADO"
            break
        end

        previous = current
    end

    closeValve()

    local final = readTank(false)

    if final and final.amount < lowest then
        lowest = final.amount
    end

    endTankSession()

    local served = math.max(0, initial - lowest)
    local cost = math.ceil(served / cfg.mb_per_token)

    if cost > credit then cost = credit end

    local change = credit - cost
    finishChange(change)

    drawMain({
        status=reason,
        credit=credit,
        served=served,
        cost=cost,
        tankAmount=lowest,
        tankCapacity=capacity,
        running=false,
        message="Cambio: " .. tostring(change) .. " FT"
    })

    sleep(3)
end

-- ============================================================
-- ESPERA / MAIN
-- ============================================================

local function waitIdleAction()
    local timer = os.startTimer(0.35)

    while true do
        local event, a, b, c = os.pullEvent()

        if event == "key" then
            if a == keys.f then
                return "start"
            elseif a == keys.c then
                return "admin"
            end
        end

        if event == "mouse_click" and buttonClicked(b, c) then
            return "start"
        end

        if event == "timer" and a == timer then
            return "refresh"
        end
    end
end

local function main()
    loadConfig()
    openModems()

    if not rednet.isOpen() then
        error("No hay modem conectado")
    end

    refreshInventories()
    autoRepairTokenID()
    closeValve()

    while true do
        refreshInventories()
        autoRepairTokenID()

        if cfg.out_of_service then
            closeValve()
            drawOutOfService()

        elseif not payment then
            drawMain({
                status="ERROR BARRIL PAGO",
                message="No encuentro inventario en " .. cfg.payment_side
            })

        elseif not storage then
            drawMain({
                status="ERROR BARRIL ALMACEN",
                message="No encuentro inventario en " .. cfg.storage_side
            })

        else
            local credit = countTokens(payment)
            local invalid = countInvalidItems()

            if credit > 0 then
                local message =
                    "Deposito " .. cleanID(cfg.tank_id) ..
                    " | F o pulsa el boton."

                if invalid > 0 then
                    message = message .. " Item invalido: " .. tostring(invalid)
                end

                drawMain({
                    status="LISTO",
                    credit=credit,
                    served=0,
                    cost=0,
                    running=false,
                    message=message
                })
            else
                local message = "Inserta Netherite Coins."

                if invalid > 0 then
                    message = "Objeto no valido en el barril."
                end

                drawMain({
                    status="ESPERANDO PAGO",
                    credit=0,
                    served=0,
                    cost=0,
                    running=false,
                    message=message
                })
            end
        end

        local action = waitIdleAction()

        if action == "admin" then
            adminMenu()
            refreshInventories()
            autoRepairTokenID()
            tankComputerID = nil

        elseif action == "start" and not cfg.out_of_service then
            refreshInventories()
            autoRepairTokenID()

            local credit = countTokens(payment)

            if credit <= 0 then
                drawMain({
                    status="SIN CREDITO",
                    message="Introduce Netherite Coins."
                })
                sleep(1.2)
            else
                refuel(credit)
            end
        end
    end
end

local ok, err = pcall(main)

pcall(closeValve)

if not ok then
    clear()

    if hasColor() then term.setTextColor(colors.red) end
    print("ERROR FATAL DEL SURTIDOR")
    resetColors()

    print("")
    print(tostring(err))
    print("")
    print("Se intento cerrar la valvula.")
end
