-- ============================================================
-- ELECTROLUZ - ADAPTACION DEL SURTIDOR ORIGINAL
-- CC:Tweaked + Create Crafts & Additions + Lightman's Currency
--
-- CONSERVA la interfaz, menus y cobro originales.
-- 1 FuelToken = 1 Netherite Coin
-- Item: lightmanscurrency:coin_netherite
--
-- Cliente: F / click = iniciar o parar
-- Administracion oculta: C, PIN 2050, flechas, ENTER, BACKSPACE
--
-- MEDICION: Redstone Relay electrico de Create Crafts & Additions
-- getThroughput() devuelve una lectura de flujo actual en FE.
-- Se estima el consumo como FE/t * ticks transcurridos (~20 t/s).
-- NO es un contador fiscal ni garantiza corte exacto sin calibracion.
--
-- IMPORTANTE: un Relay por cliente; no compartir ese paso de energia.
-- Configurar modo DIRECTO para activacion por senal continua de redstone.
-- ============================================================

local CONFIG_FILE = "/electroluz_original.cfg"
local ADMIN_PIN = "2050"
local NETHERITE_COIN_ID = "lightmanscurrency:coin_netherite"

local defaults = {
    station_name = "ELECTROLUZ",
    out_of_service = false,

    -- Se conservan Grupo + ID de estacion + ID de medidor.
    group_id = "GRUPO1",
    station_id = "S" .. tostring(os.getComputerID()),
    meter_id = "E1",
    relay_name = "auto", -- Nombre de periferico o auto si hay uno solo.

    token_name = "FuelToken",
    token_item_id = NETHERITE_COIN_ID,
    fe_per_token = 10000, -- Precio configurable: FE por Netherite Coin.

    payment_side = "right",
    storage_side = "bottom",

    open_side = "back", -- Redstone hacia el Relay electrico.
    close_side = "left", -- Solo para el modo de pulsos.
    pulse_time = 0.15,
    control_mode = "directo", -- directo=mantener senal; pulso=tu latch original.

    sample_time = 0.10,
    no_flow_limit = 0, -- 0=permitir espera sin consumo (ideal para casas).
    flow_epsilon_fe = 0,
    flow_grace_time = 1.0,

    change_retry_time = 0.5,
}

local cfg = {}
local payment, storage = nil, nil
local paymentName, storageName = nil, nil
local relay, relayName = nil, nil
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

                for k, v in pairs(data) do
                    if defaults[k] ~= nil then cfg[k] = v end
                end
            end
        end
    end

    cfg.group_id = cleanID(cfg.group_id)
    cfg.station_id = cleanID(cfg.station_id)
    cfg.meter_id = cleanID(cfg.meter_id)
    if type(cfg.fe_per_token) ~= "number" or cfg.fe_per_token < 1 then cfg.fe_per_token = defaults.fe_per_token end
    if type(cfg.sample_time) ~= "number" or cfg.sample_time < 0.05 then cfg.sample_time = defaults.sample_time end
    if cfg.control_mode ~= "directo" and cfg.control_mode ~= "pulso" then cfg.control_mode = "directo" end

    if cfg.token_item_id == "" or cfg.token_item_id == "CAMBIAR_ESTO" then
        cfg.token_item_id = NETHERITE_COIN_ID
    end

    if cfg.token_name == "" or cfg.token_name == "monedas" then
        cfg.token_name = "FuelToken"
    end

    saveConfig()
end

-- ============================================================
-- PERIFERICOS / INVENTARIOS
-- ============================================================

-- Busca el Relay ELECTRICO, no el redstone_relay propio de CC:Tweaked.
local function refreshRelay()
    relay, relayName = nil, nil
    local requested = tostring(cfg.relay_name or "auto")
    if requested ~= "auto" then
        local p = peripheral.wrap(requested)
        if p and type(p.getThroughput) == "function" then
            relay, relayName = p, requested
            return true
        end
        return false, "No se encuentra " .. requested
    end

    local found = 0
    for _, name in ipairs(peripheral.getNames()) do
        local p = peripheral.wrap(name)
        if p and type(p.getThroughput) == "function" then
            found = found + 1
            relay, relayName = p, name
        end
    end
    if found == 0 then return false, "No hay Relay electrico" end
    if found > 1 then
        relay, relayName = nil, nil
        return false, "Varios Relay: configura nombre"
    end
    return true
end

local function readRelay()
    if not relay or not relayName or not peripheral.isPresent(relayName) then
        return nil, "RELAY DESCONECTADO"
    end
    local ok, value = pcall(relay.getThroughput)
    if not ok or type(value) ~= "number" or value < 0 or value ~= value or value == math.huge then
        return nil, "LECTURA RELAY INVALIDA"
    end
    return value
end

local function diagnosticRelay()
    refreshRelay()
    clear() -- Funcion de la interfaz original.
    print("DIAGNOSTICO RELE ELECTRICO")
    print("--------------------------")
    print("Perifericos con getThroughput:")
    for _, name in ipairs(peripheral.getNames()) do
        local p = peripheral.wrap(name)
        if p and type(p.getThroughput) == "function" then
            local ok, v = pcall(p.getThroughput)
            print(name .. ": " .. (ok and tostring(v) or "ERROR") .. " FE")
        end
    end
    print("")
    print("Configurado: " .. tostring(cfg.relay_name))
    print("Pulsa una tecla...")
    os.pullEvent("key")
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
-- VALVULA (AHORA INTERRUPTOR ELECTRICO)
-- ============================================================

local function pulse(side)
    redstone.setOutput(side, true)
    sleep(cfg.pulse_time)
    redstone.setOutput(side, false)
end

-- Mantiene ambas opciones de control para instalaciones anteriores.
local function openValve()
    if cfg.control_mode == "pulso" then
        pulse(cfg.open_side)
    else
        redstone.setOutput(cfg.open_side, true)
    end
end

local function closeValve()
    if cfg.control_mode == "pulso" then
        pulse(cfg.close_side)
    else
        redstone.setOutput(cfg.open_side, false)
    end
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
    writeAt(16, 6, tostring(math.floor(served)) .. " FE", colors.cyan)

    writeAt(2, 7, "COSTE")
    writeAt(16, 7, tostring(cost) .. " FT", colors.orange)

    writeAt(2, 8, "RESTANTE")
    writeAt(16, 8, tostring(remaining) .. " FT", colors.lime)

    if state.throughput ~= nil then
        writeAt(2, 10, "MEDIDOR " .. cleanID(cfg.meter_id))
        writeAt(16, 10, tostring(math.floor(state.throughput)) .. " FE/t")
    end

    writeAt(2, 12, "PRECIO")
    writeAt(10, 12, "1 FT = " .. tostring(cfg.fe_per_token) .. " FE")

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
            label="Estado suministro",
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
            end
        },

        {
            label="ID suministro",
            value=function() return cfg.station_id end,
            edit=function()
                cfg.station_id = cleanID(promptText("ID DEL SURTIDOR", cfg.station_id))
            end
        },

        {
            label="ID medidor",
            value=function() return cfg.meter_id end,
            edit=function()
                cfg.meter_id = cleanID(promptText("ID DEL MEDIDOR", cfg.meter_id))
            end
        },

        {
            label="Nombre suministro",
            value=function() return cfg.station_name end,
            edit=function()
                cfg.station_name = promptText("Nombre surtidor", cfg.station_name)
            end
        },

        {
            label="FE por FuelToken",
            value=function() return cfg.fe_per_token end,
            edit=function()
                cfg.fe_per_token = promptNumber("FE por FuelToken", cfg.fe_per_token, 1)
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
            label="Activar suministro",
            value=function() return cfg.open_side end,
            edit=function()
                cfg.open_side = promptSide("Abrir valvula", cfg.open_side)
            end
        },

        {
            label="Desactivar suministro",
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
                    promptNumber("Lecturas sin flujo", cfg.no_flow_limit, 0)
                )
            end
        },

        {
            label="Tolerancia FE/t",
            value=function() return cfg.flow_epsilon_fe end,
            edit=function()
                cfg.flow_epsilon_fe = promptNumber(
                    "Tolerancia FE/t",
                    cfg.flow_epsilon_fe,
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
            label="Nombre Relay",
            value=function() return cfg.relay_name end,
            edit=function()
                cfg.relay_name = promptText("NOMBRE RELAY O auto", cfg.relay_name)
                refreshRelay()
            end
        },

        {
            label="Control redstone",
            value=function() return cfg.control_mode end,
            edit=function()
                closeValve()
                cfg.control_mode = cfg.control_mode == "directo" and "pulso" or "directo"
            end
        },

        {
            label="Diagnostico Relay",
            value=function() return "ABRIR" end,
            edit=diagnosticRelay
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
-- RELE / LECTURA DIRECTA
-- ============================================================

local function isStopInput(event, a, b, c)
    if event == "key" and a == keys.f then return true end
    if event == "mouse_click" and buttonClicked(b, c) then return true end
    return false
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
    local found, relayError = refreshRelay()
    if not found then
        drawMain({status="ERROR RELAY", credit=credit, message=tostring(relayError)})
        sleep(2.5)
        return
    end

    -- La medicion NO necesita ordenador de deposito ni rednet
    local initial, initialError = readRelay()
    if not initial then
        drawMain({status="ERROR RELAY", credit=credit, message=tostring(initialError)})
        sleep(2.5)
        return
    end

    -- Reserva de monedas, igual que en el codigo original.
    if not reserveCredit(credit) then
        drawMain({status="ERROR PAGO", credit=credit, message="No puedo mover las monedas."})
        sleep(3)
        return
    end

    local served = 0
    local throughput = 0
    local noFlow = 0
    local maxEnergy = credit * cfg.fe_per_token
    local reason = "FINALIZADO"
    local startedAt = os.epoch("utc")
    local lastAt = startedAt

    drawMain({
        status="SUMINISTRANDO",
        credit=credit, served=0, cost=0,
        throughput=throughput, running=true,
        message="F o boton para detener."
    })

    openValve()

    while true do
        -- Mantener lectura tambien cuando el cliente pulsa PARAR:
        -- antes de cerrar, integrar el ultimo intervalo una vez.
        local action = waitForSampleOrStop()
        local sampledAt = os.epoch("utc")
        local rate, readError = readRelay()
        if not rate then
            reason = "ERROR RELAY"
            break
        end

        throughput = rate
        local elapsedTicks = math.max(0, (sampledAt - lastAt) / 1000 * 20)
        -- Limite defensivo si el servidor se queda congelado/pausado.
        local maxTicks = math.max(1, cfg.sample_time * 40 + 4)
        elapsedTicks = math.min(elapsedTicks, maxTicks)
        lastAt = sampledAt
        if throughput > cfg.flow_epsilon_fe then
            served = served + throughput * elapsedTicks
            noFlow = 0
        elseif (sampledAt - startedAt) / 1000 >= cfg.flow_grace_time then
            noFlow = noFlow + 1
        end

        local cost = math.min(credit, math.ceil(served / cfg.fe_per_token))
        drawMain({
            status="SUMINISTRANDO", credit=credit,
            served=served, cost=cost, throughput=throughput,
            running=true, message="F o boton para detener."
        })

        if action == "stop" then
            reason = "PARADO"
            break
        elseif served >= maxEnergy then
            reason = "CREDITO AGOTADO"
            break
        elseif cfg.no_flow_limit > 0 and noFlow >= cfg.no_flow_limit then
            reason = "SUMINISTRO COMPLETADO"
            break
        end
    end

    closeValve()
    local cost = math.min(credit, math.ceil(served / cfg.fe_per_token))
    local change = credit - cost
    finishChange(change)

    drawMain({
        status=reason, credit=credit, served=served,
        cost=cost, throughput=throughput, running=false,
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
    -- No se necesita rednet ni un segundo ordenador.
    refreshInventories()
    autoRepairTokenID()
    closeValve()
    refreshRelay()

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

        elseif not refreshRelay() then
            closeValve()
            drawMain({status="ERROR RELAY", message="C para configurar Relay"})

        else
            local credit = countTokens(payment)
            local invalid = countInvalidItems()

            if credit > 0 then
                local message =
                    "Medidor " .. cleanID(cfg.meter_id) ..
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
    print("ERROR FATAL DEL SUMINISTRO")
    resetColors()

    print("")
    print(tostring(err))
    print("")
    print("Se intento cortar la electricidad.")
end