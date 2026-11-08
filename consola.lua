-- OMNIA / consola.lua (CC: Tweaked)
-- Consola de control y registro 3D (fase 1: pruebas manuales).
-- Protocolo compatible con controlador.lua y sensor.lua.
local PROTOCOL="omnia.v1"
local MAX_AGE=2.5
local SENSOR_AGE=1.5
local controllers={} -- ["1-1:stop"] = {id=, ring=, axis=, ...}
local sensors={}     -- [1] = {id=, position=, orientation=, ...}
local desired={}     -- ["1-1"] = true si la consola renueva la marcha
local duplicate={}   -- claves duplicadas: bloquean un cable
local sensorConflict={} -- sensores duplicados: bloquean anillo
local notes={}

local function now() return os.epoch("utc")/1000 end
local function key(r,a) return tostring(r).."-"..tostring(a) end
local function slot(r,a,role) return key(r,a)..":"..role end
local function online(n,age)
  return n~=nil and now()-(n.lastSeen or 0)<(age or MAX_AGE)
end
local function fmt(v)
  if not v then return "SIN DATOS" end
  return string.format("(%.2f, %.2f, %.2f)",
    tonumber(v.x) or 0,tonumber(v.y) or 0,tonumber(v.z) or 0)
end
local function send(id, msg)
  if id then rednet.send(id,msg,PROTOCOL) end
end
local function cmd(r,a,action,value)
  local role=(action=="run") and "stop" or "reverse"
  local n=controllers[slot(r,a,role)]
  if n then send(n.id,{kind="SET",ring=r,axis=a,action=action,value=value}) end
end
local function stopAxis(r,a)
  desired[key(r,a)]=nil
  cmd(r,a,"run",false)
end
local function stopRing(r)
  for a=1,4 do stopAxis(r,a) end
end
local function estop()
  desired={}
  -- doble via: difusion y mensaje directo, para aumentar la entrega
  rednet.broadcast({kind="ESTOP"},PROTOCOL)
  for _,n in pairs(controllers) do send(n.id,{kind="ESTOP"}) end
end

local function validSlot(r,a)
  if duplicate[slot(r,a,"stop")] or duplicate[slot(r,a,"reverse")] then
    return false,"ID duplicado: revisa equipos"
  end
  if sensorConflict[r] then return false,"Sensores duplicados: reinicia consola tras corregirlo" end
  local s=controllers[slot(r,a,"stop")]
  local rev=controllers[slot(r,a,"reverse")]
  if not online(s) or not online(rev) then
    return false,"Falta STOP o REVERSE conectado"
  end
  if s.tripped or rev.tripped then return false,"Parada de emergencia activa: usa reset" end
  local sensor=sensors[r]
  if not online(sensor,SENSOR_AGE) or not sensor.valid or not sensor.position then
    return false,"Sensor Sable sin posicion reciente"
  end
  if not s.anchor or not rev.anchor then return false,"Faltan coordenadas del cabrestante" end
  for _,v in ipairs({"x","y","z"}) do
    if math.abs((s.anchor[v] or 0)-(rev.anchor[v] or 0))>0.05 then
      return false,"STOP y REVERSE apuntan a cabrestantes distintos"
    end
  end
  return true
end

for _,name in ipairs(peripheral.getNames()) do
  if peripheral.hasType(name,"modem") then rednet.open(name) end
end
assert(rednet.isOpen(),"Conecta al menos un modem")

local function record(id, msg)
  if type(msg)~="table" or not msg.kind then return end
  local r=tonumber(msg.ring)
  if not r or r%1~=0 or r<1 or r>3 then return end

  if msg.kind=="HELLO" or msg.kind=="STATUS" then
    local a=tonumber(msg.axis)
    if not a or a%1~=0 or a<1 or a>4 then return end
    if msg.role~="stop" and msg.role~="reverse" then return end
    local k=slot(r,a,msg.role)
    local prev=controllers[k]
    if prev and prev.id~=id and online(prev,6) then
      duplicate[k]=true
      stopAxis(r,a)
      return
    end
    if prev and prev.boot~=msg.boot then
      -- Reinicio detectado: quitar permiso de movimiento.
      stopAxis(r,a)
    end
    controllers[k]={id=id, boot=msg.boot, ring=r, axis=a, role=msg.role,
      anchor=msg.anchor, controllerPos=msg.controllerPos,
      running=msg.running, reverse=msg.reverse, tripped=msg.tripped, lastSeen=now()}
  elseif msg.kind=="SENSOR_HELLO" then
    local prev=sensors[r]
    if prev and prev.id~=id and online(prev,6) then
      stopRing(r)
      sensorConflict[r]=true
      notes[r]="Dos sensores para el mismo anillo"
      return
    end
    if prev and prev.boot~=msg.boot then stopRing(r) end
    if not prev or prev.id~=id or prev.boot~=msg.boot then
      sensors[r]={id=id,boot=msg.boot,lastSeen=now(),valid=false}
    end
  elseif msg.kind=="POSE" then
    local prev=sensors[r]
    if prev and prev.id~=id and online(prev,6) then
      stopRing(r)
      sensorConflict[r]=true
      notes[r]="Dos sensores para el mismo anillo"
      return
    end
    if prev and prev.boot~=msg.boot then stopRing(r) end
    msg.id=id; msg.lastSeen=now()
    sensors[r]=msg
    notes[r]=msg.error
  end
end

local function networkLoop()
  while true do
    local id,msg=rednet.receive(PROTOCOL,0.2)
    if id then record(id,msg) end
  end
end

local function tickLoop()
  while true do
    rednet.broadcast({kind="HEARTBEAT"},PROTOCOL)
    for k,on in pairs(desired) do
      if on then
        local r,a=k:match("^(%d+)%-(%d+)$")
        r=tonumber(r); a=tonumber(a)
        local ok=validSlot(r,a)
        if ok then
          cmd(r,a,"run",true) -- renovar permiso cada ~0.4 segundos
        else
          stopAxis(r,a)
        end
      end
    end
    sleep(0.4)
  end
end

local function status()
  print("=== OMNIA - ESTADO ===")
  for r=1,3 do
    local count=0
    for a=1,4 do
      for _,role in ipairs({"stop","reverse"}) do
        if online(controllers[slot(r,a,role)]) then count=count+1 end
      end
    end
    local sn=sensors[r]
    local s=(online(sn,SENSOR_AGE) and sn.valid) and "SENSOR OK" or "SIN SENSOR"
    print(string.format("R%d: %d/8 controladores, %s",r,count,s))
    if sn and sn.position then print("  Pose "..fmt(sn.position)) end
  end
  local n=0
  for _,v in pairs(desired) do if v then n=n+1 end end
  print("Cabrestantes con permiso de marcha: "..n)
end

local function listControllers()
  for r=1,3 do
    print("=== ANILLO "..r.." ===")
    for a=1,4 do
      for _,role in ipairs({"stop","reverse"}) do
        local k=slot(r,a,role)
        local c=controllers[k]
        local st=online(c) and "OK" or "OFF"
        local id=c and tostring(c.id) or "?"
        print(k.." ID="..id.." "..st..(duplicate[k] and " DUPLICADO" or ""))
        if c and c.controllerPos then print("  PC "..fmt(c.controllerPos)) end
      end
    end
  end
end

-- Modelo espacial: 4 anclajes de techo por anillo y pose completa del subnivel.
-- No calcula distancias de cuerdas sin puntos de union LOCALES en cada anillo.
local function buildMap()
  local world={version=1, updatedUtcMs=os.epoch("utc"), rings={}}
  for r=1,3 do
    local s=sensors[r]
    local entry={ring=r, kind=({"grande","mediano","pequeno"})[r],
      pose=s and {valid=s.valid, position=s.position,
        orientation=s.orientation,rotationPoint=s.rotationPoint,
        linearVelocity=s.linearVelocity,angularVelocity=s.angularVelocity,
        uuid=s.uuid} or {valid=false}, cables={}}
    for a=1,4 do
      local st=controllers[slot(r,a,"stop")]
      local rev=controllers[slot(r,a,"reverse")]
      entry.cables[a]={axis=a,anchor=(st and st.anchor) or (rev and rev.anchor),
        stopID=st and st.id,reverseID=rev and rev.id,
        stopPosition=st and st.controllerPos,
        reversePosition=rev and rev.controllerPos,
        running=desired[key(r,a)]==true}
    end
    world.rings[r]=entry
  end
  return world
end

local function mostrarMapa()
  local m=buildMap()
  print("=== MAPA 3D (COORDENADAS X Y Z) ===")
  for _,r in ipairs(m.rings) do
    print("R"..r.ring.." - "..r.kind)
    print("  Pose  "..fmt(r.pose.position))
    print("  Vlineal "..fmt(r.pose.linearVelocity))
    print("  Vangular "..fmt(r.pose.angularVelocity))
    local q=r.pose.orientation
    if q then
      print(string.format("  Rotacion q(wxyz): %.3f %.3f %.3f %.3f",
        q.w or 0,q.x or 0,q.y or 0,q.z or 0))
    end
    for _,c in ipairs(r.cables) do
      print("  "..r.ring.."-"..c.axis.." WINCH "..fmt(c.anchor))
    end
    if notes[r.ring] then print("  AVISO: "..notes[r.ring]) end
  end
end

local function exportMap()
  local file="/omnia_mapa.json"
  local h=assert(fs.open(file,"w"))
  h.write(textutils.serializeJSON(buildMap()))
  h.close()
  print("Modelo 3D guardado en "..file)
end

local function parseAxis(word)
  local r,a=word and word:match("^(%d+)%-(%d+)$")
  r=tonumber(r); a=tonumber(a)
  if not r or not a or r<1 or r>3 or a<1 or a>4 then
    print("Usa un ID de cable de 1-1 a 3-4")
    return nil
  end
  return r,a
end

local function help()
  print("=== COMANDOS OMNIA ===")
  print("status       Resumen de los 3 anillos")
  print("list         Listar los 24 controladores")
  print("map          Posiciones y orientaciones 3D")
  print("export       Guardar /omnia_mapa.json")
  print("dir 1-1 up   Poner direccion normal (parado)")
  print("dir 1-1 down Poner direccion invertida (parado)")
  print("run 1-1      Mover ESE cabrestante")
  print("stop 1-1     Parar ESE cabrestante")
  print("estop        PARADA DE TODOS")
  print("reset        Rearmar despues de estop")
  print("exit         Parar todo y salir")
  print("IMPORTANTE: up/down son etiquetas por calibrar.")
end

local function interface()
  term.clear()
  term.setCursorPos(1,1)
  print("OMNIA - CONSOLA CENTRAL")
  print("ID CONSOLA: "..os.getComputerID())
  print("Todos los motores arrancan detenidos.")
  help()
  while true do
    write("\nOMNIA> ")
    local line=read()
    if not line then return end
    local parts={}
    for word in line:gmatch("%S+") do parts[#parts+1]=word end
    local op=parts[1]
    if op=="help" then help()
    elseif op=="status" then status()
    elseif op=="list" then listControllers()
    elseif op=="map" then mostrarMapa()
    elseif op=="export" then exportMap()
    elseif op=="estop" then estop(); print("PARADA GENERAL ENVIADA")
    elseif op=="reset" then
      desired={}
      rednet.broadcast({kind="RESET"},PROTOCOL)
      for _,n in pairs(controllers) do send(n.id,{kind="RESET"}) end
      print("Rearme enviado; comprobar status y luego mover")
    elseif op=="exit" then return
    elseif op=="stop" then
      local r,a=parseAxis(parts[2]); if r then stopAxis(r,a); print("STOP "..key(r,a)) end
    elseif op=="run" then
      local r,a=parseAxis(parts[2])
      if r then
        local ok,reason=validSlot(r,a)
        if ok then
          desired[key(r,a)]=true
          print("Permiso de marcha: "..key(r,a).." (usa stop para parar)")
        else print("NO SE PUEDE ARRANCAR: "..reason) end
      end
    elseif op=="dir" then
      local r,a=parseAxis(parts[2])
      if r then
        if parts[3]~="up" and parts[3]~="down" then
          print("Utiliza 'up' o 'down'")
        elseif desired[key(r,a)] then
          print("Primero escribe stop "..key(r,a))
        else
          local stopper=controllers[slot(r,a,"stop")]
          local reverser=controllers[slot(r,a,"reverse")]
          if not online(stopper) or not online(reverser) then
            print("Falta controlador STOP o REVERSE")
          elseif stopper.running then
            print("STOP todavia no confirmado; espera y reintenta")
          else
            cmd(r,a,"reverse",parts[3]=="down")
            print("Direccion solicitada: "..parts[3].." (CALIBRAR)")
          end
        end
      end
    elseif op==nil then
      -- entrada vacia
    else
      print("Comando desconocido. Escribe help")
    end
  end
end

local ok,err=pcall(function()
  parallel.waitForAny(interface,networkLoop,tickLoop)
end)
estop()
if not ok then print("ERROR CONSOLA: "..tostring(err)) end
