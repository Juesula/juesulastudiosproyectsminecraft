-- ============================================================
-- SURTIDOR DE COMBUSTIBLE - CC:Tweaked + Lightman's Currency
-- 1 FuelToken = 1 lightmanscurrency:coin_netherite
-- ============================================================

local CONFIG_FILE = "/surtidor.cfg"
local ADMIN_PIN = "2050"

local defaults = {
    station_name = "SURTIDOR",
    token_name = "FuelToken",
    token_item_id = "lightmanscurrency:coin_netherite",
    mb_per_token = 1000,

    payment_side = "right",   -- Barril pago/cambio
    storage_side = "bottom",  -- Barril caja/almacen

    open_side = "back",       -- Pulso ABRIR valvula
    close_side = "left",      -- Pulso CERRAR valvula
    pulse_time = 0.15,

    sample_time = 0.15,
    no_flow_limit = 10,
    sale_start_delay = 1.0,
    change_retry_time = 0.5,

    protocol = "surtidor_tanque",
    tank_host = "tanque_1",
    tank_timeout = 2.0,
}

local cfg = {}
local tankID = nil
local payment, storage
local paymentName, storageName

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

                -- Migracion desde versiones anteriores
                if data.coin_id then
                    cfg.token_item_id = data.coin_id
                end

                if data.currency_name then
                    cfg.token_name = data.currency_name
                end

                if data.mb_per_coin then
                    cfg.mb_per_token = data.mb_per_coin
                end

                for k, v in pairs(data) do
                    if defaults[k] ~= nil then
                        cfg[k] = v
                    end
                end
            end
        end
    end

    if cfg.token_item_id == "CAMBIAR_ESTO" then
        cfg.token_item_id =
            "lightmanscurrency:coin_netherite"
    end

    if cfg.token_name == "monedas" then
        cfg.token_name = "FuelToken"
    end

    saveConfig()
end

local function clear()
    term.clear()
    term.setCursorPos(1, 1)
end

local function openModems()

    for _, name in ipairs(peripheral.getNames()) do

        local types = {
            peripheral.getType(name)
        }

        for _, t in ipairs(types) do

            if t == "modem" then
                pcall(rednet.open, name)
            end

        end
    end
end

local function refreshInventories()

    payment =
        peripheral.wrap(cfg.payment_side)

    storage =
        peripheral.wrap(cfg.storage_side)

    paymentName =
        payment and
        peripheral.getName(payment)
        or nil

    storageName =
        storage and
        peripheral.getName(storage)
        or nil

    if payment and
        (not payment.list or
         not payment.pushItems)
    then
        payment = nil
    end

    if storage and
        (not storage.list or
         not storage.pushItems)
    then
        storage = nil
    end
end

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
        "1 " ..
        cfg.token_name ..
        " = " ..
        cfg.mb_per_token ..
        " mB"
    )

    print("Item: Netherite Coin")

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

    if extra and extra ~= "" then
        print("")
        print(extra)
    end

    print("")
    print("[C] Administrador")
end

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

    local value = read()

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

    local text = read()

    if text == "" then
        return current
    end

    local value =
        tonumber(text)

    if not value or
        (minimum and
         value < minimum)
    then

        print("Valor invalido.")
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

    print(
        "Usa left/right/top/bottom/front/back"
    )

    sleep(1.5)

    return current
end

local function adminMenu()

    clear()

    print("ADMINISTRADOR")
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

        clear()

        print("================================")
        print(" CONFIGURACION SURTIDOR")
        print("================================")

        print(
            "1  Nombre: " ..
            cfg.station_name
        )

        print(
            "2  Nombre token: " ..
            cfg.token_name
        )

        print(
            "3  Item token: " ..
            cfg.token_item_id
        )

        print(
            "4  mB por token: " ..
            cfg.mb_per_token
        )

        print(
            "5  Barril pago: " ..
            cfg.payment_side
        )

        print(
            "6  Barril almacen: " ..
            cfg.storage_side
        )

        print(
            "7  Senal ABRIR: " ..
            cfg.open_side
        )

        print(
            "8  Senal CERRAR: " ..
            cfg.close_side
        )

        print(
            "9  Tiempo pulso: " ..
            cfg.pulse_time
        )

        print(
            "10 Intervalo lectura: " ..
            cfg.sample_time
        )

        print(
            "11 Lecturas sin flujo: " ..
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

        print(
            "17 Restaurar Netherite Coin"
        )

        print("")
        print("0  GUARDAR Y SALIR")
        print("")

        write("> ")

        local option = read()

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
                    "ID item token",
                    cfg.token_item_id
                )

        elseif option == "4" then

            cfg.mb_per_token =
                askNumber(
                    "mB por token",
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
                    "Intervalo lectura",
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

            print("")
            print(
                "1 FuelToken = 1 Netherite Coin"
            )

            sleep(1.5)

        elseif option == "0" then

            saveConfig()

            refreshInventories()

            tankID = nil

            print(
                "Configuracion guardada."
            )

            sleep(1)

            return
        end
    end
end

local function waitWithAdmin(seconds)

    local timer =
        os.startTimer(seconds)

    while true do

        local event, value =
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

local function findTankComputer()

    tankID =
        rednet.lookup(
            cfg.protocol,
            cfg.tank_host,
            cfg.tank_timeout
        )

    return tankID ~= nil
end

local function sendTankCommand(
    command,
    waitReply
)

    if not tankID and
        not findTankComputer()
    then
        return nil, "NO_TANK_PC"
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
              sender,
              message,
              protocol =
            os.pullEvent()

        if event ==
            "rednet_message"
        then

            if sender == tankID
                and protocol ==
                    cfg.protocol
            then
                return message
            end

        elseif event == "timer"
            and sender == timer
        then

            tankID = nil

            return nil, "TIMEOUT"
        end
    end
end

local function readTank()

    local message, err =
        sendTankCommand(
            "read",
            true
        )

    if not message then
        return nil, err
    end

    if type(message) ~= "table" then
        return nil, "BAD_REPLY"
    end

    if message.ok == false then
        return nil,
            message.error or
            "TANK_ERROR"
    end

    if type(message.amount)
        ~= "number"
    then
        return nil, "BAD_AMOUNT"
    end

    return message
end

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

local function countInvalidItems()

    if not payment then
        return 0
    end

    local total = 0

    for _, item in pairs(
        payment.list()
    ) do

        if item.name ~=
            cfg.token_item_id
        then

            total =
                total +
                item.count
        end
    end

    return total
end

local function moveTokens(
    source,
    destinationName,
    amount
)

    if amount <= 0 then
        return 0
    end

    local moved = 0

    for slot, item in pairs(
        source.list()
    ) do

        if item.name ==
            cfg.token_item_id
        then

            local wanted =
                math.min(
                    item.count,
                    amount - moved
                )

            if wanted > 0 then

                local ok, quantity =
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
                    (quantity or 0)

                if moved >= amount then
                    break
                end
            end
        end
    end

    return moved
end

local function reserveCredit(amount)

    refreshInventories()

    if not payment
        or not storage
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
        return true, moved
    end

    -- Si no caben todas,
    -- devolver las que se movieron
    if moved > 0 then

        moveTokens(
            storage,
            paymentName,
            moved
        )
    end

    return false, moved
end

local function returnChange(amount)

    refreshInventories()

    if not payment
        or not storage
    then
        return 0
    end

    return moveTokens(
        storage,
        paymentName,
        amount
    )
end

local function finishChange(change)

    local pending = change

    while pending > 0 do

        local returned =
            returnChange(pending)

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
                pending ..
                " " ..
                cfg.token_name ..
                "\nLibera espacio en el barril derecho."
            )

            waitWithAdmin(
                cfg.change_retry_time
            )

            refreshInventories()
        end
    end
end

local function refuel(credit)

    -- Seguridad
    closeValve()

    -- Guardamos primero todas
    -- las monedas introducidas
    local reserved =
        reserveCredit(credit)

    if not reserved then

        show(
            "CAJA LLENA",
            credit,
            0,
            0,
            "No puedo guardar los FuelTokens.\nVacia el barril inferior."
        )

        sleep(3)

        return
    end

    -- Bloquear configuracion
    -- del lector durante la venta
    sendTankCommand(
        "begin",
        false
    )

    local first, err =
        readTank()

    if not first then

        closeValve()

        sendTankCommand(
            "end",
            false
        )

        -- No se ha servido combustible.
        -- Devolver todo el credito.
        finishChange(credit)

        show(
            "ERROR TANQUE",
            0,
            0,
            0,
            tostring(err)
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
        "ABRIENDO",
        credit,
        0,
        0
    )

    openValve()

    while true do

        sleep(
            cfg.sample_time
        )

        local data, readErr =
            readTank()

        if not data then

            reason =
                "ERROR COMUNICACION"

            break
        end

        local current =
            data.amount

        -- Si aumenta durante la venta,
        -- el tanque esta siendo rellenado
        -- y ya no podemos medir bien.
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

            "Restante: " ..
            math.max(
                0,
                credit - cost
            ) ..
            " " ..
            cfg.token_name
        )

        -- Todo el credito gastado
        if served >= maxFuel then

            reason =
                "CREDITO AGOTADO"

            break
        end

        -- Tanque de la estacion vacio
        if current <= 0 then

            reason =
                "TANQUE VACIO"

            break
        end

        -- Detectar deposito del
        -- cliente lleno/sin flujo
        if current == previous then

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

    -- CERRAR SIEMPRE
    closeValve()

    sendTankCommand(
        "end",
        false
    )

    -- Lectura final
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

    -- Como los FuelToken
    -- son indivisibles,
    -- se redondea hacia arriba.
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
    -- del barril inferior al derecho
    finishChange(change)

    show(
        reason,
        credit,
        served,
        cost,

        "Cambio: " ..
        change ..
        " " ..
        cfg.token_name ..
        "\nRetira el cambio del barril derecho."
    )

    sleep(3)
end

local function main()

    loadConfig()

    openModems()

    if not rednet.isOpen() then

        error(
            "No hay modem conectado al ordenador del surtidor"
        )
    end

    refreshInventories()

    -- Siempre intentar cerrar
    -- al arrancar
    closeValve()

    while true do

        refreshInventories()

        if not payment then

            show(
                "ERROR BARRIL PAGO",
                0,
                0,
                0,

                "Debe estar en: " ..
                cfg.payment_side
            )

            waitWithAdmin(1)

        elseif not storage then

            show(
                "ERROR BARRIL ALMACEN",
                0,
                0,
                0,

                "Debe estar en: " ..
                cfg.storage_side
            )

            waitWithAdmin(1)

        else

            local credit =
                countTokens(
                    payment
                )

            local invalid =
                countInvalidItems()

            if credit <= 0 then

                local extra =
                    "Inserta Netherite Coins." ..
                    "\n1 moneda = 1 " ..
                    cfg.token_name

                if invalid > 0 then

                    extra =
                        extra ..
                        "\nHay " ..
                        invalid ..
                        " item(s) no validos."
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

            else

                show(
                    "CREDITO DETECTADO",
                    credit,
                    0,
                    0,

                    "Inserta mas o espera para comenzar."
                )

                local admin =
                    waitWithAdmin(
                        cfg.sale_start_delay
                    )

                if not admin then

                    -- Recontar por si el
                    -- usuario metio mas
                    credit =
                        countTokens(
                            payment
                        )

                    if credit > 0 then

                        refuel(
                            credit
                        )

                        -- No iniciar nueva venta
                        -- hasta retirar el cambio.
                        while
                            countTokens(
                                payment
                            ) > 0
                        do

                            show(
                                "RETIRA EL CAMBIO",

                                countTokens(
                                    payment
                                ),

                                0,
                                0,

                                "Vacia los FuelTokens del barril derecho."
                            )

                            sleep(0.5)
                        end
                    end
                end
            end
        end
    end
end

local ok, err =
    pcall(main)

-- Si termina por error o CTRL+T,
-- intentar cerrar la valvula.
pcall(closeValve)

if not ok then

    clear()

    print(
        "ERROR FATAL DEL SURTIDOR"
    )

    print("")
    print(err)
end
