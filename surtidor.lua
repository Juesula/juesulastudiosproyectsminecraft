-- ============================================================
-- SURTIDOR DE COMBUSTIBLE
-- CC:Tweaked + Lightman's Currency
--
-- 1 FuelToken = 1 Netherite Coin
-- Item esperado:
-- lightmanscurrency:coin_netherite
--
-- C = Administrador
-- PIN = 2050
-- ============================================================

local CONFIG_FILE = "/surtidor.cfg"
local ADMIN_PIN = "2050"

-- ============================================================
-- CONFIGURACION POR DEFECTO
-- ============================================================

local defaults = {

    station_name = "SURTIDOR",

    token_name = "FuelToken",

    token_item_id =
        "lightmanscurrency:coin_netherite",

    -- Combustible comprado por cada FuelToken
    mb_per_token = 1000,

    -- Barril donde el cliente mete monedas
    -- y donde recibe el cambio
    payment_side = "right",

    -- Barril donde se guardan
    -- las monedas cobradas
    storage_side = "bottom",

    -- Señales para la valvula
    open_side = "back",
    close_side = "left",

    -- Duracion del pulso de redstone
    pulse_time = 0.15,

    -- Cada cuanto consultar el tanque
    sample_time = 0.15,

    -- Numero de lecturas sin bajar
    -- antes de considerar que no hay flujo
    no_flow_limit = 10,

    -- Tiempo desde detectar monedas
    -- hasta comenzar el repostaje
    sale_start_delay = 1.0,

    -- Reintento si no cabe el cambio
    change_retry_time = 0.5,

    -- Comunicacion con PC del tanque
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
        textutils.serialize(cfg)
    )

    file.close()
end


local function loadConfig()

    copyDefaults()

    if fs.exists(CONFIG_FILE) then

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

            if type(data) == "table" then

                -- Migracion desde
                -- versiones anteriores

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

                for k, v in pairs(data) do

                    if defaults[k] ~= nil then
                        cfg[k] = v
                    end
                end
            end
        end
    end

    -- Corregir configuracion antigua

    if cfg.token_item_id ==
        "CAMBIAR_ESTO"
    then

        cfg.token_item_id =
            "lightmanscurrency:coin_netherite"
    end

    if cfg.token_name ==
        "monedas"
    then

        cfg.token_name =
            "FuelToken"
    end

    saveConfig()
end


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
-- MODEMS
-- ============================================================

local function openModems()

    for _, name in ipairs(
        peripheral.getNames()
    ) do

        local types = {
            peripheral.getType(name)
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

    -- Comprobar que realmente sean
    -- inventarios compatibles

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
-- PANTALLA PRINCIPAL
-- ============================================================

local function show(
    status,
    credit,
    served,
    cost,
    extra
)

    clear()

    print("================================")
    print(" " .. tostring(cfg.station_name))
    print("================================")
    print("")

    print(
        "Estado: " ..
        tostring(status)
    )

    print("")

    print(
        "Precio:"
    )

    print(
        "1 " ..
        cfg.token_name ..
        " = " ..
        tostring(cfg.mb_per_token) ..
        " mB"
    )

    print("")

    print(
        "Credito: " ..
        tostring(credit or 0) ..
        " " ..
        cfg.token_name
    )

    print(
        "Servido: " ..
        tostring(served or 0) ..
        " mB"
    )

    print(
        "Coste:   " ..
        tostring(cost or 0) ..
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
-- FUNCIONES DEL MENU
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

        print("Numero invalido.")

        sleep(1)

        return current
    end

    if minimum and
        value < minimum
    then

        print(
            "El minimo es " ..
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
    print("Lado invalido.")
    print(
        "left/right/top/bottom/front/back"
    )

    sleep(2)

    return current
end


-- ============================================================
-- DETECTAR ITEM DEL BARRIL
-- ============================================================

local function detectItem()

    refreshInventories()

    clear()

    print("================================")
    print(" DETECTOR DE ITEM")
    print("================================")
    print("")

    if not payment then

        print(
            "No encuentro el barril"
        )

        print(
            "en: " ..
            cfg.payment_side
        )

        print("")
        print(
            "Pulsa ENTER..."
        )

        read()

        return
    end

    local items =
        payment.list()

    local found = false

    for slot, item in pairs(items) do

        found = true

        print(
            "Slot: " ..
            tostring(slot)
        )

        print(
            "Cantidad: " ..
            tostring(item.count)
        )

        print("")

        print("ID DETECTADO:")

        print(
            tostring(item.name)
        )

        print("")

        print(
            "ID configurado:"
        )

        print(
            cfg.token_item_id
        )

        print("")

        if item.name ==
            cfg.token_item_id
        then

            print(
                "RESULTADO: VALIDO"
            )

        else

            print(
                "RESULTADO: NO COINCIDE"
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
        "Pulsa ENTER..."
    )

    read()
end


-- ============================================================
-- USAR ITEM DETECTADO COMO FUELTOKEN
-- ============================================================

local function setDetectedItem()

    refreshInventories()

    clear()

    print("================================")
    print(" CONFIGURAR FUELTOKEN")
    print("================================")
    print("")

    if not payment then

        print(
            "No encuentro el barril"
        )

        sleep(2)

        return
    end

    local items =
        payment.list()

    for _, item in pairs(items) do

        print(
            "Detectado:"
        )

        print(
            item.name
        )

        print("")

        write(
            "Usar como FuelToken? S/N: "
        )

        local answer =
            string.lower(
                read()
            )

        if answer == "s" or
            answer == "si"
        then

            cfg.token_item_id =
                item.name

            saveConfig()

            print("")
            print(
                "FuelToken actualizado."
            )

            sleep(2)
        end

        return
    end

    print(
        "El barril esta vacio."
    )

    sleep(2)
end


-- ============================================================
-- MENU ADMINISTRADOR
-- ============================================================

local function adminMenu()

    clear()

    print("================================")
    print(" ADMINISTRADOR")
    print("================================")
    print("")

    write("Codigo: ")

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

        print("================================")
        print(" CONFIGURACION SURTIDOR")
        print("================================")
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
            "4  mB por FuelToken: " ..
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
            "17 Restaurar Netherite Coin"
        )

        print(
            "18 Ver item del barril"
        )

        print(
            "19 Usar item del barril"
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
                askText(
                    "ID FuelToken",
                    cfg.token_item_id
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
                "lightmanscurrency:coin_netherite"

            saveConfig()

            print("")
            print(
                "Restaurado:"
            )

            print(
                "lightmanscurrency:coin_netherite"
            )

            sleep(2)


        elseif option == "18" then

            detectItem()


        elseif option == "19" then

            setDetectedItem()


        elseif option == "0" then

            saveConfig()

            refreshInventories()

            tankID = nil

            print("")
            print(
                "Configuracion guardada."
            )

            sleep(1)

            return
        end
    end
end


-- ============================================================
-- ESPERA CON TECLA C
-- ============================================================

local function waitWithAdmin(seconds)

    local timer =
        os.startTimer(
            seconds
        )

    while true do

        local event,
              value =
            os.pullEvent()

        if event == "timer"
            and value == timer
        then

            return false
        end

        if event == "key"
            and value == keys.c
        then

            adminMenu()

            return true
        end
    end
end


-- ============================================================
-- REDNET / TANQUE
-- ============================================================

local function findTankComputer()

    tankID =
        rednet.lookup(
            cfg.protocol,
            cfg.tank_host
        )

    return tankID ~= nil
end


local function sendTankCommand(
    command,
    waitReply
)

    if not tankID then

        if not findTankComputer() then
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

            if sender == tankID
                and protocol ==
                    cfg.protocol
            then

                return message
            end

        elseif event == "timer"
            and a == timer
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
        return nil, err
    end

    if type(message) ~=
        "table"
    then

        return nil,
            "BAD_REPLY"
    end

    if message.ok == false then

        return nil,
            message.error
            or "TANK_ERROR"
    end

    if type(message.amount) ~=
        "number"
    then

        return nil,
            "BAD_AMOUNT"
    end

    return message
end


-- ============================================================
-- CONTAR FUELTOKENS
-- ============================================================

local function countTokens(inv)

    if not inv then
        return 0
    end

    local total = 0

    for _, item in pairs(
        inv.list()
    ) do

        if item.name ==
            cfg.token_item_id
        then

            total =
                total +
                item.count
        end
    end

    return total
end


-- ============================================================
-- OBJETOS NO VALIDOS
-- ============================================================

local function getInvalidItems()

    if not payment then
        return 0, {}
    end

    local total = 0
    local names = {}

    for _, item in pairs(
        payment.list()
    ) do

        if item.name ~=
            cfg.token_item_id
        then

            total =
                total +
                item.count

            names[item.name] =
                (
                    names[item.name]
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
    invalidNames
)

    local text = ""

    for name, count in pairs(
        invalidNames
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
-- MOVER FUELTOKENS
-- ============================================================

local function moveTokens(
    source,
    destinationName,
    amount
)

    if not source or
        not destinationName or
        amount <= 0
    then

        return 0
    end

    local moved = 0

    for slot, item in pairs(
        source.list()
    ) do

        if item.name ==
            cfg.token_item_id
        then

            local remaining =
                amount - moved

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

    if not payment or
        not storage
    then

        return false, 0
    end

    local moved =
        moveTokens(
            payment,
            storageName,
            amount
        )

    if moved == amount then

        return true,
            moved
    end

    -- Si no pudieron pasar todas,
    -- devolvemos lo movido.

    if moved > 0 then

        moveTokens(
            storage,
            paymentName,
            moved
        )
    end

    return false,
        moved
end


-- ============================================================
-- DEVOLVER CAMBIO
-- ============================================================

local function returnChange(
    amount
)

    refreshInventories()

    if not payment or
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
    change
)

    local pending =
        change

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
                tostring(pending) ..
                " " ..
                cfg.token_name ..
                "\nLibera espacio en el barril derecho."
            )

            sleep(
                cfg.change_retry_time
            )

            refreshInventories()
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

    -- Pasar monedas primero
    -- al barril inferior

    local reserved =
        reserveCredit(
            credit
        )

    if not reserved then

        show(
            "NO PUEDO GUARDAR PAGO",
            credit,
            0,
            0,

            "Comprueba el barril inferior\ny la conexion de perifericos."
        )

        sleep(4)

        return
    end


    -- Avisar al lector
    sendTankCommand(
        "begin",
        false
    )


    -- Primera lectura

    local first,
          readError =
        readTank()

    if not first then

        closeValve()

        sendTankCommand(
            "end",
            false
        )

        finishChange(
            credit
        )

        show(
            "ERROR TANQUE",
            0,
            0,
            0,
            tostring(readError)
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

    local noFlow = 0

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


        local data,
              err =
            readTank()


        if not data then

            reason =
                "ERROR COMUNICACION"

            break
        end


        local current =
            data.amount


        -- Si el tanque aumenta,
        -- alguien lo esta rellenando
        -- durante la venta.

        if current > previous then

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


        if cost > credit then
            cost = credit
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
                    credit - cost
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

        if current <= 0 then

            reason =
                "TANQUE VACIO"

            break
        end


        -- Detectar ausencia de flujo

        if current ==
            previous
        then

            noFlow =
                noFlow + 1

        else

            noFlow = 0
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


    -- Cerrar siempre
    closeValve()


    sendTankCommand(
        "end",
        false
    )


    -- Ultima lectura

    sleep(0.2)

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


    if cost > credit then
        cost = credit
    end


    local change =
        credit -
        cost


    -- Devolver monedas sobrantes

    finishChange(
        change
    )


    show(
        reason,
        credit,
        served,
        cost,

        "Cambio: " ..
        tostring(change) ..
        " " ..
        cfg.token_name ..
        "\nRetira el cambio del barril derecho."
    )


    sleep(3)
end


-- ============================================================
-- PROGRAMA PRINCIPAL
-- ============================================================

local function main()

    loadConfig()

    openModems()


    if not rednet.isOpen() then

        error(
            "No hay modem conectado al surtidor"
        )
    end


    refreshInventories()


    -- Seguridad:
    -- cerrar valvula al iniciar

    closeValve()


    while true do

        refreshInventories()


        -- ============================
        -- ERROR BARRIL PAGO
        -- ============================

        if not payment then

            show(
                "ERROR BARRIL PAGO",
                0,
                0,
                0,

                "No encuentro un inventario en:\n" ..
                cfg.payment_side
            )

            waitWithAdmin(1)


        -- ============================
        -- ERROR BARRIL ALMACEN
        -- ============================

        elseif not storage then

            show(
                "ERROR BARRIL ALMACEN",
                0,
                0,
                0,

                "No encuentro un inventario en:\n" ..
                cfg.storage_side
            )

            waitWithAdmin(1)


        else

            -- Contar FuelTokens validos

            local credit =
                countTokens(
                    payment
                )


            -- Detectar otros items

            local invalid,
                  invalidNames =
                getInvalidItems()


            -- ============================
            -- NO HAY CREDITO
            -- ============================

            if credit <= 0 then

                local extra =
                    "Inserta Netherite Coins.\n" ..
                    "1 Netherite Coin = 1 " ..
                    cfg.token_name


                if invalid > 0 then

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


            -- ============================
            -- CREDITO DETECTADO
            -- ============================

            else

                local extra =
                    "FuelTokens detectados: " ..
                    tostring(credit)


                if invalid > 0 then

                    extra =
                        extra ..
                        "\n\nOBJETO NO VALIDO:\n" ..
                        invalidItemText(
                            invalidNames
                        )
                end


                show(
                    "CREDITO DETECTADO",
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

                    -- Volver a contar por si
                    -- introduce mas monedas

                    credit =
                        countTokens(
                            payment
                        )


                    if credit > 0 then

                        refuel(
                            credit
                        )


                        -- Esperar a que retire
                        -- las monedas de cambio

                        while
                            countTokens(
                                payment
                            ) > 0
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

                                "Retira las Netherite Coins\ndel barril derecho."
                            )

                            sleep(0.5)
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


-- Intentar cerrar siempre
-- la valvula si ocurre un error

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
        "La valvula se ha intentado cerrar."
    )
end
