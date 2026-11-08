-- OMNIA / controlador.lua (CC: Tweaked)
-- Un ordenador por funcion y por cable: STOP o REVERSE.
-- IMPORTANTE: STOP utiliza una antorcha inversora: salida 0 = clutch ENCENDIDO (parado).
local PROTOCOL = "omnia.v1"
local CONFIG_FILE = "/omnia_controlador.cfg"
local TIMEOUT = 1.6 -- segundos sin permiso de marcha => STOP

local function pedir(texto, validator)
  while true do
    write(texto .. ": ")
    local val = read()
    if not validator or validator(val) then return val end
    print("Valor no valido, vuelve a intentarlo.")
  end
end

local function coord(texto)
  return tonumber(pedir(texto, function(v) return tonumber(v) ~= nil end))
end

local function vec3(x,y,z) return {x=x, y=y, z=z} end

local function configurar()
  term.clear()
  term.setCursorPos(1,1)
  print("OMNIA - PRIMER ARRANQUE CONTROLADOR")
  print("1 = anillo grande | 3 = pequeno")
  local r = tonumber(pedir("Anillo (1-3)", function(v) return tonumber(v) and tonumber(v)>=1 and tonumber(v)<=3 and tonumber(v)%1==0 end))
  local a = tonumber(pedir("Eje/cable (1-4)", function(v) return tonumber(v) and tonumber(v)>=1 and tonumber(v)<=4 and tonumber(v)%1==0 end))
  local role = pedir("Funcion (parar / direccion)", function(v) return v=="parar" or v=="direccion" end)
  role = (role=="parar") and "stop" or "reverse"
  local sides = {top=true, bottom=true, front=true, back=true, left=true, right=true}
  local side = pedir("Lado salida redstone", function(v) return sides[v] end)
  local master = tonumber(pedir("ID ordenador consola", function(v) return tonumber(v) and tonumber(v)>=0 and tonumber(v)%1==0 end))
  print("Introduce COORDENADAS DEL CABRESTANTE")
  print("(bloque Rope Winch, NO del ordenador)")
  local anchor = vec3(coord("X winch"), coord("Y winch"), coord("Z winch"))
  local pos = nil
  print("Buscando posicion del ordenador por GPS...")
  local ok, x,y,z = pcall(gps.locate, 1)
  if ok and x then
    pos = vec3(x,y,z)
    print("GPS: "..x..", "..y..", "..z)
  else
    print("Sin GPS: introduce las coords del ORDENADOR")
    pos = vec3(coord("X ordenador"),coord("Y ordenador"),coord("Z ordenador"))
  end
  local cfg = {ring=r, axis=a, role=role, side=side, master=master,
               anchor=anchor, controllerPos=pos}
  local h=assert(fs.open(CONFIG_FILE,"w"))
  h.write(textutils.serialize(cfg)); h.close()
  return cfg
end

local function cargar()
  if not fs.exists(CONFIG_FILE) then return configurar() end
  local h=assert(fs.open(CONFIG_FILE,"r"))
  local cfg=textutils.unserialize(h.readAll()); h.close()
  assert(type(cfg)=="table" and cfg.role and cfg.master, "Configuracion corrupta")
  return cfg
end

local cfg=cargar()
local id=os.getComputerID()
local boot=tostring(os.epoch("utc")) .. "-" .. tostring(id)
local running=false
local reverse=false
local tripped=false
local lastRun=-1e20
local lastHeartbeat=-1e20
local lastHello=-1e20
local lastReport=-1e20

local function apply()
  if cfg.role=="stop" then
    -- INVERSOR obligatorio: salida false => antorcha ON => clutch ON => STOP
    redstone.setOutput(cfg.side, running)
  else
    redstone.setOutput(cfg.side, reverse)
  end
end

local function safe()
  -- No tocar la direccion en una parada: hacerlo podria invertir un motor
  -- que aun no se haya desacoplado por latencia en otro ordenador.
  if cfg.role=="stop" then running=false; lastRun=-1e20 end
  apply()
end
safe()

local function abrirModems()
  for _,name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name,"modem") then rednet.open(name) end
  end
  assert(rednet.isOpen(), "Conecta al menos un modem")
end
abrirModems()

local function send(kind)
  rednet.send(cfg.master, {
    kind=kind, id=id, boot=boot, role=cfg.role, ring=cfg.ring, axis=cfg.axis,
    anchor=cfg.anchor, controllerPos=cfg.controllerPos,
    running=running, reverse=reverse, tripped=tripped, side=cfg.side
  }, PROTOCOL)
end

local function loop()
  print("OMNIA " .. cfg.ring .. "-" .. cfg.axis .. " " .. cfg.role)
  print("ID: "..id .."  CONSOLA: "..cfg.master)
  print("Modo seguro activado")
  while true do
    local now=os.epoch("utc")/1000
    if cfg.role=="stop" and running and
       (now-lastRun>TIMEOUT or now-lastHeartbeat>TIMEOUT) then
      safe(); send("STATUS")
    end
    if now-lastHello>2 then send("HELLO"); lastHello=now end
    if now-lastReport>1 then send("STATUS"); lastReport=now end

    local sender, msg=rednet.receive(PROTOCOL,0.15)
    if sender==cfg.master and type(msg)=="table" then
      local time=os.epoch("utc")/1000
      if msg.kind=="HEARTBEAT" then
        lastHeartbeat=time
      elseif msg.kind=="ESTOP" then
        tripped=true; safe(); send("STATUS")
      elseif msg.kind=="RESET" then
        tripped=false; safe(); send("STATUS")
      elseif msg.kind=="SET" and msg.ring==cfg.ring and msg.axis==cfg.axis then
        if msg.action=="run" and cfg.role=="stop" then
          -- Arrancar solo si la consola sigue viva y renueva el permiso.
          running=(msg.value==true) and not tripped and (time-lastHeartbeat<TIMEOUT)
          if running then lastRun=time end
          apply(); send("STATUS")
        elseif msg.action=="reverse" and cfg.role=="reverse" then
          if not tripped then
            reverse=(msg.value==true)
            apply()
          end
          send("STATUS")
        end
      end
    end
  end
end

local ok,err=pcall(loop)
safe()
if not ok then print("ERROR: "..tostring(err)) end
