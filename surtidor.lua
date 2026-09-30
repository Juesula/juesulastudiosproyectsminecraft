-- ============================================
--          SURTIDOR DE COMBUSTIBLE
-- ============================================

local CONFIG_FILE = "/surtidor.cfg"
local ADMIN_PIN = "2050"

-- =========================
-- CONFIGURACION POR DEFECTO
-- =========================

local defaults = {
    station_name = "SURTIDOR",
    currency_name = "monedas",

    coin_id = "CAMBIAR_ESTO",
    mb_per_coin = 1000,

    payment_side = "right",
    storage_side = "bottom",

    open_side = "back",
    close_side = "left",

    pulse_time = 0.15,
    sample_time = 0.15,
    no_flow_limit = 10,

    protocol = "surtidor_tanque",
    tank_host = "tanque_1",
    tank_timeout = 2
}

local cfg = {}

for k, v in pairs(defaults) do
    cfg[k] = v
end


-- ============================================
-- CONFIGURACION
-- ============================================

local function guardarConfig()
    local f = fs.open(CONFIG_FILE, "w")

    if not f then
        error("No se pudo guardar la configuracion")
    end

    f.write(textutils.serialize(cfg))
    f.close()
end


local function cargarConfig()
    if not fs.exists(CONFIG_FILE) then
        guardarConfig()
        return
    end

    local f = fs.open(CONFIG_FILE, "r")

    if not f then
        return
    end

    local datos = textutils.unserialize(f.readAll())
    f.close()

    if type(datos) == "table" then
        for k, v in pairs(datos) do
            if defaults[k] ~= nil then
                cfg[k] = v
            end
        end
    end
end


cargarConfig()


-- ============================================
-- REDNET
-- ============================================

local function abrirModems()
    for _, nombre in ipairs(peripheral.getNames()) do
        local tipos = {peripheral.getType(nombre)}

        for _, tipo in ipairs(tipos) do
            if tipo == "modem" then
                pcall(rednet.open, nombre)
            end
        end
    end
end

abrirModems()

if not rednet.isOpen() then
    error("No hay modem conectado")
end


-- ============================================
-- INVENTARIOS
-- ============================================

local payment = nil
local storage = nil
local storageName = nil


local function actualizarInventarios()
    payment = peripheral.wrap(cfg.payment_side)
    storage = peripheral.wrap(cfg.storage_side)

    if storage then
        storageName = peripheral.getName(storage)
    else
        storageName = nil
    end
end


actualizarInventarios()


-- ============================================
-- FUNCIONES DE PANTALLA
-- ============================================

local function limpiar()
    term.clear()
    term.setCursorPos(1, 1)
end


local function pantalla(estado, credito, servido, coste)
    limpiar()

    print("================================")
    print(" " .. cfg.station_name)
    print("================================")
    print("")
    print("Estado: " .. estado)
    print("")
    print("Credito: " .. credito .. " " .. cfg.currency_name)
    print("Servido: " .. servido .. " mB")
    print("Coste:   " .. coste .. " " .. cfg.currency_name)
    print("")
    print("1 " .. cfg.currency_name .. " = " ..
        cfg.mb_per_coin .. " mB")
    print("")
    print("[C] Configuracion administrador")
end


local function pausa()
    print("")
    print("Pulsa ENTER para continuar...")
    read()
end


-- ============================================
-- ENTRADA DE CONFIGURACION
-- ============================================

local ladosValidos = {
    left = true,
    right = true,
    top = true,
    bottom = true,
    front = true,
    back = true
}


local function pedirTexto(nombre, actual)
    write(nombre .. " [" .. tostring(actual) .. "]: ")

    local valor = read()

    if valor == "" then
        return actual
    end

    return valor
end


local function pedirNumero(nombre, actual, minimo)
    write(nombre .. " [" .. tostring(actual) .. "]: ")

    local texto = read()

    if texto == "" then
        return actual
    end

    local numero = tonumber(texto)

    if not numero then
        print("Valor invalido.")
        sleep(1)
        return actual
    end

    if minimo and numero < minimo then
        print("Debe ser >= " .. minimo)
        sleep(1)
        return actual
    end

    return numero
end


local function pedirLado(nombre, actual)
    write(nombre .. " [" .. actual .. "]: ")

    local valor = read()

    if valor == "" then
        return actual
    end

    valor = string.lower(valor)

    if ladosValidos[valor] then
        return valor
    end

    print("Lado invalido.")
    print("Usa: left/right/top/bottom/front/back")
    sleep(2)

    return actual
end


-- ============================================
-- DETECTAR MONEDA
-- ============================================

local function detectarMoneda()
    local inv = peripheral.wrap(cfg.payment_side)

    limpiar()

    print("DETECTAR MONEDA")
    print("")
    print("Mete UNA moneda en el")
    print("barril de pago.")
    print("")
    print("Pulsa ENTER cuando este lista.")

    read()

    if not inv or not inv.list then
        print("")
        print("No encuentro el barril.")
        pausa()
        return
    end

    local items = inv.list()

    for slot, item in pairs(items) do
        cfg.coin_id = item.name

        print("")
        print("Moneda detectada:")
        print(item.name)
        print("")
        print("Guardada correctamente.")

        guardarConfig()
        pausa()

        return
    end

    print("")
    print("El barril esta vacio.")
    pausa()
end


-- ============================================
-- MENU ADMIN
-- ============================================

local tankID = nil


local function menuAdmin()
    limpiar()

    print("================================")
    print(" ADMINISTRADOR")
    print("================================")
    print("")
    write("Codigo: ")

    local pin = read("*")

    if pin ~= ADMIN_PIN then
        print("")
        print("CODIGO INCORRECTO")
        sleep(2)
        return
    end

    while true do
        limpiar()

        print("================================")
        print(" CONFIGURACION SURTIDOR")
        print("================================")
        print("")
        print("1  Nombre: " .. cfg.station_name)
        print("2  Nombre moneda: " .. cfg.currency_name)
        print("3  ID moneda: " .. cfg.coin_id)
        print("4  mB por moneda: " .. cfg.mb_per_coin)
        print("")
        print("5  Barril pago: " .. cfg.payment_side)
        print("6  Barril almacen: " .. cfg.storage_side)
        print("")
        print("7  Abrir valvula: " .. cfg.open_side)
        print("8  Cerrar valvula: " .. cfg.close_side)
        print("")
        print("9  Pulso redstone: " .. cfg.pulse_time)
        print("10 Lectura tanque: " .. cfg.sample_time)
        print("11 Limite sin flujo: " .. cfg.no_flow_limit)
        print("")
        print("12 Protocolo: " .. cfg.protocol)
        print("13 PC tanque: " .. cfg.tank_host)
        print("14 Timeout: " .. cfg.tank_timeout)
        print("")
        print("15 Detectar moneda")
        print("")
        print("0  GUARDAR Y SALIR")
        print("")
        write("> ")

        local opcion = read()

        if opcion == "1" then

            cfg.station_name =
                pedirTexto(
                    "Nombre surtidor",
                    cfg.station_name
                )

        elseif opcion == "2" then

            cfg.currency_name =
                pedirTexto(
                    "Nombre moneda",
                    cfg.currency_name
                )

        elseif opcion == "3" then

            cfg.coin_id =
                pedirTexto(
                    "ID moneda",
                    cfg.coin_id
                )

        elseif opcion == "4" then

            cfg.mb_per_coin =
                pedirNumero(
                    "mB por moneda",
                    cfg.mb_per_coin,
                    1
                )

        elseif opcion == "5" then

            cfg.payment_side =
                pedirLado(
                    "Lado barril pago",
                    cfg.payment_side
                )

        elseif opcion == "6" then

            cfg.storage_side =
                pedirLado(
                    "Lado barril almacen",
                    cfg.storage_side
                )

        elseif opcion == "7" then

            cfg.open_side =
                pedirLado(
                    "Lado ABRIR",
                    cfg.open_side
                )

        elseif opcion == "8" then

            cfg.close_side =
                pedirLado(
                    "Lado CERRAR",
                    cfg.close_side
                )

        elseif opcion == "9" then

            cfg.pulse_time =
                pedirNumero(
                    "Duracion pulso",
                    cfg.pulse_time,
                    0.05
                )

        elseif opcion == "10" then

            cfg.sample_time =
                pedirNumero(
                    "Intervalo lectura",
                    cfg.sample_time,
                    0.05
                )

        elseif opcion == "11" then

            cfg.no_flow_limit =
                pedirNumero(
                    "Lecturas sin flujo",
                    cfg.no_flow_limit,
                    1
                )

            cfg.no_flow_limit =
                math.floor(cfg.no_flow_limit)

        elseif opcion == "12" then

            cfg.protocol =
                pedirTexto(
                    "Protocolo Rednet",
                    cfg.protocol
                )

        elseif opcion == "13" then

            cfg.tank_host =
                pedirTexto(
                    "Nombre PC tanque",
                    cfg.tank_host
                )

        elseif opcion == "14" then

            cfg.tank_timeout =
                pedirNumero(
                    "Timeout tanque",
                    cfg.tank_timeout,
                    0.1
                )

        elseif opcion == "15" then

            detectarMoneda()

        elseif opcion == "0" then

            guardarConfig()

            tankID = nil

            actualizarInventarios()

            limpiar()

            print("CONFIGURACION GUARDADA")
            sleep(1)

            return
        end
    end
end


-- ============================================
-- REDSTONE
-- ============================================

local function pulso(lado)
    redstone.setOutput(lado, true)

    sleep(cfg.pulse_time)

    redstone.setOutput(lado, false)
end


local function abrirValvula()
    pulso(cfg.open_side)
end


local function cerrarValvula()
    pulso(cfg.close_side)
end


-- Cerramos al arrancar por seguridad
cerrarValvula()


-- ============================================
-- TANQUE REMOTO
-- ============================================

local function buscarTanque()
    tankID =
        rednet.lookup(
            cfg.protocol,
            cfg.tank_host,
            cfg.tank_timeout
        )

    return tankID ~= nil
end


local function leerTanque()
    if not tankID then
        if not buscarTanque() then
            return nil
        end
    end

    rednet.send(
        tankID,
        "read",
        cfg.protocol
    )

    local timer =
        os.startTimer(cfg.tank_timeout)

    while true do
        local event, a, b, c =
            os.pullEvent()

        if event == "rednet_message" then

            local sender = a
            local mensaje = b
            local protocolo = c

            if sender == tankID
                and protocolo == cfg.protocol
                and type(mensaje) == "table"
            then
                return mensaje
            end

        elseif event == "timer"
            and a == timer
        then

            tankID = nil
            return nil
        end
    end
end


-- ============================================
-- MONEDAS
-- ============================================

local function contarMonedas()
    if not payment or not payment.list then
        return 0
    end

    local total = 0

    for slot, item in pairs(payment.list()) do
        if item.name == cfg.coin_id then
            total = total + item.count
        end
    end

    return total
end


local function cobrarMonedas(cantidad)
    if cantidad <= 0 then
        return true
    end

    actualizarInventarios()

    if not payment
        or not storage
        or not storageName
    then
        return false
    end

    local pendientes = cantidad

    for slot, item in pairs(payment.list()) do

        if item.name == cfg.coin_id then

            local mover =
                math.min(
                    item.count,
                    pendientes
                )

            local ok, movidas =
                pcall(
                    payment.pushItems,
                    storageName,
                    slot,
                    mover
                )

            if not ok then
                return false
            end

            pendientes =
                pendientes - movidas

            if pendientes <= 0 then
                return true
            end
        end
    end

    return false
end


-- ============================================
-- ESPERA + TECLA C
-- ============================================

local function esperarConAdmin(segundos)
    local timer =
        os.startTimer(segundos)

    while true do
        local event, a =
            os.pullEvent()

        if event == "timer"
            and a == timer
        then
            return false
        end

        if event == "key"
            and a == keys.c
        then
            menuAdmin()
            return true
        end
    end
end


-- ============================================
-- REPOSTAJE
-- ============================================

local function repostar(credito)
    cerrarValvula()

    local datos = leerTanque()

    if not datos then
        pantalla(
            "ERROR: PC TANQUE",
            credito,
            0,
            0
        )

        sleep(2)
        return
    end

    local inicial = datos.amount or 0
    local anterior = inicial

    local maximo =
        credito * cfg.mb_per_coin

    local servido = 0
    local sinFlujo = 0

    pantalla(
        "ABRIENDO VALVULA",
        credito,
        0,
        0
    )

    abrirValvula()

    while true do
        sleep(cfg.sample_time)

        datos = leerTanque()

        if not datos then
            cerrarValvula()

            pantalla(
                "ERROR COMUNICACION",
                credito,
                servido,
                0
            )

            sleep(3)
            return
        end

        local actual =
            datos.amount or 0

        servido =
            inicial - actual

        if servido < 0 then
            servido = 0
        end

        local coste =
            math.ceil(
                servido /
                cfg.mb_per_coin
            )

        if coste > credito then
            coste = credito
        end

        pantalla(
            "REPOSTANDO...",
            credito,
            servido,
            coste
        )

        -- Credito agotado
        if servido >= maximo then
            break
        end

        -- Tanque surtidor vacio
        if actual <= 0 then
            break
        end

        -- Detectar si deja de salir combustible
        if actual == anterior then
            sinFlujo =
                sinFlujo + 1
        else
            sinFlujo = 0
        end

        anterior = actual

        if sinFlujo >=
            cfg.no_flow_limit
        then
            break
        end
    end

    -- CERRAR SIEMPRE ANTES DE COBRAR
    cerrarValvula()

    sleep(0.25)

    -- Medicion final
    local final =
        leerTanque()

    if final then
        servido =
            inicial -
            (final.amount or inicial)

        if servido < 0 then
            servido = 0
        end
    end

    local coste =
        math.ceil(
            servido /
            cfg.mb_per_coin
        )

    if coste > credito then
        coste = credito
    end

    local cambio =
        credito - coste

    local cobrado =
        cobrarMonedas(coste)

    if not cobrado then
        pantalla(
            "ERROR ALMACEN MONEDAS",
            credito,
            servido,
            coste
        )

        print("")
        print("REVISA EL BARRIL INFERIOR")

        sleep(5)
        return
    end

    pantalla(
        "REPOSTAJE TERMINADO",
        credito,
        servido,
        coste
    )

    print("")
    print("Cambio: " ..
        cambio .. " " ..
        cfg.currency_name)

    print("")
    print("Retira el cambio")
    print("del barril derecho.")

    sleep(3)
end


-- ============================================
-- PROGRAMA PRINCIPAL
-- ============================================

while true do

    actualizarInventarios()

    if not payment then

        pantalla(
            "ERROR BARRIL PAGO",
            0,
            0,
            0
        )

        esperarConAdmin(1)

    elseif not storage then

        pantalla(
            "ERROR BARRIL ALMACEN",
            0,
            0,
            0
        )

        esperarConAdmin(1)

    else

        local monedas =
            contarMonedas()

        if monedas <= 0 then

            pantalla(
                "INTRODUCE MONEDAS",
                0,
                0,
                0
            )

            esperarConAdmin(0.5)

        else

            pantalla(
                "CREDITO DETECTADO",
                monedas,
                0,
                0
            )

            -- Da un segundo para entrar al
            -- administrador ANTES de repostar.
            local admin =
                esperarConAdmin(1)

            if not admin then
                -- Releer por si anadio monedas
                monedas =
                    contarMonedas()

                if monedas > 0 then
                    repostar(monedas)

                    -- Esperar retirada del cambio
                    while contarMonedas() > 0 do

                        pantalla(
                            "RETIRA EL CAMBIO",
                            contarMonedas(),
                            0,
                            0
                        )

                        sleep(0.5)
                    end
                end
            end
        end
    end
end
