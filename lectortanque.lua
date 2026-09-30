-- ============================================================
-- LECTOR DE TANQUE - Advanced Peripherals + CC:Tweaked
-- ============================================================

local CONFIG_FILE = "/tanque.cfg"
local ADMIN_PIN = "2050"

local defaults = {
    protocol = "surtidor_tanque",
    hostname = "tanque_1",

    -- "auto" o nombre exacto
    -- del periferico
    tank_peripheral = "auto",
}

local cfg = {}

local tank = nil
local tankName = nil

local locked = false
local lastData = nil
local hostError = nil

local function copyDefaults()

    cfg = {}

    for k, v in pairs(defaults) do
        cfg[k] = v
    end
end

local function saveConfig()

    local f =
        fs.open(
            CONFIG_FILE,
            "w"
        )

    if not f then
        error(
            "No se pudo guardar " ..
            CONFIG_FILE
        )
    end

    f.write(
        textutils.serialize(
            cfg
        )
    )

    f.close()
end

local function loadConfig()

    copyDefaults()

    if fs.exists(
        CONFIG_FILE
    ) then

        local f =
            fs.open(
                CONFIG_FILE,
                "r"
            )

        if f then

            local data =
                textutils.unserialize(
                    f.readAll()
                )

            f.close()

            if type(data) ==
                "table"
            then

                for k, v in pairs(data) do

                    if defaults[k]
                        ~= nil
                    then

                        cfg[k] = v
                    end
                end
            end
        end
    end

    saveConfig()
end

local function clear()

    term.clear()

    term.setCursorPos(
        1,
        1
    )
end

local function openModems()

    for _, name in ipairs(
        peripheral.getNames()
    ) do

        local types = {
            peripheral.getType(name)
        }

        for _, t in ipairs(types) do

            if t == "modem" then
                pcall(
                    rednet.open,
                    name
                )
            end
        end
    end
end

local function hasMethod(
    obj,
    method
)

    return obj and
        type(
            obj[method]
        ) == "function"
end

local function findTank()

    tank = nil
    tankName = nil

    -- Nombre manual
    if cfg.tank_peripheral ~= ""
        and
        cfg.tank_peripheral ~= "auto"
    then

        local p =
            peripheral.wrap(
                cfg.tank_peripheral
            )

        if p and (
            hasMethod(p, "info")
            or
            hasMethod(p, "getInfo")
            or
            hasMethod(p, "tanks")
        ) then

            tank = p

            tankName =
                peripheral.getName(
                    p
                )

            return true
        end

        return false
    end

    -- Advanced Peripherals moderno
    local p, name

    p =
        peripheral.find(
            "fluid_tank",

            function(n)

                name = n

                return true
            end
        )

    if p then

        tank = p

        tankName =
            name or
            peripheral.getName(p)

        return true
    end

    -- Advanced Peripherals antiguo
    p =
        peripheral.find(
            "fluidTank",

            function(n)

                name = n

                return true
            end
        )

    if p then

        tank = p

        tankName =
            name or
            peripheral.getName(p)

        return true
    end

    -- Fallback para API generica
    -- de fluidos de CC:Tweaked
    for _, n in ipairs(
        peripheral.getNames()
    ) do

        local obj =
            peripheral.wrap(n)

        if obj and (
            hasMethod(
                obj,
                "getInfo"
            )
            or
            hasMethod(
                obj,
                "tanks"
            )
        ) then

            tank = obj
            tankName = n

            return true
        end
    end

    return false
end

local function fluidName(
    fluid
)

    if type(fluid) ==
        "string"
    then

        return fluid
    end

    if type(fluid) ~=
        "table"
    then

        return "vacio"
    end

    return
        fluid.name
        or fluid.id
        or fluid.registryName
        or fluid.displayName
        or "desconocido"
end

local function fluidAmount(
    fluid
)

    if type(fluid) ~=
        "table"
    then

        return 0
    end

    return tonumber(
        fluid.amount
        or fluid.count
        or fluid.quantity
        or 0
    ) or 0
end

local function readTank()

    if not tank and
        not findTank()
    then

        return nil,
            "No encuentro el tanque/periferico"
    end

    -- =========================
    -- ADVANCED PERIPHERALS 0.8+
    -- =========================

    if hasMethod(
        tank,
        "info"
    ) then

        local ok, info =
            pcall(
                tank.info
            )

        if not ok or
            type(info) ~=
            "table"
        then

            return nil,
                "Fallo tank.info()"
        end

        local amount = 0
        local name = "vacio"

        if info.fluid ~=
            nil
        then

            amount =
                fluidAmount(
                    info.fluid
                )

            name =
                fluidName(
                    info.fluid
                )
        end

        -- Compatibilidad extra
        if amount == 0 and
            tonumber(
                info.amount
            )
        then

            amount =
                tonumber(
                    info.amount
                )
        end

        return {
            ok = true,

            amount =
                amount,

            capacity =
                tonumber(
                    info.capacity
                    or 0
                ) or 0,

            fluid =
                name,

            peripheral =
                tankName,
        }
    end

    -- =========================
    -- ADVANCED PERIPHERALS 0.7
    -- =========================

    if hasMethod(
        tank,
        "getInfo"
    ) then

        local ok, info =
            pcall(
                tank.getInfo
            )

        if not ok or
            type(info) ~=
            "table"
        then

            return nil,
                "Fallo tank.getInfo()"
        end

        return {
            ok = true,

            amount =
                tonumber(
                    info.amount
                    or 0
                ) or 0,

            capacity =
                tonumber(
                    info.capacity
                    or 0
                ) or 0,

            fluid =
                fluidName(
                    info.fluid
                ),

            peripheral =
                tankName,
        }
    end

    -- =========================
    -- FALLBACK CC:TWEAKED
    -- =========================

    if hasMethod(
        tank,
        "tanks"
    ) then

        local ok, tanks =
            pcall(
                tank.tanks
            )

        if not ok or
            type(tanks) ~=
            "table"
        then

            return nil,
                "Fallo tank.tanks()"
        end

        local amount = 0
        local capacity = 0
        local name = "vacio"

        for _, entry in pairs(
            tanks
        ) do

            if type(entry) ==
                "table"
            then

                amount =
                    amount +
                    (
                        tonumber(
                            entry.amount
                            or entry.count
                            or 0
                        )
                        or 0
                    )

                capacity =
                    capacity +
                    (
                        tonumber(
                            entry.capacity
                            or 0
                        )
                        or 0
                    )

                if name == "vacio"
                    and
                    (
                        entry.name
                        or entry.id
                    )
                then

                    name =
                        entry.name
                        or entry.id
                end
            end
        end

        return {
            ok = true,

            amount =
                amount,

            capacity =
                capacity,

            fluid =
                name,

            peripheral =
                tankName,
        }
    end

    tank = nil
    tankName = nil

    return nil,
        "API del tanque no reconocida"
end

local function registerHost()

    hostError = nil

    local ok, err =
        pcall(
            rednet.host,
            cfg.protocol,
            cfg.hostname
        )

    if not ok then

        hostError =
            tostring(err)
    end

    return ok
end

local function showStatus(
    message
)

    clear()

    print("================================")
    print(" LECTOR DE TANQUE")
    print("================================")

    print(
        "Host: " ..
        cfg.hostname
    )

    print(
        "Protocolo: " ..
        cfg.protocol
    )

    print(
        "Tanque: " ..
        tostring(
            tankName
            or "NO DETECTADO"
        )
    )

    print(
        "Bloqueado: " ..
        (
            locked
            and "SI"
            or "NO"
        )
    )

    if lastData then

        print("")

        print(
            "Cantidad: " ..
            tostring(
                lastData.amount
            ) ..
            " mB"
        )

        print(
            "Capacidad: " ..
            tostring(
                lastData.capacity
            ) ..
            " mB"
        )

        print(
            "Fluido: " ..
            tostring(
                lastData.fluid
            )
        )
    end

    if hostError then

        print("")

        print(
            "ERROR HOST: " ..
            hostError
        )
    end

    if message then

        print("")
        print(message)
    end

    print("")

    if locked then

        print(
            "Configuracion bloqueada durante venta"
        )

    else

        print(
            "[C] Administrador"
        )
    end
end

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

local function adminMenu()

    clear()

    print(
        "ADMINISTRADOR TANQUE"
    )

    print("")

    write("Codigo: ")

    local pin =
        read("*")

    if pin ~= ADMIN_PIN then

        print("")
        print("CODIGO INCORRECTO")

        sleep(2)

        return
    end

    local oldProtocol =
        cfg.protocol

    while true do

        clear()

        print("================================")
        print(" CONFIGURACION LECTOR")
        print("================================")

        print(
            "1 Protocolo: " ..
            cfg.protocol
        )

        print(
            "2 Hostname: " ..
            cfg.hostname
        )

        print(
            "3 Tanque/periferico: " ..
            cfg.tank_peripheral
        )

        print(
            "4 Buscar tanque automaticamente"
        )

        print("")
        print("0 GUARDAR Y SALIR")
        print("")

        write("> ")

        local option =
            read()

        if option == "1" then

            cfg.protocol =
                askText(
                    "Protocolo",
                    cfg.protocol
                )

        elseif option == "2" then

            cfg.hostname =
                askText(
                    "Hostname",
                    cfg.hostname
                )

        elseif option == "3" then

            cfg.tank_peripheral =
                askText(
                    "Nombre periferico o auto",
                    cfg.tank_peripheral
                )

        elseif option == "4" then

            cfg.tank_peripheral =
                "auto"

            findTank()

            print(
                "Detectado: " ..
                tostring(
                    tankName
                    or "ninguno"
                )
            )

            sleep(1.5)

        elseif option == "0" then

            pcall(
                rednet.unhost,
                oldProtocol
            )

            saveConfig()

            findTank()

            registerHost()

            showStatus(
                "Configuracion guardada"
            )

            sleep(1)

            return
        end
    end
end

local function sendReply(
    target,
    data
)

    rednet.send(
        target,
        data,
        cfg.protocol
    )
end

local function main()

    loadConfig()

    openModems()

    if not rednet.isOpen() then

        error(
            "No hay modem conectado al lector del tanque"
        )
    end

    findTank()

    registerHost()

    showStatus(
        "Esperando al surtidor..."
    )

    while true do

        local event,
              value1,
              value2,
              value3 =
            os.pullEvent()

        -- =========================
        -- MENU ADMIN
        -- =========================

        if event == "key"
            and value1 ==
                keys.c
        then

            if locked then

                showStatus(
                    "No se puede configurar durante un repostaje"
                )

            else

                adminMenu()
            end

        -- =========================
        -- REDNET
        -- =========================

        elseif event ==
            "rednet_message"
        then

            local sender =
                value1

            local message =
                value2

            local protocol =
                value3

            if protocol ==
                cfg.protocol
            then

                -- El surtidor avisa
                -- que comienza una venta
                if message ==
                    "begin"
                then

                    locked = true

                    showStatus(
                        "Venta iniciada por PC " ..
                        sender
                    )

                -- Venta terminada
                elseif message ==
                    "end"
                then

                    locked = false

                    showStatus(
                        "Venta finalizada por PC " ..
                        sender
                    )

                -- Solicitud de lectura
                elseif message ==
                    "read"
                then

                    local data, err =
                        readTank()

                    if data then

                        lastData =
                            data

                        sendReply(
                            sender,
                            data
                        )

                        showStatus(
                            "Ultima lectura para PC " ..
                            sender
                        )

                    else

                        sendReply(
                            sender,
                            {
                                ok = false,
                                error = err
                            }
                        )

                        showStatus(
                            "ERROR: " ..
                            tostring(err)
                        )
                    end
                end
            end
        end
    end
end

local ok, err =
    pcall(main)

if not ok then

    clear()

    print(
        "ERROR FATAL DEL LECTOR"
    )

    print("")
    print(err)
end
