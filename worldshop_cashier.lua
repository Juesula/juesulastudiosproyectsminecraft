-- WorldShop 3.2 | Cajero automatico de monedas fisicas Lightman's Currency
-- Requiere dos inventarios conectados por modems CON CABLE: entrada y caja fuerte.
local P,HOST='worldshop.v1','worldshop'
local CFG='worldshop_cashier.cfg'
local JOURNAL='worldshop_cashier_pending'
local function save(path,obj)
  local h=assert(fs.open(path,'w'));h.write(textutils.serialize(obj));h.close()
end
local function load(path)
  if not fs.exists(path) then return nil end
  local h=fs.open(path,'r');local data=textutils.unserialize(h.readAll());h.close();return data
end
local modems=0
for _,n in ipairs(peripheral.getNames()) do
  if peripheral.hasType(n,'modem') then rednet.open(n);modems=modems+1 end
end
if modems==0 then printError('Conecta un modem');return end
local coins={
  ['lightmanscurrency:coin_copper']=1,
  ['lightmanscurrency:coin_iron']=10,
  ['lightmanscurrency:coin_gold']=100,
  ['lightmanscurrency:coin_emerald']=1000,
  ['lightmanscurrency:coin_diamond']=10000,
  ['lightmanscurrency:coin_netherite']=100000,
}
local function inventoryList()
  print('Inventarios visibles (tienen que estar conectados por cable):')
  for _,name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name,'inventory') then print(' - '..name) end
  end
end
-- Conserva la configuracion anterior, pero permite primera instalacion sin clave
-- ni nombres tecnicos de perifericos.
local conf=load(CFG) or {}
if type(conf)~='table' then conf={} end
if type(conf.coins)~='table' then conf.coins=coins end
local function inventory(name)
  if not name or name=='' or not peripheral.isPresent(name) or not peripheral.hasType(name,'inventory') then return nil end
  return peripheral.wrap(name)
end
local function knownBarrels()
  local names={}
  for _,name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name,'inventory') then names[#names+1]=name end
  end
  table.sort(names)
  return names
end
local function useBarrels(inp,vault)
  if inp==vault or not inventory(inp) or not inventory(vault) then return false end
  conf.input,conf.vault=inp,vault
  save(CFG,conf)
  return true
end
local function barrelsReady()
  if conf.input and conf.vault and conf.input~=conf.vault and inventory(conf.input) and inventory(conf.vault) then return true end
  -- Solo puede deducirse la posicion si el ordenador los expone como lados.
  if inventory('right') and inventory('bottom') then return useBarrels('right','bottom') end
  return false
end
local function itemCount(name)
  local inv=inventory(name)
  if not inv then return nil end
  local ok,items=pcall(function() return inv.list() end)
  if not ok or type(items)~='table' then return nil end
  local count=0
  for _,it in pairs(items) do if type(it)=='table' then count=count+(tonumber(it.count) or 0) end end
  return count
end
local function configureBarrels()
  if barrelsReady() then return true end
  local names=knownBarrels()
  print('=== WorldShop | Calibracion automatica ===')
  print('El cajero necesita ver los DOS barriles por modem con CABLE.')
  if #names~=2 then
    printError('Se detectan '..#names..' inventarios. Deben aparecer exactamente 2.')
    inventoryList()
    print('Comprueba los cables y desconecta cofres adicionales.')
    return false
  end
  print('No hace falta escribir nombres de perifericos.')
  print('El modem cableado no indica cual barril esta a la derecha.')
  local before={}
  for _,n in ipairs(names) do before[n]=itemCount(n) end
  if before[names[1]]==nil or before[names[2]]==nil then
    printError('No se pueden leer los barriles.');return false
  end
  for attempt=1,3 do
    print('PON AHORA una moneda u objeto EXTRA en el BARRIL DERECHO.')
    print('No toques el barril de abajo. Pulsa ENTER despues.')
    read()
    local changed={}
    for _,n in ipairs(names) do
      local after=itemCount(n)
      if after==nil then printError('Barril desconectado');return false end
      if after>before[n] then changed[#changed+1]=n end
      before[n]=after
    end
    if #changed==1 then
      local inp=changed[1]
      local vault=names[1]==inp and names[2] or names[1]
      if useBarrels(inp,vault) then
        print('BARRILES LISTOS: entrada a la derecha, boveda abajo.')
        return true
      end
    end
    printError('No se ha detectado una unica entrada; vuelve a intentarlo.')
  end
  return false
end
local seq=0;math.randomseed((os.epoch('utc')+os.getComputerID())%2147483647)
local server=rednet.lookup(P,HOST)
local paired=false
local function rpc(op,content)
  if op~='ATM_PAIR' and not paired then
    local link=rpc('ATM_PAIR',{})
    if not link.ok then return link end
    if type(link.key)~='string' or #link.key<10 then return {ok=false,error='Enlace del cajero invalido'} end
    conf.key=link.key;paired=true;save(CFG,conf)
  end
  if not server then server=rednet.lookup(P,HOST) end
  if not server then return {ok=false,error='Servidor WorldShop no encontrado'} end
  seq=seq+1
  local id=tostring(os.getComputerID())..'-'..os.epoch('utc')..'-'..seq..'-'..math.random(10000,99999)
  content=content or {};content.v=1;content.op=op;content.req=id
  if op~='ATM_PAIR' then content.key=conf.key end
  for _=1,3 do
    rednet.send(server,content,P)
    local deadline=os.epoch('utc')+4000
    repeat
      local sid,r=rednet.receive(P,math.max(0,(deadline-os.epoch('utc'))/1000))
      if not sid then break end
      if sid==server and type(r)=='table' and r.req==id and r.v==1 then return r end
    until os.epoch('utc')>=deadline
  end
  return {ok=false,error='No responde el servidor'}
end
-- Si el servidor arranca mas tarde, se reintenta el enlace al iniciar sesion.
local link=rpc('ATM_PAIR',{})
if link.ok and type(link.key)=='string' and #link.key>=10 then
  conf.key=link.key;paired=true;save(CFG,conf)
else
  print('Enlace pendiente: '..tostring(link.error or 'servidor no disponible'))
end
local pending=load(JOURNAL) or {}
local auth=nil;local loginName=nil;local loginBalance=0
local function syncPending()
  if #pending==0 then return end
  print('Enviando '..#pending..' deposito(s) pendientes...')
  for i=#pending,1,-1 do
    local t=pending[i]
    local r=rpc('ATM_CREDIT',{code=t.code,auth=t.auth,tx=t.id,amount=t.amount})
    if r.ok then
      print('Confirmado: '..t.user..' +'..t.amount..' WS$')
      if loginName==t.user then loginBalance=r.balance or (loginBalance+t.amount) end
      table.remove(pending,i);save(JOURNAL,pending)
    else printError('Pendiente '..t.id..': '..tostring(r.error)) end
  end
end
local function deposits()
  if not barrelsReady() and not configureBarrels() then return end
  local inp,vault=inventory(conf.input),inventory(conf.vault)
  if not inp or not vault then printError('No se encuentran los barriles; revisa los cables.');return end
  if #pending>0 then syncPending();if #pending>0 then printError('Resuelve los depositos pendientes primero.');return end end
  if not auth or not loginName then printError('Primero inicia sesion desde el panel');return end
  print('Cuenta: @'..loginName)
  print('Introduce MONEDAS en el cofre de entrada.')
  print('El cofre de la caja fuerte debe estar protegido.')
  print('Tras contar y confirmar, se moveran fisicamente.')
  write('Pulsa ENTER para contar...');read()
  local manifest,total={},0
  local found=inp.list()
  for slot,item in pairs(found) do
    local value=conf.coins[item.name]
    if value then
      manifest[#manifest+1]={slot=slot,name=item.name,count=item.count,value=value}
      total=total+item.count*value
    end
  end
  if total<=0 then printError('No hay monedas reconocidas.');return end
  print('Monedas:')
  for _,it in ipairs(manifest) do print('  '..it.count..' x '..it.name..' = '..(it.count*it.value)) end
  print('Total previsto: '..total..' WS$')
  write('CONFIRMAR transferencia? (SI): ')
  if read():upper()~='SI' then print('Cancelado.');return end
  -- Solo los objetos transferidos realmente dan saldo.
  local moved=0
  for _,it in ipairs(manifest) do
    local ok,num=pcall(function() return inp.pushItems(conf.vault,it.slot,it.count) end)
    if ok and type(num)=='number' and num>0 then moved=moved+num*it.value
    else printError('No se pudieron transferir las monedas de slot '..it.slot) end
  end
  if moved<=0 then printError('No se movieron monedas; saldo sin cambios');return end
  local tx=tostring(os.getComputerID())..'-'..tostring(os.epoch('utc'))..'-'..math.random(10000,99999)
  -- Se guarda el recibo antes de solicitar saldo. Reintentos son idempotentes.
  pending[#pending+1]={id=tx,auth=auth,user=loginName,amount=moved}
  save(JOURNAL,pending)
  auth=nil -- Cada autorizacion es para un solo deposito.
  print('Transferidas monedas por '..moved..' WS$.')
  syncPending()
  if #pending==0 then print('DEPOSITO COMPLETADO.') else printError('Dinero almacenado, credito PENDIENTE. Guarda este ordenador.') end
end
local function login()
  term.setBackgroundColor(colors.black);term.clear()
  term.setTextColor(colors.cyan);print('     WORLDSHOP / ACCESO AL CAJERO')
  term.setTextColor(colors.white)
  print('');write('Usuario WorldShop: ');local name=(read() or ''):lower()
  if name=='' then return false end
  write('Contrasena: ');local pass=read('*')
  local r=rpc('ATM_LOGIN',{user=name,pass=pass})
  pass=nil
  if not r.ok then printError('Acceso denegado: '..tostring(r.error));return false end
  loginName=r.user;auth=r.auth;loginBalance=r.balance or 0
  return true
end
local function label(y,str,fg,bg)
  local w,h=term.getSize();if y<1 or y>h then return end
  term.setBackgroundColor(bg or colors.black);term.setTextColor(fg or colors.white)
  term.setCursorPos(1,y);str=tostring(str or '')
  term.write(str:sub(1,w)..(' '):rep(math.max(0,w-#str)))
end
local function dashboard()
  local w,h=term.getSize()
  term.setBackgroundColor(colors.black);term.clear()
  label(1,'  WS  WORLDSHOP  |  CAJERO',colors.white,colors.blue)
  label(2,'  ID '..os.getComputerID()..(paired and '  * CONECTADO' or '  * ENLACE PENDIENTE'),colors.white,colors.gray)
  label(4,loginName and ('  SESION: @'..loginName..'  |  '..loginBalance..' WS$') or '  SIN SESION INICIADA',loginName and colors.lime or colors.orange)
  label(6,'  [BARRIL DERECHA]  INGRESAR MONEDAS',colors.white,colors.green)
  label(7,'  '..(conf.input or 'Pendiente de calibrar'),colors.lightGray)
  label(9,'  [BARRIL ABAJO]    GUARDAR MONEDAS',colors.white,colors.blue)
  label(10,'  '..(conf.vault or 'Pendiente de calibrar'),colors.lightGray)
  label(12,'  PENDIENTES: '..#pending..'  |  [1] INGRESAR',colors.yellow)
  label(13,'  [2] Iniciar sesion / Cambiar usuario',colors.white)
  label(14,'  [3] Reintentar ingreso pendiente',colors.white)
  if h>=18 then label(16,'  [4] Monedas [5] Lista [6] Calibrar',colors.cyan) end
  label(h-1,'  [0] Apagar   |   Click en opciones',colors.lightGray,colors.gray)
  label(h,'  World Studios  *  WorldShop ATM 3.1',colors.white,colors.blue)
  while true do
    local ev,a,x,y=os.pullEvent()
    if ev=='monitor_touch' then ev,a,x,y='mouse_click',1,x,y end
    if ev=='char' and a:match('[0-6]') then return a
    elseif ev=='mouse_click' then
      if y==12 then return '1' elseif y==13 then return '2'
      elseif y==14 then return '3' elseif y==16 then return x<w/3 and '4' or (x<2*w/3 and '5' or '6')
      elseif y==h-1 then return '0' end
    end
  end
end
while true do
  local c=dashboard()
  if c=='0' then break
  elseif c=='1' then
    if not auth then login() end
    if auth then deposits() end
  elseif c=='2' then auth=nil;loginName=nil;login()
  elseif c=='3' then syncPending()
  elseif c=='4' then for item,v in pairs(conf.coins) do print(item..' = '..v..' WS$') end
  elseif c=='5' then inventoryList()
  elseif c=='6' then
    inventoryList()
    print('BARRIL DERECHO = entrada; BARRIL ABAJO = boveda.')
    print('Pulsa ENTER para detectar/calibrar automaticamente.')
    print('Escribe M para configurar nombres a mano (avanzado).')
    local mode=(read() or ''):lower()
    if mode=='m' then
      write('Nombre periferico BARRIL DERECHO: ');local inp=read()
      write('Nombre periferico BARRIL ABAJO: ');local vault=read()
      if useBarrels(inp,vault) then print('Configuracion guardada')
      else printError('Perifericos incorrectos o identicos') end
    else
      -- Fuerza una nueva identificacion si el usuario ha cambiado cables.
      conf.input=nil;conf.vault=nil
      configureBarrels()
    end
  end
  if c~='0' then
    print('');term.setTextColor(colors.lightGray);print('Pulsa ENTER para volver al panel...');read()
  end
end