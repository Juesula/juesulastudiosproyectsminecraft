-- ============================================================================
-- COSMONAUTICS FLIGHT COMPUTER - MASTER AUTOPILOT (startup.lua)
-- COMPLETE v5: velocity-vector guidance + anti-gravity entry + no rigid angle hold
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

    -- ARRANQUE AUTOMÁTICO
    AUTO_LAUNCH_ENABLED        = true,                  -- Si true, despega sin pulsar L
    AUTO_LAUNCH_DELAY          = 3.0,                   -- Espera tras arrancar el ordenador
    AUTO_RELAUNCH_AFTER_FALLBACK = true,               -- Si vuelve al Overworld durante inserción, retoma ascenso

    -- ESTABILIZACIÓN AL ENTRAR EN DEEP SPACE
    DEEP_SPACE_ENTRY_HOLD_POWER = 0.22,                -- Mantiene empuje mientras aparece physics.space
    DEEP_SPACE_ENTRY_HOLD_TIME  = 4.0,                 -- Tiempo máximo de hold inicial
    DEEP_SPACE_MIN_OUTWARD_SPEED = 120.0,              -- Salida radial mínima antes de soltar ascenso
    DEEP_SPACE_TARGET_OUTWARD_SPEED = 180.0,             -- Objetivo normal de Vrad durante entrada
    DEEP_SPACE_FALLBACK_GUARD   = 8.0,                   -- Protección tras cruzar la frontera
    ENTRY_SAFE_PERIAPSIS_ALT    = 25000.0,               -- No coast hasta tener Pe segura
    ENTRY_TANGENTIAL_BLEND      = 0.35,                  -- Construcción gradual de velocidad tangencial
    ENTRY_MAX_THRUST            = 0.55,                  -- No exigir orientación/ángulo perfecto

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

    -- VELOCIDADES ORBITALES REALES.
    -- En Cosmonautics el Overworld usa velocidades de DECENAS DE km/s.
    -- Los antiguos límites 30/45/60 m/s impedían literalmente entrar en órbita.
    SPACE_CRUISE_SPEED         = 18000.0,
    SPACE_MAX_SPEED            = 25000.0,
    SPACE_EMERGENCY_SPEED      = 32000.0,
    SPACE_MAX_ACCELERATION     = 10.0,
    SPACE_BRAKE_KP             = 0.00015,
    SPACE_SPEED_TOLERANCE      = 250.0,

    -- QUEMAS CORTAS Y COAST EN ESPACIO
    SPACE_BURN_DURATION        = 0.8,   -- Segundos que dura cada pulso de aceleración
    SPACE_COAST_DURATION       = 1.2,   -- Segundos de inercia/medición entre pulsos

    -- Universo estándar Cosmonautics 26.08.307 (confirmado en StandardUniverseProvider).
    OVERWORLD_RADIUS           = 3000000.0,
    OVERWORLD_SURFACE_G        = 11.0,
    OVERWORLD_ROTATION_PERIOD  = 1200.0,
    MOON_RADIUS                = 750000.0,
    LUNAR_ORBIT_PERIOD         = 28800.0, -- 24 días MC * 1200 s
    UNIVERSE_SECONDS_PER_TICK  = 0.05,

    -- Órbitas y transferencia lunar
    PARKING_TARGET_ALT         = 32000.0,
    PARKING_ECC_TARGET         = 0.045,
    PARKING_RADIAL_CLIMB       = 120.0,
    ORBIT_VELOCITY_TOLERANCE   = 35.0,
    LUNAR_WINDOW_TOLERANCE_DEG = 1.25,
    LUNAR_ENCOUNTER_OFFSET     = 900000.0, -- pasa ~150 km sobre superficie lunar
    MIDCOURSE_START_DISTANCE   = 6000000.0,
    MIDCOURSE_APPROACH_SPEED   = 2300.0,
    MIDCOURSE_DV_TOLERANCE     = 80.0,
    LUNAR_CAPTURE_ECC_TARGET   = 0.08,
    LUNAR_CAPTURE_RADIAL_SAFE  = 120.0,

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
    { key = "SPACE_CRUISE_SPEED",        label = "SPACE CRUISE",    step = 100.0, bigStep = 500.0, min = 1000.0 },
    { key = "SPACE_MAX_SPEED",           label = "SPACE MAX",       step = 100.0, bigStep = 500.0, min = 1500.0 },
    { key = "SPACE_EMERGENCY_SPEED",     label = "SPACE EMERGENCY", step = 100.0, bigStep = 1000.0, min = 2000.0 }
}

local selectedSpeedParam = 1

local function sanitizeSpeedLimits()
    if not isFinite(CONFIG.ASCENT_MAX_VERTICAL_SPEED) or CONFIG.ASCENT_MAX_VERTICAL_SPEED < 0.5 then
        CONFIG.ASCENT_MAX_VERTICAL_SPEED = 0.5
    end

    -- Migración automática desde la versión antigua (30/45/60 m/s).
    if not isFinite(CONFIG.SPACE_CRUISE_SPEED) or CONFIG.SPACE_CRUISE_SPEED < 1000 then
        CONFIG.SPACE_CRUISE_SPEED = 18000.0
    end
    if not isFinite(CONFIG.SPACE_MAX_SPEED) or CONFIG.SPACE_MAX_SPEED < 1500 then
        CONFIG.SPACE_MAX_SPEED = 25000.0
    end
    if not isFinite(CONFIG.SPACE_EMERGENCY_SPEED) or CONFIG.SPACE_EMERGENCY_SPEED < 2000 then
        CONFIG.SPACE_EMERGENCY_SPEED = 32000.0
    end

    if CONFIG.SPACE_MAX_SPEED < CONFIG.SPACE_CRUISE_SPEED then
        CONFIG.SPACE_MAX_SPEED = CONFIG.SPACE_CRUISE_SPEED + 1000
    end
    if CONFIG.SPACE_EMERGENCY_SPEED <= CONFIG.SPACE_MAX_SPEED then
        CONFIG.SPACE_EMERGENCY_SPEED = CONFIG.SPACE_MAX_SPEED + 5000
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

local function vecAdd(a, b)
    return vec3(a.x + b.x, a.y + b.y, a.z + b.z)
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
    lunarPhaseError = nil,
    lunarDistance = nil,
    moonPos = vec3(0, 0, 0),
    moonVel = vec3(0, 0, 0),
    overworldMu = nil,
    tliDepartureSpeed = nil,
    tliArrivalTick = nil,
    tliStartTick = nil,
    lunarDataReady = false,

    recoveryAttempts = 0,
    recoveryReason = "",
    recoveryTarget = States.DEEP_SPACE_ENTRY,
    recoveryResumeAt = 0,

    deepSpaceEntryTime = 0,
    lastDeepSpaceSeen = 0,
    autoLaunchAt = 0,
    autoLaunchArmed = false,

    nextManeuver = "AUTO-LAUNCH IN 3s (U TO TOGGLE)"
}

local flightTimers = {
    launchStartTime = 0,
    programStartTime = os.epoch("utc"),
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
            telemetry.spaceAvailable = false
            telemetry.validSpaceVector = false
            telemetry.sputnikOnline = false
            return
        end

        -- getGlobalPos()
        local gpOk, gp = pcall(peripheral.call, devices.sputnikSide, "getGlobalPos")
        if gpOk and type(gp) == "table" and isFinite(gp.x) and isFinite(gp.y) and isFinite(gp.z) then
            telemetry.pos = vec3(gp.x, gp.y, gp.z)
        end
    else
        telemetry.sputnikOnline = false
        telemetry.spaceAvailable = false
        telemetry.validSpaceVector = false
        return
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
-- MÁQUINA DE ESTADOS DEL AUTOPILOTO
-- ÓRBITA REAL + TRANSFERENCIA LUNAR ANALÍTICA (Cosmonautics 26.08.307)
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
        -- Nunca ABORT automático: sigue reintentando indefinidamente en modo seguro.
        telemetry.nextManeuver = string.format(
            "[SAFE RETRY %d] %s",
            telemetry.recoveryAttempts,
            telemetry.recoveryReason
        )
    end
end

local function parentIsMoon()
    local p = tostring(telemetry.parentBody or ""):lower()
    return p:find("moon", 1, true) ~= nil or p:find("luna", 1, true) ~= nil
end

local function parentIsOverworld()
    local p = tostring(telemetry.parentBody or ""):lower()
    return p:find("overworld", 1, true) ~= nil
end

local function currentMu()
    if not telemetry.validSpaceVector then return nil end
    local r = vecLen(telemetry.spacePos)
    if r <= 1 or not isFinite(telemetry.localGravity) or telemetry.localGravity <= 0 then
        return nil
    end
    local mu = telemetry.localGravity * r * r
    return isFinite(mu) and mu > 0 and mu or nil
end

local function circularSpeed(mu, r)
    if not isFinite(mu) or not isFinite(r) or mu <= 0 or r <= 0 then return nil end
    return math.sqrt(mu / r)
end

local function escapeSpeed(mu, r)
    if not isFinite(mu) or not isFinite(r) or mu <= 0 or r <= 0 then return nil end
    return math.sqrt(2 * mu / r)
end

local function lunarPlaneTangent(rHat)
    -- La órbita lunar estándar usa orbitAxis = Vector3D.PLUS_J.
    -- Prograde = +J x r.
    local tangent = vecCross(vec3(0, 1, 0), rHat)
    if vecLen(tangent) <= 1e-6 then
        tangent = orthogonalUnit(rHat)
    end
    return vecNorm(tangent)
end

local function orbitalTangentFromVelocity(rHat, v)
    local vRad = vecDot(v, rHat)
    local tan = vecSub(v, vecScale(rHat, vRad))
    if vecLen(tan) <= 1e-6 then
        return lunarPlaneTangent(rHat)
    end
    return vecNorm(tan)
end

-- Dirección tangencial "natural": conserva el plano real de vuelo.
-- Solo cae al plano lunar estándar si todavía no existe componente tangencial útil.
local function naturalEntryTangent(rHat)
    if telemetry.validSpaceVector then
        local vRad = vecDot(telemetry.spaceVel, rHat)
        local tan = vecSub(telemetry.spaceVel, vecScale(rHat, vRad))
        if vecLen(tan) >= CONFIG.MIN_TANGENTIAL_VECTOR_SPEED then
            return vecNorm(tan)
        end
    end
    return lunarPlaneTangent(rHat)
end

-- Control de entrada por VELOCIDAD, no por ángulo de nave.
-- El ordenador pide un vector de velocidad deseado y thrustVector lo transforma
-- continuamente al frame local; no intenta fijar una orientación absoluta.
local function entryVelocityGuidance(rHat, mu, r)
    local tangent = naturalEntryTangent(rHat)
    local vCirc = circularSpeed(mu, r)
    if not vCirc then return false, 0 end

    local currentTan = telemetry.tangentialSpeed or 0
    local desiredTan = math.max(currentTan, math.min(vCirc, currentTan + 900.0))
    desiredTan = currentTan + (desiredTan - currentTan) * CONFIG.ENTRY_TANGENTIAL_BLEND

    local desiredRad = CONFIG.DEEP_SPACE_TARGET_OUTWARD_SPEED
    if telemetry.peAlt and telemetry.peAlt >= CONFIG.ENTRY_SAFE_PERIAPSIS_ALT then
        desiredRad = math.max(40.0, CONFIG.DEEP_SPACE_MIN_OUTWARD_SPEED)
    end

    local targetVel = vecAdd(
        vecScale(tangent, desiredTan),
        vecScale(rHat, desiredRad)
    )

    local err = vecSub(targetVel, telemetry.spaceVel)
    local dv = vecLen(err)

    if dv < 20 then
        actuators.stopAll()
        return true, dv
    end

    thrustVector(err, clamp(dv / 1200.0, 0.10, CONFIG.ENTRY_MAX_THRUST))
    return false, dv
end

local function velocityController(targetVel, tolerance, minPower, maxPower)
    local err = vecSub(targetVel, telemetry.spaceVel)
    local dv = vecLen(err)
    tolerance = tolerance or CONFIG.ORBIT_VELOCITY_TOLERANCE

    if dv <= tolerance then
        actuators.stopAll()
        return true, dv
    end

    local p = clamp(dv / 1800.0, minPower or 0.08, maxPower or 0.75)
    thrustVector(err, p)
    return false, dv
end

local function moonStateAtTicks(ticks, overworldMu)
    if not isFinite(ticks) or not isFinite(overworldMu) or overworldMu <= 0 then
        return nil, nil, nil
    end

    local T = CONFIG.LUNAR_ORBIT_PERIOD
    local n = 2 * math.pi / T
    local r = math.pow(overworldMu * T * T / (4 * math.pi * math.pi), 1 / 3)
    local t = ticks * CONFIG.UNIVERSE_SECONDS_PER_TICK
    local theta = n * t

    -- Cosmonautics:
    -- setCircularOrbit(period, PLUS_J) -> initial position PLUS_J.orthogonal().
    -- Hipparchus PLUS_J.orthogonal() == MINUS_K.
    -- v0 = PLUS_J x MINUS_K = MINUS_I.
    local s = math.sin(theta)
    local c = math.cos(theta)

    local pos = vec3(-r * s, 0, -r * c)
    local vel = vec3(-r * n * c, 0, r * n * s)
    return pos, vel, r
end

local function signedAngleAroundY(a, b)
    local an = vecNorm(vec3(a.x, 0, a.z))
    local bn = vecNorm(vec3(b.x, 0, b.z))
    if vecLen(an) <= 1e-6 or vecLen(bn) <= 1e-6 then return nil end
    local cross = vecCross(an, bn)
    local sinv = clamp(cross.y, -1, 1)
    local cosv = clamp(vecDot(an, bn), -1, 1)
    return math.deg(math.atan2(sinv, cosv))
end

local function buildLunarTransferPlan()
    if not telemetry.validSpaceVector or not telemetry.universeTime or parentIsMoon() then
        return nil
    end

    local mu = currentMu()
    if not mu then return nil end

    telemetry.overworldMu = mu

    local r1 = vecLen(telemetry.spacePos)
    local _, _, moonR = moonStateAtTicks(telemetry.universeTime, mu)
    if not moonR or moonR <= r1 then return nil end

    -- Apuntamos deliberadamente por delante de la Luna para no atravesar su centro.
    local targetR = math.sqrt(moonR * moonR +
                              CONFIG.LUNAR_ENCOUNTER_OFFSET * CONFIG.LUNAR_ENCOUNTER_OFFSET)

    local aTransfer = (r1 + targetR) * 0.5
    local tof = math.pi * math.sqrt((aTransfer * aTransfer * aTransfer) / mu)
    local arrivalTicks = telemetry.universeTime + tof / CONFIG.UNIVERSE_SECONDS_PER_TICK

    local moonPos, moonVel = moonStateAtTicks(arrivalTicks, mu)
    if not moonPos or not moonVel then return nil end

    local moonTan = vecNorm(moonVel)
    local targetPoint = vec3(
        moonPos.x + moonTan.x * CONFIG.LUNAR_ENCOUNTER_OFFSET,
        moonPos.y + moonTan.y * CONFIG.LUNAR_ENCOUNTER_OFFSET,
        moonPos.z + moonTan.z * CONFIG.LUNAR_ENCOUNTER_OFFSET
    )

    local targetRadius = vecLen(targetPoint)
    aTransfer = (r1 + targetRadius) * 0.5
    tof = math.pi * math.sqrt((aTransfer * aTransfer * aTransfer) / mu)
    arrivalTicks = telemetry.universeTime + tof / CONFIG.UNIVERSE_SECONDS_PER_TICK

    -- Recalcular una vez con el TOF definitivo.
    moonPos, moonVel = moonStateAtTicks(arrivalTicks, mu)
    moonTan = vecNorm(moonVel)
    targetPoint = vec3(
        moonPos.x + moonTan.x * CONFIG.LUNAR_ENCOUNTER_OFFSET,
        moonPos.y + moonTan.y * CONFIG.LUNAR_ENCOUNTER_OFFSET,
        moonPos.z + moonTan.z * CONFIG.LUNAR_ENCOUNTER_OFFSET
    )
    targetRadius = vecLen(targetPoint)

    local rHat = vecNorm(telemetry.spacePos)
    local desiredDepartureRadial = vecScale(vecNorm(targetPoint), -1)
    local phaseError = signedAngleAroundY(rHat, desiredDepartureRadial)

    local vp = math.sqrt(mu * (2 / r1 - 1 / ((r1 + targetRadius) * 0.5)))
    local tangent = lunarPlaneTangent(rHat)

    telemetry.lunarOrbitRadius = moonR
    telemetry.lunarTransferTime = tof
    telemetry.lunarPhaseError = phaseError
    telemetry.lunarRequiredPhase = phaseError
    telemetry.tliDepartureSpeed = vp
    telemetry.moonPos = moonPos
    telemetry.moonVel = moonVel
    telemetry.lunarDataReady = true

    return {
        mu = mu,
        r1 = r1,
        targetRadius = targetRadius,
        targetPoint = targetPoint,
        moonPos = moonPos,
        moonVel = moonVel,
        tof = tof,
        arrivalTicks = arrivalTicks,
        phaseError = phaseError,
        departureSpeed = vp,
        departureTangent = tangent
    }
end

local function updateMoonDistanceNow()
    if not telemetry.universeTime or not telemetry.overworldMu or parentIsMoon() then
        telemetry.lunarDistance = nil
        return
    end
    local p, v = moonStateAtTicks(telemetry.universeTime, telemetry.overworldMu)
    if p then
        telemetry.moonPos = p
        telemetry.moonVel = v
        telemetry.lunarDistance = vecLen(vecSub(p, telemetry.spacePos))
    end
end

local function beginBurnCycle(now)
    flightTimers.spacePulsePhase = "BURN"
    flightTimers.spacePulseTimer = now
end

local function updateAutopilot()
    local now = os.epoch("utc")

    -- ABORT solo existe si lo pulsa el usuario.
    if telemetry.state == States.ABORT then
        actuators.stopAll()
        return
    end

    -- Fallos recuperables: jamás terminan el programa.
    if telemetry.state ~= States.RECOVERY and not telemetry.sputnikOnline then
        requestRecovery("SPUTNIK OFFLINE", telemetry.inDeepSpace and States.DEEP_SPACE_ENTRY or States.ASCENT)
        return
    end

    local attitudeCritical =
        telemetry.state ~= States.ASCENT and
        telemetry.state ~= States.DEEP_SPACE_ENTRY and
        telemetry.state ~= States.ORBIT_INSERTION and
        telemetry.state ~= States.ORBIT_BUILD and
        telemetry.state ~= States.COAST_TO_APEX

    if telemetry.state ~= States.RECOVERY and attitudeCritical and
       vecLen(telemetry.angVel) > CONFIG.MAX_ANGULAR_VELOCITY then
        requestRecovery("ANGULAR VELOCITY TOO HIGH", telemetry.inDeepSpace and States.DEEP_SPACE_ENTRY or States.ASCENT)
        return
    end

    if telemetry.state ~= States.READY and telemetry.state ~= States.RECOVERY then
        if not telemetry.thrusterLinkOnline then
            requestRecovery("THRUSTER LINK LOST", telemetry.inDeepSpace and States.DEEP_SPACE_ENTRY or States.ASCENT)
            return
        end
    end

    if telemetry.mode ~= "AUTO" and telemetry.state ~= States.READY then
        actuators.stopAll()
        return
    end

    -- Protección de velocidad basada en velocidad de escape REAL, no en 45 m/s.
    if telemetry.inDeepSpace and telemetry.validSpaceVector and
       telemetry.state ~= States.TLI and telemetry.state ~= States.MIDCOURSE and
       telemetry.state ~= States.LUNAR_CAPTURE then
        local mu = currentMu()
        local r = vecLen(telemetry.spacePos)
        local esc = mu and escapeSpeed(mu, r) or nil
        local dynamicEmergency = esc and (esc * 1.35) or CONFIG.SPACE_EMERGENCY_SPEED
        local emergency = math.max(dynamicEmergency, CONFIG.SPACE_EMERGENCY_SPEED)

        if telemetry.speed > emergency then
            local retro = vecScale(telemetry.spaceVel, -1)
            thrustVector(retro, clamp((telemetry.speed - emergency) / 5000, 0.15, 0.65))
            telemetry.nextManeuver = string.format(
                "DYNAMIC OVERSPEED BRAKE %.0f / %.0f m/s",
                telemetry.speed, emergency
            )
            return
        end
    end

    -- ========================================================================
    -- 1. LAUNCH
    -- ========================================================================
    if telemetry.state == States.LAUNCH then
        telemetry.recoveryAttempts = 0
        telemetry.insertionPrograde = vec3(0, 0, 0)
        telemetry.orbitNormal = vec3(0, 0, 0)
        flightTimers.launchStartTime = now
        telemetry.nextManeuver = "CONTROLLED SOFT-START IGNITION"
        actuators.down(0)
        actuators.up(0.2)
        telemetry.state = States.ASCENT

    -- ========================================================================
    -- 2. ASCENT
    -- ========================================================================
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
        local deadband = CONFIG.ASCENT_DEADBAND

        if currentVy < targetVy - deadband then
            local upPower = clamp((targetVy - currentVy) * CONFIG.ASCENT_KP, 0.1, 1.0) * ramp
            actuators.up(upPower)
            actuators.down(0)
        elseif currentVy > targetVy + deadband then
            local brake = clamp((currentVy - targetVy) * CONFIG.ASCENT_BRAKE_KP, 0.1, 0.8)
            if currentVy > CONFIG.ASCENT_MAX_VERTICAL_SPEED then
                brake = clamp(brake + (currentVy - CONFIG.ASCENT_MAX_VERTICAL_SPEED) *
                              CONFIG.ASCENT_BRAKE_KP, 0.3, 1.0)
            end
            actuators.up(0)
            actuators.down(brake)
        else
            actuators.up(0)
            actuators.down(0)
        end

        if telemetry.inDeepSpace then
            telemetry.deepSpaceEntryTime = now
            telemetry.lastDeepSpaceSeen = now
            -- NO apagamos todo al cruzar la frontera. Mantener algo de empuje evita
            -- caer otra vez al Overworld mientras physics.space tarda unos ticks.
            actuators.down(0)
            actuators.up(CONFIG.DEEP_SPACE_ENTRY_HOLD_POWER)
            telemetry.state = States.DEEP_SPACE_ENTRY
            telemetry.nextManeuver = "DEEP SPACE: HOLDING OUTWARD WHILE ACQUIRING FRAME"
        end

    -- ========================================================================
    -- 3. DEEP SPACE ENTRY
    -- ========================================================================
    elseif telemetry.state == States.DEEP_SPACE_ENTRY then
        if telemetry.inDeepSpace then
            telemetry.lastDeepSpaceSeen = now
        end

        -- Si Cosmonautics nos devuelve momentáneamente al Overworld durante la
        -- transición, no abortamos ni entramos en recovery orbital: retomamos ascenso.
        if not telemetry.inDeepSpace then
            local sinceEntry = (now - (telemetry.deepSpaceEntryTime or now)) / 1000
            if CONFIG.AUTO_RELAUNCH_AFTER_FALLBACK and sinceEntry <= CONFIG.DEEP_SPACE_FALLBACK_GUARD then
                telemetry.state = States.ASCENT
                telemetry.nextManeuver = "FALLBACK TO OVERWORLD: AUTO-RELAUNCHING"
                actuators.down(0)
                actuators.up(0.35)
                return
            end

            requestRecovery("LEFT DEEP SPACE DURING ENTRY", States.ASCENT)
            return
        end

        local sinceEntry = (now - (telemetry.deepSpaceEntryTime or now)) / 1000

        if not telemetry.validSpaceVector then
            -- Durante los primeros segundos seguimos empujando hacia fuera en el eje
            -- de lanzamiento. Esto evita que el movimiento/rotación del planeta nos
            -- cruce de vuelta antes de tener un vector orbital coherente.
            if sinceEntry <= CONFIG.DEEP_SPACE_ENTRY_HOLD_TIME then
                actuators.down(0)
                actuators.up(CONFIG.DEEP_SPACE_ENTRY_HOLD_POWER)
                telemetry.nextManeuver = string.format(
                    "DEEP SPACE HOLD: ACQUIRING physics.space (%.1fs)", sinceEntry
                )
            else
                actuators.stopAll()
                telemetry.nextManeuver = "WAITING FOR COHERENT physics.space VECTOR"
            end
            return
        end

        local mu = currentMu()
        if not mu then
            -- A veces gravity llega uno o dos ticks después que position/velocity.
            if sinceEntry <= CONFIG.DEEP_SPACE_ENTRY_HOLD_TIME then
                actuators.down(0)
                actuators.up(CONFIG.DEEP_SPACE_ENTRY_HOLD_POWER)
                telemetry.nextManeuver = "DEEP SPACE HOLD: WAITING GRAVITY/MU"
                return
            end
            requestRecovery("NO VALID GRAVITY PARAMETER", States.DEEP_SPACE_ENTRY)
            return
        end

        local r = vecLen(telemetry.spacePos)
        local rHat = vecNorm(telemetry.spacePos)

        -- No fijamos un ángulo. Construimos energía orbital mediante error de velocidad:
        -- radial positiva + componente tangencial creciente.
        local settled, dv = entryVelocityGuidance(rHat, mu, r)

        telemetry.nextManeuver = string.format(
            "ENTRY VECTOR CONTROL: Vrad %.0f | Vtan %.0f | dV %.0f | Pe %s",
            telemetry.radialSpeed or 0,
            telemetry.tangentialSpeed or 0,
            dv or 0,
            telemetry.peAlt and string.format("%.0f", telemetry.peAlt) or "N/A"
        )

        local periapsisSafe = telemetry.peAlt and
                              telemetry.peAlt >= CONFIG.ENTRY_SAFE_PERIAPSIS_ALT

        -- No pasamos a inserción libre hasta que la trayectoria no pueda cortar
        -- de nuevo el límite atmosférico.
        if telemetry.radialSpeed >= CONFIG.DEEP_SPACE_MIN_OUTWARD_SPEED and periapsisSafe then
            telemetry.recoveryAttempts = 0
            telemetry.state = States.ORBIT_INSERTION
            beginBurnCycle(now)
            telemetry.nextManeuver = "ENTRY SAFE: CONTINUING ORBIT INSERTION"
        end
        return

    -- ========================================================================
    -- 4/5. ORBIT INSERTION
    -- ========================================================================
    elseif telemetry.state == States.COAST_TO_APEX or
           telemetry.state == States.ORBIT_INSERTION or
           telemetry.state == States.ORBIT_BUILD then

        if not telemetry.inDeepSpace then
            if CONFIG.AUTO_RELAUNCH_AFTER_FALLBACK then
                telemetry.state = States.ASCENT
                telemetry.nextManeuver = "ORBIT ENTRY FELL BACK: AUTO-RELAUNCHING"
                actuators.down(0)
                actuators.up(0.40)
                return
            end
            requestRecovery("FELL BACK TO OVERWORLD DURING INSERTION", States.ASCENT)
            return
        end

        if not telemetry.validSpaceVector then
            requestRecovery("ORBIT VECTOR LOST DURING INSERTION", States.DEEP_SPACE_ENTRY)
            return
        end

        local mu = currentMu()
        if not mu then
            requestRecovery("NO MU DURING INSERTION", States.DEEP_SPACE_ENTRY)
            return
        end

        local r = vecLen(telemetry.spacePos)
        local rHat = vecNorm(telemetry.spacePos)
        local tangent = naturalEntryTangent(rHat)
        local vCirc = circularSpeed(mu, r)

        if not vCirc then
            requestRecovery("CANNOT COMPUTE CIRCULAR SPEED", States.DEEP_SPACE_ENTRY)
            return
        end

        -- En el universo estándar, el lanzamiento desde la dimensión ya hereda
        -- ~16 km/s de rotación planetaria. Solo faltan cientos de m/s, no 16 km/s.
        local targetAlt = CONFIG.PARKING_TARGET_ALT
        local radialTarget = 0

        if not telemetry.peAlt or telemetry.peAlt < CONFIG.ENTRY_SAFE_PERIAPSIS_ALT then
            radialTarget = CONFIG.DEEP_SPACE_TARGET_OUTWARD_SPEED
        elseif telemetry.altitude and telemetry.altitude < targetAlt then
            radialTarget = CONFIG.PARKING_RADIAL_CLIMB
        elseif telemetry.reentryGuard then
            radialTarget = CONFIG.PARKING_RADIAL_CLIMB
        end

        local targetVel = vec3(
            tangent.x * vCirc + rHat.x * radialTarget,
            tangent.y * vCirc + rHat.y * radialTarget,
            tangent.z * vCirc + rHat.z * radialTarget
        )

        local done, dv = velocityController(targetVel, CONFIG.ORBIT_VELOCITY_TOLERANCE, 0.08, 0.75)

        telemetry.nextManeuver = string.format(
            "INSERTION: V %.0f / Vcirc %.0f | dV %.0f | Pe %s",
            telemetry.speed,
            vCirc,
            dv,
            telemetry.peAlt and string.format("%.0f", telemetry.peAlt) or "N/A"
        )

        if telemetry.safeOrbit and telemetry.altitude and
           telemetry.altitude >= targetAlt - 1000 then
            if telemetry.ecc and telemetry.ecc <= CONFIG.PARKING_ECC_TARGET then
                actuators.stopAll()
                telemetry.state = States.PARKING_ORBIT
                telemetry.nextManeuver = string.format(
                    "PARKING ORBIT ACQUIRED: Pe %.0fm e %.4f",
                    telemetry.peAlt or 0, telemetry.ecc or 0
                )
            else
                actuators.stopAll()
                telemetry.state = States.ORBIT_CIRCULARIZE
                telemetry.nextManeuver = "SAFE ORBIT: FINAL CIRCULARIZATION"
            end
        elseif done and telemetry.altitude and telemetry.altitude < targetAlt then
            -- Velocidad ya correcta pero aún demasiado bajo: empuje radial suave.
            thrustVector(rHat, 0.12)
        end

    -- ========================================================================
    -- 6. CIRCULARIZATION: control vectorial directo
    -- ========================================================================
    elseif telemetry.state == States.ORBIT_CIRCULARIZE then
        if not telemetry.validSpaceVector then
            requestRecovery("ORBIT VECTOR LOST DURING CIRCULARIZATION", States.DEEP_SPACE_ENTRY)
            return
        end

        local mu = currentMu()
        local r = vecLen(telemetry.spacePos)
        if not mu or r <= 0 then
            requestRecovery("NO ORBITAL MU FOR CIRCULARIZATION", States.DEEP_SPACE_ENTRY)
            return
        end

        local rHat = vecNorm(telemetry.spacePos)
        local tangent

        if parentIsMoon() then
            tangent = orbitalTangentFromVelocity(rHat, telemetry.spaceVel)
        else
            tangent = lunarPlaneTangent(rHat)
        end

        local vCirc = circularSpeed(mu, r)
        local radialTarget = 0
        local safeAlt = (parentIsMoon() and CONFIG.MOON_TRANSITION_HEIGHT or
                         CONFIG.OVERWORLD_TRANSITION_HEIGHT) + CONFIG.ORBIT_SAFETY_MARGIN

        if telemetry.altitude and telemetry.altitude < safeAlt + 3000 then
            radialTarget = parentIsMoon() and CONFIG.LUNAR_CAPTURE_RADIAL_SAFE or
                           CONFIG.PARKING_RADIAL_CLIMB
        end

        local targetVel = vec3(
            tangent.x * vCirc + rHat.x * radialTarget,
            tangent.y * vCirc + rHat.y * radialTarget,
            tangent.z * vCirc + rHat.z * radialTarget
        )

        local done, dv = velocityController(targetVel, CONFIG.ORBIT_VELOCITY_TOLERANCE, 0.06, 0.55)

        telemetry.nextManeuver = string.format(
            "CIRCULARIZING: e %.4f dV %.0f Pe %s",
            telemetry.ecc or 9.999,
            dv,
            telemetry.peAlt and string.format("%.0f", telemetry.peAlt) or "N/A"
        )

        if telemetry.safeOrbit and telemetry.ecc then
            local eccTarget = parentIsMoon() and CONFIG.LUNAR_CAPTURE_ECC_TARGET or
                              CONFIG.PARKING_ECC_TARGET
            if telemetry.ecc <= eccTarget and done then
                actuators.stopAll()
                if parentIsMoon() then
                    telemetry.state = States.LUNAR_ORBIT
                    telemetry.nextManeuver = string.format(
                        "LUNAR PARKING ORBIT: Pe %.0fm e %.4f",
                        telemetry.peAlt or 0, telemetry.ecc
                    )
                else
                    telemetry.state = States.PARKING_ORBIT
                    telemetry.nextManeuver = string.format(
                        "OVERWORLD PARKING ORBIT: Pe %.0fm e %.4f",
                        telemetry.peAlt or 0, telemetry.ecc
                    )
                end
            end
        end

    -- ========================================================================
    -- 7. PARKING ORBIT -> cálculo real de la órbita lunar
    -- ========================================================================
    elseif telemetry.state == States.PARKING_ORBIT then
        actuators.stopAll()

        if parentIsMoon() then
            telemetry.state = States.LUNAR_ORBIT
            return
        end

        if not parentIsOverworld() then
            requestRecovery("PARKING ORBIT NOT IN OVERWORLD FRAME", States.DEEP_SPACE_ENTRY)
            return
        end

        local plan = buildLunarTransferPlan()
        if not plan then
            telemetry.nextManeuver = "PARKING ORBIT: WAITING FOR UNIVERSE TIME / MU"
            return
        end

        telemetry.state = States.WAIT_LUNAR_WINDOW
        telemetry.nextManeuver = string.format(
            "LUNAR PLAN READY: TOF %.0fs, waiting phase window",
            plan.tof
        )

    -- ========================================================================
    -- 8. WAIT FOR LUNAR WINDOW
    -- ========================================================================
    elseif telemetry.state == States.WAITING_FOR_MOON_TARGET or
           telemetry.state == States.WAITING_FOR_LUNAR_DATA or
           telemetry.state == States.WAIT_LUNAR_WINDOW then

        actuators.stopAll()

        if parentIsMoon() then
            telemetry.state = States.LUNAR_APPROACH
            return
        end

        if not parentIsOverworld() then
            requestRecovery("LOST OVERWORLD FRAME BEFORE TLI", States.WAIT_LUNAR_WINDOW)
            return
        end

        local plan = buildLunarTransferPlan()
        if not plan or not isFinite(plan.phaseError) then
            telemetry.nextManeuver = "WAITING FOR LUNAR EPHEMERIS"
            return
        end

        telemetry.nextManeuver = string.format(
            "LUNAR WINDOW: phase error %+.2f deg | TOF %.0fs",
            plan.phaseError, plan.tof
        )

        if math.abs(plan.phaseError) <= CONFIG.LUNAR_WINDOW_TOLERANCE_DEG then
            telemetry.tliStartTick = telemetry.universeTime
            telemetry.tliArrivalTick = plan.arrivalTicks
            telemetry.tliDepartureSpeed = plan.departureSpeed
            telemetry.state = States.TLI
            beginBurnCycle(now)
            telemetry.nextManeuver = "TLI WINDOW OPEN: EXECUTING PROGRADE BURN"
        end

    -- ========================================================================
    -- 9. TLI
    -- ========================================================================
    elseif telemetry.state == States.TLI then
        if parentIsMoon() then
            actuators.stopAll()
            telemetry.state = States.LUNAR_APPROACH
            return
        end

        if not telemetry.validSpaceVector or not parentIsOverworld() then
            requestRecovery("TLI LOST OVERWORLD ORBIT VECTOR", States.TLI)
            return
        end

        local mu = telemetry.overworldMu or currentMu()
        local r = vecLen(telemetry.spacePos)
        if not mu or r <= 0 or not telemetry.tliDepartureSpeed then
            requestRecovery("TLI PARAMETERS INVALID", States.WAIT_LUNAR_WINDOW)
            return
        end

        local rHat = vecNorm(telemetry.spacePos)
        local tangent = lunarPlaneTangent(rHat)

        -- Recalcular velocidad de transferencia usando el radio actual para absorber
        -- el pequeño movimiento durante una quema no instantánea.
        local moonR = telemetry.lunarOrbitRadius
        local targetR = moonR and math.sqrt(
            moonR * moonR + CONFIG.LUNAR_ENCOUNTER_OFFSET * CONFIG.LUNAR_ENCOUNTER_OFFSET
        ) or nil

        if not targetR then
            requestRecovery("NO LUNAR TARGET RADIUS DURING TLI", States.WAIT_LUNAR_WINDOW)
            return
        end

        local a = (r + targetR) * 0.5
        local vp = math.sqrt(mu * (2 / r - 1 / a))
        telemetry.tliDepartureSpeed = vp

        local targetVel = vecScale(tangent, vp)
        local done, dv = velocityController(targetVel, 25.0, 0.08, 0.85)

        telemetry.nextManeuver = string.format(
            "TLI BURN: V %.0f / %.0f | dV %.0f",
            telemetry.speed, vp, dv
        )

        if done then
            actuators.stopAll()

            local tof = math.pi * math.sqrt((a * a * a) / mu)
            telemetry.lunarTransferTime = tof
            telemetry.tliArrivalTick = telemetry.universeTime +
                                       tof / CONFIG.UNIVERSE_SECONDS_PER_TICK
            telemetry.state = States.COAST
            telemetry.nextManeuver = string.format(
                "TLI COMPLETE: COAST %.0fs TO LUNAR ENCOUNTER",
                tof
            )
        end

    -- ========================================================================
    -- 10. TRANS-LUNAR COAST / MIDCOURSE
    -- ========================================================================
    elseif telemetry.state == States.COAST or telemetry.state == States.MIDCOURSE then
        if parentIsMoon() then
            actuators.stopAll()
            telemetry.state = States.LUNAR_APPROACH
            telemetry.nextManeuver = "LUNAR SOI ACQUIRED"
            return
        end

        if not telemetry.validSpaceVector or not parentIsOverworld() then
            requestRecovery("TRANSFER VECTOR LOST", States.COAST)
            return
        end

        updateMoonDistanceNow()

        local moonDist = telemetry.lunarDistance
        local nowTicks = telemetry.universeTime
        local remaining = telemetry.tliArrivalTick and
                          (telemetry.tliArrivalTick - nowTicks) *
                          CONFIG.UNIVERSE_SECONDS_PER_TICK or nil

        if moonDist and moonDist <= CONFIG.MIDCOURSE_START_DISTANCE then
            telemetry.state = States.MIDCOURSE

            -- Powered terminal guidance to a moving point ~900 km ahead of Moon.
            -- This guarantees entry into the lunar SOI without aiming at its centre.
            local moonPos, moonVel = moonStateAtTicks(nowTicks, telemetry.overworldMu)
            local moonTan = moonVel and vecNorm(moonVel) or vec3(0, 0, 0)

            if moonPos and vecLen(moonTan) > 0 then
                local targetPoint = vec3(
                    moonPos.x + moonTan.x * CONFIG.LUNAR_ENCOUNTER_OFFSET,
                    moonPos.y + moonTan.y * CONFIG.LUNAR_ENCOUNTER_OFFSET,
                    moonPos.z + moonTan.z * CONFIG.LUNAR_ENCOUNTER_OFFSET
                )
                local rel = vecSub(targetPoint, telemetry.spacePos)
                local dist = vecLen(rel)

                local approach = CONFIG.MIDCOURSE_APPROACH_SPEED
                if dist < 2500000 then approach = 1500 end
                if dist < 1500000 then approach = 800 end

                local desiredVel = vec3(
                    moonVel.x + vecNorm(rel).x * approach,
                    moonVel.y + vecNorm(rel).y * approach,
                    moonVel.z + vecNorm(rel).z * approach
                )

                local done, dv = velocityController(
                    desiredVel,
                    CONFIG.MIDCOURSE_DV_TOLERANCE,
                    0.04,
                    dist < 2000000 and 0.35 or 0.22
                )

                telemetry.nextManeuver = string.format(
                    "MIDCOURSE: Moon %.0fkm | aim %.0fkm | dV %.0f",
                    (moonDist or 0) / 1000,
                    dist / 1000,
                    dv
                )
            else
                actuators.stopAll()
                telemetry.nextManeuver = "MIDCOURSE: WAITING MOON EPHEMERIS"
            end
        else
            actuators.stopAll()
            telemetry.nextManeuver = string.format(
                "TRANS-LUNAR COAST: Moon %s | ETA %s",
                moonDist and string.format("%.0fkm", moonDist / 1000) or "N/A",
                remaining and string.format("%.0fs", remaining) or "N/A"
            )
        end

        -- Si el encuentro se ha retrasado mucho, no abortar: pasar a guía terminal.
        if remaining and remaining < -600 and telemetry.state == States.COAST then
            telemetry.state = States.MIDCOURSE
        end

    -- ========================================================================
    -- 11. LUNAR APPROACH
    -- ========================================================================
    elseif telemetry.state == States.LUNAR_APPROACH then
        actuators.stopAll()

        if not parentIsMoon() then
            telemetry.nextManeuver = "WAITING FOR LUNAR REFERENCE FRAME"
            return
        end

        if not telemetry.validSpaceVector then
            requestRecovery("LUNAR FRAME WITHOUT ORBIT VECTOR", States.LUNAR_APPROACH)
            return
        end

        telemetry.state = States.LUNAR_CAPTURE
        telemetry.nextManeuver = "LUNAR CAPTURE: MATCHING SAFE ORBIT"

    -- ========================================================================
    -- 12. LUNAR CAPTURE
    -- ========================================================================
    elseif telemetry.state == States.LUNAR_CAPTURE then
        if not parentIsMoon() or not telemetry.validSpaceVector then
            requestRecovery("LUNAR CAPTURE VECTOR LOST", States.LUNAR_APPROACH)
            return
        end

        local mu = currentMu()
        local r = vecLen(telemetry.spacePos)
        if not mu or r <= 0 then
            requestRecovery("NO LUNAR MU", States.LUNAR_APPROACH)
            return
        end

        local rHat = vecNorm(telemetry.spacePos)
        local tangent = orbitalTangentFromVelocity(rHat, telemetry.spaceVel)
        local vCirc = circularSpeed(mu, r)
        local safeAlt = CONFIG.MOON_TRANSITION_HEIGHT + CONFIG.ORBIT_SAFETY_MARGIN

        -- Si entramos demasiado bajos, añadimos componente radial positiva.
        local radialTarget = 0
        if telemetry.altitude and telemetry.altitude < safeAlt + 10000 then
            radialTarget = CONFIG.LUNAR_CAPTURE_RADIAL_SAFE
        elseif telemetry.reentryGuard then
            radialTarget = CONFIG.LUNAR_CAPTURE_RADIAL_SAFE
        end

        local targetVel = vec3(
            tangent.x * vCirc + rHat.x * radialTarget,
            tangent.y * vCirc + rHat.y * radialTarget,
            tangent.z * vCirc + rHat.z * radialTarget
        )

        local done, dv = velocityController(targetVel, 30.0, 0.05, 0.70)

        telemetry.nextManeuver = string.format(
            "LUNAR CAPTURE: alt %s | V %.0f/Vc %.0f | dV %.0f | e %s",
            telemetry.altitude and string.format("%.0f", telemetry.altitude) or "N/A",
            telemetry.speed,
            vCirc,
            dv,
            telemetry.ecc and string.format("%.3f", telemetry.ecc) or "N/A"
        )

        if telemetry.safeOrbit and telemetry.ecc and
           telemetry.ecc <= CONFIG.LUNAR_CAPTURE_ECC_TARGET and done then
            actuators.stopAll()
            telemetry.state = States.LUNAR_ORBIT
            telemetry.nextManeuver = string.format(
                "LUNAR ORBIT COMPLETE: Pe %.0fm Ap %.0fm e %.4f",
                telemetry.peAlt or 0,
                telemetry.apAlt or 0,
                telemetry.ecc
            )
        elseif telemetry.orbitalSolutionValid and telemetry.ecc and
               telemetry.ecc < 1 and telemetry.safeOrbit then
            telemetry.state = States.ORBIT_CIRCULARIZE
        end

    -- ========================================================================
    -- 13. LUNAR ORBIT
    -- ========================================================================
    elseif telemetry.state == States.LUNAR_ORBIT then
        actuators.stopAll()
        telemetry.nextManeuver = string.format(
            "LUNAR PARKING ORBIT HOLD | Pe %s Ap %s e %s",
            telemetry.peAlt and string.format("%.0fm", telemetry.peAlt) or "N/A",
            telemetry.apAlt and string.format("%.0fm", telemetry.apAlt) or "N/A",
            telemetry.ecc and string.format("%.4f", telemetry.ecc) or "N/A"
        )

    -- ========================================================================
    -- DATA LOCK -> recovery
    -- ========================================================================
    elseif telemetry.state == States.ORBITAL_DATA_LOCK then
        requestRecovery("ORBITAL DATA LOCK", telemetry.inDeepSpace and States.DEEP_SPACE_ENTRY or States.ASCENT)

    -- ========================================================================
    -- RECOVERY: 5 intentos mínimos; después continúa indefinidamente.
    -- ========================================================================
    elseif telemetry.state == States.RECOVERY then
        actuators.stopAll()

        scanHardware()
        if devices.modemSide then
            local okOpen, isOpen = pcall(rednet.isOpen, devices.modemSide)
            if okOpen and not isOpen then
                pcall(rednet.open, devices.modemSide)
            end
        end

        if now >= telemetry.recoveryResumeAt then
            local canRetry = telemetry.sputnikOnline

            if telemetry.inDeepSpace then
                canRetry = canRetry and telemetry.validSpaceVector
            end

            if telemetry.recoveryTarget ~= States.READY and
               telemetry.recoveryTarget ~= States.ASCENT then
                canRetry = canRetry and telemetry.thrusterLinkOnline
            end

            if canRetry then
                telemetry.state = telemetry.recoveryTarget or
                                  (telemetry.inDeepSpace and States.DEEP_SPACE_ENTRY or States.ASCENT)
                telemetry.nextManeuver = string.format(
                    "RECOVERY %d: CONDITIONS RESTORED - RETRYING",
                    telemetry.recoveryAttempts
                )
            else
                telemetry.recoveryResumeAt = now + CONFIG.RECOVERY_RETRY_DELAY * 1000
                telemetry.nextManeuver = string.format(
                    "[SAFE RETRY %d] WAITING: %s",
                    telemetry.recoveryAttempts,
                    telemetry.recoveryReason
                )
            end
        end
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
    print(string.format("AUTO-LAUNCH: %s | AUTO-RELAUNCH: %s",
        CONFIG.AUTO_LAUNCH_ENABLED and "ON" or "OFF",
        CONFIG.AUTO_RELAUNCH_AFTER_FALLBACK and "ON" or "OFF"))
    print("ENTRY GUIDANCE: VELOCITY VECTOR (NO RIGID ANGLE HOLD)")

    local moonDistStr = telemetry.lunarDistance and string.format("%.0fkm", telemetry.lunarDistance / 1000) or "N/A"
    local phaseStr = telemetry.lunarPhaseError and string.format("%+.2fdeg", telemetry.lunarPhaseError) or "N/A"
    local tofStr = telemetry.lunarTransferTime and string.format("%.0fs", telemetry.lunarTransferTime) or "N/A"
    print(string.format("MOON: DIST %-8s PHASE %-8s TOF %s", moonDistStr, phaseStr, tofStr))

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
    print("[L]LAUNCH [U]AUTO-LAUNCH [A]ABORT [M]AUTO/MAN [Q]EXIT")
    term.setTextColor(colors.lightGray)
    write("UP/DOWN: SELECT | LEFT/RIGHT: CHANGE (SHIFT: x" .. tostring(speedSettingsSchema[1].bigStep / speedSettingsSchema[1].step) .. ")")
end

-- ============================================================================
-- EJECUCIÓN PRINCIPAL CON PROTECCIÓN TOTAL (XPCALL)
-- ============================================================================

local function main()
    local timerId = os.startTimer(CONFIG.LOOP_TICK_RATE)
    local shiftHeld = false
    telemetry.autoLaunchAt = os.epoch("utc") + CONFIG.AUTO_LAUNCH_DELAY * 1000
    telemetry.autoLaunchArmed = CONFIG.AUTO_LAUNCH_ENABLED

    while true do
        local event, p1, p2 = os.pullEvent()

        if event == "timer" and p1 == timerId then
            pollTelemetry()
            serviceRednet()

            -- AUTO-LAUNCH: arranca solo tras el delay configurado.
            if telemetry.state == States.READY and
               CONFIG.AUTO_LAUNCH_ENABLED and
               telemetry.mode == "AUTO" and
               os.epoch("utc") >= telemetry.autoLaunchAt then
                telemetry.recoveryAttempts = 0
                telemetry.recoveryReason = ""
                telemetry.insertionPrograde = vec3(0, 0, 0)
                telemetry.orbitNormal = vec3(0, 0, 0)
                telemetry.state = States.LAUNCH
                telemetry.autoLaunchArmed = false
                telemetry.nextManeuver = "AUTO-LAUNCH: IGNITION"
            end

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
            elseif key == "U" then
                CONFIG.AUTO_LAUNCH_ENABLED = not CONFIG.AUTO_LAUNCH_ENABLED
                telemetry.autoLaunchArmed = CONFIG.AUTO_LAUNCH_ENABLED
                telemetry.autoLaunchAt = os.epoch("utc") + CONFIG.AUTO_LAUNCH_DELAY * 1000
                telemetry.nextManeuver = CONFIG.AUTO_LAUNCH_ENABLED and
                    "AUTO-LAUNCH ENABLED" or "AUTO-LAUNCH DISABLED"
            elseif key == "A" then
                actuators.stopAll()
                telemetry.state = States.ABORT
                telemetry.autoLaunchArmed = false
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