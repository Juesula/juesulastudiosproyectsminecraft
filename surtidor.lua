-- ============================================================
-- SURTIDOR DE COMBUSTIBLE
-- CC:Tweaked + Lightman's Currency
--
-- 1 FuelToken = 1 Netherite Coin
-- lightmanscurrency:coin_netherite
--
-- CONTROLES:
--   F              = INICIAR / PARAR
--   CLICK BOTON    = INICIAR / PARAR
--   C              = ADMINISTRADOR
--
-- ADMIN:
--   PIN 2050
--   FLECHA ARRIBA/ABAJO = navegar
--   ENTER                = editar
--   ESC                  = guardar y salir
-- ============================================================

local CONFIG_FILE = "/surtidor.cfg"
local ADMIN_PIN = "2050"

local NETHERITE_COIN_ID =
    "lightmanscurrency:coin_netherite"


-- ============================================================
-- CONFIGURACION
-- ============================================================

local defaults = {

    station_name = "SURTIDOR",

    token_name = "FuelToken",

    token_item_id =
        NETHERITE_COIN_ID,

    -- 1 FuelToken compra esta cantidad
    mb_per_token = 1000,

    -- Barril cliente / cambio
    payment_side = "right",

    -- Barril dinero cobrado
    storage_side = "bottom",

    -- Valvula
    open_side = "back",
    close_side = "left",

    pulse_time = 0.15,

    -- Lectura del deposito
    sample_time = 0.20,

    -- Lecturas sin bajar antes
    -- de considerar fin de flujo
    no_flow_limit = 8,

    -- Ignorar cambios menores
    flow_epsilon_mb = 1,

    -- Tiempo de gracia al abrir
    -- antes de comprobar falta de flujo
    flow_grace_time = 1.0,

    -- Rednet
    protocol = "surtidor_tanque",
    tank_host = "tanque_1",
    tank_timeout = 2.0,

    -- Cambio
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

local buttonBounds = {
    x1 = 1,
    x2 = 1,
    y1 = 1,
    y2 = 1
}


-- ============================================================
-- TERMINAL / COLORES
-- ============================================================

local function hasColor()

    return term.isColor()
end


local function resetColors()

    if hasColor() then

        term.setBackgroundColor(
            colors.black
        )

        term.setTextColor(
            colors.white
        )
    end
end


local function clear()

    resetColors()

    term.clear()
    term.setCursorPos(1, 1)
end


local function writeAt(
    x,
    y,
    text,
    fg,
    bg
)

    local w, h =
        term.getSize()

    if y < 1 or y > h then
        return
    end

    if x < 1 then
        x = 1
    end

    text =
        tostring(text or "")

    if x > w then
        return
    end

    if #text >
        (w - x + 1)
    then

        text =
            string.sub(
                text,
                1,
                w - x + 1
            )
    end


    if hasColor() then

        if bg then
            term.setBackgroundColor(bg)
        end

        if fg then
            term.setTextColor(fg)
        end
    end


    term.setCursorPos(
        x,
        y
    )

    term.write(text)

    resetColors()
end


local function centerText(
    y,
    text,
    fg,
    bg
)

    local w =
        select(
            1,
            term.getSize()
        )

    text =
        tostring(text)

    local x =
        math.floor(
            (w - #text) / 2
        ) + 1

    if x < 1 then
        x = 1
    end

    writeAt(
        x,
        y,
        text,
        fg,
        bg
    )
end


local function fillLine(
    y,
    bg
)

    local w =
        select(
            1,
            term.getSize()
        )

    if hasColor() then
        term.setBackgroundColor(bg)
    end

    term.setCursorPos(
        1,
        y
    )

    term.write(
        string.rep(
            " ",
            w
        )
    )

    resetColors()
end


-- ============================================================
-- UTILIDADES
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


local function isFuelToken(item)

    if type(item) ~= "table" then
        return false
    end

    local id =
        normalizeID(
            item.name
        )

    if id ==
        normalizeID(
            cfg.token_item_id
        )
    then
        return true
    end

    -- Siempre aceptar Netherite Coin
    if id ==
        NETHERITE_COIN_ID
    then
        return true
    end

    return false
end


-- ============================================================
-- CONFIG
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

                -- Migracion antigua

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


                -- Config actual

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
-- VALVULA
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
-- INTERFAZ PRINCIPAL
-- ============================================================

local function drawButton(
    running,
    enabled
)

    local w, h =
        term.getSize()

    local label

    if running then

        label =
            " [ F ]  PARAR "

    else

        label =
            " [ F ]  COMENZAR "
    end


    local x =
        math.floor(
            (w - #label) / 2
        ) + 1

    local y =
        h - 2


    buttonBounds.x1 = x
    buttonBounds.x2 =
        x + #label - 1

    buttonBounds.y1 = y
    buttonBounds.y2 = y


    local background =
        colors.gray

    local foreground =
        colors.white


    if hasColor() then

        if running then

            background =
                colors.red

        elseif enabled then

            background =
                colors.green

        else

            background =
                colors.gray
        end
    end


    writeAt(
        x,
        y,
        label,
        foreground,
        background
    )
end


local function buttonClicked(
    x,
    y
)

    return
        x >= buttonBounds.x1
        and
        x <= buttonBounds.x2
        and
        y >= buttonBounds.y1
        and
        y <= buttonBounds.y2
end


local function drawMain(
    state
)

    state =
        state or {}

    local w, h =
        term.getSize()


    clear()


    -- ========================================
    -- CABECERA
    -- ========================================

    if hasColor() then

        fillLine(
            1,
            colors.blue
        )

        centerText(
            1,
            cfg.station_name,
            colors.white,
            colors.blue
        )

    else

        centerText(
            1,
            cfg.station_name
        )
    end


    centerText(
        2,
        string.rep(
            "-",
            math.min(
                w,
                30
            )
        )
    )


    -- ========================================
    -- ESTADO
    -- ========================================

    local status =
        state.status
        or
        "ESPERANDO"


    local statusColor =
        colors.white


    if hasColor() then

        if state.running then

            statusColor =
                colors.lime

        elseif status:find(
            "ERROR"
        ) then

            statusColor =
                colors.red

        elseif status ==
            "LISTO"
        then

            statusColor =
                colors.yellow
        end
    end


    centerText(
        3,
        status,
        statusColor
    )


    -- ========================================
    -- DATOS
    -- ========================================

    local credit =
        state.credit or 0

    local served =
        state.served or 0

    local cost =
        state.cost or 0

    local remaining =
        math.max(
            0,
            credit - cost
        )


    writeAt(
        2,
        5,
        "CREDITO"
    )

    writeAt(
        16,
        5,
        tostring(credit) ..
        " FT",
        colors.yellow
    )


    writeAt(
        2,
        6,
        "SUMINISTRADO"
    )

    writeAt(
        16,
        6,
        tostring(served) ..
        " mB",
        colors.cyan
    )


    writeAt(
        2,
        7,
        "COSTE"
    )

    writeAt(
        16,
        7,
        tostring(cost) ..
        " FT",
        colors.orange
    )


    writeAt(
        2,
        8,
        "RESTANTE"
    )

    writeAt(
        16,
        8,
        tostring(remaining) ..
        " FT",
        colors.lime
    )


    if state.tankAmount ~= nil then

        writeAt(
            2,
            10,
            "DEPOSITO"
        )

        local tankText =
            tostring(
                state.tankAmount
            ) ..
            " mB"


        if state.tankCapacity and
            state.tankCapacity > 0
        then

            tankText =
                tankText ..
                " / " ..
                tostring(
                    state.tankCapacity
                )
        end


        writeAt(
            16,
            10,
            tankText
        )
    end


    -- ========================================
    -- PRECIO
    -- ========================================

    writeAt(
        2,
        12,
        "PRECIO:"
    )

    writeAt(
        10,
        12,
        "1 FT = " ..
        tostring(
            cfg.mb_per_token
        ) ..
        " mB"
    )


    -- ========================================
    -- MENSAJE
    -- ========================================

    if state.message then

        local message =
            tostring(
                state.message
            )

        local maxLength =
            math.max(
                1,
                w - 4
            )

        local line1 =
            string.sub(
                message,
                1,
                maxLength
            )

        local line2 =
            ""

        if #message >
            maxLength
        then

            line2 =
                string.sub(
                    message,
                    maxLength + 1,
                    maxLength * 2
                )
        end


        writeAt(
            2,
            h - 5,
            line1
        )

        if line2 ~= "" then

            writeAt(
                2,
                h - 4,
                line2
            )
        end
    end


    -- ========================================
    -- BOTON
    -- ========================================

    drawButton(
        state.running == true,
        credit > 0
    )


    centerText(
        h,
        "[C] ADMIN",
        colors.lightGray
    )


    resetColors()
end


-- ============================================================
-- INPUT ADMIN
-- ============================================================

local validSides = {

    left = true,
    right = true,
    top = true,
    bottom = true,
    front = true,
    back = true
}


local function promptText(
    title,
    current
)

    clear()

    centerText(
        1,
        title
    )

    print("")
    print(
        "Actual:"
    )

    print(
        tostring(current)
    )

    print("")
    write("> ")

    local value =
        read()

    if value == "" then
        return current
    end

    return value
end


local function promptNumber(
    title,
    current,
    minimum
)

    local value =
        promptText(
            title,
            current
        )

    if tostring(value) ==
        tostring(current)
    then

        return current
    end


    local number =
        tonumber(value)

    if not number then

        clear()

        print(
            "Numero invalido"
        )

        sleep(1)

        return current
    end


    if minimum and
        number < minimum
    then

        clear()

        print(
            "Valor minimo: " ..
            tostring(minimum)
        )

        sleep(1)

        return current
    end


    return number
end


local function promptSide(
    title,
    current
)

    local value =
        string.lower(
            promptText(
                title,
                current
            )
        )


    if validSides[value] then
        return value
    end


    clear()

    print(
        "Lado invalido"
    )

    print("")
    print(
        "left"
    )

    print(
        "right"
    )

    print(
        "top"
    )

    print(
        "bottom"
    )

    print(
        "front"
    )

    print(
        "back"
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
        "DIAGNOSTICO DE MONEDAS"
    )

    print(
        "----------------------"
    )

    print("")


    if not payment then

        print(
            "No encuentro el barril de pago."
        )

        print("")
        print(
            "Pulsa una tecla..."
        )

        os.pullEvent("key")

        return
    end


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
            "x"
        )

        print(
            tostring(
                item.name
            )
        )


        if isFuelToken(
            item
        ) then

            print(
                ">> FUELTOKEN VALIDO"
            )

        else

            print(
                ">> NO VALIDO"
            )
        end

        print("")
    end


    if not found then

        print(
            "Barril vacio."
        )
    end


    print(
        "Pulsa una tecla..."
    )

    os.pullEvent("key")
end


-- ============================================================
-- MENU ADMIN CON SCROLL
-- ============================================================

local function adminOptions()

    return {

        {
            label =
                "Nombre surtidor",

            value =
                function()
                    return cfg.station_name
                end,

            edit =
                function()

                    cfg.station_name =
                        promptText(
                            "Nombre surtidor",
                            cfg.station_name
                        )
                end
        },


        {
            label =
                "Nombre token",

            value =
                function()
                    return cfg.token_name
                end,

            edit =
                function()

                    cfg.token_name =
                        promptText(
                            "Nombre token",
                            cfg.token_name
                        )
                end
        },


        {
            label =
                "ID FuelToken",

            value =
                function()
                    return cfg.token_item_id
                end,

            edit =
                function()

                    cfg.token_item_id =
                        normalizeID(
                            promptText(
                                "ID FuelToken",
                                cfg.token_item_id
                            )
                        )
                end
        },


        {
            label =
                "mB por FuelToken",

            value =
                function()
                    return cfg.mb_per_token
                end,

            edit =
                function()

                    cfg.mb_per_token =
                        promptNumber(
                            "mB por FuelToken",
                            cfg.mb_per_token,
                            1
                        )
                end
        },


        {
            label =
                "Barril pago",

            value =
                function()
                    return cfg.payment_side
                end,

            edit =
                function()

                    cfg.payment_side =
                        promptSide(
                            "Barril pago",
                            cfg.payment_side
                        )
                end
        },


        {
            label =
                "Barril almacen",

            value =
                function()
                    return cfg.storage_side
                end,

            edit =
                function()

                    cfg.storage_side =
                        promptSide(
                            "Barril almacen",
                            cfg.storage_side
                        )
                end
        },


        {
            label =
                "Abrir valvula",

            value =
                function()
                    return cfg.open_side
                end,

            edit =
                function()

                    cfg.open_side =
                        promptSide(
                            "Abrir valvula",
                            cfg.open_side
                        )
                end
        },


        {
            label =
                "Cerrar valvula",

            value =
                function()
                    return cfg.close_side
                end,

            edit =
                function()

                    cfg.close_side =
                        promptSide(
                            "Cerrar valvula",
                            cfg.close_side
                        )
                end
        },


        {
            label =
                "Tiempo pulso",

            value =
                function()
                    return cfg.pulse_time
                end,

            edit =
                function()

                    cfg.pulse_time =
                        promptNumber(
                            "Tiempo pulso",
                            cfg.pulse_time,
                            0.05
                        )
                end
        },


        {
            label =
                "Intervalo lectura",

            value =
                function()
                    return cfg.sample_time
                end,

            edit =
                function()

                    cfg.sample_time =
                        promptNumber(
                            "Intervalo lectura",
                            cfg.sample_time,
                            0.05
                        )
                end
        },


        {
            label =
                "Lecturas sin flujo",

            value =
                function()
                    return cfg.no_flow_limit
                end,

            edit =
                function()

                    cfg.no_flow_limit =
                        math.floor(
                            promptNumber(
                                "Lecturas sin flujo",
                                cfg.no_flow_limit,
                                1
                            )
                        )
                end
        },


        {
            label =
                "Tolerancia mB",

            value =
                function()
                    return cfg.flow_epsilon_mb
                end,

            edit =
                function()

                    cfg.flow_epsilon_mb =
                        promptNumber(
                            "Tolerancia mB",
                            cfg.flow_epsilon_mb,
                            0
                        )
                end
        },


        {
            label =
                "Gracia inicial",

            value =
                function()
                    return cfg.flow_grace_time
                end,

            edit =
                function()

                    cfg.flow_grace_time =
                        promptNumber(
                            "Gracia inicial segundos",
                            cfg.flow_grace_time,
                            0
                        )
                end
        },


        {
            label =
                "Protocolo",

            value =
                function()
                    return cfg.protocol
                end,

            edit =
                function()

                    cfg.protocol =
                        promptText(
                            "Protocolo Rednet",
                            cfg.protocol
                        )

                    tankID = nil
                end
        },


        {
            label =
                "Host tanque",

            value =
                function()
                    return cfg.tank_host
                end,

            edit =
                function()

                    cfg.tank_host =
                        promptText(
                            "Host tanque",
                            cfg.tank_host
                        )

                    tankID = nil
                end
        },


        {
            label =
                "Timeout tanque",

            value =
                function()
                    return cfg.tank_timeout
                end,

            edit =
                function()

                    cfg.tank_timeout =
                        promptNumber(
                            "Timeout tanque",
                            cfg.tank_timeout,
                            0.2
                        )
                end
        },


        {
            label =
                "Restaurar Netherite Coin",

            value =
                function()
                    return "ACCION"
                end,

            edit =
                function()

                    cfg.token_item_id =
                        NETHERITE_COIN_ID

                    cfg.token_name =
                        "FuelToken"

                    saveConfig()

                    clear()

                    print(
                        "Netherite Coin restaurada."
                    )

                    sleep(1)
                end
        },


        {
            label =
                "Diagnostico monedas",

            value =
                function()
                    return "ABRIR"
                end,

            edit =
                function()

                    diagnosticCoins()
                end
        }
    }
end


local function drawAdmin(
    selected,
    firstVisible
)

    local options =
        adminOptions()

    local w, h =
        term.getSize()

    local visible =
        math.max(
            4,
            h - 6
        )


    clear()


    if hasColor() then

        fillLine(
            1,
            colors.blue
        )

        centerText(
            1,
            "ADMINISTRADOR",
            colors.white,
            colors.blue
        )

    else

        centerText(
            1,
            "ADMINISTRADOR"
        )
    end


    centerText(
        2,
        "UP/DOWN + ENTER"
    )


    local finalVisible =
        math.min(
            #options,
            firstVisible +
            visible -
            1
        )


    local screenY =
        4


    for i =
        firstVisible,
        finalVisible
    do

        local option =
            options[i]

        local value =
            tostring(
                option.value()
            )


        local prefix =
            "  "


        local fg =
            colors.white

        local bg =
            colors.black


        if i ==
            selected
        then

            prefix =
                "> "

            if hasColor() then

                fg =
                    colors.black

                bg =
                    colors.lightGray
            end
        end


        local text =
            prefix ..
            option.label ..
            ": " ..
            value


        if #text >
            w
        then

            text =
                string.sub(
                    text,
                    1,
                    w
                )
        end


        if hasColor() and
            i == selected
        then

            fillLine(
                screenY,
                bg
            )
        end


        writeAt(
            1,
            screenY,
            text,
            fg,
            bg
        )


        screenY =
            screenY + 1
    end


    if firstVisible >
        1
    then

        writeAt(
            w,
            3,
            "^",
            colors.yellow
        )
    end


    if finalVisible <
        #options
    then

        writeAt(
            w,
            h - 2,
            "v",
            colors.yellow
        )
    end


    centerText(
        h,
        "ESC = GUARDAR Y SALIR",
        colors.lightGray
    )


    return visible
end


local function adminMenu()

    clear()

    centerText(
        2,
        "ADMINISTRADOR"
    )

    centerText(
        4,
        "Introduce codigo"
    )

    term.setCursorPos(
        2,
        6
    )

    write(
        "PIN: "
    )


    local pin =
        read("*")


    if pin ~=
        ADMIN_PIN
    then

        clear()

        centerText(
            5,
            "CODIGO INCORRECTO",
            colors.red
        )

        sleep(1.5)

        return
    end


    local selected =
        1

    local firstVisible =
        1


    while true do

        local options =
            adminOptions()

        local visible =
            drawAdmin(
                selected,
                firstVisible
            )


        local event,
              a =
            os.pullEvent()


        if event ==
            "key"
        then

            -- ARRIBA

            if a ==
                keys.up
            then

                selected =
                    selected - 1

                if selected <
                    1
                then

                    selected =
                        #options
                end


            -- ABAJO

            elseif a ==
                keys.down
            then

                selected =
                    selected + 1

                if selected >
                    #options
                then

                    selected =
                        1
                end


            -- PAGE UP

            elseif a ==
                keys.pageUp
            then

                selected =
                    math.max(
                        1,
                        selected -
                        visible
                    )


            -- PAGE DOWN

            elseif a ==
                keys.pageDown
            then

                selected =
                    math.min(
                        #options,
                        selected +
                        visible
                    )


            -- ENTER

            elseif a ==
                keys.enter
            then

                options[
                    selected
                ].edit()


            -- ESC

            elseif a ==
                keys.escape
            then

                saveConfig()

                refreshInventories()

                autoRepairTokenID()

                tankID = nil

                return
            end


        -- RUEDA RATON OPCIONAL

        elseif event ==
            "mouse_scroll"
        then

            if a > 0 then

                selected =
                    math.min(
                        #options,
                        selected + 1
                    )

            else

                selected =
                    math.max(
                        1,
                        selected - 1
                    )
            end
        end


        -- Ajustar scroll

        if selected <
            firstVisible
        then

            firstVisible =
                selected
        end


        if selected >=
            firstVisible +
            visible
        then

            firstVisible =
                selected -
                visible +
                1
        end


        if selected == 1 then
            firstVisible = 1
        end
    end
end


-- ============================================================
-- REDNET
-- ============================================================

local function findTankComputer()

    tankID =
        rednet.lookup(
            cfg.protocol,
            cfg.tank_host
        )

    return tankID ~= nil
end


local function isStopInput(
    event,
    a,
    b,
    c
)

    if event ==
        "key"
        and
        a == keys.f
    then

        return true
    end


    if event ==
        "mouse_click"
        and
        buttonClicked(
            b,
            c
        )
    then

        return true
    end


    return false
end


local function sendTankCommand(
    command,
    waitReply,
    allowStop
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

            if a ==
                tankID
                and
                c ==
                    cfg.protocol
            then

                return b
            end


        elseif event ==
            "timer"
            and
            a == timer
        then

            tankID = nil

            return nil,
                "TIMEOUT"


        elseif allowStop and
            isStopInput(
                event,
                a,
                b,
                c
            )
        then

            return nil,
                "USER_STOP"
        end
    end
end


local function readTank(
    allowStop
)

    local message,
          err =
        sendTankCommand(
            "read",
            true,
            allowStop
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
-- MONEDAS
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


    -- Si solo movio una parte,
    -- devolverla.

    if moved > 0 then

        moveTokens(
            storage,
            paymentName,
            moved
        )
    end


    return false
end


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

            drawMain({

                status =
                    "CAMBIO PENDIENTE",

                credit = 0,

                served = 0,

                cost = 0,

                running = false,

                message =
                    "Libera espacio en el barril derecho."
            })


            sleep(
                cfg.change_retry_time
            )
        end
    end
end


-- ============================================================
-- ESPERAR SIGUIENTE LECTURA
-- PERO PERMITIENDO PARAR CON F/CLICK
-- ============================================================

local function waitForSampleOrStop()

    local timer =
        os.startTimer(
            cfg.sample_time
        )


    while true do

        local event,
              a,
              b,
              c =
            os.pullEvent()


        if event ==
            "timer"
            and
            a == timer
        then

            return "sample"
        end


        if isStopInput(
            event,
            a,
            b,
            c
        )
        then

            return "stop"
        end
    end
end


-- ============================================================
-- REPOSTAJE
-- ============================================================

local function refuel(
    credit
)

    -- ========================================
    -- CERRAR ANTES DE EMPEZAR
    -- ========================================

    closeValve()


    -- ========================================
    -- RESERVAR TODAS LAS MONEDAS
    -- ========================================

    if not
        reserveCredit(
            credit
        )
    then

        drawMain({

            status =
                "ERROR PAGO",

            credit =
                credit,

            message =
                "No puedo mover las monedas al barril inferior."
        })

        sleep(3)

        return
    end


    -- ========================================
    -- AVISAR LECTOR
    -- ========================================

    sendTankCommand(
        "begin",
        false,
        false
    )


    -- ========================================
    -- LECTURA INICIAL
    -- ========================================

    local first,
          firstError =
        readTank(
            true
        )


    -- Pulsaste F antes incluso
    -- de abrir la valvula.

    if firstError ==
        "USER_STOP"
    then

        closeValve()

        sendTankCommand(
            "end",
            false,
            false
        )

        finishChange(
            credit
        )

        return
    end


    if not first then

        closeValve()

        sendTankCommand(
            "end",
            false,
            false
        )

        finishChange(
            credit
        )


        drawMain({

            status =
                "ERROR TANQUE",

            credit = 0,

            message =
                tostring(
                    firstError
                )
        })


        sleep(3)

        return
    end


    local initial =
        first.amount

    local previous =
        initial

    local lowest =
        initial

    local capacity =
        first.capacity or 0

    local noFlow =
        0

    local maxFuel =
        credit *
        cfg.mb_per_token

    local reason =
        "FINALIZADO"

    local startedAt =
        os.clock()


    -- ========================================
    -- ABRIR
    -- ========================================

    drawMain({

        status =
            "REPOSTANDO",

        credit =
            credit,

        served =
            0,

        cost =
            0,

        tankAmount =
            initial,

        tankCapacity =
            capacity,

        running =
            true,

        message =
            "Pulsa F o el boton para parar."
    })


    openValve()


    -- ========================================
    -- BUCLE DE REPOSTAJE
    -- ========================================

    while true do

        -- Esperar siguiente lectura
        -- permitiendo PARAR.

        local action =
            waitForSampleOrStop()


        if action ==
            "stop"
        then

            reason =
                "PARADO POR USUARIO"

            break
        end


        -- ====================================
        -- LEER DEPOSITO
        -- ====================================

        local data,
              readError =
            readTank(
                true
            )


        if readError ==
            "USER_STOP"
        then

            reason =
                "PARADO POR USUARIO"

            break
        end


        if not data then

            reason =
                "ERROR COMUNICACION"

            break
        end


        local current =
            data.amount


        if data.capacity then
            capacity =
                data.capacity
        end


        -- ====================================
        -- SI EL DEPOSITO SUBE, SE ESTA
        -- RELLENANDO MIENTRAS MEDIMOS.
        -- ====================================

        if current >
            previous +
            cfg.flow_epsilon_mb
        then

            reason =
                "DEPOSITO RELLENANDOSE"

            break
        end


        -- ====================================
        -- GUARDAR NIVEL MAS BAJO
        -- ====================================

        if current <
            lowest
        then

            lowest =
                current
        end


        -- ====================================
        -- CALCULAR SERVIDO
        -- ====================================

        local served =
            math.max(
                0,
                initial -
                lowest
            )


        -- ====================================
        -- PRECIO
        -- ====================================

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


        -- ====================================
        -- INTERFAZ EN TIEMPO REAL
        -- ====================================

        drawMain({

            status =
                "REPOSTANDO",

            credit =
                credit,

            served =
                served,

            cost =
                cost,

            tankAmount =
                current,

            tankCapacity =
                capacity,

            running =
                true,

            message =
                "F / CLICK = PARAR"
        })


        -- ====================================
        -- CREDITO AGOTADO
        -- ====================================

        if served >=
            maxFuel
        then

            reason =
                "CREDITO AGOTADO"

            break
        end


        -- ====================================
        -- DEPOSITO VACIO
        -- ====================================

        if current <= 0 then

            reason =
                "DEPOSITO VACIO"

            break
        end


        -- ====================================
        -- DETECTAR SI SIGUE BAJANDO
        -- ====================================

        local difference =
            previous -
            current


        local elapsed =
            os.clock() -
            startedAt


        -- Dar tiempo a que empiece
        -- a moverse el fluido.

        if elapsed >=
            cfg.flow_grace_time
        then

            if difference >
                cfg.flow_epsilon_mb
            then

                noFlow = 0

            else

                noFlow =
                    noFlow + 1
            end
        end


        -- ====================================
        -- YA NO BAJA EL CONTADOR
        -- ====================================

        if noFlow >=
            cfg.no_flow_limit
        then

            reason =
                "REPOSTAJE COMPLETADO"

            break
        end


        previous =
            current
    end


    -- ========================================
    -- CERRAR INMEDIATAMENTE
    -- ========================================

    closeValve()


    sendTankCommand(
        "end",
        false,
        false
    )


    -- ========================================
    -- LECTURA FINAL
    -- ========================================

    local final =
        readTank(
            false
        )


    if final then

        if final.amount <
            lowest
        then

            lowest =
                final.amount
        end
    end


    -- ========================================
    -- TOTAL REAL QUE SALIO
    -- ========================================

    local served =
        math.max(
            0,
            initial -
            lowest
        )


    -- ========================================
    -- PRECIO FINAL
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
    -- CAMBIO
    -- ========================================

    local change =
        credit -
        cost


    finishChange(
        change
    )


    -- ========================================
    -- RESULTADO FINAL
    -- ========================================

    drawMain({

        status =
            reason,

        credit =
            credit,

        served =
            served,

        cost =
            cost,

        tankAmount =
            lowest,

        tankCapacity =
            capacity,

        running =
            false,

        message =
            "Cambio: " ..
            tostring(change) ..
            " FuelToken(s)"
    })


    sleep(3)
end


-- ============================================================
-- ESPERA PRINCIPAL
-- ============================================================

local function waitIdleAction()

    local timer =
        os.startTimer(
            0.35
        )


    while true do

        local event,
              a,
              b,
              c =
            os.pullEvent()


        -- F

        if event ==
            "key"
        then

            if a ==
                keys.f
            then

                return "start"

            elseif a ==
                keys.c
            then

                return "admin"
            end
        end


        -- CLICK BOTON

        if event ==
            "mouse_click"
        then

            if buttonClicked(
                b,
                c
            )
            then

                return "start"
            end
        end


        -- Actualizar pantalla

        if event ==
            "timer"
            and
            a == timer
        then

            return "refresh"
        end
    end
end


-- ============================================================
-- ITEMS INVALIDOS
-- ============================================================

local function countInvalidItems()

    if not payment then
        return 0
    end


    local total =
        0


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
        end
    end


    return total
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


    -- Seguridad al arrancar

    closeValve()


    while true do

        refreshInventories()

        autoRepairTokenID()


        -- ====================================
        -- ERROR BARRIL PAGO
        -- ====================================

        if not payment then

            drawMain({

                status =
                    "ERROR BARRIL PAGO",

                message =
                    "No encuentro inventario en " ..
                    cfg.payment_side
            })


        -- ====================================
        -- ERROR BARRIL ALMACEN
        -- ====================================

        elseif not storage then

            drawMain({

                status =
                    "ERROR BARRIL ALMACEN",

                message =
                    "No encuentro inventario en " ..
                    cfg.storage_side
            })


        else

            -- =================================
            -- CREDITO
            -- =================================

            local credit =
                countTokens(
                    payment
                )


            local invalid =
                countInvalidItems()


            local message


            if credit > 0 then

                message =
                    "F o CLICK para comenzar."

                if invalid > 0 then

                    message =
                        message ..
                        " Hay " ..
                        tostring(
                            invalid
                        ) ..
                        " item(s) no validos."
                end


                drawMain({

                    status =
                        "LISTO",

                    credit =
                        credit,

                    served =
                        0,

                    cost =
                        0,

                    running =
                        false,

                    message =
                        message
                })

            else

                message =
                    "Inserta Netherite Coins."

                if invalid > 0 then

                    message =
                        "Objeto no valido en el barril."
                end


                drawMain({

                    status =
                        "ESPERANDO PAGO",

                    credit =
                        0,

                    served =
                        0,

                    cost =
                        0,

                    running =
                        false,

                    message =
                        message
                })
            end
        end


        -- ====================================
        -- ESPERAR ACCION
        -- ====================================

        local action =
            waitIdleAction()


        -- ====================================
        -- ADMIN
        -- ====================================

        if action ==
            "admin"
        then

            adminMenu()

            refreshInventories()

            autoRepairTokenID()

            tankID = nil


        -- ====================================
        -- COMENZAR
        -- ====================================

        elseif action ==
            "start"
        then

            refreshInventories()

            autoRepairTokenID()


            local credit =
                countTokens(
                    payment
                )


            if credit <= 0 then

                drawMain({

                    status =
                        "SIN CREDITO",

                    credit =
                        0,

                    message =
                        "Introduce Netherite Coins primero."
                })

                sleep(1.2)

            else

                refuel(
                    credit
                )
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


-- Intentar cerrar la valvula
-- ante cualquier error.

pcall(
    closeValve
)


if not ok then

    clear()

    if hasColor() then
        term.setTextColor(
            colors.red
        )
    end

    print(
        "ERROR FATAL DEL SURTIDOR"
    )

    resetColors()

    print("")
    print(
        tostring(err)
    )

    print("")
    print(
        "Se intento cerrar la valvula."
    )
end
