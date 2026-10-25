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

