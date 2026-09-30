-- ============================================
--            LECTOR DEL TANQUE
-- ============================================

local CONFIG_FILE = "/tanque.cfg"
local ADMIN_PIN = "2050"

local defaults = {
    protocol = "surtidor_tanque",
    hostname = "tanque_1"
}

local cfg = {}

for k, v in pairs(defaults) do
    cfg[k] = v
end


local function guardar()
    local f = fs.open(CONFIG_FILE, "w")

    f.write(textutils.serialize(cfg))
    f.close()
end


local function cargar()
    if not fs.exists(CONFIG_FILE) then
        guardar()
        return
    end

    local f = fs.open(CONFIG_FILE, "r")

    local datos =
        textutils.unserialize(
            f.readAll()
        )

    f.close()

    if type(datos) == "table" then
        for k, v in pairs(datos) do
            if defaults[k] ~= nil then
                cfg[k] = v
            end
        end
    end
end


cargar()


-- =========================
-- MODEMS
-- =========================

for _, nombre in ipairs(peripheral.getNames()) do

    local tipos =
        {peripheral.getType(nombre)}

    for _, tipo in ipairs(tipos) do
        if tipo == "modem" then
            pcall(rednet.open, nombre)
        end
    end
end


if not rednet.isOpen() then
    error("No hay modem")
end


-- =========================
-- TANQUE
-- =========================

local function buscarTanque()
    return
        peripheral.find("fluid_tank")
        or
        peripheral.find("fluidTank")
end


local tank = buscarTanque()

if not tank then
    error("No encuentro Fluid Tank de Create")
end


-- Advanced Peripherals 0.8 usa fluid_tank + info(),
-- mientras las ramas antiguas usaban fluidTank + getInfo().
-- Ambas quedan soportadas.
-- https://docs.advanced-peripherals.de/

local function leerTanque()

    if tank.info then

        local info =
            tank.info()

        local cantidad = 0
        local nombre = "vacio"

        if info.fluid then

            cantidad =
                info.fluid.count
                or info.fluid.amount
                or 0

            nombre =
                info.fluid.name
                or info.fluid.displayName
                or "desconocido"
        end

        return {
            amount = cantidad,
            capacity =
                info.capacity or 0,
            fluid = nombre
        }

    elseif tank.getInfo then

        local info =
            tank.getInfo()

        return {
            amount =
                info.amount or 0,

            capacity =
                info.capacity or 0,

            fluid =
                info.fluid or "vacio"
        }
    end

    error(
        "API del tanque no reconocida"
    )
end


-- =========================
-- HOST REDNET
-- =========================

local function registrarHost()

    pcall(
        rednet.host,
        cfg.protocol,
        cfg.hostname
    )
end


registrarHost()


-- =========================
-- ADMIN
-- =========================

local function menuAdmin()
    term.clear()
    term.setCursorPos(1, 1)

    print("ADMINISTRADOR TANQUE")
    print("")
    write("Codigo: ")

    local pin = read("*")

    if pin ~= ADMIN_PIN then
        print("")
        print("CODIGO INCORRECTO")
        sleep(2)
        return
    end

    local protocoloAnterior =
        cfg.protocol

    while true do

        term.clear()
        term.setCursorPos(1, 1)

        print("============================")
        print(" CONFIGURACION TANQUE")
        print("============================")
        print("")
        print("1 Protocolo: " ..
            cfg.protocol)

        print("2 Hostname: " ..
            cfg.hostname)

        print("")
        print("0 GUARDAR Y SALIR")
        print("")
        write("> ")

        local op = read()

        if op == "1" then

            write(
                "Protocolo [" ..
                cfg.protocol ..
                "]: "
            )

            local x = read()

            if x ~= "" then
                cfg.protocol = x
            end

        elseif op == "2" then

            write(
                "Hostname [" ..
                cfg.hostname ..
                "]: "
            )

            local x = read()

            if x ~= "" then
                cfg.hostname = x
            end

        elseif op == "0" then

            pcall(
                rednet.unhost,
                protocoloAnterior
            )

            guardar()
            registrarHost()

            return
        end
    end
end


-- =========================
-- PROGRAMA
-- =========================

while true do

    local event, a, b, c =
        os.pullEvent()

    if event == "key"
        and a == keys.c
    then

        menuAdmin()

    elseif event ==
        "rednet_message"
    then

        local sender = a
        local mensaje = b
        local protocolo = c

        if protocolo == cfg.protocol
            and mensaje == "read"
        then

            local datos =
                leerTanque()

            rednet.send(
                sender,
                datos,
                cfg.protocol
            )

            term.clear()
            term.setCursorPos(1, 1)

            print("LECTOR TANQUE")
            print("")
            print(
                "Cantidad: " ..
                datos.amount ..
                " mB"
            )

            print(
                "Capacidad: " ..
                datos.capacity ..
                " mB"
            )

            print(
                "Fluido: " ..
                tostring(datos.fluid)
            )

            print("")
            print(
                "PC surtidor: " ..
                sender
            )

            print("")
            print(
                "[C] Configuracion"
            )
        end
    end
end
