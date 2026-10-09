local PROTOCOLO = "CLOUD_MACHINE_V6"
local USERNAME = ""
local MY_PLANES = {}
local FREE_TYPES = {}

local function abrirModem() local modems = {peripheral.find("modem")}; if #modems == 0 then return false end; rednet.open(peripheral.getName(modems[1])); return true end

local function pantallaLogin()
    while true do
        term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1, 2); term.setTextColor(colors.cyan)
        print("   =============================\n         WORLD SHELL LOGIN      \n   =============================")
        term.setTextColor(colors.white); term.setCursorPos(4, 6); write("Usuario: "); local u = read()
        term.setCursorPos(4, 7); write("Clave: "); local p = read("*")
        
        if u ~= "" and p ~= "" then
            if u:lower() == "juesulastudios" then u = "Juesulastudios" end
            term.setCursorPos(4, 9); term.setTextColor(colors.yellow); print("Autenticando en la red...")
            rednet.broadcast({tipo="LOGIN", user=u, pass=p}, PROTOCOLO)
            local t = os.startTimer(2); local exito = false
            while true do
                local ev, p1, p2, p3 = os.pullEvent()
                if ev == "rednet_message" and p3 == PROTOCOLO and type(p2)=="table" and p2.tipo == "LOGIN_RES" then
                    if p2.ok then USERNAME = u; MY_PLANES = p2.planes or {["FREE"]=true}; FREE_TYPES = p2.free_types or {["FREE"]=true}; exito = true; break
                    else term.setCursorPos(4, 11); term.setTextColor(colors.red); print("Error: " .. p2.error); sleep(2); break end
                elseif ev == "timer" and p1 == t then term.setCursorPos(4, 11); term.setTextColor(colors.red); print("Error: Red inactiva."); sleep(2); break end
            end
            if exito then break end
        end
    end
end

local function conectar(server_id)
    local solo_free = true
    if MY_PLANES["ADMIN"] then solo_free = false end
    for p, _ in pairs(MY_PLANES) do if not FREE_TYPES[p] and p ~= "FREE" then solo_free = false; break end end
    local d_id = solo_free and "Oculto" or server_id

    local w, h = term.getSize()
    rednet.send(server_id, {tipo="CONECTAR", w=w, h=h-1, user=USERNAME}, PROTOCOLO)
    local id, msg = rednet.receive(PROTOCOLO, 2)
    
    if id == server_id and type(msg) == "table" and msg.tipo == "SINC" then
        term.setBackgroundColor(colors.black); term.clear()
        term.setCursorPos(1, 1); term.setBackgroundColor(colors.gray); term.setTextColor(colors.white); term.clearLine()
        term.write(" [X] Salir | Srv: " .. d_id .. " | User: " .. USERNAME); term.setBackgroundColor(colors.black)
        
        local old_term = term.current()
        local remote_win = window.create(old_term, 1, 2, w, h-1)
        term.redirect(remote_win) 
        
        local function bucleInputs()
            local validos = { key=true, key_up=true, char=true, paste=true, mouse_click=true, mouse_drag=true, mouse_scroll=true, mouse_up=true }
            while true do
                local ev = {os.pullEventRaw()}
                if ev[1] == "terminate" then rednet.send(server_id, {tipo="DESCONECTAR"}, PROTOCOLO); return
                elseif validos[ev[1]] then
                    if ev[1]:sub(1,5) == "mouse" then
                        if ev[4] == 1 then
                            if ev[1] == "mouse_click" and ev[3] >= 2 and ev[3] <= 10 then rednet.send(server_id, {tipo="DESCONECTAR"}, PROTOCOLO); return end
                        else ev[4] = ev[4] - 1; rednet.send(server_id, {tipo="EVENTO", evento=ev}, PROTOCOLO) end
                    else rednet.send(server_id, {tipo="EVENTO", evento=ev}, PROTOCOLO) end
                end
            end
        end
        
        local function buclePantalla()
            while true do
                local s_id, s_msg = rednet.receive(PROTOCOLO)
                if s_id == server_id and type(s_msg) == "table" then
                    if s_msg.tipo == "TERM" and remote_win[s_msg.func] then remote_win[s_msg.func](table.unpack(s_msg.args))
                    elseif s_msg.tipo == "DESCONECTAR" then return end
                end
            end
        end
        parallel.waitForAny(bucleInputs, buclePantalla)
        
        term.redirect(old_term)
        term.setTextColor(colors.white); term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1,1); print("Desconectado.")
        sleep(1.5)
    else 
        term.setTextColor(colors.red)
        print(msg and msg.msg or "Fallo de conexion.") 
        sleep(2) 
    end
end

local function buscarYConectar(grupo_objetivo)
    local solo_free = true
    if MY_PLANES["ADMIN"] then solo_free = false end
    for p, _ in pairs(MY_PLANES) do if not FREE_TYPES[p] and p ~= "FREE" then solo_free = false; break end end

    print("\nBuscando servidor [" .. grupo_objetivo .. "] ...")
    rednet.broadcast({tipo="BUSCAR", grupo=grupo_objetivo, user_planes=MY_PLANES, user=USERNAME}, PROTOCOLO)
    
    local t_id = nil; local cooldown_min = nil; local admin_kick_id = nil; local colas = {}
    local t = os.startTimer(1.5)
    while true do
        local e, p1, p2, p3 = os.pullEvent()
        if e=="rednet_message" and p3==PROTOCOLO and type(p2)=="table" then
            if p2.tipo=="OFERTA" then if p2.admin_kick then admin_kick_id = p1 end; t_id = p1; break
            elseif p2.tipo=="ERROR_COOLDOWN" then cooldown_min = p2.min
            elseif p2.tipo=="INFO_COLA" then colas[p1] = p2.qlen end
        elseif e == "timer" and p1 == t then break end
    end
    
    if admin_kick_id then conectar(admin_kick_id)
    elseif t_id then conectar(t_id)
    elseif cooldown_min then term.setTextColor(colors.red); print("COOLDOWN: Espera " .. cooldown_min .. " min."); sleep(3)
    elseif next(colas) then
        local best_id, min_q = nil, 9999
        for s_id, qlen in pairs(colas) do if qlen < min_q then best_id = s_id; min_q = qlen end end
        
        rednet.send(best_id, {tipo="JOIN_QUEUE", grupo=grupo_objetivo, user_planes=MY_PLANES, user=USERNAME}, PROTOCOLO)
        
        local esperando = true
        while esperando do
            local e, p1, p2, p3 = os.pullEvent()
            if e == "rednet_message" and p3 == PROTOCOLO and type(p2)=="table" and p1 == best_id then
                if p2.tipo == "QUEUE_UPDATE" then
                    term.clear(); term.setCursorPos(1,1); term.setTextColor(colors.cyan)
                    print("=== SALA DE ESPERA ===")
                    term.setTextColor(colors.white)
                    print("Servidor asignado: " .. (solo_free and "Oculto" or best_id))
                    print("Tu posicion en la cola: " .. p2.pos)
                    print("\n(Presiona 'Q' para salir de la cola)")
                elseif p2.tipo == "OFERTA_COLA" then
                    term.clear(); term.setCursorPos(1,1); term.setTextColor(colors.green)
                    print("¡Tu turno! Conectando..."); esperando = false; conectar(best_id)
                end
            elseif e == "key" and p2 == keys.q then
                rednet.send(best_id, {tipo="LEAVE_QUEUE"}, PROTOCOLO)
                term.clear(); term.setCursorPos(1,1); term.setTextColor(colors.red); print("Saliste de la cola."); sleep(1); esperando = false
            end
        end
    else print("Ningun servidor libre."); sleep(2) end
end

local function panelAdmin()
    term.clear(); term.setCursorPos(1,1); term.setTextColor(colors.yellow); print("Obteniendo DB de la red...")
    rednet.broadcast({tipo="GET_DB"}, PROTOCOLO); local id, msg = rednet.receive(PROTOCOLO, 2)
    if id and msg and msg.tipo == "DB_SYNC" then
        local db = msg.db
        while true do
            term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1,1); term.setTextColor(colors.red)
            print("--- PANEL DE ADMINISTRACION ---\n"); term.setTextColor(colors.white); print("1. Administrar Planes de Usuario"); print("2. Crear alias de plan FREE"); print("3. Salir")
            local _, key = os.pullEvent("key")
            if key == keys.three then break
            elseif key == keys.two then
                print("\nEscribe el nombre del nuevo plan (Ej: FREE_LATAM):"); local n = read():upper()
                if n ~= "" then db.free_types[n] = true; rednet.broadcast({tipo="SET_DB", db=db}, PROTOCOLO); print("Plan creado."); sleep(1) end
            elseif key == keys.one then
                term.clear(); term.setCursorPos(1,1); term.setTextColor(colors.yellow)
                print("Usuarios registrados:")
                term.setTextColor(colors.white)
                
                local lista_usuarios = {}
                for u, _ in pairs(db.cuentas) do table.insert(lista_usuarios, u) end
                print(table.concat(lista_usuarios, " | "))
                
                print("\nUsuario a modificar:"); local input = read()
                if db.cuentas[input] then
                    if type(db.cuentas[input].planes) ~= "table" then db.cuentas[input].planes = { ["FREE"] = true } end
                    while true do
                        term.clear(); term.setCursorPos(1,1); term.setTextColor(colors.yellow); print("Planes activos de " .. input .. ":")
                        for p, _ in pairs(db.cuentas[input].planes) do print(" - " .. p) end
                        term.setTextColor(colors.white); print("\nEscribe plan a anadir/quitar (Q para volver):"); local plan = read():upper()
                        if plan == "Q" then break end
                        if plan ~= "" then
                            if db.cuentas[input].planes[plan] then db.cuentas[input].planes[plan] = nil else db.cuentas[input].planes[plan] = true end
                            rednet.broadcast({tipo="SET_DB", db=db}, PROTOCOLO); print("DB actualizada!"); sleep(1)
                        end
                    end
                else term.setTextColor(colors.red); print("Usuario no existe."); sleep(1) end
            end
        end
    else term.setTextColor(colors.red); print("No se pudo obtener la DB."); sleep(2) end
end

local function main()
    if not abrirModem() then return end; pantallaLogin()
    while true do
        local solo_free = true
        if MY_PLANES["ADMIN"] then solo_free = false end
        for p, _ in pairs(MY_PLANES) do if not FREE_TYPES[p] and p ~= "FREE" then solo_free = false; break end end
        
        term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1,1); term.setTextColor(colors.cyan)
        print("====== WORLD SHELL ======"); term.setTextColor(colors.white)
        local textPlanes = ""; for p, _ in pairs(MY_PLANES) do textPlanes = textPlanes .. p .. " " end
        print("Usuario: " .. USERNAME .. " | Planes: " .. textPlanes .. "\n")
        if solo_free then print("1. Autoconectar (Asignacion Automatica)") else print("1. Buscar Grupos y Conectar") end
        print("2. Cerrar Sesion")
        if MY_PLANES["ADMIN"] then term.setTextColor(colors.red); print("3. Panel de Administrador"); term.setTextColor(colors.white); print("4. Actualizar Cliente") else print("3. Actualizar Cliente") end
        
        term.setTextColor(colors.yellow)
        print("\n[ V ] Servidores Dedicados en Venta")
        term.setTextColor(colors.white)
        
        local _, key = os.pullEvent("key")
        if key == keys.two then USERNAME = ""; MY_PLANES = {}; pantallaLogin()
        elseif key == keys.three and MY_PLANES["ADMIN"] then panelAdmin()
        elseif (key == keys.four and MY_PLANES["ADMIN"]) or (key == keys.three and not MY_PLANES["ADMIN"]) then
            term.clear(); term.setCursorPos(1,1); term.setTextColor(colors.yellow); print("Actualizando cliente...")
            local ruta = shell.getRunningProgram()
            fs.delete(ruta)
            shell.run("pastebin", "get", "BYuGBbNC", ruta)
            os.reboot()
        elseif key == keys.v then
            term.clear(); term.setCursorPos(1,1); term.setTextColor(colors.yellow); print("Buscando Servidores en Venta...")
            rednet.broadcast({tipo="GET_VENTA"}, PROTOCOLO)
            local ventas = {}
            local tv = os.startTimer(1.5)
            while true do
                local ev, p1, p2, p3 = os.pullEvent()
                if ev == "rednet_message" and p3 == PROTOCOLO and type(p2)=="table" and p2.tipo=="INFO_VENTA" then
                    ventas[p1] = p2
                elseif ev == "timer" and p1 == tv then break end
            end
            
            local l_ventas = {}; for k,v in pairs(ventas) do table.insert(l_ventas, {id=k, data=v}) end
            term.clear(); term.setCursorPos(1,1); term.setTextColor(colors.white)
            if #l_ventas == 0 then term.setTextColor(colors.red); print("No hay servidores en venta."); sleep(2)
            else
                print("Servidores Dedicados:\n")
                for i, v in ipairs(l_ventas) do 
                    local st = v.data.status
                    local ow = v.data.owner or "Nadie"
                    print(i .. ". ID: " .. v.id .. " | Est: " .. st .. " | Dueño: " .. ow) 
                end
                print("\nElige numero para Reclamar/Conectar (Q = Salir):")
                while true do
                    local ev = {os.pullEvent()}
                    if ev[1] == "char" then 
                        local num = tonumber(ev[2])
                        if num and l_ventas[num] then 
                            local obj = l_ventas[num]
                            if obj.data.status == "FOR_SALE" then
                                rednet.send(obj.id, {tipo="CLAIM_VENTA", user=USERNAME}, PROTOCOLO)
                                local _, msg = rednet.receive(PROTOCOLO, 2)
                                if msg and msg.tipo == "CLAIM_RES" and msg.ok then
                                    term.setTextColor(colors.green)
                                    print("\n¡Reclamado con exito!")
                                    print("Ahora ve a un Cajero Fisico y vincula el ID " .. obj.id .. " para darle saldo.")
                                    sleep(4); break
                                else print("Error al reclamar."); sleep(2); break end
                            elseif obj.data.owner == USERNAME then
                                conectar(obj.id); break
                            else
                                term.setTextColor(colors.red); print("No eres el dueño o no está libre."); sleep(2); break
                            end
                        end
                    elseif ev[1] == "key" and ev[2] == keys.q then break end
                end
            end
        elseif key == keys.one then
            if solo_free then buscarYConectar("AUTO")
            else
                term.clear(); term.setCursorPos(1,1); term.setTextColor(colors.yellow); print("Escaneando red...")
                rednet.broadcast({tipo="GET_GRUPOS", user_planes=MY_PLANES, user=USERNAME}, PROTOCOLO)
                local grupos = {}; local timer = os.startTimer(1.5)
                while true do
                    local ev, p1, p2, p3 = os.pullEvent()
                    if ev == "rednet_message" and p3 == PROTOCOLO and type(p2)=="table" and p2.tipo=="INFO_GRUPO" then grupos[p2.grupo] = true
                    elseif ev == "timer" and p1 == timer then break end
                end
                
                local lista = {}; for g, _ in pairs(grupos) do table.insert(lista, g) end
                term.clear(); term.setCursorPos(1,1); term.setTextColor(colors.white)
                if #lista == 0 then term.setTextColor(colors.red); print("No hay servidores disponibles."); sleep(2)
                else
                    print("Grupos disponibles:\n")
                    for i, g in ipairs(lista) do print(i .. ". " .. g) end
                    print("\nPulsa numero o haz clic (Q para cancelar):")
                    while true do
                        local ev = {os.pullEvent()}
                        if ev[1] == "char" then local num = tonumber(ev[2]); if num and lista[num] then buscarYConectar(lista[num]); break end
                        elseif ev[1] == "key" and ev[2] == keys.q then break
                        elseif ev[1] == "mouse_click" then local idx = ev[4] - 3; if idx >= 1 and idx <= #lista then buscarYConectar(lista[idx]); break end end
                    end
                end
            end
        end
    end
end
main()
