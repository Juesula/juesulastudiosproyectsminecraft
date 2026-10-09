local PROTOCOLO = "CLOUD_MACHINE_V6"
local SESSION_DIR = "cloud_session"
local DB_FILE = "cloud_db.json"

local config = { grupo = "FREE", plan = "FREE", comandos = {}, mensaje = "Bienvenido a World Shell", activo = false, permisos = { fs = false, rednet = false, http = false, os = false } }
local db = { cuentas = {}, free_types = { ["FREE"] = true } }
local cola_espera = {}

local active_sessions = {}
local session_keys = {} 
local session_count = 0
local view_mode = "DASHBOARD"
local monitor_index = 1

local oldFS = {}; for k, v in pairs(fs) do oldFS[k] = v end
local oldOS = {}; for k, v in pairs(os) do oldOS[k] = v end
local oldRednet = {}; for k, v in pairs(rednet) do oldRednet[k] = v end
local oldPeripheral = {}; for k, v in pairs(peripheral) do oldPeripheral[k] = v end
local oldHTTP = http and {} or nil
if http then for k, v in pairs(http) do oldHTTP[k] = v end end

os.version = function() return "World Shell 1.0" end

local function cargarDB()
    if oldFS.exists(DB_FILE) then local f = oldFS.open(DB_FILE, "r"); local data = textutils.unserialize(f.readAll()); f.close(); if data then db = data end end
    if not db.free_types then db.free_types = { ["FREE"] = true } end
    if not db.cuentas["Juesulastudios"] then db.cuentas["Juesulastudios"] = { pass = nil, planes = { ["ADMIN"] = true }, cooldown = 0 } 
    else if type(db.cuentas["Juesulastudios"].planes) ~= "table" then db.cuentas["Juesulastudios"].planes = {} end; db.cuentas["Juesulastudios"].planes["ADMIN"] = true end
    for k, v in pairs(db.cuentas) do if not v.cooldown then v.cooldown = 0 end end; guardarDB()
end

function guardarDB() local f = oldFS.open(DB_FILE, "w"); f.write(textutils.serialize(db)); f.close() end
local function abrirModem() local modems = {peripheral.find("modem")}; if #modems == 0 then return false end; oldRednet.open(peripheral.getName(modems[1])); return true end

local function normalizar(path) return oldFS.combine("", path) end
local function dentroDeLaCarcel(path) local abs = normalizar(path); return abs == SESSION_DIR or abs:sub(1, #SESSION_DIR + 1) == SESSION_DIR .. "/" end
local function esRomDelSistema(path) local abs = normalizar(path); return abs == "rom" or abs:sub(1, 4) == "rom/" end
local function esRutaDeArranque(path) local abs = normalizar(path); return abs == "startup" or abs == "startup.lua" or abs:sub(1, 8) == "startup/" end

local function getCurrentSession()
    local co = coroutine.running()
    for id, s in pairs(active_sessions) do if s.co == co then return s end end
    return nil 
end

local function aplicarSandboxGlobal()
    if oldFS.exists(SESSION_DIR) and not oldFS.isDir(SESSION_DIR) then oldFS.delete(SESSION_DIR) end
    if not oldFS.exists(SESSION_DIR) then oldFS.makeDir(SESSION_DIR) end

    local oldAttributes = oldFS.attributes
    if oldAttributes then fs.attributes = function(path) local s = getCurrentSession(); if not s or s.perms.fs then return oldAttributes(path) end local abs = normalizar(path); if abs == SESSION_DIR or abs:sub(1, #SESSION_DIR+1) == SESSION_DIR.."/" or esRomDelSistema(path) then return oldAttributes(path) end return nil, "Acceso denegado" end end
    
    local oldFind = oldFS.find
    if oldFind then fs.find = function(path) local s = getCurrentSession(); if not s or s.perms.fs then return oldFind(path) end if oldFS.exists(path) then return {path} else return {} end end end

    if oldFS.getCapacity then fs.getCapacity = function(path) return oldFS.getCapacity(SESSION_DIR) end end
    if oldFS.getFreeSpace then fs.getFreeSpace = function(path) return oldFS.getFreeSpace(SESSION_DIR) end end

    fs.open = function(path, mode) local s = getCurrentSession(); if not s or s.perms.fs then return oldFS.open(path, mode) end; if esRutaDeArranque(path) then return nil, "Acceso denegado" end; if dentroDeLaCarcel(path) then return oldFS.open(path, mode) end; if mode == "r" and esRomDelSistema(path) then return oldFS.open(path, mode) end; return nil, "Acceso denegado (Aislado)" end
    fs.delete = function(path) local s = getCurrentSession(); if not s or s.perms.fs then return oldFS.delete(path) end if dentroDeLaCarcel(path) then return oldFS.delete(path) end return false end
    fs.makeDir = function(path) local s = getCurrentSession(); if not s or s.perms.fs then return oldFS.makeDir(path) end if dentroDeLaCarcel(path) then return oldFS.makeDir(path) end return false end
    fs.move = function(p1, p2) local s = getCurrentSession(); if not s or s.perms.fs then return oldFS.move(p1, p2) end if dentroDeLaCarcel(p1) and dentroDeLaCarcel(p2) then return oldFS.move(p1, p2) end return false end
    fs.copy = function(p1, p2) local s = getCurrentSession(); if not s or s.perms.fs then return oldFS.copy(p1, p2) end if (dentroDeLaCarcel(p1) or esRomDelSistema(p1)) and dentroDeLaCarcel(p2) then return oldFS.copy(p1, p2) end return false end
    fs.list = function(path) local s = getCurrentSession(); if not s or s.perms.fs then return oldFS.list(path) end local abs = normalizar(path); if abs == "" then return { SESSION_DIR, "rom" } end if esRutaDeArranque(path) then return {} end if dentroDeLaCarcel(path) or esRomDelSistema(path) then return oldFS.list(path) end return {} end
    fs.exists = function(path) local s = getCurrentSession(); if not s or s.perms.fs then return oldFS.exists(path) end local abs = normalizar(path); if abs == "" then return true end if esRutaDeArranque(path) then return false end if dentroDeLaCarcel(path) or esRomDelSistema(path) then return oldFS.exists(path) end return false end
    fs.isDir = function(path) local s = getCurrentSession(); if not s or s.perms.fs then return oldFS.isDir(path) end local abs = normalizar(path); if abs == "" then return true end if dentroDeLaCarcel(path) or esRomDelSistema(path) then return oldFS.isDir(path) end return false end
    fs.isReadOnly = function(path) local s = getCurrentSession(); if not s or s.perms.fs then return oldFS.isReadOnly(path) end if dentroDeLaCarcel(path) then return oldFS.isReadOnly(path) end return true end
    fs.getSize = function(path) local s = getCurrentSession(); if not s or s.perms.fs then return oldFS.getSize(path) end if dentroDeLaCarcel(path) or esRomDelSistema(path) then return oldFS.getSize(path) end return 0 end
    
    -- Reinicios Virtuales Aislados
    os.shutdown = function() local s = getCurrentSession(); if s then error("SHUTDOWN_SESSION", 0) else oldOS.shutdown() end end
    os.reboot = function() local s = getCurrentSession(); if s then error("REBOOT_SESSION", 0) else oldOS.reboot() end end
    
    peripheral.find = function(typ, ...) local s = getCurrentSession(); if s and not s.perms.rednet then if typ == "drive" or typ == "modem" then return nil end end return oldPeripheral.find(typ, ...) end
    peripheral.getMethods = function(sd) local s = getCurrentSession(); if s and not s.perms.rednet then local pt = oldPeripheral.getType(sd); if pt == "drive" or pt == "modem" then return nil end end return oldPeripheral.getMethods(sd) end
    peripheral.call = function(sd, method, ...) local s = getCurrentSession(); if s and not s.perms.rednet then local pt = oldPeripheral.getType(sd); if pt == "drive" or pt == "modem" then return nil end end return oldPeripheral.call(sd, method, ...) end
    
    rednet.broadcast = function(m, pr) local s = getCurrentSession(); if not s or s.perms.rednet then oldRednet.broadcast(m,pr) else print("Bloqueado") end end
    rednet.send = function(i,m,pr) local s = getCurrentSession(); if not s or s.perms.rednet then oldRednet.send(i,m,pr) else print("Bloqueado") end end
    rednet.receive = function(...) local s = getCurrentSession(); if not s or s.perms.rednet then return oldRednet.receive(...) else sleep(1) end end
    
    if http then http.get = function(...) local s = getCurrentSession(); if not s or s.perms.http then return oldHTTP.get(...) end return nil, "Bloqueado" end; http.post = function(...) local s = getCurrentSession(); if not s or s.perms.http then return oldHTTP.post(...) end return nil, "Bloqueado" end; http.request = function(...) local s = getCurrentSession(); if not s or s.perms.http then return oldHTTP.request(...) end print("Bloqueado") end; http.checkURL = function(...) local s = getCurrentSession(); if not s or s.perms.http then return oldHTTP.checkURL(...) end return false, "Bloqueado" end end
end

aplicarSandboxGlobal()

local function enviarActualizacionCola() for i, req in ipairs(cola_espera) do oldRednet.send(req.id, {tipo="QUEUE_UPDATE", pos=i}, PROTOCOLO) end end
local function ordenarCola() table.sort(cola_espera, function(a, b) if a.premium and not b.premium then return true end if not a.premium and b.premium then return false end return a.time < b.time end) end
local function tieneAcceso(user, user_planes) if user == "Juesulastudios" then return true end local has = user_planes["ADMIN"] or user_planes[config.plan]; if config.plan == "FREE" then for p, _ in pairs(user_planes) do if db.free_types[p] then has = true; break end end end return has end

local function enCooldown(user)
    if user == "Juesulastudios" then return false, 0 end
    local now = os.epoch("utc")
    if db.cuentas[user] and db.cuentas[user].cooldown > now then
        return true, math.ceil((db.cuentas[user].cooldown - now) / 1000)
    end
    return false, 0
end

local function procesarGlobalRednet(id, msg)
    if msg.tipo == "LOGIN" then
        local u, p = msg.user, msg.pass; if u and u:lower() == "juesulastudios" then u = "Juesulastudios" end
        if not db.cuentas[u] then db.cuentas[u] = { pass = p, planes = (u=="Juesulastudios" and {["ADMIN"]=true} or {["FREE"]=true}), cooldown = 0 }; guardarDB() end
        if db.cuentas[u].pass == nil and u == "Juesulastudios" then db.cuentas[u].pass = p; guardarDB() end
        if u == "Juesulastudios" then if type(db.cuentas[u].planes) ~= "table" then db.cuentas[u].planes = {} end; db.cuentas[u].planes["ADMIN"] = true; guardarDB() end
        if db.cuentas[u].pass == p then oldRednet.send(id, {tipo="LOGIN_RES", ok=true, planes=db.cuentas[u].planes, free_types=db.free_types}, PROTOCOLO) else oldRednet.send(id, {tipo="LOGIN_RES", ok=false, error="Clave incorrecta."}, PROTOCOLO) end
        return true
    elseif msg.tipo == "GET_DB" then oldRednet.send(id, {tipo="DB_SYNC", db=db}, PROTOCOLO); return true
    elseif msg.tipo == "SET_DB" then db = msg.db; guardarDB(); return true
    end
    return false
end

local function endSession(id)
    if active_sessions[id] then
        oldRednet.send(id, {tipo="DESCONECTAR"}, PROTOCOLO)
        active_sessions[id].win.setVisible(false)
        if db.free_types[config.plan] and active_sessions[id].user ~= "Juesulastudios" then
            db.cuentas[active_sessions[id].user].cooldown = os.epoch("utc") + 300000; guardarDB(); oldRednet.broadcast({tipo="SET_DB", db=db}, PROTOCOLO)
        end
        active_sessions[id] = nil; session_count = session_count - 1
        for i, k in ipairs(session_keys) do if k == id then table.remove(session_keys, i); break end end
        if monitor_index > #session_keys then monitor_index = math.max(1, #session_keys) end
    end
end

local function resumeSession(id, ev_data)
    local s = active_sessions[id]
    if not s then return end
    local old_t = term.current()
    term.redirect(s.term_remota)
    local ok, filt = coroutine.resume(s.co, table.unpack(ev_data))
    term.redirect(old_t)
    if ok then if coroutine.status(s.co) == "dead" then endSession(id) end else endSession(id) end
end

local function spawnSession(id, msg)
    local w, h = msg.w, msg.h
    local win = window.create(term.native(), 1, 2, w, h, false)
    local term_remota = {}
    for k, v in pairs(win) do term_remota[k] = function(...) oldRednet.send(id, {tipo="TERM", func=k, args={...}}, PROTOCOLO); return v(...) end end
    
    term_remota.setBackgroundColor = function(c) if c == colors.black then c = colors.blue end; oldRednet.send(id, {tipo="TERM", func="setBackgroundColor", args={c}}, PROTOCOLO); return win.setBackgroundColor(c) end
    term_remota.setBackgroundColour = term_remota.setBackgroundColor
    term_remota.getCursorPos = function() return win.getCursorPos() end; term_remota.getSize = function() return win.getSize() end

    local p_perms = (msg.user == "Juesulastudios") and {fs=true, rednet=true, http=true, os=true} or config.permisos
    local co = coroutine.create(function()
        while true do
            term.setBackgroundColor(colors.blue); term.setTextColor(colors.white); term.clear(); term.setCursorPos(1,1)
            term.setTextColor(colors.cyan); print("[ World Shell ]: " .. config.mensaje); print(string.rep("-", w)); term.setTextColor(colors.white)
            
            local ok, err = pcall(function() if #config.comandos == 0 then shell.run("shell") else for _, cmd in ipairs(config.comandos) do shell.run(cmd) end; shell.run("shell") end end)
            
            if not ok and err == "REBOOT_SESSION" then
                -- Continúa el bucle reiniciando la maquina limpia
            else
                break -- Salida normal / shutdown
            end
        end
        oldRednet.send(id, {tipo="DESCONECTAR"}, PROTOCOLO)
    end)
    
    active_sessions[id] = { co = co, win = win, term_remota = term_remota, user = msg.user, is_free = db.free_types[config.plan], expire_time = os.epoch("utc") + 180000, filter = nil, perms = p_perms }
    table.insert(session_keys, id); session_count = session_count + 1
    
    local old_t = term.current()
    term.redirect(term_remota)
    local ok = coroutine.resume(co)
    term.redirect(old_t)
    if not ok then endSession(id) end
end

local function renderUI()
    term.redirect(term.native())
    if view_mode == "DASHBOARD" then
        for _, id in ipairs(session_keys) do active_sessions[id].win.setVisible(false) end
        term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1,1); term.setTextColor(colors.cyan)
        print("=== SERVIDOR WORLD SHELL ==="); term.setTextColor(colors.white)
        print("ID: " .. os.getComputerID() .. " | Grupo: " .. config.grupo .. " | Plan: " .. config.plan)
        print("Usuarios activos: " .. session_count .. " / " .. (db.free_types[config.plan] and 3 or 1))
        term.setCursorPos(1, 10); term.setTextColor(colors.yellow)
        print("[<- / ->] Espiar pantallas de Clientes")
        print("[   Q   ] Apagar el Servidor")
    elseif view_mode == "MONITOR" then
        term.setBackgroundColor(colors.black); term.clear()
        term.setBackgroundColor(colors.gray); term.setTextColor(colors.white); term.setCursorPos(1,1); term.clearLine()
        if session_count == 0 then
            print(" [D] Dashboard | (No hay clientes conectados)"); for _, id in ipairs(session_keys) do active_sessions[id].win.setVisible(false) end
        else
            local active_id = session_keys[monitor_index]; local s = active_sessions[active_id]
            print(" [D] Volver | Clientes: " .. monitor_index .. "/" .. session_count .. " | Viendo a: " .. s.user)
            for _, id in ipairs(session_keys) do active_sessions[id].win.setVisible(id == active_id) end
        end
    end
end

local function runServerEngine()
    local old_dir = shell.dir(); shell.setDir(SESSION_DIR)
    
    while config.activo do
        local max_u = db.free_types[config.plan] and 3 or 1
        if session_count < max_u and #cola_espera > 0 then
            local next_client = table.remove(cola_espera, 1); enviarActualizacionCola()
            oldRednet.send(next_client.id, {tipo="OFERTA_COLA", grupo=config.grupo}, PROTOCOLO)
        end
        
        renderUI()
        local ev = {os.pullEventRaw()}
        
        if ev[1] == "terminate" then config.activo = false; break end

        if ev[1] == "key" then
            if ev[2] == keys.right and view_mode == "MONITOR" then monitor_index = monitor_index + 1; if monitor_index > session_count then monitor_index = 1 end
            elseif ev[2] == keys.left and view_mode == "MONITOR" then monitor_index = monitor_index - 1; if monitor_index < 1 then monitor_index = math.max(1, session_count) end
            elseif (ev[2] == keys.right or ev[2] == keys.left) and view_mode == "DASHBOARD" then view_mode = "MONITOR"
            elseif ev[2] == keys.d then view_mode = "DASHBOARD"
            elseif ev[2] == keys.q and view_mode == "DASHBOARD" then config.activo = false; break end
        end

        if ev[1] == "rednet_message" and ev[4] == PROTOCOLO then
            local id, msg = ev[2], ev[3]
            if type(msg) == "table" then
                if not procesarGlobalRednet(id, msg) then
                    if msg.tipo == "EVENTO" and active_sessions[id] then resumeSession(id, msg.evento)
                    elseif msg.tipo == "DESCONECTAR" then endSession(id)
                    elseif msg.tipo == "GET_GRUPOS" then local up = msg.user_planes or {["FREE"]=true}; if tieneAcceso(msg.user, up) then oldRednet.send(id, {tipo="INFO_GRUPO", grupo=config.grupo}, PROTOCOLO) end
                    elseif msg.tipo == "BUSCAR" then
                        local up = msg.user_planes or {["FREE"]=true}
                        if tieneAcceso(msg.user, up) then
                            local cd, segs = enCooldown(msg.user)
                            if cd then oldRednet.send(id, {tipo="ERROR_COOLDOWN", segs=segs}, PROTOCOLO)
                            elseif (msg.grupo == "AUTO" and db.free_types[config.plan]) or (msg.grupo == config.grupo) then
                                if session_count < max_u then oldRednet.send(id, {tipo="OFERTA", grupo=config.grupo}, PROTOCOLO)
                                else
                                    if msg.user == "Juesulastudios" then oldRednet.send(id, {tipo="OFERTA", grupo=config.grupo, admin_kick=true}, PROTOCOLO)
                                    else oldRednet.send(id, {tipo="INFO_COLA", grupo=config.grupo, qlen=#cola_espera}, PROTOCOLO) end
                                end
                            end
                        end
                    elseif msg.tipo == "JOIN_QUEUE" and not enCooldown(msg.user) then
                        local up = msg.user_planes or {["FREE"]=true}
                        if tieneAcceso(msg.user, up) and ((msg.grupo == "AUTO" and db.free_types[config.plan]) or (msg.grupo == config.grupo)) then
                            local is_premium = false; for p, _ in pairs(up) do if p ~= "FREE" and not db.free_types[p] then is_premium = true end end
                            table.insert(cola_espera, {id=id, user=msg.user, premium=is_premium, time=os.epoch("utc")}); ordenarCola(); enviarActualizacionCola()
                        end
                    elseif msg.tipo == "LEAVE_QUEUE" then for i, req in ipairs(cola_espera) do if req.id == id then table.remove(cola_espera, i); break end end; enviarActualizacionCola()
                    elseif msg.tipo == "CONECTAR" then
                        if msg.user == "Juesulastudios" and session_count >= max_u then
                            oldRednet.send(session_keys[1], {tipo="DESCONECTAR"}, PROTOCOLO); endSession(session_keys[1])
                            oldRednet.send(id, {tipo="SINC", msg=config.mensaje}, PROTOCOLO); spawnSession(id, msg)
                        elseif session_count < max_u then oldRednet.send(id, {tipo="SINC", msg=config.mensaje}, PROTOCOLO); spawnSession(id, msg)
                        else oldRednet.send(id, {tipo="ERROR", msg="Servidor lleno."}, PROTOCOLO) end
                    end
                end
            end
        end

        local is_phys = (ev[1] == "key" or ev[1] == "char" or ev[1] == "mouse_click" or ev[1]:sub(1,5)=="mouse" or ev[1] == "paste" or ev[1] == "key_up")
        
        if ev[1] == "rednet_message" then
            if ev[4] ~= PROTOCOLO then
                for id, s in pairs(active_sessions) do if s.perms.rednet then resumeSession(id, ev) end end
            end
        elseif not is_phys then
            for id, s in pairs(active_sessions) do resumeSession(id, ev) end
        end
        
        local now = os.epoch("utc")
        for id, s in pairs(active_sessions) do
            if s.is_free and s.user ~= "Juesulastudios" and now > s.expire_time then oldRednet.send(id, {tipo="DESCONECTAR"}, PROTOCOLO); endSession(id) end
        end
    end
    
    for _, id in ipairs(session_keys) do oldRednet.send(id, {tipo="DESCONECTAR"}, PROTOCOLO) end
    active_sessions = {}; session_keys = {}; session_count = 0
    term.redirect(term.native()); shell.setDir(old_dir)
end

local function configurarServidor()
    local function drawMenu()
        term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1,1); term.setTextColor(colors.cyan)
        print("=== SETUP WORLD SHELL ==="); term.setTextColor(colors.white)
        print("\n1. Estado Activo: " .. (config.activo and "[ SI ]" or "[ NO ]"))
        print("2. Grupo asignado: " .. config.grupo)
        print("3. Plan requerido: " .. config.plan)
        print("4. Permisos Sandbox (Modificar)")
        print("\n[ ENTER ] Iniciar Host")
    end
    drawMenu()
    
    while true do
        local ev = {os.pullEventRaw()}
        if ev[1] == "terminate" then term.setBackgroundColor(colors.black); term.setTextColor(colors.white); term.clear(); term.setCursorPos(1,1); print("World Shell apagado."); os.exit() end
        if ev[1] == "key" then
            local key = ev[2]
            if key == keys.one then config.activo = not config.activo; drawMenu()
            elseif key == keys.two then term.setCursorPos(1, 10); term.clearLine(); write("Nuevo grupo: "); local input = read(); if input ~= "" then config.grupo = input end; drawMenu()
            elseif key == keys.three then term.setCursorPos(1, 10); term.clearLine(); write("Nuevo plan: "); local input = read(); if input ~= "" then config.plan = input:upper() end; drawMenu()
            elseif key == keys.four then config.permisos.fs = not config.permisos.fs; config.permisos.rednet = not config.permisos.rednet; config.permisos.http = not config.permisos.http; config.permisos.os = not config.permisos.os; term.setCursorPos(1,10); print("Permisos invertidos."); os.sleep(1); drawMenu()
            elseif key == keys.enter then if config.activo then runServerEngine(); drawMenu() else term.setCursorPos(1, 12); term.setTextColor(colors.red); print("! Activa el servidor primero"); os.sleep(1.5); drawMenu() end
            end
        elseif ev[1] == "rednet_message" and ev[4] == PROTOCOLO then
            procesarGlobalRednet(ev[2], ev[3])
        end
    end
end

local function main() cargarDB(); if not abrirModem() then print("Falta modem.") return end; configurarServidor() end; main()
