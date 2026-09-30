-- ============================================================
-- SURTIDOR DE COMBUSTIBLE
-- CC:Tweaked + Lightman's Currency
--
-- 1 FuelToken = 1 Netherite Coin
-- ID:
-- lightmanscurrency:coin_netherite
--
-- C = Administrador
-- PIN = 2050
-- ============================================================

local CONFIG_FILE = "/surtidor.cfg"
local ADMIN_PIN = "2050"

-- ============================================================
-- CONSTANTES
-- ============================================================

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

    -- mB que compra 1 FuelToken
    mb_per_token = 1000,

    -- Barril cliente / cambio
    payment_side = "right",

    -- Barril caja
    storage_side = "bottom",

    -- Valvula
    open_side = "back",
    close_side = "left",

    pulse_time = 0.15,

    -- Lectura del tanque
    sample_time = 0.15,
    no_flow_limit = 10,

    -- Espera antes de comenzar
    sale_start_delay = 1.0,

    -- Cambio
    change_retry_time = 0.5,

    -- Rednet
    protocol = "surtidor_tanque",
    tank_host = "tanque_1",
    tank_timeout = 2.0,
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
-- UTILIDADES
-- ============================================================

local function clear()

    term.clear()

    term.setCursorPos(
        1,
        1
    )
end


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

    value =
        string.lower(
            value
        )

    return value
end


local function isFuelToken(item)

    if type(item) ~= "table" then
        return false
    end

    local itemID =
        normalizeID(
            item.name
        )

    local configuredID =
        normalizeID(
            cfg.token_item_id
        )

    -- ID configurado
    if itemID ==
        configuredID
    then

        return true
    end

    -- Netherite Coin oficial.
    -- Esto evita que una configuracion
    -- antigua rompa el surtidor.
    if itemID ==
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

                -- =============================
                -- MIGRACION VERSION ANTIGUA
                -- =============================

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


                -- =============================
                -- CONFIGURACION ACTUAL
                -- =============================

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


    -- ========================================================
    -- REPARAR CONFIGURACIONES ANTIGUAS
    -- ========================================================

    local configured =
        normalizeID(
            cfg.token_item_id
        )


    if configured == "" or
        configured ==
            "cambiar_esto"
    then

        cfg.token_item_id =
            NETHERITE_COIN_ID
    end


    if cfg.token_name ==
        "monedas"
        or
        cfg.token_name == ""
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

        paymentName = nil
    end


    if storage then

        storageName =
            peripheral.getName(
                storage
            )

    else

        storageName = nil
    end


    -- Comprobar API de inventario

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
-- AUTODETECTAR NETHERITE COIN
-- ============================================================

local function autoRepairTokenID()

    if not payment then
        return
    end

    local items =
        payment.list()


    for _, item in pairs(items) do

        local itemID =
            normalizeID(
                item.name
            )


        if itemID ==
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
-- REDSTONE
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
        "1 " ..
        cfg.token_name ..
        " = " ..
        tostring(
            cfg.mb_per_token
        ) ..
        " mB"
    )

    print(
        "1 Netherite Coin = 1 " ..
        cfg.token_name
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
        "Coste:   " ..
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
    print("[C] Administrador")
end


-- ============================================================
-- MENU - FUNCIONES
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
        tonumber(text)


    if not value then

        print("")
        print(
            "Numero invalido."
        )

        sleep(1)

        return current
    end


    if minimum and
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
        "Lado invalido."
    )

    print(
        "left/right/top/bottom/front/back"
    )

    sleep(2)


    return current
end


-- ============================================================
-- DIAGNOSTICO DEL BARRIL
-- ============================================================

local function detectItem()

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
            "No encuentro el barril"
        )

        print(
            "en lado: " ..
            cfg.payment_side
        )

        print("")
        print(
            "ENTER para volver"
        )

        read()

        return
    end


    local items =
        payment.list()

    local found =
        false


    print(
        "ID configurado:"
    )

    print(
        normalizeID(
            cfg.token_item_id
        )
    )

    print("")


    for slot, item in pairs(
        items
    ) do

        found = true

        print(
            "SLOT " ..
            tostring(slot)
        )

        print(
            tostring(
                item.count
            ) ..
            "x"
        )

        print(
            tostring(
                item.name
            )
        )

        print("")

        print(
            "Normalizado:"
        )

        print(
            normalizeID(
                item.name
            )
        )

        print("")


        if isFuelToken(item) then

            print(
                ">>> FUELTOKEN VALIDO <<<"
            )

        else

            print(
                ">>> OBJETO NO VALIDO <<<"
            )
        end

        print("")
    end


    if not found then

        print(
            "El barril esta vacio."
        )
    end


    print("")
    print(
        "ENTER para volver"
    )

    read()
end


-- ============================================================
-- MENU ADMIN
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


    if pin ~= ADMIN_PIN then

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
            "1  Nombre: " ..
            cfg.station_name
        )


        print(
            "2  Nombre token: " ..
            cfg.token_name
        )


        print(
            "3  ID FuelToken:"
        )

        print(
            "   " ..
            cfg.token_item_id
        )


        print(
            "4  mB por token: " ..
            cfg.mb_per_token
        )


        print("")


        print(
            "5  Barril pago: " ..
            cfg.payment_side
        )


        print(
            "6  Barril almacen: " ..
            cfg.storage_side
        )


        print("")


        print(
            "7  Abrir valvula: " ..
            cfg.open_side
        )


        print(
            "8  Cerrar valvula: " ..
            cfg.close_side
        )


        print(
            "9  Tiempo pulso: " ..
            cfg.pulse_time
        )


        print("")


        print(
            "10 Intervalo tanque: " ..
            cfg.sample_time
        )


        print(
            "11 Limite sin flujo: " ..
            cfg.no_flow_limit
        )


        print(
            "12 Espera inicio: " ..
            cfg.sale_start_delay
        )


        print(
            "13 Reintento cambio: " ..
            cfg.change_retry_time
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
            "16 Timeout tanque: " ..
            cfg.tank_timeout
        )


        print("")


        print(
            "17 FORZAR Netherite Coin"
        )


        print(
            "18 Diagnostico monedas"
        )


        print("")

        print(
            "0  GUARDAR Y SALIR"
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
                        "ID FuelToken",
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

            cfg.open_side =
                askSide(
                    "Senal ABRIR",
                    cfg.open_side
                )


        elseif option == "8" then

            cfg.close_side =
                askSide(
                    "Senal CERRAR",
                    cfg.close_side
                )


        elseif option == "9" then

            cfg.pulse_time =
                askNumber(
                    "Tiempo pulso",
                    cfg.pulse_time,
                    0.05
                )


        elseif option == "10" then

            cfg.sample_time =
                askNumber(
                    "Intervalo tanque",
                    cfg.sample_time,
                    0.05
                )


        elseif option == "11" then

            cfg.no_flow_limit =
                math.floor(
                    askNumber(
                        "Lecturas sin flujo",
                        cfg.no_flow_limit,
                        1
                    )
                )


        elseif option == "12" then

            cfg.sale_start_delay =
                askNumber(
                    "Espera inicio",
                    cfg.sale_start_delay,
                    0
                )


        elseif option == "13" then

            cfg.change_retry_time =
                askNumber(
                    "Reintento cambio",
                    cfg.change_retry_time,
                    0.1
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
                    "Timeout tanque",
                    cfg.tank_timeout,
                    0.2
                )


        elseif option == "17" then

            cfg.token_name =
                "FuelToken"

            cfg.token_item_id =
                NETHERITE_COIN_ID

            saveConfig()

            print("")
            print(
                "ID reparado:"
            )

            print(
                NETHERITE_COIN_ID
            )

            sleep(2)


        elseif option == "18" then

            detectItem()


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
-- ESPERA + TECLA C
-- ============================================================

local function waitWithAdmin(
    seconds
)

    local timer =
        os.startTimer(
            seconds
        )


    while true do

        local event,
              value =
            os.pullEvent()


        if event ==
            "timer"
            and
            value == timer
        then

            return false
        end


        if event ==
            "key"
            and
            value == keys.c
        then

            adminMenu()

            return true
        end
    end
end


-- ============================================================
-- TANQUE REMOTO
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

            local sender = a
            local message = b
            local protocol = c


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

            tankID = nil

            return nil,
                "TIMEOUT"
        end
    end
end


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
-- CONTAR FUELTOKENS
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
-- RESERVAR PAGO
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


    -- Si falla, devolver
    -- las que hayan pasado.

    if moved > 0 then

        moveTokens(
            storage,
            paymentName,
            moved
        )
    end


    return false
end


-- ============================================================
-- CAMBIO
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


    while pending > 0 do

        local returned =
            returnChange(
                pending
            )


        pending =
            pending -
            returned


        if pending > 0 then

            show(
                "CAMBIO PENDIENTE",
                0,
                0,
                0,

                "Faltan " ..
                tostring(
                    pending
                ) ..
                " " ..
                cfg.token_name ..
                "\nLibera espacio en el barril derecho."
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

    -- Seguridad
    closeValve()


    -- Guardar las monedas
    -- antes de suministrar.

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

            "Comprueba el barril inferior\ny la red de inventarios."
        )

        sleep(4)

        return
    end


    sendTankCommand(
        "begin",
        false
    )


    local first,
          tankError =
        readTank()


    if not first then

        closeValve()

        sendTankCommand(
            "end",
            false
        )

        -- No se sirvio nada.
        finishChange(
            credit
        )

        show(
            "ERROR TANQUE",
            0,
            0,
            0,
            tostring(
                tankError
            )
        )

        sleep(3)

        return
    end


    local initial =
        first.amount

    local previous =
        initial

    local minimumSeen =
        initial

    local noFlow =
        0


    local maxFuel =
        credit *
        cfg.mb_per_token


    local reason =
        "FINALIZADO"


    show(
        "ABRIENDO VALVULA",
        credit,
        0,
        0
    )


    openValve()


    while true do

        sleep(
            cfg.sample_time
        )


        local data =
            readTank()


        if not data then

            reason =
                "ERROR COMUNICACION"

            break
        end


        local current =
            data.amount


        -- El tanque no debe
        -- rellenarse durante venta.

        if current >
            previous
        then

            reason =
                "TANQUE RELLENANDOSE"

            break
        end


        if current <
            minimumSeen
        then

            minimumSeen =
                current
        end


        local served =
            math.max(
                0,
                initial -
                minimumSeen
            )


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


        show(
            "REPOSTANDO",
            credit,
            served,
            cost,

            "Credito restante: " ..
            tostring(
                math.max(
                    0,
                    credit -
                    cost
                )
            ) ..
            " " ..
            cfg.token_name
        )


        -- Credito agotado

        if served >=
            maxFuel
        then

            reason =
                "CREDITO AGOTADO"

            break
        end


        -- Tanque vacio

        if current <=
            0
        then

            reason =
                "TANQUE VACIO"

            break
        end


        -- Sin flujo

        if current ==
            previous
        then

            noFlow =
                noFlow + 1

        else

            noFlow =
                0
        end


        if noFlow >=
            cfg.no_flow_limit
        then

            reason =
                "DEPOSITO LLENO / SIN FLUJO"

            break
        end


        previous =
            current
    end


    -- Seguridad:
    -- cerrar antes de calcular

    closeValve()


    sendTankCommand(
        "end",
        false
    )


    sleep(
        0.2
    )


    local final =
        readTank()


    if final and
        final.amount <
            minimumSeen
    then

        minimumSeen =
            final.amount
    end


    local served =
        math.max(
            0,
            initial -
            minimumSeen
        )


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


    local change =
        credit -
        cost


    finishChange(
        change
    )


    show(
        reason,
        credit,
        served,
        cost,

        "Cambio: " ..
        tostring(
            change
        ) ..
        " " ..
        cfg.token_name ..
        "\nRetira las monedas del barril derecho."
    )


    sleep(3)
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


    -- Reparar automaticamente
    -- si ya hay Netherite Coins
    -- en el barril.

    autoRepairTokenID()


    -- Seguridad al arrancar

    closeValve()


    while true do

        refreshInventories()

        autoRepairTokenID()


        -- ====================================
        -- BARRIL DE PAGO
        -- ====================================

        if not payment then

            show(
                "ERROR BARRIL PAGO",
                0,
                0,
                0,

                "No encuentro inventario en:\n" ..
                cfg.payment_side
            )

            waitWithAdmin(
                1
            )


        -- ====================================
        -- BARRIL ALMACEN
        -- ====================================

        elseif not storage then

            show(
                "ERROR BARRIL ALMACEN",
                0,
                0,
                0,

                "No encuentro inventario en:\n" ..
                cfg.storage_side
            )

            waitWithAdmin(
                1
            )


        else

            local credit =
                countTokens(
                    payment
                )


            local invalid,
                  invalidNames =
                getInvalidItems()


            -- ====================================
            -- ESPERANDO PAGO
            -- ====================================

            if credit <= 0 then

                local extra =

                    "Inserta Netherite Coins.\n" ..
                    "1 Netherite Coin = 1 " ..
                    cfg.token_name


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


                waitWithAdmin(
                    0.5
                )


            -- ====================================
            -- CREDITO DETECTADO
            -- ====================================

            else

                local extra =

                    "Netherite Coins: " ..
                    tostring(
                        credit
                    ) ..
                    "\nCredito disponible: " ..
                    tostring(
                        credit
                    ) ..
                    " " ..
                    cfg.token_name


                if invalid >
                    0
                then

                    extra =
                        extra ..
                        "\n\nOtros objetos:\n" ..
                        invalidItemText(
                            invalidNames
                        )
                end


                show(
                    "PAGO DETECTADO",
                    credit,
                    0,
                    0,
                    extra
                )


                local admin =
                    waitWithAdmin(
                        cfg.sale_start_delay
                    )


                if not admin then

                    -- Volver a contar
                    -- antes de comenzar.

                    refreshInventories()

                    credit =
                        countTokens(
                            payment
                        )


                    if credit >
                        0
                    then

                        refuel(
                            credit
                        )


                        -- Esperar retirada
                        -- del cambio.

                        while
                            countTokens(
                                payment
                            ) >
                            0
                        do

                            local remaining =
                                countTokens(
                                    payment
                                )


                            show(
                                "RETIRA EL CAMBIO",
                                remaining,
                                0,
                                0,

                                "Retira " ..
                                tostring(
                                    remaining
                                ) ..
                                " Netherite Coin(s)\n" ..
                                "del barril derecho."
                            )


                            sleep(
                                0.5
                            )
                        end
                    end
                end
            end
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


-- Si ocurre cualquier error,
-- intentar cerrar la valvula.

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
        tostring(err)
    )

    print("")

    print(
        "Se intento cerrar la valvula."
    )
end
