-- ============================================================
-- ELECTROLUZ: MEDIDOR IZQUIERDO (sin barriles)
-- CC:Tweaked + Create Crafts & Additions
-- Basado en la UI y la administracion del surtidor original.
--
-- El Relay ELECTRICO va a la IZQUIERDA del ordenador.
-- No se usan inventarios de monedas, ni acumulador ni ordenador remoto.
-- La pantalla calcula el coste en FuelTokens (NO los cobra).
--
-- F o click: comenzar/parar suministro
-- C: menu oculto, PIN 2050, flechas, ENTER, BACKSPACE
--
-- getThroughput() da flujo ACTUAL, no un contador acumulado.
-- Se estima FE = flujo * segundos * ticks_por_segundo.
-- Verificar esta conversion en la version concreta del mod.
-- ============================================================

local CONFIG_FILE = "/electroluz_original.cfg" -- conserva las preferencias anteriores
local LEDGER_FILE = "/electroluz_consumo.dat"
local ADMIN_PIN = "2050"

local defaults = {
    station_name = "ELECTROLUZ",
    out_of_service = false,
    group_id = "GRUPO1",
    station_id = "S" .. tostring(os.getComputerID()),
    meter_id = "E1",
    fe_per_token = 10000,
    -- Solo lectura por la izquierda. No hay barril de pago.
    relay_side = "left",
    open_side = "back",  -- salida redstone para habilitar el Relay
    close_side = "right", -- solo modo pulso; nunca LEFT (ocupado por Relay)
    pulse_time = 0.15,
    control_mode = "directo",
    sample_time = 0.10,
    no_flow_limit = 0,   -- 0: la casa puede estar sin consumir temporalmente
    flow_epsilon_fe = 0,
    flow_grace_time = 1.0,
    ticks_per_second = 20,  -- FACTOR ESTIMADO: calibrar en la version del mod
}

local cfg = {}
local relay = nil
local ledger = {total_fe = 0, sessions = 0}
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
            local ok, data = pcall(textutils.unserialize, f.readAll())
            f.close()
            if ok and type(data) == "table" then
                for key in pairs(defaults) do
                    if data[key] ~= nil then cfg[key] = data[key] end
                end
            end
        end
    end
    cfg.relay_side = "left" -- exigido por esta instalacion
    cfg.group_id = cleanID(cfg.group_id)
    cfg.station_id = cleanID(cfg.station_id)
    cfg.meter_id = cleanID(cfg.meter_id)
    if type(cfg.fe_per_token) ~= "number" or cfg.fe_per_token < 1 then cfg.fe_per_token = defaults.fe_per_token end
    if type(cfg.sample_time) ~= "number" or cfg.sample_time < 0.05 then cfg.sample_time = defaults.sample_time end
    if type(cfg.ticks_per_second) ~= "number" or cfg.ticks_per_second < 1 then cfg.ticks_per_second = 20 end
    if type(cfg.flow_epsilon_fe) ~= "number" or cfg.flow_epsilon_fe < 0 then cfg.flow_epsilon_fe = 0 end
    if type(cfg.flow_grace_time) ~= "number" or cfg.flow_grace_time < 0 then cfg.flow_grace_time = 1 end
    if type(cfg.no_flow_limit) ~= "number" or cfg.no_flow_limit < 0 then cfg.no_flow_limit = 0 end
    if cfg.control_mode ~= "directo" and cfg.control_mode ~= "pulso" then cfg.control_mode = "directo" end
    if cfg.open_side == "left" then cfg.open_side = "back" end
    if cfg.close_side == "left" then cfg.close_side = "right" end
    saveConfig()
end


-- ============================================================
-- PERIFERICO IZQUIERDO: EL RELE ELECTRICO
-- ============================================================
local function refreshRelay()
    relay = peripheral.wrap("left")
    if not relay or type(relay.getThroughput) ~= "function" then
        relay = nil
        return false, "Coloca el Relay electrico a la izquierda"
    end
    return true
end

local function readRelay()
    if not relay or not peripheral.isPresent("left") then
        return nil, "RELAY IZQUIERDO DESCONECTADO"
    end
    local ok, value = pcall(relay.getThroughput)
    if not ok or type(value) ~= "number" or value < 0 or value ~= value or value == math.huge then
        return nil, "LECTURA DE RELE INVALIDA"
    end
    return value
end

local function loadLedger()
    ledger = {total_fe = 0, sessions = 0}
    if fs.exists(LEDGER_FILE) then
        local f = fs.open(LEDGER_FILE, "r")
        if f then
            local ok, data = pcall(textutils.unserialize, f.readAll())
            f.close()
            if ok and type(data) == "table" and type(data.total_fe) == "number"
                and data.total_fe >= 0 and data.total_fe < math.huge then
                ledger.total_fe = data.total_fe
                ledger.sessions = math.max(0, math.floor(tonumber(data.sessions) or 0))
            end
        end
    end
end

local function saveLedger()
    -- Primero escribimos un archivo temporal para no truncar el registro antiguo.
    local temp = LEDGER_FILE .. ".tmp"
    local f = fs.open(temp, "w")
    if not f then error("No se pudo guardar contador") end
    f.write(textutils.serialize(ledger))
    f.close()
    if fs.exists(LEDGER_FILE) then fs.delete(LEDGER_FILE) end
    fs.move(temp, LEDGER_FILE)
end

local function diagnosticRelay()
    clear()
    print("DIAGNOSTICO RELE IZQUIERDO")
    print("--------------------------")
    local found, reason = refreshRelay()
    print("Lado: left")
    if not found then
        print(reason)
    else
        local value, err = readRelay()
        if value then
            print("getThroughput(): " .. tostring(value))
            print("Lectura de flujo FE (sin calibrar)")
        else
            print(tostring(err))
        end
        if type(relay.isPowered) == "function" then
            local ok, state = pcall(relay.isPowered)
            if ok then print("isPowered(): " .. tostring(state)) end
        end
    end
    print("")
    print("Pulsa una tecla...")
    os.pullEvent("key")
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
        elseif status:find("ERROR") then
            statusColor = colors.red
        elseif status == "LISTO" then
            statusColor = colors.yellow
        end
    end
    centerText(3, status, statusColor)

    local served = state.served or 0
    local cost = math.ceil(served / cfg.fe_per_token)
    local totalCost = math.ceil(ledger.total_fe / cfg.fe_per_token)
    writeAt(2, 5, "SESIONES")
    writeAt(16, 5, tostring(ledger.sessions), colors.yellow)
    writeAt(2, 6, "SUMINISTRADO")
    writeAt(16, 6, tostring(math.floor(served)) .. " FE", colors.cyan)
    writeAt(2, 7, "COSTE")
    writeAt(16, 7, tostring(cost) .. " FT", colors.orange)
    writeAt(2, 8, "TOTAL")
    writeAt(16, 8, tostring(totalCost) .. " FT", colors.lime)

    if state.throughput ~= nil then
        writeAt(2, 10, "MEDIDOR " .. cleanID(cfg.meter_id))
        writeAt(16, 10, tostring(math.floor(state.throughput)) .. " FE*")
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
    drawButton(state.running == true, state.enabled ~= false)
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

-- Ya no hay barril de pago ni inventario de monedas.
local function resetLedger()
    clear()
    centerText(2, "REINICIAR CONTADOR")
    print("")
    print("Pone total FE y sesiones a 0.")
    print("Escribe REINICIAR para confirmar")
    write("> ")
    if read() == "REINICIAR" then
        ledger = {total_fe=0, sessions=0}
        saveLedger()
    end
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
            label="Lado medidor",
            value=function() return "left (fijo)" end,
            edit=diagnosticRelay
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
            label="Factor ticks/s",
            value=function() return cfg.ticks_per_second end,
            edit=function()
                cfg.ticks_per_second = promptNumber("Factor estimado ticks/s", cfg.ticks_per_second, 1)
            end
        },

        {
            label="Diagnostico Relay",
            value=function() return "ABRIR" end,
            edit=diagnosticRelay
        },

        {
            label="Reiniciar contador",
            value=function() return "CONFIRMAR" end,
            edit=resetLedger
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
                    return
                end

                if option.edit then
                    option.edit()
                    saveConfig()
                end

            elseif a == keys.backspace then
                saveConfig()
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
-- SUMINISTRO + CONTADOR IZQUIERDO
-- ============================================================
local function isStopInput(event, a, b, c)
    if event == "key" and a == keys.f then return true end
    if event == "mouse_click" and buttonClicked(b, c) then return true end
    return false
end

local function waitForSampleOrStop()
    local timer = os.startTimer(cfg.sample_time)
    while true do
        local event, a, b, c = os.pullEvent()
        if event == "timer" and a == timer then return "sample" end
        if isStopInput(event, a, b, c) then return "stop" end
    end
end

local function supplyElectricity()
    if cfg.out_of_service then
        closeValve()
        return
    end
    closeValve()
    local found, err = refreshRelay()
    if not found then
        drawMain({status="ERROR RELAY", enabled=false, message=tostring(err)})
        sleep(2)
        return
    end
    local initial, readError = readRelay()
    if initial == nil then
        drawMain({status="ERROR RELAY", enabled=false, message=tostring(readError)})
        sleep(2)
        return
    end

    local served, flow, noFlow = 0, initial, 0
    local startedAt = os.epoch("utc")
    local lastAt, lastSave = startedAt, startedAt
    local reason = "FINALIZADO"
    ledger.sessions = ledger.sessions + 1
    saveLedger()
    drawMain({status="SUMINISTRANDO", served=0, throughput=flow,
        running=true, message="F o boton para detener."})
    openValve()

    while true do
        local action = waitForSampleOrStop()
        local now = os.epoch("utc")
        local reading, errorMsg = readRelay()
        if reading == nil then
            reason = "ERROR RELAY"
            break
        end
        flow = reading
        -- La documentacion dice 'throughput actual en FE', no contador total.
        -- HIPOTESIS DE CALCULO: lectura aproximadamente por tick.
        -- Es una estimacion; calibrar el factor en tu version del mod.
        local deltaSeconds = math.max(0, (now - lastAt) / 1000)
        deltaSeconds = math.min(deltaSeconds, math.max(0.25, cfg.sample_time * 2))
        lastAt = now
        if flow > cfg.flow_epsilon_fe then
            local fe = flow * deltaSeconds * cfg.ticks_per_second
            served = served + fe
            ledger.total_fe = ledger.total_fe + fe
            noFlow = 0
        elseif (now - startedAt) / 1000 >= cfg.flow_grace_time then
            noFlow = noFlow + 1
        end
        if now - lastSave >= 2000 then
            saveLedger()
            lastSave = now
        end
        drawMain({status="SUMINISTRANDO", served=served, throughput=flow,
            running=true, message="F o boton para detener."})
        if action == "stop" then
            reason = "PARADO"
            break
        end
        if cfg.no_flow_limit > 0 and noFlow >= cfg.no_flow_limit then
            reason = "SIN CONSUMO"
            break
        end
    end
    closeValve()
    saveLedger()
    drawMain({status=reason, served=served, throughput=flow,
        running=false, message="Coste estimado; sin cobro automatico."})
    sleep(3)
end


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
    loadLedger()
    closeValve()  -- cortado al arrancar
    refreshRelay()
    while true do
        if cfg.out_of_service then
            closeValve()
            drawOutOfService()
        else
            local found, problem = refreshRelay()
            if not found then
                closeValve()
                drawMain({status="ERROR RELAY", enabled=false,
                    message=tostring(problem)})
            else
                local rate, readErr = readRelay()
                if rate == nil then
                    closeValve()
                    drawMain({status="ERROR RELAY", enabled=false,
                        message=tostring(readErr)})
                else
                    drawMain({status="LISTO", throughput=rate, served=0,
                        message="Medidor izquierdo | F o boton."})
                end
            end
        end
        local action = waitIdleAction()
        if action == "admin" then
            closeValve()
            adminMenu()
        elseif action == "start" and not cfg.out_of_service then
            supplyElectricity()
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
