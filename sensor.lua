-- OMNIA / sensor.lua (CC: Sable + CC: Tweaked)
-- ESTE ORDENADOR DEBE FORMAR PARTE DEL ANILLO FISICO (sublevel).
local PROTOCOL="omnia.v1"
local CONFIG_FILE="/omnia_sensor.cfg"

local function pedirNum(titulo, min, max)
  while true do
    write(titulo .. ": ")
    local n=tonumber(read())
    if n and n%1==0 and n>=min and n<=max then return n end
    print("Numero no valido")
  end
end

local function cargar()
  if fs.exists(CONFIG_FILE) then
    local h=assert(fs.open(CONFIG_FILE,"r"))
    local cfg=textutils.unserialize(h.readAll()); h.close()
    assert(type(cfg)=="table" and cfg.ring and cfg.master,"Config corrupta")
    return cfg
  end
  print("OMNIA - PRIMER ARRANQUE SENSOR")
  local cfg={ring=pedirNum("Anillo (1 grande, 2 mediano, 3 pequeno)",1,3),
             master=pedirNum("ID ordenador consola",0,65535)}
  local h=assert(fs.open(CONFIG_FILE,"w"))
  h.write(textutils.serialize(cfg)); h.close()
  return cfg
end

local cfg=cargar()
local id=os.getComputerID()
local boot=tostring(os.epoch("utc")).."-"..id

for _,name in ipairs(peripheral.getNames()) do
  if peripheral.hasType(name,"modem") then rednet.open(name) end
end
assert(rednet.isOpen(),"Conecta un modem al sensor")
assert(type(sublevel)=="table","Falta CC: Sable (API sublevel)")

-- Convertir userdata/tablas con metatablas a numeros simples para Rednet.
local function v3(v)
  if not v then return nil end
  return {x=tonumber(v.x),y=tonumber(v.y),z=tonumber(v.z)}
end
local function quat(q)
  if not q then return nil end
  return {w=tonumber(q.w or q.r or q[1]),
          x=tonumber(q.x or q.i or q[2]),
          y=tonumber(q.y or q.j or q[3]),
          z=tonumber(q.z or q.k or q[4])}
end

local function muestra()
  if not sublevel.isInPlotGrid() then
    return {valid=false, error="Ordenador fuera de sublevel"}
  end
  local pose=sublevel.getLogicalPose()
  local s={valid=true, position=v3(pose.position),
           orientation=quat(pose.orientation),
           rotationPoint=v3(pose.rotationPoint),
           scale=v3(pose.scale),
           linearVelocity=v3(sublevel.getLinearVelocity()),
           angularVelocity=v3(sublevel.getAngularVelocity()),
           uuid=sublevel.getUniqueId()}
  if not s.position or s.position.x==nil then
    s.valid=false; s.error="Posicion no disponible"
  end
  return s
end

print("OMNIA SENSOR R"..cfg.ring.." ID "..id)
print("Leyendo pose 4 veces por segundo")
local lastHello=-1e20
while true do
  local now=os.epoch("utc")/1000
  if now-lastHello>2 then
    rednet.send(cfg.master,{kind="SENSOR_HELLO",ring=cfg.ring,id=id,boot=boot},PROTOCOL)
    lastHello=now
  end
  local ok,s=pcall(muestra)
  if not ok then s={valid=false,error=tostring(s)} end
  s.kind="POSE"; s.ring=cfg.ring; s.id=id; s.boot=boot
  rednet.send(cfg.master,s,PROTOCOL)
  sleep(0.25)
end
