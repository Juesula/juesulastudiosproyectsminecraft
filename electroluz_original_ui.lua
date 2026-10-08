-- ============================================================
-- ELECTROLUZ - ADAPTACION DEL SURTIDOR ORIGINAL
-- CC:Tweaked + Create Crafts & Additions + Lightman's Currency
--
-- CONSERVA la interfaz, menus y cobro originales.
-- PAGO REAL: Diamond Coins + Netherite Coins (1 NC = 10 DC).
-- TARIFA: 3 DC por 10 FE (redondeo por bloque).
-- Item: lightmanscurrency:coin_diamond
-- Barril derecho = insertar y recibir cambio; abajo = caja de ingresos.
-- Relay electrico a la izquierda; redstone de control por detras.
-- F/Click: iniciar/parar (PIN obligatorio para detener 24h).
-- M: alternar 24 horas / repostada. C: administracion.
-- R: reanudar sesion 24h protegida tras pausa/reinicio.
-- IMPORTANTE: getThroughput() = flujo instantaneo, conversion FE/t estimada.
-- Precisa calibracion; limite el flujo para evitar sobreentrega.
-- Si no hay flujo, no es posible distinguir falta de energia de falta de demanda.
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

local CONFIG_FILE = "/electroluz_diamond.cfg"
local LEDGER_FILE = "/electroluz_diamond_seguro_ledger.dat"
local ADMIN_PIN = "2050"
local DIAMOND_COIN_ID = "lightmanscurrency:coin_diamond"
local NETHERITE_COIN_ID = "lightmanscurrency:coin_netherite"
local NETHERITE_VALUE = 10

local defaults = {
    station_name = "ELECTROLUZ",
    admin_pin = ADMIN_PIN,
    out_of_service = false,

    -- Se conservan Grupo + ID de estacion + ID de medidor.
    group_id = "GRUPO1",
    station_id = "S" .. tostring(os.getComputerID()),
    meter_id = "E1",
    relay_name = "left", -- Relay electrico a la izquierda.

    token_name = "DiamondCoin",
    token_item_id = DIAMOND_COIN_ID,
    coins_per_block = 3,
    fe_per_block = 10,
    mode = "repostada", -- Alternar con M: repostada/24horas.
    max_hours = 24,
    ticks_per_second = 20, -- CALIBRAR segun version del Relay.

    payment_side = "right",
    storage_side = "bottom",

    open_side = "back", -- Redstone hacia el Relay electrico.
    close_side = "top", -- Solo para el modo de pulsos; left ocupado por Relay.
    pulse_time = 0.15,
    control_mode = "directo", -- directo=mantener senal; pulso=tu latch original.

    sample_time = 0.05,
    no_flow_seconds = 5, -- Solo repostada: 24h permite consumo cero.
    flow_epsilon_fe = 0,
    flow_grace_time = 1.0,

    change_retry_time = 0.5,
}

local cfg = {}
local payment, storage = nil, nil
local paymentName, storageName = nil, nil
local relay, relayName = nil, nil
local buttonBounds = {x1=1, x2=1, y1=1, y2=1}
local adminCancelRequested = false

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
    if type(cfg.coins_per_block) ~= "number" or cfg.coins_per_block < 1 then cfg.coins_per_block = 3 end
    cfg.coins_per_block = math.floor(cfg.coins_per_block)
    if type(cfg.fe_per_block) ~= "number" or cfg.fe_per_block <= 0 then cfg.fe_per_block = 10 end
    if type(cfg.sample_time) ~= "number" or cfg.sample_time < 0.05 then cfg.sample_time = 0.05 end
    if type(cfg.no_flow_seconds) ~= "number" or cfg.no_flow_seconds < 0.5 then cfg.no_flow_seconds = 5 end
    if type(cfg.ticks_per_second) ~= "number" or cfg.ticks_per_second <= 0 then cfg.ticks_per_second = 20 end
    if cfg.control_mode ~= "directo" and cfg.control_mode ~= "pulso" then cfg.control_mode = "directo" end
    if cfg.mode ~= "repostada" and cfg.mode ~= "24horas" then cfg.mode = "repostada" end
    -- La modalidad continua dura como maximo 24 horas reales.
    cfg.max_hours = 24
    -- Forzar diamante aun si una configuracion anterior tenia netherite.
    cfg.token_item_id = DIAMOND_COIN_ID
    cfg.token_name = "DiamondCoin"

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
-- MONEDAS MIXTAS + LIBRO DE SESION SEGURO
-- ============================================================
-- 1 Netherite Coin = 10 Diamond Coins de VALOR (NO se fabrican monedas).
local denominations = {
    diamond = {id=DIAMOND_COIN_ID, value=1},
    netherite = {id=NETHERITE_COIN_ID, value=NETHERITE_VALUE},
}
local function normalizeItemID(value)
    if type(value) ~= "string" then return "" end
    return value:gsub("^%s+", ""):gsub("%s+$", ""):lower()
end
local function itemDenom(item)
    if type(item) ~= "table" then return nil end
    local id = normalizeItemID(item.name)
    for key, data in pairs(denominations) do
        if id == data.id then return key end
    end
end
local function countCurrency(inv)
    local counts = {diamond=0,netherite=0}
    if not inv then return counts end
    local ok, items = pcall(inv.list)
    if not ok or type(items) ~= "table" then return counts end
    for _, item in pairs(items) do
        local key = itemDenom(item)
        if key then counts[key] = counts[key] + math.floor(item.count or 0) end
    end
    return counts
end
local function valueOf(c)
    return (c.diamond or 0) + NETHERITE_VALUE*(c.netherite or 0)
end
local function countInvalidItems()
    if not payment then return 0 end
    local ok, items = pcall(payment.list)
    if not ok then return 0 end
    local total = 0
    for _, item in pairs(items) do
        if not itemDenom(item) then total = total + (item.count or 0) end
    end
    return total
end
local function moveDenom(source, destinationName, key, amount)
    local moved=0
    if not source or not destinationName or amount<=0 then return 0 end
    local ok, items = pcall(source.list)
    if not ok then return 0 end
    for slot, item in pairs(items) do
        if itemDenom(item) == key then
            local wanted = math.min(item.count, amount-moved)
            local success, actual = pcall(source.pushItems, destinationName, slot, wanted)
            if not success then break end
            moved = moved + (actual or 0)
            if moved>=amount then break end
        end
    end
    return moved
end

local closeValve, drawMain
local ledger = {
    pending=0, spent=0, total_fe=0, total_paid=0,
    diamond_in=0, netherite_in=0,
    active=false, claim_required=false, mode="", session_pin="",
    start_ms=0, served=0, reason="", price_coins=3, price_fe=10,
}
local function saveLedger()
    -- Copia anterior para poder recuperar el registro si falla un guardado.
    local file=LEDGER_FILE..".new"
    local f=fs.open(file,"w")
    if not f then error("No se pudo guardar el registro") end
    f.write(textutils.serialize(ledger))
    f.close()
    if fs.exists(LEDGER_FILE) then
        if fs.exists(LEDGER_FILE..".bak") then fs.delete(LEDGER_FILE..".bak") end
        fs.move(LEDGER_FILE,LEDGER_FILE..".bak")
    end
    fs.move(file,LEDGER_FILE)
end
local function loadLedger()
    for _,name in ipairs({LEDGER_FILE,LEDGER_FILE..".bak"}) do
        if fs.exists(name) then
            local f=fs.open(name,"r")
            if f then
                local ok, data=pcall(textutils.unserialize,f.readAll())
                f.close()
                if ok and type(data)=="table" then
                    for k,v in pairs(ledger) do
                        if type(v)==type(data[k]) then ledger[k]=data[k] end
                    end
                    return
                end
            end
        end
    end
end
local function costFor(fe)
    if fe <= 0 then return 0 end
    return math.ceil(fe/ledger.price_fe - 1e-9)*ledger.price_coins
end
local function creditEnough(v)
    return v >= cfg.coins_per_block
end
-- El coste se redondea por bloques, pero un bloque ya abonado permite
-- consumir TODOS sus FE. No cortar cuando se cobra el primer FE del bloque.
local function prepaidFE()
    if ledger.price_coins <= 0 or ledger.price_fe <= 0 then return 0 end
    return math.floor(ledger.pending / ledger.price_coins) * ledger.price_fe
end
local function remainingFE()
    return math.max(0, prepaidFE() - ledger.served)
end
local function startBlockedByChange(amounts)
    if (amounts.netherite or 0)<=0 then return false end
    -- No hay conversor fisico de monedas. Garantizar hasta 9 DC para
    -- devolver las fracciones de una Netherite Coin.
    local stock=countCurrency(storage)
    return stock.diamond + amounts.diamond < 9
end
local function addPaymentFunds(amounts)
    -- Cada movimiento confirmado se registra; ante error se detiene el servicio.
    local moved={diamond=0,netherite=0}
    for _,key in ipairs({"diamond","netherite"}) do
        if (amounts[key] or 0)>0 then
            moved[key]=moveDenom(payment,storageName,key,amounts[key])
            if moved[key]>0 then
                ledger.pending=ledger.pending+moved[key]*denominations[key].value
                if key=="diamond" then ledger.diamond_in=ledger.diamond_in+moved[key]
                else ledger.netherite_in=ledger.netherite_in+moved[key] end
                saveLedger()
            end
            if moved[key]~=amounts[key] then return false, moved end
        end
    end
    return true,moved
end
local function refundExact(change)
    refreshInventories()
    if not payment or not storage then return 0,"FALTA INVENTARIO" end
    local stock=countCurrency(storage)
    local n=math.min(math.floor(change/NETHERITE_VALUE),stock.netherite)
    while n>=0 and (change-NETHERITE_VALUE*n)>stock.diamond do n=n-1 end
    if n<0 then return 0,"FALTAN DIAMOND COINS DE CAMBIO" end
    local d=change-NETHERITE_VALUE*n
    local valueMoved=0
    for _,entry in ipairs({{"netherite",n},{"diamond",d}}) do
        local key,quantity=entry[1],entry[2]
        if quantity>0 then
            local m=moveDenom(storage,paymentName,key,quantity)
            local v=m*denominations[key].value
            valueMoved=valueMoved+v
            ledger.pending=math.max(ledger.spent,ledger.pending-v)
            saveLedger()
            if m~=quantity then return valueMoved,"BARRIL LLENO O CAMBIO INSUFICIENTE" end
        end
    end
    return valueMoved,nil
end
local function resetSession()
    ledger.pending,ledger.spent=0,0
    ledger.diamond_in,ledger.netherite_in=0,0
    ledger.active,ledger.claim_required=false,false
    ledger.mode,ledger.session_pin,ledger.reason="","",""
    ledger.start_ms,ledger.served=0,0
    saveLedger()
end
local function settleSession(reason)
    closeValve()
    ledger.active=false
    ledger.reason=reason
    saveLedger()
    local due=math.max(0,ledger.pending-ledger.spent)
    while due>0 do
        local returned,why=refundExact(due)
        due=math.max(0,ledger.pending-ledger.spent)
        if due>0 then
            -- Una sesion segura NO expone el cambio por si sola:
            -- esta funcion solo se invoca despues del PIN o autorizacion admin.
            drawMain({status="CAMBIO PENDIENTE",credit=ledger.pending,
                cost=ledger.spent,served=ledger.served,mode=ledger.mode,
                message=tostring(why or "Libera espacio en el barril derecho")})
            sleep(cfg.change_retry_time)
        end
    end
    ledger.total_fe=ledger.total_fe+ledger.served
    ledger.total_paid=ledger.total_paid+ledger.spent
    local cost=ledger.spent
    local served=ledger.served
    resetSession() -- El PIN se borra SOLO aqui, una vez atendido el cambio.
    return cost,served
end
local function freezeProtected(reason)
    closeValve()
    ledger.active=false
    ledger.claim_required=true
    ledger.reason=reason
    saveLedger()
end

-- En una parada automatica de 24h el saldo sobrante se bloquea.
-- No se devuelve al barril hasta que el propietario introduce su PIN.
local function finishSession(reason, authorized)
    closeValve()
    ledger.active=false
    ledger.reason=reason
    saveLedger()
    if ledger.mode=="24horas" and not authorized
            and ledger.pending>ledger.spent then
        freezeProtected(reason)
        return false,ledger.spent,ledger.served
    end
    local paid,fe=settleSession(reason)
    return true,paid,fe
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

closeValve = function()
    if cfg.control_mode == "pulso" then
        pulse(cfg.close_side)
    else
        redstone.setOutput(cfg.open_side, false)
    end
end

-- ============================================================

-- INTERFAZ
-- ============================================================

local function drawButton(running, enabled, locked)
    local w, h = term.getSize()

    local label = locked and " [ F ]  RECLAMAR " or (running and " [ F ]  PARAR " or " [ F ]  COMENZAR ")
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

drawMain = function(state)
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
    writeAt(16, 5, tostring(credit) .. " DC", colors.yellow)

    writeAt(2, 6, "SUMINISTRADO")
    writeAt(16, 6, tostring(math.floor(served)) .. " FE", colors.cyan)

    writeAt(2, 7, "COSTE")
    writeAt(16, 7, tostring(cost) .. " DC", colors.orange)

    writeAt(2, 8, "RESTANTE")
    writeAt(16, 8, tostring(remaining) .. " DC", colors.lime)
    if state.fe_remaining ~= nil then
        writeAt(2, 9, "FE PENDIENTES")
        writeAt(16, 9, tostring(math.floor(math.max(0,state.fe_remaining))) .. " FE",colors.lime)
    end

    if state.throughput ~= nil then
        writeAt(2, 10, "MEDIDOR " .. cleanID(cfg.meter_id))
        writeAt(16, 10, tostring(math.floor(state.throughput)) .. " FE/t")
    end

    writeAt(2, 12, "PRECIO")
    writeAt(10, 12, tostring(cfg.coins_per_block) .. " DC = " .. tostring(cfg.fe_per_block) .. " FE")
    writeAt(2, 13, "MODO: " .. (state.mode or cfg.mode) .. " [M]", colors.yellow)

    if state.message then
        local msg = tostring(state.message)
        local maxLen = math.max(1, w - 4)

        writeAt(2, h - 4, msg:sub(1, maxLen))
        if #msg > maxLen then
            writeAt(2, h - 3, msg:sub(maxLen + 1, maxLen * 2))
        end
    end

    drawButton(state.running == true, credit > 0, state.locked == true)
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
    if not payment then print("No encuentro barril pago")
    else
        local c=countCurrency(payment)
        print("Diamond Coins: "..c.diamond)
        print("Netherite Coins: "..c.netherite)
        print("Valor: "..valueOf(c).." DC")
        print("Objetos invalidos: "..countInvalidItems())
    end
    print("")
    print("Pulsa una tecla...")
    os.pullEvent("key")
end
local function promptPIN(title)
    clear()
    centerText(2,title)
    centerText(4,"PIN numerico: 4-8 cifras")
    term.setCursorPos(2,6)
    write("PIN: ")
    local pin=read("*")
    if type(pin)~="string" then return nil end
    if #pin<4 or #pin>8 or not pin:match("^%d+$") then return nil end
    return pin
end
local function createSessionPIN()
    local p=promptPIN("NUEVA SESION 24 HORAS")
    if not p then
        clear() centerText(5,"PIN INVALIDO",colors.red) sleep(1.5)
        return nil
    end
    clear()
    centerText(2,"CONFIRMAR PIN")
    term.setCursorPos(2,6) write("Repite el PIN: ")
    if read("*")~=p then
        clear() centerText(5,"NO COINCIDE",colors.red) sleep(1.5)
        return nil
    end
    return p
end
local function checkSessionPIN(title)
    local p=promptPIN(title)
    if not p or p~=ledger.session_pin then
        clear() centerText(5,"PIN INCORRECTO",colors.red) sleep(1.5)
        return false
    end
    return true
end
local function changeAdminPIN()
    local pin=promptPIN("NUEVO PIN ADMIN")
    if not pin then return end
    clear() centerText(2,"CONFIRMAR PIN ADMIN")
    term.setCursorPos(2,6) write("Repite PIN: ")
    if read("*")==pin then cfg.admin_pin=pin
    else clear() centerText(5,"NO COINCIDE",colors.red) sleep(1.5) end
end
local function adminCancelSession()
    if ledger.session_pin=="" and ledger.pending<=0 then
        clear() print("No hay sesion activa") sleep(1.5)
        return
    end
    clear()
    centerText(2,"CANCELACION ADMIN")
    print("") print("Se cortara el suministro y")
    print("se intentara devolver el saldo.")
    print("Escribe CANCELAR para continuar:")
    write("> ")
    if read()=="CANCELAR" then adminCancelRequested=true end
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
            label="Monedas por bloque",
            value=function() return cfg.coins_per_block end,
            edit=function()
                cfg.coins_per_block = math.floor(promptNumber("Diamond Coins por bloque", cfg.coins_per_block, 1))
            end
        },
        {
            label="FE por bloque",
            value=function() return cfg.fe_per_block end,
            edit=function()
                cfg.fe_per_block = promptNumber("FE por bloque", cfg.fe_per_block, 0.001)
            end
        },
        {
            label="Tipo de carga",
            value=function() return cfg.mode end,
            edit=function()
                cfg.mode = cfg.mode == "24horas" and "repostada" or "24horas"
            end
        },
        {
            label="Duracion de 24h",
            value=function() return "24 horas fijas" end,
            edit=function() end
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
            label="Segundos sin energia",
            value=function() return cfg.no_flow_seconds end,
            edit=function()
                cfg.no_flow_seconds = promptNumber("Sin flujo parar a los (s)", cfg.no_flow_seconds, 0.5)
            end
        },
        {
            label="Factor ticks/seg",
            value=function() return cfg.ticks_per_second end,
            edit=function()
                cfg.ticks_per_second = promptNumber("Calibracion FE por tick", cfg.ticks_per_second, 0.1)
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
            label="Cambiar PIN admin",
            value=function() return "CAMBIAR" end,
            edit=changeAdminPIN
        },
        {
            label="PIN sesion 24h",
            value=function() return ledger.session_pin ~= "" and ledger.session_pin or "NINGUNO" end,
            edit=function()
                clear() centerText(2,"PIN SESION ACTIVA")
                centerText(5,ledger.session_pin ~= "" and ledger.session_pin or "NINGUNO",colors.yellow)
                centerText(8,"Pulsa una tecla...") os.pullEvent("key")
            end
        },
        {
            label="Cancelar sesion",
            value=function() return (ledger.active or ledger.claim_required or ledger.pending>0) and "CANCELAR" or "NINGUNA" end,
            edit=adminCancelSession
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

    if read("*") ~= cfg.admin_pin then
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
                        return
                end

                if option.edit then
                    option.edit()
                    saveConfig()
                end

            elseif a == keys.backspace then
                saveConfig()
                refreshInventories()
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
-- RELE / SESION PROTEGIDA
-- ============================================================
local function isStopInput(event,a,b,c)
    return (event=="key" and a==keys.f)
        or (event=="mouse_click" and buttonClicked(b,c))
end
local function waitAction()
    local timer=os.startTimer(cfg.sample_time)
    while true do
        local event,a,b,c=os.pullEvent()
        if event=="timer" and a==timer then return "sample" end
        if isStopInput(event,a,b,c) then return "stop" end
        if event=="key" and a==keys.c then return "admin" end
    end
end
local function sessionScreen(message,active,flow)
    drawMain({status=active and "SUMINISTRANDO" or (ledger.reason~="" and ledger.reason or "PAUSADA"),
        credit=ledger.pending,served=ledger.served,cost=ledger.spent,
        throughput=flow or 0,mode=ledger.mode,running=active,
        locked=ledger.claim_required,fe_remaining=remainingFE(),
        message=message})
end
local function runSession()
    local found,err=refreshRelay()
    if not found then
        if ledger.mode=="24horas" then freezeProtected("ERROR RELAY")
        else settleSession("ERROR RELAY") end
        return
    end
    local v,why=readRelay()
    if v==nil then
        if ledger.mode=="24horas" then freezeProtected(tostring(why))
        else settleSession("ERROR RELAY") end
        return
    end
    if remainingFE() <= 0 then
        finishSession("CREDITO AGOTADO",false)
        return
    end
    local now=os.epoch("utc")
    if ledger.mode=="24horas" and now-ledger.start_ms >= cfg.max_hours*3600000 then
        finishSession("24 HORAS COMPLETADAS",false)
        return
    end
    ledger.active=true
    ledger.claim_required=false
    ledger.reason=""
    saveLedger()
    local zeroSince=now
    local lastSave=now
    local elapsedSinceStart=now
    openValve()
    -- El reloj de facturacion arranca DESPUES de habilitar el suministro.
    local lastAt=os.epoch("utc")
    local reason=nil
    local authorized=false
    local rate=0
    while true do
        local action=waitAction()
        now=os.epoch("utc")
        local sample,readError=readRelay()
        if sample==nil then
            reason="ERROR RELAY"
            break
        end
        rate=sample
        local elapsed=math.max(0,(now-lastAt)/1000)
        local ticks=math.min(elapsed,(cfg.sample_time*2+0.2))*cfg.ticks_per_second
        lastAt=now
        if sample>cfg.flow_epsilon_fe then
            ledger.served=ledger.served+sample*ticks
            zeroSince=now
        elseif ledger.mode ~= "24horas"
               and now-elapsedSinceStart>=cfg.flow_grace_time*1000
               and now-zeroSince>=cfg.no_flow_seconds*1000 then
            reason="SIN ENERGIA / SIN CONSUMO"
        end
        local previousSpent=ledger.spent
        ledger.spent=math.min(ledger.pending,costFor(ledger.served))

        -- Puede recargar durante las 24 horas. Primero verificamos cambio.
        if ledger.mode=="24horas" and not reason then
            refreshInventories()
            if not payment or not storage then reason="ERROR INVENTARIO"
            else
                local topup=countCurrency(payment)
                if valueOf(topup)>0 and not startBlockedByChange(topup) then
                    local ok=addPaymentFunds(topup)
                    if not ok then reason="ERROR RECARGA" end
                end
            end
        end

        -- Persistir siempre que cambie la parte cobrada y al menos cada 1s.
        if now-lastSave>=1000 or ledger.spent~=previousSpent or action~="sample" or reason then
            saveLedger()
            lastSave=now
        end
        if ledger.mode=="24horas" and now-ledger.start_ms>=cfg.max_hours*3600000 then
            reason="24 HORAS COMPLETADAS"
        end
        -- No agotar el credito al cobrar el PRIMER FE de un bloque de 10.
        -- Cada bloque comprado se puede utilizar hasta completar sus 10 FE.
        if remainingFE() <= 0 then
            reason="CREDITO AGOTADO"
        end
        if reason then break end

        local message
        if ledger.mode == "24horas" then
            message = rate <= cfg.flow_epsilon_fe
                and "24H EN ESPERA | F+PIN: parar"
                or "F: PIN para parar | C: admin"
        else
            message="F: parar"
        end
        sessionScreen(message,true,rate)

        if action=="stop" then
            closeValve()
            saveLedger()
            if ledger.mode=="24horas" then
                if checkSessionPIN("PARAR SESION 24H") then
                    reason="PARADO CON PIN"
                    authorized=true
                    break
                end
            else
                reason="PARADO"
                authorized=true
                break
            end
            -- PIN incorrecto: NO cancelar, sin suministro durante el dialogo.
            lastAt=os.epoch("utc")
            zeroSince=lastAt
            elapsedSinceStart=lastAt
            openValve()
        elseif action=="admin" then
            closeValve()
            saveLedger()
            adminMenu()
            if adminCancelRequested then
                reason="CANCELACION ADMIN"
                authorized=true
                adminCancelRequested=false
                break
            end
            if cfg.out_of_service then
                reason="FUERA DE SERVICIO"
                break
            end
            -- No facturar el tiempo detenido mientras se usa el menu.
            lastAt=os.epoch("utc")
            zeroSince=lastAt
            elapsedSinceStart=lastAt
            openValve()
        end
    end
    closeValve()
    -- Conservamos los datos del coste y saldo antes de devolver cambio.
    ledger.spent=math.min(ledger.pending,costFor(ledger.served))
    saveLedger()
    local credit,cost,served=ledger.pending,ledger.spent,ledger.served
    local done=finishSession(reason or "FINALIZADO",authorized)
    if not done then
        sessionScreen("SALDO PROTEGIDO: F + PIN | R: REANUDAR",false,rate)
    else
        drawMain({status=reason or "FINALIZADO", credit=credit,served=served,
            cost=cost, throughput=rate, mode=cfg.mode,
            message="Cobrado: "..cost.." DC. Cambio: "..(credit-cost).." DC"})
        sleep(2.5)
    end
end
local function beginSession()
    closeValve()
    if cfg.out_of_service or ledger.pending>0 or ledger.claim_required then return end
    local ok,err=refreshRelay()
    if not ok then drawMain({status="ERROR RELAY",message=tostring(err)}) sleep(2) return end
    local v,e=readRelay()
    if v==nil then drawMain({status="ERROR RELAY",message=tostring(e)}) sleep(2) return end
    refreshInventories()
    if not payment or not storage then return end
    local amounts=countCurrency(payment)
    local value=valueOf(amounts)
    if not creditEnough(value) then
        drawMain({status="SIN CREDITO",message="Introduce al menos "..cfg.coins_per_block.." DC"})
        sleep(1.5)
        return
    end
    if startBlockedByChange(amounts) then
        drawMain({status="SIN CAMBIO",message="Repon 9 Diamond Coins en la caja"})
        sleep(2)
        return
    end
    local pin=""
    if cfg.mode=="24horas" then
        pin=createSessionPIN()
        if not pin then return end
    end
    ledger.mode=cfg.mode
    ledger.start_ms=os.epoch("utc")
    ledger.price_coins=cfg.coins_per_block
    ledger.price_fe=cfg.fe_per_block
    ledger.session_pin=pin
    ledger.pending,ledger.spent,ledger.served=0,0,0
    ledger.diamond_in,ledger.netherite_in=0,0
    ledger.active=false
    ledger.claim_required=false
    ledger.reason=""
    saveLedger()
    local moved,detail=addPaymentFunds(amounts)
    if not moved then
        if ledger.pending>0 then
            freezeProtected("ERROR PAGO / REVISAR")
            if ledger.mode~="24horas" then settleSession("ERROR PAGO") end
        else
            resetSession()
        end
        drawMain({status="ERROR PAGO",message="No se movieron todas las monedas"})
        sleep(2)
        return
    end
    runSession()
end
local function claimOrResume(resume)
    if not ledger.claim_required or ledger.mode~="24horas" then return end
    if not checkSessionPIN(resume and "REANUDAR SESION" or "FINALIZAR SESION") then return end
    if resume then
        if remainingFE() <= 0 then
            drawMain({status="SIN CREDITO",message="Primero finaliza y reclama tu saldo"})
            sleep(2) return
        end
        if os.epoch("utc")-ledger.start_ms>=cfg.max_hours*3600000 then
            drawMain({status="24H COMPLETADAS",message="Solo puedes reclamar el cambio"})
            sleep(2) return
        end
        runSession()
    else
        local paid,fe=settleSession("PARADO CON PIN")
        drawMain({status="FINALIZADO", cost=paid,served=fe,
            message="Cambio entregado. PIN eliminado."})
        sleep(2)
    end
end
local function waitIdleAction()
    local timer=os.startTimer(0.35)
    while true do
        local event,a,b,c=os.pullEvent()
        if event=="key" then
            if a==keys.f then return "start"
            elseif a==keys.c then return "admin"
            elseif a==keys.m then return "mode"
            elseif a==keys.r then return "resume" end
        end
        if event=="mouse_click" and buttonClicked(b,c) then return "start" end
        if event=="timer" and a==timer then return "refresh" end
    end
end
local function main()
    loadConfig()
    closeValve()
    loadLedger()
    -- Un reinicio no libera el dinero de la sesion 24h a cualquier persona.
    if ledger.active or (ledger.mode=="24horas" and ledger.pending>0
            and ledger.session_pin~="") then
        ledger.active=false
        ledger.claim_required=(ledger.mode=="24horas")
        ledger.reason="REINICIO: SESION BLOQUEADA"
        saveLedger()
    end
    -- Migrar saldo antiguo sin PIN? No se cargan automaticamente los antiguos
    -- ledgers del programa anterior: usa archivos separados para mayor seguridad.
    refreshRelay()
    while true do
        refreshInventories()
        closeValve()
        if ledger.claim_required then
            sessionScreen("PIN PARA RECUPERAR SALDO | F: FIN | R: SEGUIR",false,0)
        elseif ledger.pending>0 then
            -- Caso de reinicio en modo repostada: se intenta devolver cambio.
            local c=settleSession("RECUPERACION")
            drawMain({status="RECUPERACION",message="Saldo recuperado"})
        elseif cfg.out_of_service then
            drawOutOfService()
        elseif not payment then
            drawMain({status="ERROR BARRIL PAGO",message="Falta barril en "..cfg.payment_side})
        elseif not storage then
            drawMain({status="ERROR BARRIL ALMACEN",message="Falta inventario en "..cfg.storage_side})
        elseif not refreshRelay() then
            drawMain({status="ERROR RELAY",message="Conecta Redstone Relay a la izquierda"})
        else
            local c=countCurrency(payment)
            local value=valueOf(c)
            local invalid=countInvalidItems()
            local msg
            if startBlockedByChange(c) then msg="Para NC, pon 9 DC de cambio en caja"
            elseif value>=cfg.coins_per_block then msg="F comenzar | M cambiar modo"
            elseif value>0 then msg="Faltan "..(cfg.coins_per_block-value).." DC"
            elseif invalid>0 then msg="Objeto invalido en barril pago"
            else msg="Introduce Diamond / Netherite Coins" end
            drawMain({status=value>=cfg.coins_per_block and "LISTO" or "ESPERANDO PAGO",
                credit=value,served=0,cost=0,throughput=0,mode=cfg.mode,message=msg})
        end
        local action=waitIdleAction()
        if action=="admin" then
            adminMenu()
            if adminCancelRequested then
                adminCancelRequested=false
                if ledger.claim_required or ledger.pending>0 then
                    settleSession("CANCELACION ADMIN")
                end
            end
        elseif ledger.claim_required then
            if action=="start" then claimOrResume(false)
            elseif action=="resume" then claimOrResume(true) end
        elseif action=="mode" then
            cfg.mode=cfg.mode=="repostada" and "24horas" or "repostada"
            saveConfig()
        elseif action=="start" and not cfg.out_of_service then
            beginSession()
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
