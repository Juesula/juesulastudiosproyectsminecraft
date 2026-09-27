-- ============================================================================
-- COSMONAUTICS FLIGHT COMPUTER - MASTER AUTOPILOT (startup.lua)
-- Revised for Cosmonautics 26.08.307: API-grounded orbital control + lunar-data safety gate
-- Minecraft 1.21.1 NeoForge / CC:Tweaked / CC:Sable / Cosmonautics 26.08.307
-- ============================================================================

-- ARCHIVO DE PERSISTENCIA DE CONFIGURACIÓN
local SETTINGS_FILE = "autopilot_settings.dat"

-- CONFIGURACIÓN PRINCIPAL (VALORES CONFIRMADOS COSMONAUTICS 26.08.307)
local CONFIG = {
    MAIN_DOWN_SIDE            = "front",               -- Salida analógica LOCAL para propulsor DOWN
    SECONDARY_ID              = nil,                   -- ID del ordenador secundario (nil = auto-emparejar)
    PROTOCOL                  = "SPACECRAFT_THRUSTER", -- Protocolo Rednet
    HEARTBEAT_INTERVAL        = 0.25,                  -- Frecuencia de heartbeat (segundos)
    WATCHDOG_LINK_TIMEOUT     = 1.0,                   -- Timeout para declarar THRUSTER LINK: LOST
    MAX_ANGULAR_VELOCITY      = 1.8,                   -- Límite de seguridad de velocidad angular (rad/s)
    ORBIT_CIRCULAR_TOLERANCE  = 0.05,                  -- Excentricidad objetivo para órbita circular
    LOOP_TICK_RATE            = 0.05,                  -- 20 Hz

    -- ========================================================================
    -- PARÁMETROS REALES DE REENTRADA Y SEGURIDAD ORBITAL (v26.08.307)
    -- ========================================================================
    OVERWORLD_TRANSITION_HEIGHT    = 20000, -- Altura real de transferencia dimensional Overworld
    MOON_TRANSITION_HEIGHT         = 20000, -- Altura real de transferencia dimensional Luna
    ORBIT_SAFETY_MARGIN            = 3000,  -- Margen de seguridad sobre transition height (Pe > 23000)
    APEX_RADIAL_SPEED_TOLERANCE    = 1.0,   -- Tolerancia para declarar llegada al ápex (|Vrad| <= 1 m/s)
    POSITION_CONSISTENCY_TOLERANCE = 1500,  -- Tolerancia entre |r|-R y distanceToPlanet

    -- CONTROL DE ASCENSO
    ASCENT_MAX_VERTICAL_SPEED  = 18.0,  -- Velocidad vertical máxima permitida en ascenso
    ASCENT_SLOW_VERTICAL_SPEED = 10.0,  -- Velocidad vertical de crucero objetivo
    ASCENT_DEADBAND            = 0.5,   -- Margen/zona muerta de velocidad vertical objetivo
    ASCENT_KP                  = 0.12,  -- Ganancia proporcional de aceleración UP
    ASCENT_BRAKE_KP            = 0.18,  -- Ganancia proporcional de frenado DOWN
    SOFT_START_RAMP            = 2.0,   -- Segundos de rampa de despegue suave

    -- LÍMITES DE VELOCIDAD EN ESPACIO
    SPACE_MAX_SPEED            = 45.0,  -- Velocidad máxima nominal permitida en espacio
    SPACE_CRUISE_SPEED         = 30.0,  -- Inicio de estrangulamiento progresivo de empuje
    SPACE_MAX_ACCELERATION     = 10.0,  -- Límite de aceleración/potencia aplicado
    SPACE_BRAKE_KP             = 0.15,  -- Ganancia proporcional de frenado en espacio
    SPACE_SPEED_TOLERANCE      = 2.0,   -- Margen antes de activar frenado retrógrado suave
    SPACE_EMERGENCY_SPEED      = 60.0,  -- Límite crítico de seguridad de velocidad total

    -- QUEMAS CORTAS Y COAST EN ESPACIO
    SPACE_BURN_DURATION        = 0.8,   -- Segundos que dura cada pulso de aceleración
    SPACE_COAST_DURATION       = 1.2,   -- Segundos de inercia/medición entre pulsos

    -- Datos del universo estándar de Cosmonautics 26.08.307.
    -- Se usan SOLO para diagnóstico/planificación. No se ejecuta TLI sin vector lunar real.
    OVERWORLD_RADIUS           = 3000000.0,
    OVERWORLD_SURFACE_G        = 11.0,
    MOON_RADIUS                = 750000.0,
    LUNAR_ORBIT_PERIOD         = 28800.0, -- 24 días MC * 1200 s
    PARKING_ECC_TARGET         = 0.08,

    -- Recuperación automática
    MAX_RECOVERY_ATTEMPTS       = 5,
    RECOVERY_RETRY_DELAY        = 1.0,

    -- Inserción orbital robusta
    MIN_TANGENTIAL_VECTOR_SPEED = 0.25,
    INSERTION_MIN_THROTTLE      = 0.18,
    INSERTION_MAX_THROTTLE      = 0.75
}

-- ============================================================================
-- VERIFICACIÓN DE VALORES NUMÉRICOS FINITOS (ANTI-NaN)
-- ============================================================================

local function isFinite(x)
    return type(x) == "number"
       and x == x
       and x ~= math.huge
       and x ~= -math.huge
end

local function clamp(val, minVal, maxVal)
    return math.max(minVal, math.min(maxVal, val))
end

local function powerToAnalog(power)
    if not isFinite(power) then return 0 end
    return math.floor(clamp(power, 0, 1) * 15 + 0.5)
end

-- ============================================================================
-- VALIDACIÓN Y PERSISTENCIA DE LÍMITES DE VELOCIDAD
-- ============================================================================

local speedSettingsSchema = {
    { key = "ASCENT_MAX_VERTICAL_SPEED", label = "ASCENT MAX",      step = 0.5, bigStep = 2.0, min = 0.5 },
    { key = "SPACE_CRUISE_SPEED",        label = "SPACE CRUISE",    step = 1.0, bigStep = 5.0, min = 1.0 },
    { key = "SPACE_MAX_SPEED",           label = "SPACE MAX",       step = 1.0, bigStep = 5.0, min = 1.5 },
    { key = "SPACE_EMERGENCY_SPEED",     label = "SPACE EMERGENCY", step = 1.0, bigStep = 5.0, min = 2.0 }
}

local selectedSpeedParam = 1

local function sanitizeSpeedLimits()
    if not isFinite(CONFIG.ASCENT_MAX_VERTICAL_SPEED) or CONFIG.ASCENT_MAX_VERTICAL_SPEED < 0.5 then
        CONFIG.ASCENT_MAX_VERTICAL_SPEED = 0.5
    end
    if not isFinite(CONFIG.SPACE_CRUISE_SPEED) or CONFIG.SPACE_CRUISE_SPEED < 1.0 then
        CONFIG.SPACE_CRUISE_SPEED = 1.0
    end
    if not isFinite(CONFIG.SPACE_MAX_SPEED) or CONFIG.SPACE_MAX_SPEED < CONFIG.SPACE_CRUISE_SPEED then
        CONFIG.SPACE_MAX_SPEED = CONFIG.SPACE_CRUISE_SPEED
    end
    if not isFinite(CONFIG.SPACE_EMERGENCY_SPEED) or CONFIG.SPACE_EMERGENCY_SPEED <= CONFIG.SPACE_MAX_SPEED then
        CONFIG.SPACE_EMERGENCY_SPEED = CONFIG.SPACE_MAX_SPEED + 1.0
    end
end

local function saveSpeedSettings()
    sanitizeSpeedLimits()
    local payload = {
        ASCENT_MAX_VERTICAL_SPEED = CONFIG.ASCENT_MAX_VERTICAL_SPEED,
        SPACE_CRUISE_SPEED        = CONFIG.SPACE_CRUISE_SPEED,
        SPACE_MAX_SPEED           = CONFIG.SPACE_MAX_SPEED,
        SPACE_EMERGENCY_SPEED     = CONFIG.SPACE_EMERGENCY_SPEED
    }
    local f = fs.open(SETTINGS_FILE, "w")
    if f then
        f.write(textutils.serialize(payload))
        f.close()
    end
end

local function loadSpeedSettings()
    if fs.exists(SETTINGS_FILE) then
        local f = fs.open(SETTINGS_FILE, "r")
        if f then
            local raw = f.readAll()
            f.close()
            local data = textutils.unserialize(raw)
            if type(data) == "table" then
                if isFinite(data.ASCENT_MAX_VERTICAL_SPEED) then
                    CONFIG.ASCENT_MAX_VERTICAL_SPEED = data.ASCENT_MAX_VERTICAL_SPEED
                end
                if isFinite(data.SPACE_CRUISE_SPEED) then
                    CONFIG.SPACE_CRUISE_SPEED = data.SPACE_CRUISE_SPEED
                end
                if isFinite(data.SPACE_MAX_SPEED) then
                    CONFIG.SPACE_MAX_SPEED = data.SPACE_MAX_SPEED
                end
                if isFinite(data.SPACE_EMERGENCY_SPEED) then
                    CONFIG.SPACE_EMERGENCY_SPEED = data.SPACE_EMERGENCY_SPEED
                end
            end
        end
    end
    sanitizeSpeedLimits()
end

loadSpeedSettings()

-- ============================================================================
-- BIBLIOTECA MATEMÁTICA PURA (VECTORES 3D Y CUATERIONES)
-- ============================================================================

local function vec3(x, y, z)
    return {
        x = isFinite(x) and x or 0,
        y = isFinite(y) and y or 0,
        z = isFinite(z) and z or 0
    }
end

local function vecLen(v)
    return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end

local function vecNorm(v)
    local l = vecLen(v)
    if l == 0 or not isFinite(l) then return vec3(0, 0, 0) end
    return vec3(v.x / l, v.y / l, v.z / l)
end

local function vecDot(a, b)
    return a.x * b.x + a.y * b.y + a.z * b.z
end

local function vecCross(a, b)
    return vec3(
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x
    )
end

local function vecScale(v, s)
    return vec3(v.x * s, v.y * s, v.z * s)
end

local function vecSub(a, b)
    return vec3(a.x - b.x, a.y - b.y, a.z - b.z)
end

local function safeDirection(v)
    if vecLen(v) <= 1e-6 then return nil end
    return vecNorm(v)
end

local function projectOnPlane(v, normal)
    local d = vecDot(v, normal)
    return vecSub(v, vecScale(normal, d))
end

local function orthogonalUnit(n)
    -- Elige un eje poco paralelo a n para construir una tangente estable.
    local ref
    if math.abs(n.y) < 0.85 then
        ref = vec3(0, 1, 0)
    elseif math.abs(n.x) < 0.85 then
        ref = vec3(1, 0, 0)
    else
        ref = vec3(0, 0, 1)
    end
    return vecNorm(vecCross(ref, n))
end

local function parseQuat(q)
    if type(q) ~= "table" then return { w = 1, x = 0, y = 0, z = 0 } end
    local w = q.w or q[4] or 1
    local x = q.x or q[1] or 0
    local y = q.y or q[2] or 0
    local z = q.z or q[3] or 0
    local mag = math.sqrt(w * w + x * x + y * y + z * z)
    if mag == 0 or not isFinite(mag) then return { w = 1, x = 0, y = 0, z = 0 } end
    return { w = w / mag, x = x / mag, y = y / mag, z = z / mag }
end

local function quatRotate(q, v)
    local qv = vec3(q.x, q.y, q.z)
    local uv = vecCross(qv, v)
    local uuv = vecCross(qv, uv)
    return vec3(
        v.x + ((uv.x * q.w) + uuv.x) * 2,
        v.y + ((uv.y * q.w) + uuv.y) * 2,
        v.z + ((uv.z * q.w) + uuv.z) * 2
    )
end

local function worldToLocal(q, v)
    local qConj = { w = q.w, x = -q.x, y = -q.y, z = -q.z }
    return quatRotate(qConj, v)
end

local function quatToEulerDeg(q)
    local siny_cosp = 2 * (q.w * q.y + q.x * q.z)
    local cosy_cosp = 1 - 2 * (q.y * q.y + q.z * q.z)
    local yaw = math.deg(math.atan2(siny_cosp, cosy_cosp))

    local sinp = 2 * (q.w * q.x - q.y * q.z)
    local pitch
    if math.abs(sinp) >= 1 then
        pitch = math.deg((sinp >= 0 and 1 or -1) * (math.pi / 2))
    else
        pitch = math.deg(math.asin(sinp))
    end

    local sinr_cosp = 2 * (q.w * q.z + q.x * q.y)
    local cosr_cosp = 1 - 2 * (q.x * q.x + q.z * q.z)
    local roll = math.deg(math.atan2(sinr_cosp, cosr_cosp))

    return yaw, pitch, roll
end

-- ============================================================================
-- DESCUBRIMIENTO Y REGISTRO DE PERIFÉRICOS
-- ============================================================================

local devices = {
    sputnikSide = nil,
    navSide = nil,
    modemSide = nil
}

local navMethods = {}

local function scanHardware()
    devices.sputnikSide = nil
    devices.navSide = nil
    devices.modemSide = nil
    navMethods = {}

    local names = peripheral.getNames()
    for _, name in ipairs(names) do
        local pType = peripheral.getType(name)
        local methods = peripheral.getMethods(name)
        local mMap = {}
        for _, m in ipairs(methods) do mMap[m] = true end

        if pType == "sputnik" or mMap["getDeepSpaceData"] then
            devices.sputnikSide = name
        end

        if pType == "navigation_table" or mMap["getTargetType"] or mMap["hasTarget"] then
            devices.navSide = name
            navMethods = mMap
        end

        if pType == "modem" then
            devices.modemSide = name
        end
    end
end

scanHardware()

if devices.modemSide then
    rednet.open(devices.modemSide)
end

-- ============================================================================
-- GESTOR DE COMUNICACIÓN Y ENLACE DE ACTUADORES
-- ============================================================================

local thrusterLink = {
    targetId = CONFIG.SECONDARY_ID,
    online = false,
    lastAckTime = 0,
    lastHeartbeatSent = 0
}

local function sendSecondary(cmd, power)
    if not devices.modemSide then return end
    local msg = { command = cmd }
    if power ~= nil then
        msg.power = clamp(power, 0, 1)
    end

    if thrusterLink.targetId then
        rednet.send(thrusterLink.targetId, msg, CONFIG.PROTOCOL)
    else
        rednet.broadcast(msg, CONFIG.PROTOCOL)
    end
end

local actuators = {}

function actuators.forward(power)  sendSecondary("FORWARD", power) end
function actuators.backward(power) sendSecondary("BACKWARD", power) end
function actuators.turnLeft(power) sendSecondary("LEFT", power) end
function actuators.turnRight(power)sendSecondary("RIGHT", power) end
function actuators.up(power)       sendSecondary("UP", power) end

function actuators.down(power)
    local analog = powerToAnalog(power)
    redstone.setAnalogOutput(CONFIG.MAIN_DOWN_SIDE, analog)
end

function actuators.stopAll()
    redstone.setAnalogOutput(CONFIG.MAIN_DOWN_SIDE, 0)
    sendSecondary("STOP")
end

-- ============================================================================
-- ESTADOS DEL VUELO Y TELEMETRÍA (SECUENCIA ACTUALIZADA)
-- ============================================================================

local States = {
    READY                   = "READY",
    LAUNCH                  = "LAUNCH",
    ASCENT                  = "ASCENT",
    DEEP_SPACE_ENTRY        = "DEEP_SPACE_ENTRY",
    COAST_TO_APEX           = "COAST_TO_APEX",
    ORBIT_INSERTION         = "ORBIT_INSERTION",
    ORBIT_BUILD             = "ORBIT_BUILD", -- alias
    ORBIT_CIRCULARIZE       = "ORBIT_CIRCULARIZE",
    PARKING_ORBIT           = "PARKING_ORBIT",
    WAITING_FOR_MOON_TARGET = "WAITING_FOR_MOON_TARGET",
    WAIT_LUNAR_WINDOW       = "WAIT_LUNAR_WINDOW",
    TLI                     = "TLI",
    COAST                   = "COAST",
    MIDCOURSE               = "MIDCOURSE",
    LUNAR_APPROACH          = "LUNAR_APPROACH",
    LUNAR_CAPTURE           = "LUNAR_CAPTURE",
    LUNAR_ORBIT             = "LUNAR_ORBIT",
    WAITING_FOR_LUNAR_DATA  = "WAITING_FOR_LUNAR_DATA",
    ORBITAL_DATA_LOCK       = "ORBITAL_DATA_LOCK",
    RECOVERY                = "RECOVERY",
    ABORT                   = "ABORT"
}

local telemetry = {
    destination = "MOON",
    mode = "AUTO",
    state = States.READY,

    sputnikOnline = false,
    navTableOnline = false,
    thrusterLinkOnline = false,

    inDeepSpace = false,
    parentBody = "NONE",
    parentRadius = nil,
    distanceToPlanet = nil,
    altitude = nil,

    pos = vec3(0, 0, 0),
    vel = vec3(0, 0, 0),
    speed = 0,
    mass = 0,

    -- Datos de physics.space confirmados
    spaceAvailable = false,
    spacePos = vec3(0, 0, 0),
    spaceVel = vec3(0, 0, 0),
    validSpaceVector = false,

    radialSpeed = 0,
    tangentialSpeed = 0,
    prograde = vec3(0, 0, 0),
    orbitNormal = vec3(0, 0, 0),
    insertionPrograde = vec3(0, 0, 0),

    angVel = vec3(0, 0, 0),
    quat = { w = 1, x = 0, y = 0, z = 0 },
    yaw = 0,
    pitch = 0,
    roll = 0,

    sma = nil,
    ecc = nil,
    period = nil,
    inclination = nil,
    localGravity = nil,
    universeTime = nil,
    inAtmosphere = false,
    atmosphereFlags = "",
    spaceFrame = "UNKNOWN",
    peAlt = nil,
    apAlt = nil,

    orbitalSolutionValid = false,
    safeOrbit = false,
    reentryGuard = false,
    orbitValid = false,

    navTarget = "NONE",
    targetDist = nil,
    closureRate = nil,

    entryPos = nil,
    entryVel = nil,

    lunarOrbitRadius = nil,
    lunarTransferTime = nil,
    lunarRequiredPhase = nil,
    lunarDataReady = false,

    recoveryAttempts = 0,
    recoveryReason = "",
    recoveryTarget = States.DEEP_SPACE_ENTRY,
    recoveryResumeAt = 0,

    nextManeuver = "PRESS 'L' TO LAUNCH"
}

local flightTimers = {
    launchStartTime = 0,
    spacePulsePhase = "COAST",
    spacePulseTimer = 0
}

-- ============================================================================
-- LECTURA DE TELEMETRÍA CON VALIDACIÓN REAL COSMONAUTICS 26.08.307
-- ============================================================================

local function pollTelemetry()
    -- 1. Sputnik - getDeepSpaceData()
    if devices.sputnikSide and peripheral.isPresent(devices.sputnikSide) then
        telemetry.sputnikOnline = true

        local dsOk, ds = pcall(peripheral.call, devices.sputnikSide, "getDeepSpaceData")
        if dsOk and type(ds) == "table" then
            telemetry.inDeepSpace = (ds.inDeepSpace == true)
            telemetry.parentBody = tostring(ds.parentBody or "UNKNOWN")
            telemetry.parentRadius = isFinite(ds.parentRadius) and ds.parentRadius or nil
            telemetry.distanceToPlanet = isFinite(ds.distanceToPlanet) and ds.distanceToPlanet or nil

            telemetry.sma = isFinite(ds.semiMajorAxis) and ds.semiMajorAxis or nil
            telemetry.ecc = isFinite(ds.eccentricity) and ds.eccentricity or nil
            telemetry.period = isFinite(ds.period) and ds.period or nil
            telemetry.inclination = isFinite(ds.inclination) and ds.inclination or nil
            telemetry.localGravity = isFinite(ds.gravity) and ds.gravity or nil
            telemetry.universeTime = isFinite(ds.universeTime) and ds.universeTime or nil
            telemetry.inAtmosphere = (ds.inAtmosphere == true)
            telemetry.atmosphereFlags = tostring(ds.atmosphereFlags or "")

            if isFinite(ds.speed) then
                telemetry.speed = ds.speed
            end
        else
            telemetry.inDeepSpace = false
            telemetry.orbitalSolutionValid = false
            telemetry.safeOrbit = false
        end

        -- 2. Sputnik - getPhysics() con physics.space
        local phOk, ph = pcall(peripheral.call, devices.sputnikSide, "getPhysics")
        if phOk and type(ph) == "table" then
            telemetry.mass = isFinite(ph.mass) and ph.mass or 0

            local pv = ph.velocity or ph.vel
            if type(pv) == "table" and isFinite(pv.x) and isFinite(pv.y) and isFinite(pv.z) then
                telemetry.vel = vec3(pv.x, pv.y, pv.z)
                if telemetry.speed == 0 then telemetry.speed = vecLen(telemetry.vel) end
            end

            local pq = ph.quaternion or ph.orientation or ph.rot
            if pq then
                telemetry.quat = parseQuat(pq)
                telemetry.yaw, telemetry.pitch, telemetry.roll = quatToEulerDeg(telemetry.quat)
            end

            -- Extracción de physics.space real
            telemetry.spaceAvailable = false
            if type(ph.space) == "table" and ph.space.available == true then
                local sp = ph.space.position
                local sv = ph.space.velocity
                if type(sp) == "table" and isFinite(sp.x) and isFinite(sp.y) and isFinite(sp.z) and
                   type(sv) == "table" and isFinite(sv.x) and isFinite(sv.y) and isFinite(sv.z) then
                    telemetry.spacePos = vec3(sp.x, sp.y, sp.z)
                    telemetry.spaceVel = vec3(sv.x, sv.y, sv.z)
                    telemetry.spaceFrame = tostring(ph.space.frame or telemetry.parentBody or "UNKNOWN")
                    telemetry.spaceAvailable = true

                    -- En Deep Space, physics.space es el vector correcto para navegación orbital.
                    telemetry.speed = vecLen(telemetry.spaceVel)
                end
            end
        else
            error("[FAILSAFE] getPhysics() falló o devolvió nil.")
        end

        -- getGlobalPos()
        local gpOk, gp = pcall(peripheral.call, devices.sputnikSide, "getGlobalPos")
        if gpOk and type(gp) == "table" and isFinite(gp.x) and isFinite(gp.y) and isFinite(gp.z) then
            telemetry.pos = vec3(gp.x, gp.y, gp.z)
        end
    else
        telemetry.sputnikOnline = false
        error("[FAILSAFE] Periférico 'sputnik' desconectado o ausente.")
    end

    -- 3. Validación de coherencia del vector orbital
    telemetry.validSpaceVector = false
    telemetry.altitude = telemetry.distanceToPlanet

    if telemetry.spaceAvailable and telemetry.parentRadius and telemetry.parentRadius > 0 then
        local rLen = vecLen(telemetry.spacePos)
        local altFromPos = rLen - telemetry.parentRadius
        if isFinite(altFromPos) and telemetry.distanceToPlanet and isFinite(telemetry.distanceToPlanet) then
            if math.abs(altFromPos - telemetry.distanceToPlanet) <= CONFIG.POSITION_CONSISTENCY_TOLERANCE then
                telemetry.validSpaceVector = true
                telemetry.altitude = altFromPos

                -- Descomposición radial y tangencial exacta en el frame orbital
                local rHat = vecNorm(telemetry.spacePos)
                local v = telemetry.spaceVel
                local vRad = vecDot(v, rHat)
                local vTanVec = vec3(v.x - rHat.x * vRad, v.y - rHat.y * vRad, v.z - rHat.z * vRad)

                telemetry.radialSpeed = vRad
                telemetry.tangentialSpeed = vecLen(vTanVec)

                -- Prograde medido, cuando existe componente tangencial suficiente.
                if telemetry.tangentialSpeed >= CONFIG.MIN_TANGENTIAL_VECTOR_SPEED then
                    telemetry.prograde = vecNorm(vTanVec)

                    -- Momento angular h = r x v. Mantiene estable el plano orbital.
                    local h = vecCross(telemetry.spacePos, telemetry.spaceVel)
                    if vecLen(h) > 1e-6 then
                        telemetry.orbitNormal = vecNorm(h)
                    end

                    -- Si aún no habíamos fijado una dirección de inserción, usamos la medida real.
                    if vecLen(telemetry.insertionPrograde) <= 1e-6 then
                        telemetry.insertionPrograde = telemetry.prograde
                    elseif vecDot(telemetry.insertionPrograde, telemetry.prograde) < 0 then
                        -- Evita invertir 180 grados por ruido numérico.
                        telemetry.prograde = vecScale(telemetry.prograde, -1)
                    end
                else
                    telemetry.prograde = vec3(0, 0, 0)
                end
            end
        end
    end

    -- 4. Cálculo analítico de periapsis, apoapsis y órbita segura
    local a = telemetry.sma
    local e = telemetry.ecc
    local R = telemetry.parentRadius

    telemetry.peAlt = nil
    telemetry.apAlt = nil
    telemetry.orbitalSolutionValid = false
    telemetry.safeOrbit = false

    if isFinite(a) and isFinite(e) and isFinite(telemetry.period) and a > 0 and e >= 0 and e < 1 and telemetry.period > 0 then
        telemetry.orbitalSolutionValid = true

        if isFinite(R) and R > 0 then
            local rp = a * (1 - e)
            local ra = a * (1 + e)
            telemetry.peAlt = rp - R
            telemetry.apAlt = ra - R

            local transHeight = CONFIG.OVERWORLD_TRANSITION_HEIGHT
            if telemetry.parentBody:lower():find("moon") or telemetry.parentBody:lower():find("luna") then
                transHeight = CONFIG.MOON_TRANSITION_HEIGHT
            end

            local minSafeAlt = transHeight + CONFIG.ORBIT_SAFETY_MARGIN
            if telemetry.peAlt > minSafeAlt then
                telemetry.safeOrbit = true
            end
        end
    end
    telemetry.orbitValid = telemetry.orbitalSolutionValid

    -- Reentry guard
    local transHeight = CONFIG.OVERWORLD_TRANSITION_HEIGHT
    if telemetry.parentBody:lower():find("moon") or telemetry.parentBody:lower():find("luna") then
        transHeight = CONFIG.MOON_TRANSITION_HEIGHT
    end
    local safeThreshold = transHeight + CONFIG.ORBIT_SAFETY_MARGIN

    if telemetry.inDeepSpace and telemetry.validSpaceVector and telemetry.radialSpeed < 0 and
       (telemetry.peAlt == nil or telemetry.peAlt <= safeThreshold) then
        telemetry.reentryGuard = true
    else
        telemetry.reentryGuard = false
    end

    -- 5. Sable sublevel
    if _G.sublevel and type(_G.sublevel.getAngularVelocity) == "function" then
        local ok, av = pcall(_G.sublevel.getAngularVelocity)
        if ok and type(av) == "table" and isFinite(av.x) and isFinite(av.y) and isFinite(av.z) then
            telemetry.angVel = vec3(av.x, av.y, av.z)
        end
    end

    -- 6. Navigation Table
    if devices.navSide and peripheral.isPresent(devices.navSide) then
        telemetry.navTableOnline = true
        local hasTgt = false
        if navMethods["hasTarget"] then
            local ok, res = pcall(peripheral.call, devices.navSide, "hasTarget")
            if ok and res == true then hasTgt = true end
        end

        if hasTgt then
            if navMethods["getTargetType"] then
                local ok, tType = pcall(peripheral.call, devices.navSide, "getTargetType")
                if ok and tType then telemetry.navTarget = tostring(tType) end
            else
                telemetry.navTarget = "TARGET_ACQUIRED"
            end
            if navMethods["getDistanceToTarget"] then
                local ok, d = pcall(peripheral.call, devices.navSide, "getDistanceToTarget")
                telemetry.targetDist = (ok and isFinite(d)) and d or nil
            end
            if navMethods["getClosureRate"] then
                local ok, c = pcall(peripheral.call, devices.navSide, "getClosureRate")
                telemetry.closureRate = (ok and isFinite(c)) and c or nil
            end
        else
            telemetry.navTarget = "NONE"
            telemetry.targetDist = nil
            telemetry.closureRate = nil
        end
    else
        telemetry.navTableOnline = false
        telemetry.navTarget = "OFFLINE"
    end
end

-- ============================================================================
-- PROCESAMIENTO DE MENSAJES REDNET Y HEARTBEAT
-- ============================================================================

local function serviceRednet()
    local now = os.epoch("utc")

    if (now - thrusterLink.lastHeartbeatSent) >= (CONFIG.HEARTBEAT_INTERVAL * 1000) then
        sendSecondary("HEARTBEAT")
        thrusterLink.lastHeartbeatSent = now
    end

    if devices.modemSide then
        while true do
            local senderId, msg, proto = rednet.receive(CONFIG.PROTOCOL, 0.001)
            if not senderId then break end

            if type(msg) == "table" and msg.type == "ACK" then
                if not thrusterLink.targetId or thrusterLink.targetId == senderId then
                    thrusterLink.targetId = senderId
                    thrusterLink.online = true
                    thrusterLink.lastAckTime = now
                end
            end
        end
    end

    if (now - thrusterLink.lastAckTime) > (CONFIG.WATCHDOG_LINK_TIMEOUT * 1000) then
        thrusterLink.online = false
    end
    telemetry.thrusterLinkOnline = thrusterLink.online
end

-- ============================================================================
-- SISTEMA DE CONTROL DIRECCIONAL (TRANSLACIÓN PURA SIN PITCH)
-- ============================================================================

local function thrustVector(worldDir, power)
    local normDir = vecNorm(worldDir)
    if vecLen(normDir) == 0 or power <= 0 then
        actuators.stopAll()
        return
    end

    local localDir = worldToLocal(telemetry.quat, normDir)

    if math.abs(localDir.x) > 0.1 then
        if localDir.x > 0 then
            actuators.turnRight(clamp(math.abs(localDir.x) * 1.5, 0.2, 1.0))
            actuators.turnLeft(0)
        else
            actuators.turnLeft(clamp(math.abs(localDir.x) * 1.5, 0.2, 1.0))
            actuators.turnRight(0)
        end
    else
        actuators.turnLeft(0)
        actuators.turnRight(0)
    end

    if localDir.z > 0.12 then
        actuators.forward(power * clamp(localDir.z * 1.3, 0.2, 1.0))
        actuators.backward(0)
    elseif localDir.z < -0.12 then
        actuators.backward(power * clamp(math.abs(localDir.z) * 1.3, 0.2, 1.0))
        actuators.forward(0)
    else
        actuators.forward(0)
        actuators.backward(0)
    end

    if localDir.y > 0.12 then
        actuators.up(power * clamp(localDir.y * 1.3, 0.2, 1.0))
        actuators.down(0)
    elseif localDir.y < -0.12 then
        actuators.down(power * clamp(math.abs(localDir.y) * 1.3, 0.2, 1.0))
        actuators.up(0)
    else
        actuators.up(0)
        actuators.down(0)
    end
end

-- ============================================================================
-- MÁQUINA DE ESTADOS DEL AUTOPILOTO (NUEVA SECUENCIA ORBITAL)
-- ============================================================================

local function requestRecovery(reason, targetState)
    actuators.stopAll()

    telemetry.recoveryAttempts = telemetry.recoveryAttempts + 1
    telemetry.recoveryReason = reason or "UNKNOWN"
    telemetry.recoveryTarget = targetState or States.DEEP_SPACE_ENTRY
    telemetry.recoveryResumeAt = os.epoch("utc") + (CONFIG.RECOVERY_RETRY_DELAY * 1000)

    telemetry.state = States.RECOVERY

    if telemetry.recoveryAttempts <= CONFIG.MAX_RECOVERY_ATTEMPTS then
        telemetry.nextManeuver = string.format(
            "[RECOVERY %d/%d] %s",
            telemetry.recoveryAttempts,
            CONFIG.MAX_RECOVERY_ATTEMPTS,
            telemetry.recoveryReason
        )
    else
        -- Nunca aborta automáticamente: entra en espera segura y sigue reintentando.
        telemetry.nextManeuver = string.format(
            "[SAFE RETRY %d] %s",
            telemetry.recoveryAttempts,
            telemetry.recoveryReason
        )
    end
end

local function buildInsertionDirection()
    if not telemetry.validSpaceVector then return nil end

    local rHat = vecNorm(telemetry.spacePos)

    -- 1) Si ya existe una tangente real útil, úsala.
    if telemetry.tangentialSpeed >= CONFIG.MIN_TANGENTIAL_VECTOR_SPEED and vecLen(telemetry.prograde) > 0 then
        telemetry.insertionPrograde = telemetry.prograde
        return telemetry.prograde
    end

    -- 2) Proyectar el "forward" actual de la nave sobre el plano tangencial.
    local bodyForward = quatRotate(telemetry.quat, vec3(0, 0, 1))
    local tangent = projectOnPlane(bodyForward, rHat)

    -- 3) Si el morro apunta casi radialmente, usar una tangente geométrica estable.
    if vecLen(tangent) <= 1e-4 then
        tangent = orthogonalUnit(rHat)
    else
        tangent = vecNorm(tangent)
    end

    -- 4) Mantener la misma dirección en todos los ticks.
    if vecLen(telemetry.insertionPrograde) > 1e-6 then
        if vecDot(tangent, telemetry.insertionPrograde) < 0 then
            tangent = vecScale(tangent, -1)
        end
    else
        telemetry.insertionPrograde = tangent
    end

    return tangent
end

local function updateAutopilot()
    local now = os.epoch("utc")

    if vecLen(telemetry.angVel) > CONFIG.MAX_ANGULAR_VELOCITY then
        requestRecovery("ANGULAR VELOCITY TOO HIGH", telemetry.inDeepSpace and States.DEEP_SPACE_ENTRY or States.ASCENT)
        return
    end

    if telemetry.state ~= States.READY and telemetry.state ~= States.ABORT then
        if not telemetry.thrusterLinkOnline then
            requestRecovery("THRUSTER LINK LOST", telemetry.inDeepSpace and States.DEEP_SPACE_ENTRY or States.ASCENT)
            return
        end
    end

    if telemetry.inDeepSpace and telemetry.speed >= CONFIG.SPACE_EMERGENCY_SPEED then
        local brakeVel = telemetry.validSpaceVector and telemetry.spaceVel or telemetry.vel
        if vecLen(brakeVel) > 0.1 then
            local retro = vec3(-brakeVel.x, -brakeVel.y, -brakeVel.z)
            thrustVector(retro, clamp((telemetry.speed - CONFIG.SPACE_MAX_SPEED) * CONFIG.SPACE_BRAKE_KP, 0.3, 1.0))
            telemetry.nextManeuver = "[ALERT] EMERGENCY SPEED BRAKE ENGAGED"
        else
            requestRecovery("SPEED LIMIT EXCEEDED - NO BRAKE VECTOR", States.DEEP_SPACE_ENTRY)
        end
        return
    end

    if telemetry.mode ~= "AUTO" and telemetry.state ~= States.READY then
        return
    end

    -- FASE 1: LAUNCH
    if telemetry.state == States.LAUNCH then
        flightTimers.launchStartTime = now
        telemetry.nextManeuver = "CONTROLLED SOFT-START IGNITION"
        actuators.down(0)
        actuators.up(0.2)
        telemetry.state = States.ASCENT

    -- FASE 2: ASCENT
    elseif telemetry.state == States.ASCENT then
        telemetry.nextManeuver = "ASCENT: CONTROLLING VERTICAL SPEED"

        if telemetry.angVel.y > 0.15 then
            actuators.turnLeft(0.4)
            actuators.turnRight(0)
        elseif telemetry.angVel.y < -0.15 then
            actuators.turnRight(0.4)
            actuators.turnLeft(0)
        else
            actuators.turnLeft(0)
            actuators.turnRight(0)
        end

        local elapsed = (now - flightTimers.launchStartTime) / 1000
        local ramp = clamp(elapsed / CONFIG.SOFT_START_RAMP, 0.2, 1.0)
        local targetVy = CONFIG.ASCENT_SLOW_VERTICAL_SPEED * ramp
        local currentVy = telemetry.vel.y
        local deadband = CONFIG.ASCENT_DEADBAND or 0.5

        if currentVy < (targetVy - deadband) then
            local errorVy = (targetVy - deadband) - currentVy
            local upPower = clamp(errorVy * CONFIG.ASCENT_KP, 0.1, 1.0) * ramp
            actuators.up(upPower)
            actuators.down(0)
        elseif currentVy > (targetVy + deadband) then
            actuators.up(0)
            local overspeed = currentVy - (targetVy + deadband)
            local brakePower = clamp(overspeed * CONFIG.ASCENT_BRAKE_KP, 0.1, 0.6)

            if currentVy > CONFIG.ASCENT_MAX_VERTICAL_SPEED then
                local excess = currentVy - CONFIG.ASCENT_MAX_VERTICAL_SPEED
                brakePower = clamp(brakePower + (excess * CONFIG.ASCENT_BRAKE_KP), 0.3, 1.0)
            end

            actuators.down(brakePower)
        else
            actuators.up(0)
            actuators.down(0)
        end

        if telemetry.inDeepSpace then
            actuators.stopAll()
            telemetry.state = States.DEEP_SPACE_ENTRY
        end

    -- FASE 3: DEEP SPACE ENTRY (TRANSICIÓN SIN FRENAR RADIAL A CERO)
    elseif telemetry.state == States.DEEP_SPACE_ENTRY then
        telemetry.nextManeuver = "DEEP SPACE ENTRY: ACQUIRING ORBITAL FRAME"

        if not telemetry.entryVel then
            telemetry.entryPos = vec3(telemetry.pos.x, telemetry.pos.y, telemetry.pos.z)
            telemetry.entryVel = vec3(telemetry.vel.x, telemetry.vel.y, telemetry.vel.z)
        end

        actuators.stopAll()

        if not telemetry.validSpaceVector then
            telemetry.nextManeuver = "WAITING FOR COHERENT physics.space VECTOR"
            return
        end

        -- Fijar una dirección tangencial estable aunque la entrada sea casi radial.
        local initialTangent = buildInsertionDirection()
        if not initialTangent or vecLen(initialTangent) <= 1e-6 then
            requestRecovery("CANNOT BUILD INITIAL TANGENTIAL VECTOR", States.DEEP_SPACE_ENTRY)
            return
        end

        telemetry.recoveryAttempts = 0

        -- Si la nave entra ascendiendo en el frame orbital, coast hasta el ápex
        if telemetry.radialSpeed > CONFIG.APEX_RADIAL_SPEED_TOLERANCE then
            telemetry.state = States.COAST_TO_APEX
        else
            -- Ya en o cerca del punto ápex
            flightTimers.spacePulsePhase = "BURN"
            flightTimers.spacePulseTimer = now
            telemetry.state = States.ORBIT_INSERTION
        end

    -- FASE 4: COAST_TO_APEX (ESPERA PASIVA HASTA Vrad ≈ 0 CON REENTRY GUARD)
    elseif telemetry.state == States.COAST_TO_APEX then
        if not telemetry.validSpaceVector then
            actuators.stopAll()
            telemetry.state = States.ORBITAL_DATA_LOCK
            telemetry.nextManeuver = "[LOCK] ORBITAL VECTOR INCONSISTENT"
            return
        end

        -- REENTRY GUARD: Si comienza a caer y el periapsis no es seguro, actuar de inmediato
        if telemetry.reentryGuard then
            if telemetry.tangentialSpeed > 0.1 and vecLen(telemetry.prograde) > 0 then
                flightTimers.spacePulsePhase = "BURN"
                flightTimers.spacePulseTimer = now
                telemetry.state = States.ORBIT_INSERTION
                return
            else
                requestRecovery("REENTRY RISK - REBUILDING ORBIT VECTOR", States.DEEP_SPACE_ENTRY)
                return
            end
        end

        -- Si la velocidad radial sigue siendo positiva, seguir en COAST
        if telemetry.radialSpeed > CONFIG.APEX_RADIAL_SPEED_TOLERANCE then
            actuators.stopAll()
            telemetry.nextManeuver = string.format("COAST TO APEX (Vrad: %+.1f m/s)", telemetry.radialSpeed)
        else
            -- Llegada al punto ápex: iniciar inserción orbital tangencial
            actuators.stopAll()
            flightTimers.spacePulsePhase = "BURN"
            flightTimers.spacePulseTimer = now
            telemetry.state = States.ORBIT_INSERTION
        end

    -- FASE 5: ORBIT_INSERTION (BURNS TANGENCIALES PARA ELEVAR PERIAPSIS > 23km)
    elseif telemetry.state == States.ORBIT_INSERTION or telemetry.state == States.ORBIT_BUILD then
        if not telemetry.validSpaceVector then
            actuators.stopAll()
            telemetry.state = States.ORBITAL_DATA_LOCK
            telemetry.nextManeuver = "[LOCK] NO COHERENT ORBITAL FRAME FOR INSERTION"
            return
        end

        local transHeight = CONFIG.OVERWORLD_TRANSITION_HEIGHT
        if telemetry.parentBody:lower():find("moon") or telemetry.parentBody:lower():find("luna") then
            transHeight = CONFIG.MOON_TRANSITION_HEIGHT
        end
        local minSafeAlt = transHeight + CONFIG.ORBIT_SAFETY_MARGIN

        -- OBJETIVO: Periapsis sobre 23000m y solución matemática válida
        if telemetry.safeOrbit then
            actuators.stopAll()
            if telemetry.ecc and telemetry.ecc > CONFIG.PARKING_ECC_TARGET then
                telemetry.state = States.ORBIT_CIRCULARIZE
                telemetry.nextManeuver = string.format("SAFE ORBIT; CIRCULARIZATION CHECK (e=%.3f)", telemetry.ecc)
            else
                telemetry.state = States.PARKING_ORBIT
                telemetry.nextManeuver = string.format("SAFE PARKING ORBIT (Pe: %.0fm)", telemetry.peAlt or 0)
            end
            return
        end

        local targetDir = buildInsertionDirection()
        if not targetDir or vecLen(targetDir) == 0 then
            requestRecovery("CANNOT RESOLVE TANGENTIAL PROGRADE", States.DEEP_SPACE_ENTRY)
            return
        end

        -- Gestión de aceleración y límites de velocidad en espacio
        local peNow = telemetry.peAlt or -CONFIG.ORBIT_SAFETY_MARGIN
        local peError = math.max(0, minSafeAlt - peNow)
        local burnThrottle = clamp(
            CONFIG.INSERTION_MIN_THROTTLE + peError / math.max(minSafeAlt, 1) * 0.35,
            CONFIG.INSERTION_MIN_THROTTLE,
            CONFIG.INSERTION_MAX_THROTTLE
        )
        if telemetry.speed >= CONFIG.SPACE_MAX_SPEED then
            burnThrottle = 0.0
            local brakeVel = telemetry.validSpaceVector and telemetry.spaceVel or telemetry.vel
            if telemetry.speed > (CONFIG.SPACE_MAX_SPEED + CONFIG.SPACE_SPEED_TOLERANCE) and vecLen(brakeVel) > 0.1 then
                local retro = vec3(-brakeVel.x, -brakeVel.y, -brakeVel.z)
                thrustVector(retro, clamp((telemetry.speed - CONFIG.SPACE_MAX_SPEED) * CONFIG.SPACE_BRAKE_KP, 0.1, 0.5))
            else
                actuators.stopAll()
            end
        elseif telemetry.speed >= CONFIG.SPACE_CRUISE_SPEED then
            local ratio = (CONFIG.SPACE_MAX_SPEED - telemetry.speed) / (CONFIG.SPACE_MAX_SPEED - CONFIG.SPACE_CRUISE_SPEED)
            burnThrottle = clamp(ratio * 0.85, 0.2, 0.85)
        end

        -- Quemas cortas con ciclo COAST y medición
        local dtPulse = (now - flightTimers.spacePulseTimer) / 1000

        if flightTimers.spacePulsePhase == "BURN" then
            if dtPulse >= CONFIG.SPACE_BURN_DURATION or burnThrottle <= 0 then
                actuators.stopAll()
                flightTimers.spacePulsePhase = "COAST"
                flightTimers.spacePulseTimer = now
            else
                thrustVector(targetDir, burnThrottle)
                if telemetry.reentryGuard then
                    telemetry.nextManeuver = string.format("REENTRY GUARD: RAISING PERIAPSIS (Pe: %.0fm)", telemetry.peAlt or 0)
                else
                    telemetry.nextManeuver = string.format("INSERTION BURN (Pe: %.0fm / %dm)", telemetry.peAlt or 0, minSafeAlt)
                end
            end
        else -- COAST
            actuators.stopAll()
            telemetry.nextManeuver = string.format("MEASURING ORBIT (Pe: %.0fm)", telemetry.peAlt or 0)
            if dtPulse >= CONFIG.SPACE_COAST_DURATION then
                if burnThrottle > 0 then
                    flightTimers.spacePulsePhase = "BURN"
                    flightTimers.spacePulseTimer = now
                end
            end
        end

    -- FASE 6: ORBIT_CIRCULARIZE
    elseif telemetry.state == States.ORBIT_CIRCULARIZE then
        if not telemetry.validSpaceVector or not telemetry.safeOrbit then
            actuators.stopAll()
            telemetry.state = States.ORBIT_INSERTION
            telemetry.nextManeuver = "CIRCULARIZATION LOST SAFE ORBIT; RETURNING TO INSERTION"
            return
        end

        if not telemetry.ecc or telemetry.ecc <= CONFIG.PARKING_ECC_TARGET then
            actuators.stopAll()
            telemetry.state = States.PARKING_ORBIT
            telemetry.nextManeuver = string.format("PARKING ORBIT CIRCULARIZED (e=%.3f)", telemetry.ecc or 0)
            return
        end

        -- Solo corregimos cerca de ápsides. En apoapsis, prograde eleva periapsis.
        -- En periapsis, retrograde reduce apoapsis, pero nunca si amenaza el periapsis seguro.
        local nearApsis = math.abs(telemetry.radialSpeed) <= CONFIG.APEX_RADIAL_SPEED_TOLERANCE
        if not nearApsis then
            actuators.stopAll()
            telemetry.nextManeuver = string.format("COAST TO APSIS FOR CIRCULARIZATION (Vrad:%+.1f)", telemetry.radialSpeed)
            return
        end

        local r = vecLen(telemetry.spacePos)
        local rp = telemetry.parentRadius and telemetry.peAlt and (telemetry.parentRadius + telemetry.peAlt) or nil
        local ra = telemetry.parentRadius and telemetry.apAlt and (telemetry.parentRadius + telemetry.apAlt) or nil
        local atApo = ra and math.abs(r - ra) <= math.abs(r - (rp or r))

        local dir
        if atApo then
            dir = telemetry.prograde
            telemetry.nextManeuver = string.format("CIRCULARIZE @ APO: PROGRADE (e=%.3f)", telemetry.ecc)
        else
            dir = vecScale(telemetry.prograde, -1)
            telemetry.nextManeuver = string.format("CIRCULARIZE @ PERI: RETROGRADE (e=%.3f)", telemetry.ecc)
        end

        local dtPulse = (now - flightTimers.spacePulseTimer) / 1000
        if flightTimers.spacePulsePhase == "BURN" then
            if dtPulse >= 0.35 then
                actuators.stopAll()
                flightTimers.spacePulsePhase = "COAST"
                flightTimers.spacePulseTimer = now
            else
                thrustVector(dir, 0.25)
            end
        else
            actuators.stopAll()
            if dtPulse >= 0.8 then
                flightTimers.spacePulsePhase = "BURN"
                flightTimers.spacePulseTimer = now
            end
        end

    -- FASE 7: PARKING_ORBIT
    elseif telemetry.state == States.PARKING_ORBIT then
        actuators.stopAll()

        -- Parámetros de transferencia Hohmann aproximada al radio orbital lunar del universo estándar.
        -- Esto NO da la dirección instantánea de la Luna; sirve para calcular energía/tiempo.
        local mu = CONFIG.OVERWORLD_SURFACE_G * CONFIG.OVERWORLD_RADIUS * CONFIG.OVERWORLD_RADIUS
        local lunarR = math.pow(mu * CONFIG.LUNAR_ORBIT_PERIOD * CONFIG.LUNAR_ORBIT_PERIOD /
                         (4 * math.pi * math.pi), 1 / 3)
        telemetry.lunarOrbitRadius = lunarR

        local r1 = vecLen(telemetry.spacePos)
        if r1 > 0 and lunarR > r1 then
            local aTrans = (r1 + lunarR) * 0.5
            telemetry.lunarTransferTime = math.pi * math.sqrt((aTrans * aTrans * aTrans) / mu)
            local moonMeanMotion = 2 * math.pi / CONFIG.LUNAR_ORBIT_PERIOD
            telemetry.lunarRequiredPhase = math.deg(math.pi - moonMeanMotion * telemetry.lunarTransferTime)
        end

        telemetry.lunarDataReady = false
        telemetry.state = States.WAITING_FOR_LUNAR_DATA
        telemetry.nextManeuver = "PARKING ORBIT STABLE; WAITING FOR REAL LUNAR POSITION/VECTOR"

    -- FASE 8+: LUNAR TRANSFER SAFETY GATE
    elseif telemetry.state == States.WAITING_FOR_MOON_TARGET or
           telemetry.state == States.WAIT_LUNAR_WINDOW or
           telemetry.state == States.WAITING_FOR_LUNAR_DATA then
        actuators.stopAll()

        -- Cosmonautics 26.08.307 Sputnik exposes ship orbital state and universeTime,
        -- but not a ComputerCraft method returning the Moon's instantaneous position.
        -- Never perform a blind TLI: a correct transfer needs a real target vector/phase.
        if telemetry.parentBody:lower():find("moon") or telemetry.parentBody:lower():find("luna") then
            telemetry.state = States.LUNAR_APPROACH
            telemetry.nextManeuver = "LUNAR SOI ACQUIRED; PREPARING CAPTURE"
        else
            local phaseTxt = telemetry.lunarRequiredPhase and string.format("%.1f deg", telemetry.lunarRequiredPhase) or "N/A"
            local tofTxt = telemetry.lunarTransferTime and string.format("%.0fs", telemetry.lunarTransferTime) or "N/A"
            telemetry.nextManeuver = "LUNAR DATA LOCK: NEED MOON VECTOR | Hohmann phase " .. phaseTxt .. " TOF " .. tofTxt
        end

    elseif telemetry.state == States.TLI then
        actuators.stopAll()
        telemetry.state = States.WAITING_FOR_LUNAR_DATA
        telemetry.nextManeuver = "[LOCK] TLI REFUSED WITHOUT REAL LUNAR TARGET VECTOR"

    elseif telemetry.state == States.COAST then
        actuators.stopAll()
        if telemetry.parentBody:lower():find("moon") or telemetry.parentBody:lower():find("luna") then
            telemetry.state = States.LUNAR_APPROACH
        end

    elseif telemetry.state == States.MIDCOURSE then
        actuators.stopAll()
        telemetry.nextManeuver = "[LOCK] MIDCOURSE NEEDS REAL TARGET VECTOR"

    elseif telemetry.state == States.LUNAR_APPROACH then
        actuators.stopAll()
        if telemetry.validSpaceVector and
           (telemetry.parentBody:lower():find("moon") or telemetry.parentBody:lower():find("luna")) then
            telemetry.state = States.LUNAR_CAPTURE
            flightTimers.spacePulsePhase = "BURN"
            flightTimers.spacePulseTimer = now
        else
            telemetry.nextManeuver = "WAITING FOR LUNAR REFERENCE FRAME"
        end

    elseif telemetry.state == States.LUNAR_CAPTURE then
        if not telemetry.validSpaceVector then
            actuators.stopAll()
            telemetry.state = States.ORBITAL_DATA_LOCK
            telemetry.nextManeuver = "[LOCK] NO LUNAR ORBIT VECTOR"
            return
        end

        local moonSafeAlt = CONFIG.MOON_TRANSITION_HEIGHT + CONFIG.ORBIT_SAFETY_MARGIN
        if telemetry.orbitalSolutionValid and telemetry.peAlt and telemetry.peAlt > moonSafeAlt and
           telemetry.ecc and telemetry.ecc < 1 then
            actuators.stopAll()
            telemetry.state = States.LUNAR_ORBIT
            telemetry.nextManeuver = string.format("LUNAR ORBIT CAPTURED (Pe %.0fm, e %.3f)",
                                                   telemetry.peAlt, telemetry.ecc)
            return
        end

        -- Capture is retrograde relative to the lunar orbital velocity.
        local retro = vecScale(telemetry.prograde, -1)
        if vecLen(retro) == 0 then
            actuators.stopAll()
            telemetry.state = States.ORBITAL_DATA_LOCK
            telemetry.nextManeuver = "[LOCK] CANNOT RESOLVE LUNAR RETROGRADE"
            return
        end

        local dtPulse = (now - flightTimers.spacePulseTimer) / 1000
        if flightTimers.spacePulsePhase == "BURN" then
            if dtPulse >= 0.35 then
                actuators.stopAll()
                flightTimers.spacePulsePhase = "COAST"
                flightTimers.spacePulseTimer = now
            else
                thrustVector(retro, 0.3)
                telemetry.nextManeuver = "LUNAR CAPTURE: RETROGRADE PULSE"
            end
        else
            actuators.stopAll()
            telemetry.nextManeuver = "LUNAR CAPTURE: MEASURING ORBIT"
            if dtPulse >= 0.8 then
                flightTimers.spacePulsePhase = "BURN"
                flightTimers.spacePulseTimer = now
            end
        end

    elseif telemetry.state == States.LUNAR_ORBIT then
        actuators.stopAll()
        telemetry.nextManeuver = "LUNAR PARKING ORBIT COMPLETE"

    -- BLOQUEOS DE EMERGENCIA
    elseif telemetry.state == States.ORBITAL_DATA_LOCK then
        requestRecovery("ORBITAL DATA LOCK", States.DEEP_SPACE_ENTRY)
        return

    elseif telemetry.state == States.RECOVERY then
        actuators.stopAll()

        -- Reescanea hardware y espera a que telemetría/enlace vuelvan a ser utilizables.
        scanHardware()
        if devices.modemSide and not rednet.isOpen(devices.modemSide) then
            pcall(rednet.open, devices.modemSide)
        end

        if now >= telemetry.recoveryResumeAt then
            local canRetry = telemetry.sputnikOnline
            if telemetry.inDeepSpace then
                canRetry = canRetry and telemetry.validSpaceVector
            end

            if canRetry then
                telemetry.state = telemetry.recoveryTarget or States.DEEP_SPACE_ENTRY
                telemetry.nextManeuver = "RECOVERY CONDITIONS RESTORED - RETRYING"
            else
                telemetry.recoveryResumeAt = now + (CONFIG.RECOVERY_RETRY_DELAY * 1000)
                telemetry.nextManeuver = string.format(
                    "[SAFE RETRY %d] WAITING FOR TELEMETRY/LINK: %s",
                    telemetry.recoveryAttempts,
                    telemetry.recoveryReason
                )
            end
        end

    elseif telemetry.state == States.ABORT then
        -- ABORT queda reservado únicamente para la tecla A del usuario.
        actuators.stopAll()
    end
end

-- ============================================================================
-- INTERFAZ GRÁFICA DE USUARIO (DASHBOARD ACTUALIZADA)
-- ============================================================================

local function drawUI()
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)

    term.setTextColor(colors.cyan)
    print("=== COSMONAUTICS FLIGHT COMPUTER ===")

    term.setTextColor(colors.white)
    write("DEST: ")
    term.setTextColor(colors.yellow)
    write(telemetry.destination)
    term.setTextColor(colors.white)
    write(" | MODE: ")
    term.setTextColor(telemetry.mode == "AUTO" and colors.green or colors.orange)
    write(telemetry.mode)
    term.setTextColor(colors.white)
    write(" | STATE: ")
    term.setTextColor(colors.lightBlue)
    print(telemetry.state)

    term.setTextColor(colors.white)
    write("HW: ")
    term.setTextColor(telemetry.sputnikOnline and colors.green or colors.red)
    write("SPUTNIK ")
    term.setTextColor(telemetry.navTableOnline and colors.green or colors.red)
    write("NAV ")
    term.setTextColor(telemetry.thrusterLinkOnline and colors.green or colors.red)
    write("LINK ")
    term.setTextColor(colors.white)
    write("| DS: ")
    term.setTextColor(telemetry.inDeepSpace and colors.green or colors.red)
    write(telemetry.inDeepSpace and "YES " or "NO ")
    term.setTextColor(colors.yellow)
    print("[" .. telemetry.parentBody .. "]")

    term.setTextColor(colors.gray)
    print("--------------------------------------------------")

    local altStr = telemetry.altitude and string.format("%.0fm", telemetry.altitude) or "N/A"
    local vrStr  = isFinite(telemetry.radialSpeed) and string.format("%+.1f", telemetry.radialSpeed) or "N/A"
    local vtStr  = isFinite(telemetry.tangentialSpeed) and string.format("%.1f", telemetry.tangentialSpeed) or "N/A"
    term.setTextColor(colors.white)
    print(string.format("ALT: %-7s | Vrad: %-6s | Vtan: %-5s", altStr, vrStr, vtStr))

    local peStr   = telemetry.peAlt and string.format("%.0fm", telemetry.peAlt) or "N/A"
    local apStr   = telemetry.apAlt and string.format("%.0fm", telemetry.apAlt) or "N/A"
    local safeStr = telemetry.safeOrbit and "YES" or "NO"
    local solStr  = telemetry.orbitalSolutionValid and "YES" or "NO"
    local rgStr   = telemetry.reentryGuard and "YES" or "NO"
    print(string.format("PE: %-7s AP: %-7s | SAFE:%-3s SOL:%-3s RG:%s", peStr, apStr, safeStr, solStr, rgStr))

    local smaStr = telemetry.sma and string.format("%.1f", telemetry.sma) or "NaN"
    local eccStr = telemetry.ecc and string.format("%.3f", telemetry.ecc) or "NaN"
    local perStr = telemetry.period and string.format("%.1fs", telemetry.period) or "NaN"
    print(string.format("SMA: %-8s ECC: %-7s PER: %s", smaStr, eccStr, perStr))

    local incStr = telemetry.inclination and string.format("%.2f", telemetry.inclination) or "N/A"
    local utStr = telemetry.universeTime and string.format("%.0f", telemetry.universeTime) or "N/A"
    print(string.format("FRAME:%-10s INC:%-7s UT:%s", telemetry.spaceFrame, incStr, utStr))
    print(string.format("RECOVERY ATTEMPTS: %d", telemetry.recoveryAttempts))

    local dStr = telemetry.targetDist and string.format("%.1fm", telemetry.targetDist) or "N/A"
    local cStr = telemetry.closureRate and string.format("%.1fm/s", telemetry.closureRate) or "N/A"
    print(string.format("NAV*: %-8s | DIST: %-7s | CLOSURE: %s", telemetry.navTarget, dStr, cStr))

    term.setTextColor(colors.yellow)
    print("NEXT: " .. telemetry.nextManeuver)

    -- ========================================================================
    -- SECCIÓN INTERACTIVA: SPEED LIMITS
    -- ========================================================================
    term.setTextColor(colors.gray)
    print("------------------ SPEED LIMITS ------------------")

    for i, p in ipairs(speedSettingsSchema) do
        local isSelected = (i == selectedSpeedParam)
        if isSelected then
            term.setTextColor(colors.yellow)
            write("> ")
        else
            term.setTextColor(colors.white)
            write("  ")
        end

        local val = CONFIG[p.key]
        local valStr = string.format("%5.1f", isFinite(val) and val or 0.0)
        write(string.format("%-18s: ", p.label))

        if isSelected then
            term.setTextColor(colors.lime)
        else
            term.setTextColor(colors.cyan)
        end
        print(valStr)
    end

    term.setTextColor(colors.gray)
    print("--------------------------------------------------")
    term.setTextColor(colors.white)
    print("[L]LAUNCH [A]ABORT [M]AUTO/MAN [Q]EXIT")
    term.setTextColor(colors.lightGray)
    write("UP/DOWN: SELECT | LEFT/RIGHT: CHANGE (SHIFT: x" .. tostring(speedSettingsSchema[1].bigStep / speedSettingsSchema[1].step) .. ")")
end

-- ============================================================================
-- EJECUCIÓN PRINCIPAL CON PROTECCIÓN TOTAL (XPCALL)
-- ============================================================================

local function main()
    local timerId = os.startTimer(CONFIG.LOOP_TICK_RATE)
    local shiftHeld = false

    while true do
        local event, p1, p2 = os.pullEvent()

        if event == "timer" and p1 == timerId then
            pollTelemetry()
            serviceRednet()
            updateAutopilot()
            drawUI()
            timerId = os.startTimer(CONFIG.LOOP_TICK_RATE)

        elseif event == "key" then
            local k = p1
            if k == keys.leftShift or k == keys.rightShift then
                shiftHeld = true

            elseif k == keys.up then
                selectedSpeedParam = selectedSpeedParam - 1
                if selectedSpeedParam < 1 then
                    selectedSpeedParam = #speedSettingsSchema
                end
            elseif k == keys.down then
                selectedSpeedParam = selectedSpeedParam + 1
                if selectedSpeedParam > #speedSettingsSchema then
                    selectedSpeedParam = 1
                end

            elseif k == keys.left or k == keys.right then
                local def = speedSettingsSchema[selectedSpeedParam]
                local step = shiftHeld and def.bigStep or def.step
                local delta = (k == keys.left) and -step or step

                CONFIG[def.key] = CONFIG[def.key] + delta
                sanitizeSpeedLimits()
                saveSpeedSettings()
            end

        elseif event == "key_up" then
            local k = p1
            if k == keys.leftShift or k == keys.rightShift then
                shiftHeld = false
            end

        elseif event == "char" then
            local key = p1:upper()
            if key == "L" then
                if telemetry.state == States.READY or telemetry.state == States.ABORT then
                    telemetry.recoveryAttempts = 0
                    telemetry.recoveryReason = ""
                    telemetry.insertionPrograde = vec3(0, 0, 0)
                    telemetry.orbitNormal = vec3(0, 0, 0)
                    telemetry.state = States.LAUNCH
                end
            elseif key == "A" then
                actuators.stopAll()
                telemetry.state = States.ABORT
                telemetry.nextManeuver = "AUTOPILOT ABORTED BY USER"
            elseif key == "M" then
                telemetry.mode = (telemetry.mode == "AUTO") and "MANUAL" or "AUTO"
            elseif key == "Q" then
                actuators.stopAll()
                break
            end
        end
    end
end

-- Ejecución encapsulada
local ok, err = xpcall(main, debug.traceback)

-- FAILSAFE OBLIGATORIO: Apagar todos los propulsores locales y remotos
actuators.stopAll()
term.setBackgroundColor(colors.black)
term.setTextColor(colors.red)
term.clear()
term.setCursorPos(1, 1)

if not ok and err then
    print("==================================================")
    print("        CRITICAL AUTOPILOT EMERGENCY STOP         ")
    print("==================================================")
    print(err)
    print("--------------------------------------------------")
    print("ALL PROPULSION HAS BEEN SHUT DOWN SAFELY.")
else
    print("Autopilot stopped cleanly. All thrusters offline.")
end