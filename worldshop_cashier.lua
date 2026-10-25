-- WorldShop 1.0 | Cajero de monedas fisicas Lightman's Currency
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
local conf=load(CFG)
if not conf then
  print('=== WorldShop / Configurar Cajero ===')
  print('Desde el servidor: opcion [C]ajero. Autoriza')
  print('este computer ID ('..os.getComputerID()..') y copia la clave.')
  write('Clave secreta: ');local secret=read()
  inventoryList()
  write('Inventario de DEPOSITO (ej: minecraft:chest_0): ');local inp=read()
  write('Inventario CAJA FUERTE (ej: minecraft:chest_1): ');local vault=read()
  conf={key=secret,input=inp,vault=vault,coins=coins}
  save(CFG,conf)
end
local function inventory(name)
  if not peripheral.isPresent(name) or not peripheral.hasType(name,'inventory') then return nil end
  return peripheral.wrap(name)
end
if conf.input==conf.vault then printError('Los dos inventarios deben ser distintos');return end
local seq=0;math.randomseed((os.epoch('utc')+os.getComputerID())%2147483647)
local server=rednet.lookup(P,HOST)
local function rpc(op,content)
  if not server then server=rednet.lookup(P,HOST) end
  if not server then return {ok=false,error='Servidor WorldShop no encontrado'} end
  seq=seq+1
  local id=tostring(os.getComputerID())..'-'..os.epoch('utc')..'-'..seq..'-'..math.random(10000,99999)
  content=content or {};content.v=1;content.op=op;content.req=id;content.key=conf.key
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
local pending=load(JOURNAL) or {}
local function syncPending()
  if #pending==0 then return end
  print('Enviando '..#pending..' deposito(s) pendientes...')
  for i=#pending,1,-1 do
    local t=pending[i]
    local r=rpc('ATM_CREDIT',{code=t.code,tx=t.id,amount=t.amount})
    if r.ok then
      print('Confirmado: '..t.user..' +'..t.amount..' WS$')
      table.remove(pending,i);save(JOURNAL,pending)
    else printError('Pendiente '..t.id..': '..tostring(r.error)) end
  end
end
local function deposits()
  local inp,vault=inventory(conf.input),inventory(conf.vault)
  if not inp or not vault then printError('No se encuentran los cofres/perifericos; revisa los cables.');return end
  if #pending>0 then syncPending();if #pending>0 then printError('Resuelve los depositos pendientes primero.');return end end
  write('Codigo del ticket WorldShop: ');local code=read()
  local check=rpc('ATM_VERIFY',{code=code})
  if not check.ok then printError(check.error);return end
  print('Cuenta: '..check.user)
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
  pending[#pending+1]={id=tx,code=code,user=check.user,amount=moved}
  save(JOURNAL,pending)
  print('Transferidas monedas por '..moved..' WS$.')
  syncPending()
  if #pending==0 then print('DEPOSITO COMPLETADO.') else printError('Dinero almacenado, credito PENDIENTE. Guarda este ordenador.') end
end
while true do
  term.setBackgroundColor(colors.black);term.setTextColor(colors.white);term.clear()
  print('==============================')
  term.setTextColor(colors.cyan);print('       WORLDSHOP BANK')
  term.setTextColor(colors.white);print('==============================')
  print('ID de cajero: '..os.getComputerID())
  print('Entrada: '..conf.input)
  print('Boveda: '..conf.vault)
  print('Pendientes: '..#pending)
  print('')
  print('[1] Depositar monedas Lightman')
  print('[2] Reintentar credito pendiente')
  print('[3] Ver valores de monedas')
  print('[4] Ver inventarios')
  print('[0] Salir')
  write('> ');local c=read()
  if c=='0' then break
  elseif c=='1' then deposits()
  elseif c=='2' then syncPending()
  elseif c=='3' then for item,v in pairs(conf.coins) do print(item..' = '..v..' WS$') end
  elseif c=='4' then inventoryList() end
  print('\nPulsa ENTER para continuar');read()
end
