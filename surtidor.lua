-- ============================================================
-- SURTIDOR DE COMBUSTIBLE
-- CC:Tweaked + Lightman's Currency
--
-- 1 FuelToken = 1 Netherite Coin
-- lightmanscurrency:coin_netherite
--
-- FUNCIONAMIENTO:
--
-- 1. El cliente mete Netherite Coins en el barril derecho.
-- 2. El ordenador detecta el credito.
-- 3. NO empieza automaticamente.
-- 4. El cliente pulsa el boton START.
-- 5. Se lee el deposito principal de gasolina.
-- 6. Se abre la valvula.
-- 7. Se cobra segun los mB que bajen del deposito.
-- 8. Cuando el nivel deja de bajar, se cierra la valvula.
-- 9. Se devuelve el cambio al barril derecho.
--
-- C = Administrador
-- PIN = 2050
-- ============================================================


local CONFIG_FILE = "/surtidor.cfg"
local ADMIN_PIN = "2050"

local NETHERITE_COIN_ID =
    "lightmanscurrency:coin_netherite"


-- ============================================================
-- CONFIGURACION POR DEFECTO
-- ============================================================

local defaults = {

    station_name = "SURTIDOR",

    token_name = "FuelToken",

    token_item_id =
        NETHERITE_COIN_ID,

    -- mB comprados por 1 FuelToken
    mb_per_token = 1000,


    -- ========================================
    -- INVENTARIOS
    -- ========================================

    -- Barril donde se introducen las monedas
    -- y donde se devuelve el cambio
    payment_side = "right",

    -- Barril donde se guarda el dinero cobrado
    storage_side = "bottom",


    -- ========================================
    -- BOTON START
    -- ========================================

    -- Boton fisico de redstone
    start_button_side = "top",


    -- ========================================
    -- VALVULA
    -- ========================================

    -- Pulso para ABRIR
    open_side = "back",

    -- Pulso para CERRAR
    close_side = "left",

    pulse_time = 0.15,


    -- ========================================
    -- MEDICION
    -- ========================================

    -- Cada cuantos segundos leer el deposito
    sample_time = 0.15,

    -- Cuantas lecturas sin bajar deben ocurrir
    -- antes de considerar que ya no entra gasolina
    no_flow_limit = 10,

    -- Cuantos mB debe bajar como minimo
    -- para considerar que existe flujo
    flow_epsilon_mb = 1,


    -- ========================================
    -- REDNET
    -- ========================================

    protocol = "surtidor_tanque",

    tank_host = "tanque_1",

    tank_timeout = 2.0,


    -- ========================================
    -- CAMBIO
    -- ========================================

    change_retry_time = 0.5,
}


-- ============================================================
-- VARIABLES
-- ============================================================

local cfg = {}

local tankID = nil

local payment = nil
local storage = nil

local paymentName = nil
local storageName = nil


-- ============================================================
-- TERMINAL
-- ============================================================

local function clear()

    term.clear()

    term.setCursorPos(
        1,
        1
    )
end


-- ============================================================
-- NORMALIZAR ID DE ITEMS
-- ============================================================

local function normalizeID(value)

    if type(value) ~= "string" then
        return ""
    end

    value =
        value:gsub(
            "^%s+",
            ""
        )

    value =
        value:gsub(
            "%s+$",
            ""
        )

    return string.lower(
        value
    )
end


-- ============================================================
-- COMPROBAR FUELTOKEN
-- ============================================================

local function isFuelToken(item)

    if type(item) ~= "table" then
        return false
    end

    local id =
        normalizeID(
            item.name
        )

    -- ID configurado
    if id ==
        normalizeID(
            cfg.token_item_id
        )
    then

        return true
    end

    -- Siempre aceptar Netherite Coin oficial
    if id ==
        NETHERITE_COIN_ID
    then

        return true
    end

    return false
end


-- ============================================================
-- CONFIGURACION
-- ============================================================

local function copyDefaults()

    cfg = {}

    for k, v in pairs(defaults) do
        cfg[k] = v
    end
end


local function saveConfig()

    local file =
        fs.open(
            CONFIG_FILE,
            "w"
        )

    if not file then

        error(
            "No se pudo guardar " ..
            CONFIG_FILE
        )
    end

    file.write(
        textutils.serialize(
            cfg
        )
    )

    file.close()
end


local function loadConfig()

    copyDefaults()

    if fs.exists(
        CONFIG_FILE
    ) then

        local file =
            fs.open(
                CONFIG_FILE,
                "r"
            )

        if file then

            local data =
                textutils.unserialize(
                    file.readAll()
                )

            file.close()

            if type(data) ==
                "table"
            then

                -- ====================================
                -- MIGRACION DESDE VERSION ANTIGUA
                -- ====================================

                if data.coin_id then

                    cfg.token_item_id =
                        data.coin_id
                end


                if data.currency_name then

                    cfg.token_name =
                        data.currency_name
                end


                if data.mb_per_coin then

                    cfg.mb_per_token =
                        data.mb_per_coin
                end


                -- ====================================
                -- CARGAR CONFIG ACTUAL
                -- ====================================

                for k, v in pairs(data) do

                    if defaults[k] ~=
                        nil
                    then

                        cfg[k] = v
                    end
                end
            end
        end
    end


    -- Reparar configuraciones antiguas

    if normalizeID(
        cfg.token_item_id
    ) == ""
        or
        normalizeID(
            cfg.token_item_id
        ) == "cambiar_esto"
    then

        cfg.token_item_id =
            NETHERITE_COIN_ID
    end


    if cfg.token_name == ""
        or
        cfg.token_name ==
            "monedas"
    then

        cfg.token_name =
            "FuelToken"
    end


    saveConfig()
end


-- ============================================================
-- MODEMS
-- ============================================================

local function openModems()

    for _, name in ipairs(
        peripheral.getNames()
    ) do

        local types = {
            peripheral.getType(
                name
            )
        }

        for _, peripheralType
            in ipairs(types)
        do

            if peripheralType ==
                "modem"
            then

                pcall(
                    rednet.open,
                    name
                )
            end
        end
    end
end


-- ============================================================
-- INVENTARIOS
-- ============================================================

local function refreshInventories()

    payment =
        peripheral.wrap(
            cfg.payment_side
        )

    storage =
        peripheral.wrap(
            cfg.storage_side
        )


    if payment then

        paymentName =
            peripheral.getName(
                payment
            )

    else

        paymentName =
            nil
    end


    if storage then

        storageName =
            peripheral.getName(
                storage
            )

    else

        storageName =
            nil
    end


    -- Deben ser inventarios

    if payment and
        (
            type(payment.list) ~=
                "function"
            or
            type(payment.pushItems) ~=
                "function"
        )
    then

        payment = nil
        paymentName = nil
    end


    if storage and
        (
            type(storage.list) ~=
                "function"
            or
            type(storage.pushItems) ~=
                "function"
        )
    then

        storage = nil
        storageName = nil
    end
end


-- ============================================================
-- REPARAR ID DE LA MONEDA AUTOMATICAMENTE
-- ============================================================

local function autoRepairTokenID()

    if not payment then
        return
    end

    for _, item in pairs(
        payment.list()
    ) do

        if normalizeID(
            item.name
        ) ==
            NETHERITE_COIN_ID
        then

            if normalizeID(
                cfg.token_item_id
            ) ~=
                NETHERITE_COIN_ID
            then

                cfg.token_item_id =
                    NETHERITE_COIN_ID

                cfg.token_name =
                    "FuelToken"

                saveConfig()
            end

            return
        end
    end
end


-- ============================================================
-- REDSTONE - VALVULA
-- ============================================================

local function pulse(side)

    redstone.setOutput(
        side,
        true
    )

    sleep(
        cfg.pulse_time
    )

    redstone.setOutput(
        side,
        false
    )
end


local function openValve()

    pulse(
        cfg.open_side
    )
end


local function closeValve()

    pulse(
        cfg.close_side
    )
end


-- ============================================================
-- BOTON START
-- ============================================================

local function startButtonPressed()

    return redstone.getInput(
        cfg.start_button_side
    )
end


-- ============================================================
-- PANTALLA
-- ============================================================

local function show(
    status,
    credit,
    served,
    cost,
    extra
)

    clear()

    print(
        "================================"
    )

    print(
        " " ..
        tostring(
            cfg.station_name
        )
    )

    print(
        "================================"
    )

    print("")

    print(
        "Estado: " ..
        tostring(status)
    )

    print("")

    print(
        "1 Netherite Coin"
    )

    print(
        "= 1 " ..
        cfg.token_name
    )

    print(
        "= " ..
        tostring(
            cfg.mb_per_token
        ) ..
        " mB"
    )

    print("")

    print(
        "Credito: " ..
        tostring(
            credit or 0
        ) ..
        " " ..
        cfg.token_name
    )

    print(
        "Servido: " ..
        tostring(
            served or 0
        ) ..
        " mB"
    )

    print(
        "Coste: " ..
        tostring(
            cost or 0
        ) ..
        " " ..
        cfg.token_name
    )


    if extra and
        extra ~= ""
    then

        print("")
        print(extra)
    end


    print("")

    print(
        "[BOTON " ..
        string.upper(
            cfg.start_button_side
        ) ..
        "] Comenzar"
    )

    print(
        "[C] Administrador"
    )
end


-- ============================================================
-- MENU - UTILIDADES
-- ============================================================

local validSides = {

    left = true,
    right = true,
    top = true,
    bottom = true,
    front = true,
    back = true,
}


local function askText(
    label,
    current
)

    write(
        label ..
        " [" ..
        tostring(current) ..
        "]: "
    )

    local value =
        read()


    if value == "" then
        return current
    end


    return value
end


local function askNumber(
    label,
    current,
    minimum
)

    write(
        label ..
        " [" ..
        tostring(current) ..
        "]: "
    )

    local text =
        read()


    if text == "" then
        return current
    end


    local value =
        tonumber(
            text
        )


    if not value then

        print("")
        print(
            "Numero invalido"
        )

        sleep(1)

        return current
    end


    if minimum
        and
        value < minimum
    then

        print("")
        print(
            "Minimo: " ..
            tostring(minimum)
        )

        sleep(1)

        return current
    end


    return value
end


local function askSide(
    label,
    current
)

    local value =
        string.lower(
            askText(
                label,
                current
            )
        )


    if validSides[value] then
        return value
    end


    print("")
    print(
        "Lado invalido"
    )

    print(
        "left/right/top/bottom/front/back"
    )

    sleep(2)


    return current
end


-- ============================================================
-- DIAGNOSTICO MONEDAS
-- ============================================================

local function diagnosticCoins()

    refreshInventories()

    clear()

    print(
        "================================"
    )

    print(
        " DIAGNOSTICO DE MONEDAS"
    )

    print(
        "================================"
    )

    print("")


    if not payment then

        print(
            "No encuentro barril"
        )

        print(
            "Lado: " ..
            cfg.payment_side
        )

        print("")
        print(
            "ENTER para volver"
        )

        read()

        return
    end


    print(
        "FuelToken configurado:"
    )

    print(
        cfg.token_item_id
    )

    print("")


    local found =
        false


    for slot, item in pairs(
        payment.list()
    ) do

        found =
            true


        print(
            "Slot " ..
            tostring(slot)
        )

        print(
            tostring(
                item.count
            ) ..
            "x " ..
            tostring(
                item.name
            )
        )


        if isFuelToken(
            item
        ) then

            print(
                "FUELTOKEN VALIDO"
            )

        else

            print(
                "OBJETO NO VALIDO"
            )
        end


        print("")
    end


    if not found then

        print(
            "Barril vacio"
        )
    end


    print("")
    print(
        "ENTER para volver"
    )

    read()
end


-- ============================================================
-- MENU ADMINISTRADOR
-- ============================================================

local function adminMenu()

    clear()

    print(
        "================================"
    )

    print(
        " ADMINISTRADOR"
    )

    print(
        "================================"
    )

    print("")

    write(
        "Codigo: "
    )


    local pin =
        read("*")


    if pin ~=
        ADMIN_PIN
    then

        print("")
        print(
            "CODIGO INCORRECTO"
        )

        sleep(2)

        return
    end


    while true do

        clear()

        print(
            "================================"
        )

        print(
            " CONFIGURACION SURTIDOR"
        )

        print(
            "================================"
        )

        print("")


        print(
            "1 Nombre: " ..
            cfg.station_name
        )


        print(
            "2 Nombre token: " ..
            cfg.token_name
        )


        print(
            "3 ID token:"
        )

        print(
            "  " ..
            cfg.token_item_id
        )


        print(
            "4 mB por FuelToken: " ..
            cfg.mb_per_token
        )


        print("")


        print(
            "5 Barril pago: " ..
            cfg.payment_side
        )


        print(
            "6 Barril almacen: " ..
            cfg.storage_side
        )


        print(
            "7 Boton START: " ..
            cfg.start_button_side
        )


        print("")


        print(
            "8 Abrir valvula: " ..
            cfg.open_side
        )


        print(
            "9 Cerrar valvula: " ..
            cfg.close_side
        )


        print(
            "10 Tiempo pulso: " ..
            cfg.pulse_time
        )


        print("")


        print(
            "11 Intervalo lectura: " ..
            cfg.sample_time
        )


        print(
            "12 Lecturas sin flujo: " ..
            cfg.no_flow_limit
        )


        print(
            "13 Minimo cambio mB: " ..
            cfg.flow_epsilon_mb
        )


        print("")


        print(
            "14 Protocolo: " ..
            cfg.protocol
        )


        print(
            "15 Host tanque: " ..
            cfg.tank_host
        )


        print(
            "16 Timeout: " ..
            cfg.tank_timeout
        )


        print("")


        print(
            "17 Restaurar Netherite Coin"
        )


        print(
            "18 Diagnostico monedas"
        )


        print("")

        print(
            "0 GUARDAR Y SALIR"
        )

        print("")


        write("> ")


        local option =
            read()


        if option == "1" then

            cfg.station_name =
                askText(
                    "Nombre",
                    cfg.station_name
                )


        elseif option == "2" then

            cfg.token_name =
                askText(
                    "Nombre token",
                    cfg.token_name
                )


        elseif option == "3" then

            cfg.token_item_id =
                normalizeID(
                    askText(
                        "ID token",
                        cfg.token_item_id
                    )
                )


        elseif option == "4" then

            cfg.mb_per_token =
                askNumber(
                    "mB por FuelToken",
                    cfg.mb_per_token,
                    1
                )


        elseif option == "5" then

            cfg.payment_side =
                askSide(
                    "Barril pago",
                    cfg.payment_side
                )


        elseif option == "6" then

            cfg.storage_side =
                askSide(
                    "Barril almacen",
                    cfg.storage_side
                )


        elseif option == "7" then

            cfg.start_button_side =
                askSide(
                    "Boton START",
                    cfg.start_button_side
                )


        elseif option == "8" then

            cfg.open_side =
                askSide(
                    "Abrir valvula",
                    cfg.open_side
                )


        elseif option == "9" then

            cfg.close_side =
                askSide(
                    "Cerrar valvula",
                    cfg.close_side
                )


        elseif option == "10" then

            cfg.pulse_time =
                askNumber(
                    "Tiempo pulso",
                    cfg.pulse_time,
                    0.05
                )


        elseif option == "11" then

            cfg.sample_time =
                askNumber(
                    "Intervalo lectura",
                    cfg.sample_time,
                    0.05
                )


        elseif option == "12" then

            cfg.no_flow_limit =
                math.floor(
                    askNumber(
                        "Lecturas sin flujo",
                        cfg.no_flow_limit,
                        1
                    )
                )


        elseif option == "13" then

            cfg.flow_epsilon_mb =
                askNumber(
                    "Minimo cambio mB",
                    cfg.flow_epsilon_mb,
                    0
                )


        elseif option == "14" then

            cfg.protocol =
                askText(
                    "Protocolo",
                    cfg.protocol
                )

            tankID = nil


        elseif option == "15" then

            cfg.tank_host =
                askText(
                    "Host tanque",
                    cfg.tank_host
                )

            tankID = nil


        elseif option == "16" then

            cfg.tank_timeout =
                askNumber(
                    "Timeout",
                    cfg.tank_timeout,
                    0.2
                )


        elseif option == "17" then

            cfg.token_item_id =
                NETHERITE_COIN_ID

            cfg.token_name =
                "FuelToken"

            saveConfig()

            print("")
            print(
                "Netherite Coin restaurada"
            )

            sleep(1.5)


        elseif option == "18" then

            diagnosticCoins()


        elseif option == "0" then

            saveConfig()

            refreshInventories()

            autoRepairTokenID()

            tankID = nil

            print("")
            print(
                "Configuracion guardada"
            )

            sleep(1)

            return
        end
    end
end


-- ============================================================
-- REDNET - BUSCAR LECTOR
-- ============================================================

local function findTankComputer()

    tankID =
        rednet.lookup(
            cfg.protocol,
            cfg.tank_host
        )


    return tankID ~=
        nil
end


-- ============================================================
-- ENVIAR COMANDO AL LECTOR
-- ============================================================

local function sendTankCommand(
    command,
    waitReply
)

    if not tankID then

        if not
            findTankComputer()
        then

            return nil,
                "NO_TANK_PC"
        end
    end


    rednet.send(
        tankID,
        command,
        cfg.protocol
    )


    if not waitReply then

        return true
    end


    local timer =
        os.startTimer(
            cfg.tank_timeout
        )


    while true do

        local event,
              a,
              b,
              c =
            os.pullEvent()


        if event ==
            "rednet_message"
        then

            local sender =
                a

            local message =
                b

            local protocol =
                c


            if sender ==
                tankID
                and
                protocol ==
                    cfg.protocol
            then

                return message
            end


        elseif event ==
            "timer"
            and
            a == timer
        then

            tankID =
                nil

            return nil,
                "TIMEOUT"
        end
    end
end


-- ============================================================
-- LEER DEPOSITO
-- ============================================================

local function readTank()

    local message,
          err =
        sendTankCommand(
            "read",
            true
        )


    if not message then

        return nil,
            err
    end


    if type(message) ~=
        "table"
    then

        return nil,
            "BAD_REPLY"
    end


    if message.ok ==
        false
    then

        return nil,
            message.error
            or
            "TANK_ERROR"
    end


    if type(
        message.amount
    ) ~= "number"
    then

        return nil,
            "BAD_AMOUNT"
    end


    return message
end


-- ============================================================
-- CONTAR TOKENS
-- ============================================================

local function countTokens(
    inventory
)

    if not inventory then
        return 0
    end


    local total =
        0


    for _, item in pairs(
        inventory.list()
    ) do

        if isFuelToken(
            item
        ) then

            total =
                total +
                item.count
        end
    end


    return total
end


-- ============================================================
-- ITEMS INVALIDOS
-- ============================================================

local function getInvalidItems()

    if not payment then

        return 0,
            {}
    end


    local total =
        0

    local names =
        {}


    for _, item in pairs(
        payment.list()
    ) do

        if not
            isFuelToken(
                item
            )
        then

            total =
                total +
                item.count


            names[item.name] =
                (
                    names[
                        item.name
                    ]
                    or 0
                )
                +
                item.count
        end
    end


    return total,
        names
end


local function invalidItemText(
    names
)

    local text =
        ""


    for name, count in pairs(
        names
    ) do

        text =
            text ..
            tostring(count) ..
            "x " ..
            tostring(name) ..
            "\n"
    end


    return text
end


-- ============================================================
-- MOVER TOKENS
-- ============================================================

local function moveTokens(
    source,
    destinationName,
    amount
)

    if not source
        or
        not destinationName
        or
        amount <= 0
    then

        return 0
    end


    local moved =
        0


    for slot, item in pairs(
        source.list()
    ) do

        if isFuelToken(
            item
        ) then

            local remaining =
                amount -
                moved


            if remaining <= 0 then
                break
            end


            local wanted =
                math.min(
                    item.count,
                    remaining
                )


            local ok,
                  quantity =
                pcall(
                    source.pushItems,
                    destinationName,
                    slot,
                    wanted
                )


            if not ok then
                return moved
            end


            moved =
                moved +
                (
                    quantity
                    or 0
                )
        end
    end


    return moved
end


-- ============================================================
-- RESERVAR CREDITO
-- ============================================================

local function reserveCredit(
    amount
)

    refreshInventories()


    if not payment
        or
        not storage
    then

        return false
    end


    local moved =
        moveTokens(
            payment,
            storageName,
            amount
        )


    if moved ==
        amount
    then

        return true
    end


    -- Si solo mueve algunas,
    -- devolverlas.

    if moved >
        0
    then

        moveTokens(
            storage,
            paymentName,
            moved
        )
    end


    return false
end


-- ============================================================
-- DEVOLVER CAMBIO
-- ============================================================

local function returnChange(
    amount
)

    refreshInventories()


    if not payment
        or
        not storage
    then

        return 0
    end


    return moveTokens(
        storage,
        paymentName,
        amount
    )
end


local function finishChange(
    amount
)

    local pending =
        amount


    while pending >
        0
    do

        local returned =
            returnChange(
                pending
            )


        pending =
            pending -
            returned


        if pending >
            0
        then

            show(
                "CAMBIO PENDIENTE",
                0,
                0,
                0,

                "Faltan " ..
                tostring(
                    pending
                ) ..
                " FuelToken(s)\n" ..
                "Libera espacio en el barril derecho."
            )


            sleep(
                cfg.change_retry_time
            )
        end
    end
end


-- ============================================================
-- REPOSTAJE
-- ============================================================

local function refuel(
    credit
)

    -- ============================================
    -- 1. CERRAR POR SEGURIDAD
    -- ============================================

    closeValve()


    -- ============================================
    -- 2. RESERVAR LAS MONEDAS
    -- ============================================

    if not
        reserveCredit(
            credit
        )
    then

        show(
            "ERROR AL GUARDAR PAGO",
            credit,
            0,
            0,

            "Comprueba el barril inferior."
        )

        sleep(3)

        return
    end


    -- ============================================
    -- 3. LEER DEPOSITO ANTES DE ABRIR
    -- ============================================

    sendTankCommand(
        "begin",
        false
    )


    local first,
          firstError =
        readTank()


    if not first then

        closeValve()

        sendTankCommand(
            "end",
            false
        )

        -- No se ha servido nada:
        -- devolver todo.

        finishChange(
            credit
        )


        show(
            "ERROR LECTOR TANQUE",
            0,
            0,
            0,

            tostring(
                firstError
            )
        )

        sleep(3)

        return
    end


    local initial =
        first.amount


    local previous =
        initial


    local lowest =
        initial


    local noFlow =
        0


    -- Maximo que puede comprar
    -- con sus monedas.

    local maxFuel =
        credit *
        cfg.mb_per_token


    local reason =
        "FINALIZADO"


    -- ============================================
    -- 4. ABRIR VALVULA
    -- ============================================

    show(
        "REPOSTANDO",
        credit,
        0,
        0,

        "Deposito inicial: " ..
        tostring(
            initial
        ) ..
        " mB"
    )


    openValve()


    -- ============================================
    -- 5. MEDIR CUANTO BAJA EL DEPOSITO
    -- ============================================

    while true do

        sleep(
            cfg.sample_time
        )


        local data,
              readError =
            readTank()


        -- ========================================
        -- ERROR DE COMUNICACION
        -- ========================================

        if not data then

            reason =
                "ERROR COMUNICACION"

            break
        end


        local current =
            data.amount


        -- ========================================
        -- EL DEPOSITO HA SUBIDO
        -- ========================================
        --
        -- Esto significa que se esta rellenando
        -- mientras estamos midiendo.
        --
        -- No podemos saber correctamente cuanto
        -- combustible ha salido.
        -- ========================================

        if current >
            previous
        then

            reason =
                "DEPOSITO RELLENANDOSE"

            break
        end


        -- Guardar el nivel mas bajo observado

        if current <
            lowest
        then

            lowest =
                current
        end


        -- ========================================
        -- CALCULAR mB SERVIDOS
        -- ========================================

        local served =
            math.max(
                0,
                initial -
                lowest
            )


        -- ========================================
        -- CALCULAR PRECIO
        -- ========================================

        local cost =
            math.ceil(
                served /
                cfg.mb_per_token
            )


        if cost >
            credit
        then

            cost =
                credit
        end


        -- ========================================
        -- MOSTRAR DATOS EN TIEMPO REAL
        -- ========================================

        show(
            "REPOSTANDO",
            credit,
            served,
            cost,

            "Deposito: " ..
            tostring(
                current
            ) ..
            " mB\n" ..

            "Bajada: " ..
            tostring(
                served
            ) ..
            " mB\n" ..

            "Credito restante: " ..
            tostring(
                math.max(
                    0,
                    credit -
                    cost
                )
            )
        )


        -- ========================================
        -- CREDITO AGOTADO
        -- ========================================

        if served >=
            maxFuel
        then

            reason =
                "CREDITO AGOTADO"

            break
        end


        -- ========================================
        -- DEPOSITO VACIO
        -- ========================================

        if current <=
            0
        then

            reason =
                "DEPOSITO VACIO"

            break
        end


        -- ========================================
        -- DETECTAR SI EL CONTADOR SIGUE BAJANDO
        -- ========================================

        local difference =
            previous -
            current


        if difference >=
            cfg.flow_epsilon_mb
        then

            -- Sigue bajando:
            -- hay flujo.

            noFlow =
                0

        else

            -- No ha bajado.

            noFlow =
                noFlow +
                1
        end


        -- ========================================
        -- SI NO BAJA DURANTE VARIAS LECTURAS,
        -- EL DEPOSITO DEL VEHICULO ESTA LLENO
        -- O YA NO ADMITE MAS COMBUSTIBLE.
        -- ========================================

        if noFlow >=
            cfg.no_flow_limit
        then

            reason =
                "SIN FLUJO / DEPOSITO LLENO"

            break
        end


        previous =
            current
    end


    -- ============================================
    -- 6. CERRAR VALVULA
    -- ============================================

    closeValve()


    sendTankCommand(
        "end",
        false
    )


    -- Esperar un poco por si quedaba
    -- liquido terminando de salir.

    sleep(
        0.25
    )


    -- ============================================
    -- 7. LECTURA FINAL
    -- ============================================

    local final =
        readTank()


    if final then

        if final.amount <
            lowest
        then

            lowest =
                final.amount
        end
    end


    -- ============================================
    -- 8. CANTIDAD REAL SERVIDA
    -- ============================================

    local served =
        math.max(
            0,
            initial -
            lowest
        )


    -- ============================================
    -- 9. PRECIO FINAL
    -- ============================================

    local cost =
        math.ceil(
            served /
            cfg.mb_per_token
        )


    if cost >
        credit
    then

        cost =
            credit
    end


    -- ============================================
    -- 10. CAMBIO
    -- ============================================

    local change =
        credit -
        cost


    finishChange(
        change
    )


    -- ============================================
    -- 11. RESULTADO
    -- ============================================

    show(
        reason,
        credit,
        served,
        cost,

        "Deposito inicial: " ..
        tostring(
            initial
        ) ..
        " mB\n" ..

        "Deposito final: " ..
        tostring(
            lowest
        ) ..
        " mB\n" ..

        "Total servido: " ..
        tostring(
            served
        ) ..
        " mB\n" ..

        "Cambio: " ..
        tostring(
            change
        ) ..
        " FuelToken(s)"
    )


    sleep(4)
end


-- ============================================================
-- ESPERAR EVENTOS EN REPOSO
-- ============================================================

local function waitIdleEvent(
    lastButtonState
)

    local timer =
        os.startTimer(
            0.5
        )


    while true do

        local event,
              value =
            os.pullEvent()


        -- ========================================
        -- ADMIN
        -- ========================================

        if event ==
            "key"
            and
            value ==
                keys.c
        then

            return
                "admin",
                startButtonPressed()
        end


        -- ========================================
        -- CAMBIO DE REDSTONE
        -- ========================================

        if event ==
            "redstone"
        then

            local current =
                startButtonPressed()


            -- Solo reaccionar al flanco:
            -- OFF -> ON

            if current
                and
                not lastButtonState
            then

                return
                    "start",
                    current
            end


            lastButtonState =
                current
        end


        -- ========================================
        -- REFRESCAR PANTALLA
        -- ========================================

        if event ==
            "timer"
            and
            value ==
                timer
        then

            return
                "refresh",
                startButtonPressed()
        end
    end
end


-- ============================================================
-- PROGRAMA PRINCIPAL
-- ============================================================

local function main()

    loadConfig()

    openModems()


    if not
        rednet.isOpen()
    then

        error(
            "No hay modem conectado"
        )
    end


    refreshInventories()

    autoRepairTokenID()


    -- ============================================
    -- CERRAR VALVULA AL ARRANCAR
    -- ============================================

    closeValve()


    -- Estado inicial del boton.
    -- Asi no empieza si el boton
    -- ya estaba pulsado al iniciar.

    local lastButtonState =
        startButtonPressed()


    while true do

        refreshInventories()

        autoRepairTokenID()


        -- ========================================
        -- ERROR BARRIL PAGO
        -- ========================================

        if not payment then

            show(
                "ERROR BARRIL PAGO",
                0,
                0,
                0,

                "No encuentro inventario en:\n" ..
                cfg.payment_side
            )


        -- ========================================
        -- ERROR BARRIL ALMACEN
        -- ========================================

        elseif not storage then

            show(
                "ERROR BARRIL ALMACEN",
                0,
                0,
                0,

                "No encuentro inventario en:\n" ..
                cfg.storage_side
            )


        else

            -- ====================================
            -- CONTAR MONEDAS
            -- ====================================

            local credit =
                countTokens(
                    payment
                )


            local invalid,
                  invalidNames =
                getInvalidItems()


            local extra =
                ""


            -- ====================================
            -- SIN MONEDAS
            -- ====================================

            if credit <=
                0
            then

                extra =
                    "Inserta Netherite Coins.\n" ..
                    "Despues pulsa el boton START."


                if invalid >
                    0
                then

                    extra =
                        extra ..
                        "\n\nOBJETO NO VALIDO:\n" ..
                        invalidItemText(
                            invalidNames
                        )
                end


                show(
                    "ESPERANDO PAGO",
                    0,
                    0,
                    0,
                    extra
                )


            -- ====================================
            -- HAY CREDITO
            -- ====================================

            else

                extra =
                    tostring(
                        credit
                    ) ..
                    " Netherite Coin(s)\n" ..

                    "= " ..
                    tostring(
                        credit
                    ) ..
                    " FuelToken(s)\n\n" ..

                    "Maximo: " ..
                    tostring(
                        credit *
                        cfg.mb_per_token
                    ) ..
                    " mB\n\n" ..

                    "Pulsa el boton START."


                show(
                    "LISTO PARA REPOSTAR",
                    credit,
                    0,
                    0,
                    extra
                )
            end
        end


        -- ========================================
        -- ESPERAR BOTON / C / REFRESCO
        -- ========================================

        local event

        event,
        lastButtonState =
            waitIdleEvent(
                lastButtonState
            )


        -- ========================================
        -- ADMIN
        -- ========================================

        if event ==
            "admin"
        then

            adminMenu()

            refreshInventories()

            autoRepairTokenID()

            tankID =
                nil

            lastButtonState =
                startButtonPressed()


        -- ========================================
        -- BOTON START
        -- ========================================

        elseif event ==
            "start"
        then

            refreshInventories()

            autoRepairTokenID()


            local credit =
                countTokens(
                    payment
                )


            -- ====================================
            -- BOTON SIN MONEDAS
            -- ====================================

            if credit <=
                0
            then

                show(
                    "SIN CREDITO",
                    0,
                    0,
                    0,

                    "Introduce Netherite Coins\nantes de comenzar."
                )

                sleep(
                    1.5
                )


            -- ====================================
            -- COMENZAR REPOSTAJE
            -- ====================================

            else

                refuel(
                    credit
                )
            end


            -- Debe soltar el boton antes
            -- de poder iniciar otra venta.

            lastButtonState =
                startButtonPressed()
        end
    end
end


-- ============================================================
-- ARRANQUE SEGURO
-- ============================================================

local ok,
      err =
    pcall(
        main
    )


-- Si ocurre un error,
-- intentar cerrar siempre.

pcall(
    closeValve
)


if not ok then

    clear()

    print(
        "ERROR FATAL DEL SURTIDOR"
    )

    print("")

    print(
        tostring(
            err
        )
    )

    print("")

    print(
        "Se intento cerrar la valvula."
    )
end
