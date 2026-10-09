local PROTOCOLO = "CLOUD_MACHINE_V6"
local SESSION_DIR = "cloud_session"
local DB_FILE = "venta_db.json"

local config = { comandos = {}, mensaje = "Servidor Dedicado", activo = false, permisos = { fs = false, rednet = true, http = true, os = false } }
local db = { owner = nil, balance = 0, status = "FOR_SALE", state_time = 0 }
local active_session = nil

local oldFS = {}; for k, v in pairs(fs) do oldFS[k] = v end
local oldOS = {}; for k, v in pairs(os) do oldOS[k] = v end
local oldRednet = {}; for k, v in pairs(rednet) do oldRednet[k] = v end
local oldPeripheral = {}; for k, v in pairs(peripheral) do oldPeripheral[k] = v end
local oldHTTP = http and {} or nil
if http then for k, v in pairs(http) do oldHTTP[k] = v end end

os.version = function() return "World Shell Venta 1.0" end

local function cargarDB()
    if oldFS.exists(DB_FILE) then local f = oldFS.open(DB_FILE, "r"); local data = textutils.unserialize(f.readAll()); f.close(); if data then db = data end end
    guardarDB()
end
function guardarDB() local f = oldFS.open(DB_FILE, "w"); f.write(textutils.serialize(db)); f.close() end
local function abrirModem() local modems = {peripheral.find("modem")}; if #modems == 0 then return false end; oldRednet.open(peripheral.getName(modems[1])); return true end
local function normalizar(path) return oldFS.combine("", path) end
local function dentroDeLaCarcel(path) local abs = normalizar(path); return abs == SESSION_DIR or abs:sub(1, #SESSION_DIR + 1) == SESSION_DIR .. "/" end
local function esRomDelSistema(path) local abs = normalizar(path); return abs == "rom" or abs:sub(1, 4) == "rom/" end
local function esRutaDeArranque(path) local abs = normalizar(path); return abs == "startup" or abs == "startup.lua" or abs:sub(1, 8) == "startup/" end
local function getCurrentSession() if active_session and active_session.co == coroutine.running() then return active_session end return nil end

local function aplicarSandboxGlobal()
    if oldFS.exists(SESSION_DIR) and not oldFS.isDir(SESSION_DIR) then oldFS.delete(SESSION_DIR) end
    if not oldFS.exists(SESSION_DIR) then oldFS.makeDir(SESSION_DIR) end

    -- FIX: Proteccion profunda contra el comando edit
    local oldAttributes = oldFS.attributes
    if oldAttributes then fs.attributes = function(path) local s = getCurrentSession(); if not s or s.perms.fs then return oldAttributes(path) end local abs = normalizar(path); if abs == SESSION_DIR or abs:sub(1, #SESSION_DIR+1) == SESSION_DIR.."/" or esRomDelSistema(path) then return oldAttributes(path) end return nil, "Acceso denegado" end end
    
    local oldFind = oldFS.find
    if oldFind then fs.find = function(path) local s = getCurrentSession(); if not s or s.perms.fs then return oldFind(path) end if oldFS.exists(path) then return {path} else return {} end end end

    if oldFS.getCapacity then fs.getCapacity = function(path) return oldFS.getCapacity(SESSION_DIR) end end
    if oldFS.getFreeSpace then fs.getFreeSpace = function(path) return oldFS.getFreeSpace(SESSION_DIR) end end

    fs.open = function(path, mode) local s = getCurrentSession(); if not s or s.perms.fs then return oldFS.open(path, mode) end; if esRutaDeArranque(path) then return nil, "Acceso denegado" end; if dentroDeLaCarcel(path) then return oldFS.open(path, mode) end; if mode == "r" and esRomDelSistema(path) then return oldFS.open(path, mode) end; return nil, "Aislado" end
    fs.delete = function(path) local s = getCurrentSession(); if not s or s.perms.fs then return oldFS.delete(path) end if dentroDeLaCarcel(path) then return oldFS.delete(path) end return false end
    fs.makeDir = function(path) local s = getCurrentSession(); if not s or s.perms.fs then return oldFS.makeDir(path) end if dentroDeLaCarcel(path) then return oldFS.makeDir(path) end return false end
    fs.move = function(p1, p2) local s = getCurrentSession(); if not s or s.perms.fs then return oldFS.move(p1, p2) end if dentroDeLaCarcel(p1) and dentroDeLaCarcel(p2) then return oldFS.move(p1, p2) end return false end
    fs.copy = function(p1, p2) local s = getCurrentSession(); if not s or s.perms.fs then return oldFS.copy(p1, p2) end if (dentroDeLaCarcel(p1) or esRomDelSistema(p1)) and dentroDeLaCarcel(p2) then return oldFS.copy(p1, p2) end return false end
    fs.list = function(path) local s = getCurrentSession(); if not s or s.perms.fs then return oldFS.list(path) end local abs = normalizar(path); if abs == "" then return { SESSION_DIR, "rom" } end if esRutaDeArranque(path) then return {} end if dentroDeLaCarcel(path) or esRomDelSistema(path) then return oldFS.list(path) end return {} end
    fs.exists = function(path) local s = getCurrentSession(); if not s or s.perms.fs then return oldFS.exists(path) end local abs = normalizar(path); if abs == "" then return true end if esRutaDeArranque(path) then return false end if dentroDeLaCarcel(path) or esRomDelSistema(path) then return oldFS.exists(path) end return false end
    fs.isDir = function(path) local s = getCurrentSession(); if not s or s.perms.fs then return oldFS.isDir(path) end local abs = normalizar(path); if abs == "" then return true end if dentroDeLaCarcel(path) or esRomDelSistema(path) then return oldFS.isDir(path) end return false end
    fs.isReadOnly = function(path) local s = getCurrentSession(); if not s or s.perms.fs then return oldFS.isReadOnly(path) end if dentroDeLaCarcel(path) then return oldFS.isReadOnly(path) end return true end
    fs.getSize = function(path) local s = getCurrentSession(); if not s or s.perms.fs then return oldFS.getSize(path) end if dentroDeLaCarcel(path) or esRomDelSistema(path) then return oldFS.getSize(path) end return 0 end
    
    os.shutdown = function() local s = getCurrentSession(); if not s or s.perms.os then oldOS.shutdown() else print("Denegado.") end end
    os.reboot = function() local s = getCurrentSession(); if not s or s.perms.os then oldOS.reboot() else print("Denegado.") end end
    peripheral.find = function(t,...) local s = getCurrentSession(); if s and not s.perms.rednet then if t=="drive" or t=="modem" then return nil end end return oldPeripheral.find(t,...) end
    peripheral.getMethods = function(sd) local s = getCurrentSession(); if s and not s.perms.rednet then local pt=oldPeripheral.getType(sd); if pt=="drive" or pt=="modem" then return nil end end return oldPeripheral.getMethods(sd) end
    peripheral.call = function(sd, m, ...) local s = getCurrentSession(); if s and not s.perms.rednet then local pt=oldPeripheral.getType(sd); if pt=="drive" or pt=="modem" then return nil end end return oldPeripheral.call(sd, m, ...) end
    rednet.broadcast = function(m, pr) local s = getCurrentSession(); if not s or s.perms.rednet then oldRednet.broadcast(m,pr) else print("Bloqueado") end end
    rednet.send = function(i,m,pr) local s = getCurrentSession(); if not s or s.perms.rednet then oldRednet.send(i,m,pr) else print("Bloqueado") end end
    rednet.receive = function(...) local s = getCurrentSession(); if not s or s.perms.rednet then return oldRednet.receive(...) else sleep(1) end end
    if http then http.get = function(...) local s=getCurrentSession(); if not s or s.perms.http then return oldHTTP.get(...) end return nil, "Bloqueado" end; http.post = function(...) local s=getCurrentSession(); if not s or s.perms.http then return oldHTTP.post(...) end return nil, "Bloqueado" end; http.request = function(...) local s=getCurrentSession(); if not s or s.perms.http then return oldHTTP.request(...) end print("Bloqueado") end; http.checkURL = function(...) local s=getCurrentSession(); if not s or s.perms.http then return oldHTTP.checkURL(...) end return false, "Bloqueado" end end
end
aplicarSandboxGlobal()

local function endSession()
    if active_session then
        oldRednet.send(active_session.id, {tipo="DESCONECTAR"}, PROTOCOLO)
        active_session.win.setVisible(false)
        active_session = nil
    end
end

local function resumeSession(ev_data)
    if not active_session then return end
    local old_t = term.current()
    term.redirect(active_session.term_remota)
    local ok, filt = coroutine.resume(active_session.co, table.unpack(ev_data))
    term.redirect(old_t)
    if ok then if coroutine.status(active_session.co) == "dead" then endSession() end else endSession() end
end

local function spawnSession(id, msg)
    local w, h = msg.w, msg.h
    local win = window.create(term.native(), 1, 2, w, h, false)
    local term_remota = {}
    for k, v in pairs(win) do term_remota[k] = function(...) oldRednet.send(id, {tipo="TERM", func=k, args={...}}, PROTOCOLO); return v(...) end end
    term_remota.setBackgroundColor = function(c) if c == colors.black then c = colors.blue end oldRednet.send(id, {tipo="TERM", func="setBackgroundColor", args={c}}, PROTOCOLO); return win.setBackgroundColor(c) end
    term_remota.setBackgroundColour = term_remota.setBackgroundColor; term_remota.getCursorPos = function() return win.getCursorPos() end; term_remota.getSize = function() return win.getSize() end

    local co = coroutine.create(function()
        term.setBackgroundColor(colors.blue); term.setTextColor(colors.white); term.clear(); term.setCursorPos(1,1)
        term.setTextColor(colors.cyan); print("[ Servidor Dedicado ]"); print(string.rep("-", w)); term.setTextColor(colors.white)
        pcall(function() if #config.comandos == 0 then shell.run("shell") else for _, cmd in ipairs(config.comandos) do shell.run(cmd) end; shell.run("shell") end end)
        oldRednet.send(id, {tipo="DESCONECTAR"}, PROTOCOLO)
    end)
    
    active_session = { co = co, win = win, term_remota = term_remota, id = id, user = msg.user, perms = config.permisos }
    local old_t = term.current()
    term.redirect(term_remota)
    local ok = coroutine.resume(co)
    term.redirect(old_t)
    if not ok then endSession() end
end

local function renderUI()
    term.redirect(term.native())
    if active_session then active_session.win.setVisible(false) end
    term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1,1); term.setTextColor(colors.cyan)
    print("=== SERVIDOR EN VENTA ==="); term.setTextColor(colors.white)
    print("ID: " .. os.getComputerID())
    print("\nEstado actual: " .. db.status)
    print("Dueño:  " .. (db.owner or "Ninguno"))
    print("Saldo:  " .. db.balance .. " creditos")
    
    term.setCursorPos(1, 10); term.setTextColor(colors.yellow)
    if active_session then print(">> USUARIO " .. active_session.user .. " CONECTADO <<") else print(">> ESPERANDO CONEXION <<") end
    print("\n[ Q ] Apagar Servidor")
end

local function runServerEngine()
    local old_dir = shell.dir(); shell.setDir(SESSION_DIR)
    local bill_timer = os.startTimer(60)
    
    while config.activo do
        renderUI()
        local ev = {os.pullEventRaw()}
        
        if ev[1] == "terminate" then config.activo = false; break end

        if ev[1] == "timer" and ev[2] == bill_timer then
            if db.owner then
                if db.status == "ACTIVE" then
                    db.balance = db.balance - 2
                    if db.balance <= 0 then
                        db.balance = 0; db.status = "UNAVAILABLE"; db.state_time = os.epoch("utc")
                        endSession()
                    end
                    guardarDB()
                elseif db.status == "UNAVAILABLE" then
                    if os.epoch("utc") - db.state_time >= 86400000 then db.status = "LIMIT"; db.state_time = os.epoch("utc"); guardarDB() end
                elseif db.status == "LIMIT" then
                    if os.epoch("utc") - db.state_time >= 86400000 then
                        if oldFS.exists(SESSION_DIR) then oldFS.delete(SESSION_DIR) end; oldFS.makeDir(SESSION_DIR)
                        db.owner = nil; db.balance = 0; db.status = "FOR_SALE"; db.state_time = 0; guardarDB()
                    end
                end
            end
            bill_timer = os.startTimer(60)
        end

        if ev[1] == "key" and ev[2] == keys.q then config.activo = false; break end

        if ev[1] == "rednet_message" and ev[4] == PROTOCOLO then
            local id, msg = ev[2], ev[3]
            if type(msg) == "table" then
                if msg.tipo == "GET_VENTA" then oldRednet.send(id, {tipo="INFO_VENTA", status=db.status, owner=db.owner, balance=db.balance}, PROTOCOLO)
                elseif msg.tipo == "CLAIM_VENTA" then
                    if db.status == "FOR_SALE" then
                        db.owner = msg.user; db.status = "UNAVAILABLE"; db.state_time = os.epoch("utc"); guardarDB()
                        oldRednet.send(id, {tipo="CLAIM_RES", ok=true}, PROTOCOLO)
                    else oldRednet.send(id, {tipo="CLAIM_RES", ok=false}, PROTOCOLO) end
                elseif msg.tipo == "ADD_BALANCE" then
                    db.balance = db.balance + (msg.amount or 0)
                    if db.status == "UNAVAILABLE" or db.status == "LIMIT" then db.status = "ACTIVE" end
                    guardarDB()
                elseif msg.tipo == "CONECTAR" then
                    if db.owner ~= msg.user then oldRednet.send(id, {tipo="ERROR", msg="No eres dueño de este servidor dedicado."}, PROTOCOLO)
                    elseif db.status ~= "ACTIVE" then oldRednet.send(id, {tipo="ERROR", msg="Servidor " .. db.status .. ". Falta Saldo en el Cajero."}, PROTOCOLO)
                    elseif active_session then oldRednet.send(id, {tipo="ERROR", msg="Servidor en uso."}, PROTOCOLO)
                    else oldRednet.send(id, {tipo="SINC"}, PROTOCOLO); spawnSession(id, msg) end
                elseif msg.tipo == "DESCONECTAR" and active_session and active_session.id == id then endSession()
                elseif msg.tipo == "EVENTO" and active_session and active_session.id == id then resumeSession(msg.evento)
                end
            end
        end

        local is_phys = (ev[1] == "key" or ev[1] == "char" or ev[1] == "mouse_click" or ev[1]:sub(1,5)=="mouse" or ev[1] == "paste" or ev[1] == "key_up")
        if ev[1] == "rednet_message" then if ev[4] ~= PROTOCOLO then resumeSession(ev) end elseif not is_phys then resumeSession(ev) end
    end
    
    endSession()
    term.redirect(term.native()); shell.setDir(old_dir)
end

local function configurarServidor()
    local function drawMenu()
        term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1,1); term.setTextColor(colors.cyan)
        print("=== SETUP VENTA ==="); term.setTextColor(colors.white)
        print("\n1. Estado Activo: " .. (config.activo and "[ SI ]" or "[ NO ]"))
        print("\n[ ENTER ] Iniciar Host")
    end
    drawMenu()
    while true do
        local ev = {os.pullEventRaw()}
        if ev[1] == "terminate" then term.clear(); term.setCursorPos(1,1); print("Apagado."); os.exit() end
        if ev[1] == "key" then
            if ev[2] == keys.one then config.activo = not config.activo; drawMenu()
            elseif ev[2] == keys.enter then if config.activo then runServerEngine(); drawMenu() else print("! Activa el servidor"); os.sleep(1); drawMenu() end end
        end
    end
end
local function main() cargarDB(); if not abrirModem() then print("Falta modem.") return end; configurarServidor() end; main()
