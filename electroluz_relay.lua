-- ELECTROLUZ RELAY - CC:Tweaked + Create Crafts & Additions
-- Mide getThroughput() de Redstone Relay, NO usa acumuladores.
-- IMPORTANTE: conversion FE/t por defecto; validar en la version del mod.
-- Conexion: todo el suministro del cliente debe pasar por UN relay medido.
local C = {
  pago="right", caja="bottom", medidor="left", salida="top",
  fe_por_moneda=10000, intervalo=0.10, ticks_por_segundo=20,
  margen_ticks=4, -- corta antes del limite para compensar latencia, ajustable
  moneda="lightmanscurrency:coin_netherite", nombre="ELECTROLUZ"
}
local CFG="/electroluz_relay.cfg"
if fs.exists(CFG) then
  local f=fs.open(CFG,"r")
  if f then
    local ok,v=pcall(textutils.unserialize,f.readAll());f.close()
    if ok and type(v)=="table" then
      for k,x in pairs(v) do if C[k]~=nil and type(x)==type(C[k]) then C[k]=x end end
    end
  end
end
local function guardar()
  local f=assert(fs.open(CFG,"w"));f.write(textutils.serialize(C));f.close()
end
local function cortar() redstone.setOutput(C.salida,false) end
local function abrir() redstone.setOutput(C.salida,true) end
local function inventario(lado)
  local p=peripheral.wrap(lado)
  if p and type(p.list)=="function" and type(p.pushItems)=="function" then return p end
end
local function medidor()
  local p=peripheral.wrap(C.medidor)
  if p and type(p.getThroughput)=="function" then return p end
  return nil
end
local function flujo(p)
  local ok,n=pcall(p.getThroughput)
  if not ok or type(n)~="number" or n~=n or n<0 or n==math.huge then return nil end
  return n
end
local function contar(inv)
  local n=0
  for _,it in pairs(inv.list()) do if it.name==C.moneda then n=n+it.count end end
  return n
end
local function mover(origen,destino,cuantos)
  local n=0
  local nombre=peripheral.getName(destino)
  for slot,it in pairs(origen.list()) do
    if n>=cuantos then break end
    if it.name==C.moneda then
      local ok,cantidad=pcall(origen.pushItems,nombre,slot,math.min(it.count,cuantos-n))
      if not ok then break end
      n=n+(cantidad or 0)
    end
  end
  return n
end
local function pantalla(estado,credito,fe,coste,tasa,mensaje)
  term.setBackgroundColor(colors.black);term.setTextColor(colors.white)
  term.clear();term.setCursorPos(1,1)
  print("=== "..C.nombre.." ===")
  print("ESTADO: "..estado)
  print("CREDITO: "..credito.." monedas")
  print("FLUJO: "..string.format("%.1f",tasa or 0).." FE/t [estimado]")
  print("ENTREGADO: "..math.floor(fe).." FE [estimado]")
  print("COBRADO: "..coste.." monedas")
  print("RESTANTE: "..math.max(0,credito-coste).." monedas")
  print("PRECIO: "..C.fe_por_moneda.." FE/moneda")
  print(mensaje or "")
  print("F: iniciar/parar  C: administrar")
end
local function esperar(t)
  local timer=os.startTimer(t)
  while true do
    local e,a=os.pullEvent()
    if e=="key" and a==keys.f then return "stop" end
    if e=="timer" and a==timer then return "tick" end
  end
end
local function editar()
  cortar();term.clear();term.setCursorPos(1,1)
  write("PIN: ");if read("*")~="2050" then return end
  print("FE por moneda ("..C.fe_por_moneda.."): ")
  local n=tonumber(read())
  if n and n>=1 and n==math.floor(n) then C.fe_por_moneda=n;guardar() end
end
local function devolver(pago,caja,pendiente,credito,fe,coste)
  while pendiente>0 do
    local n=mover(caja,pago,pendiente);pendiente=pendiente-n
    if pendiente>0 then
      pantalla("CAMBIO PENDIENTE",credito,fe,coste,0,"Libera espacio en barril de pago")
      sleep(0.5)
    end
  end
end
local function sesion(pago,caja,relay,credito)
  local inicio=flujo(relay)
  if not inicio then pantalla("ERROR MEDIDOR",credito,0,0,0,"Relay sin lectura");sleep(2);return end
  -- Reservar antes de abrir.
  local movidas=mover(pago,caja,credito)
  if movidas~=credito then
    if movidas>0 then devolver(pago,caja,movidas,credito,0,0) end
    pantalla("ERROR PAGO",credito,0,0,0,"No puedo reservar monedas");sleep(2);return
  end
  local fe=0
  local coste=0
  local ultimo=os.epoch("utc")
  local razon="FINALIZADO"
  abrir()
  while true do
    local respuesta=esperar(C.intervalo)
    local ahora=os.epoch("utc")
    local delta=math.max(0,math.min((ahora-ultimo)/1000,1))
    ultimo=ahora
    local tasa=flujo(relay)
    if tasa==nil then razon="ERROR LECTURA";break end
    -- Interpretacion provisional: throughput expresado en FE/t.
    -- No facturar sin verificar esta interpretacion en el mod instalado.
    fe=fe+tasa*delta*C.ticks_por_segundo
    coste=math.min(credito,math.ceil(fe/C.fe_por_moneda))
    pantalla("SUMINISTRANDO",credito,fe,coste,tasa,"F para cortar")
    if respuesta=="stop" then razon="DETENIDO";break end
    local restante=credito*C.fe_por_moneda-fe
    if restante<=tasa*C.margen_ticks then razon="LIMITE DE CREDITO";break end
  end
  cortar()
  -- No se contabiliza el flujo posterior al cierre sin confirmacion de aislamiento.
  local cambio=credito-coste
  devolver(pago,caja,cambio,credito,fe,coste)
  pantalla(razon,credito,fe,coste,0,"Cambio: "..cambio.." monedas")
  sleep(3)
end
local function principal()
  cortar()
  while true do
    local pago=inventario(C.pago)
    local caja=inventario(C.caja)
    local relay=medidor()
    if not pago or not caja or not relay then
      pantalla("FALTA PERIFERICO",0,0,0,0,"Comprueba pago, caja y relay")
    else
      local tasa=flujo(relay)
      local saldo=contar(pago)
      pantalla(tasa and (saldo>0 and "LISTO" or "ESPERANDO PAGO") or "ERROR MEDIDOR",saldo,0,0,tasa or 0,"Sin acumulador")
    end
    local e,k=os.pullEvent()
    if e=="key" and k==keys.c then editar() end
    if e=="key" and k==keys.f and pago and caja and relay and flujo(relay) and contar(pago)>0 then
      sesion(pago,caja,relay,contar(pago))
    end
  end
end
local ok,errorMsg=pcall(principal)
cortar()
if not ok then print("ERROR: "..tostring(errorMsg)) end
