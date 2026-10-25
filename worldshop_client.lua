-- WorldShop 1.0 | Tienda para jugadores, CC:Tweaked
local P, HOST = 'worldshop.v1', 'worldshop'
local server, token, user, balance, dev=nil,nil,nil,0,false
local ready=false
for _,n in ipairs(peripheral.getNames()) do
  if peripheral.hasType(n,'modem') then rednet.open(n);ready=true end
end
if not ready then printError('WorldShop: conecta un modem.');return end
math.randomseed((os.epoch('utc')+os.getComputerID())%2147483647)
local function col(c) if term.isColor() then term.setTextColor(c) end end
local function bg(c) if term.isColor() then term.setBackgroundColor(c) end end
local function line(y,str,c)
  local w,h=term.getSize();if y<1 or y>h then return end
  term.setCursorPos(1,y);bg(colors.black);col(c or colors.white)
  str=tostring(str or '')
  term.write(str:sub(1,w)..string.rep(' ',math.max(0,w-#str)))
end
local function screen(title,sub)
  local w=term.getSize();bg(colors.black);term.clear()
  line(1,string.rep('=',w),colors.cyan)
  line(2,' WORLDSHOP / '..title,colors.lightBlue)
  line(3,string.rep('-',w),colors.gray)
  if sub then line(4,' '..sub,colors.yellow) end
  local _,h=term.getSize();line(h,'  World Studios  |  WorldShop v1.0',colors.gray)
  term.setCursorPos(1,5);col(colors.white)
end
local function waitkey()
  print('');col(colors.lightGray);print('Pulsa ENTER para volver...');read()
end
local function ask(prompt,default)
  col(colors.lightBlue);write(prompt);col(colors.white)
  local v=read();if v=='' and default then return default end;return v
end
local function intro()
  bg(colors.black);term.clear();local w,h=term.getSize()
  local s='WORLD STUDIOS';local x=math.max(1,math.floor((w-#s)/2)+1)
  col(colors.cyan)
  for i=1,#s do term.setCursorPos(x+i-1,math.floor(h/2)-1);term.write(s:sub(i,i));sleep(0.035) end
  line(math.floor(h/2)+1,'             presenta: WORLDSHOP',colors.white)
  sleep(0.5)
end
local function locate()
  server=rednet.lookup(P,HOST)
  return server~=nil
end
local seq=0
local function rpc(op,data,timeout)
  if not server and not locate() then return {ok=false,error='Servidor no encontrado (modem/ID/red)'} end
  seq=seq+1
  local id=tostring(os.getComputerID())..'-'..tostring(os.epoch('utc'))..'-'..tostring(seq)..'-'..math.random(10000,99999)
  local q=data or {};q.v=1;q.op=op;q.req=id;q.token=token
  for attempt=1,3 do
    rednet.send(server,q,P)
    local deadline=os.epoch('utc')+(timeout or 2.5)*1000
    repeat
      local seconds=math.max(0,(deadline-os.epoch('utc'))/1000)
      local sender,res=rednet.receive(P,seconds)
      if not sender then break end
      if sender==server and type(res)=='table' and res.req==id and res.v==1 then return res end
    until os.epoch('utc')>=deadline
  end
  return {ok=false,error='No responde el servidor; comprueba la conexion.'}
end
local function status(res)
  if res.ok then col(colors.lime);print('OK: '..tostring(res.message or 'Correcto'))
  else col(colors.red);print('ERROR: '..tostring(res.error)) end
  col(colors.white)
end
local function login()
  while not token do
    screen('IDENTIFICACION','Servidor '..tostring(server or '?'))
    print('[1] Iniciar sesion  [2] Crear cuenta')
    print('[R] Reconectar     [Q] Salir')
    local c=ask('> '):lower()
    if c=='q' then return false
    elseif c=='r' then server=nil;print('Conectando...');locate()
    elseif c=='1' or c=='2' then
      local name=ask('Usuario: '):lower()
      local pass=ask('Contrasena: ')
      if c=='2' then
        local r=rpc('REGISTER',{user=name,pass=pass});status(r);waitkey()
      else
        local r=rpc('LOGIN',{user=name,pass=pass})
        if r.ok then token=r.token; user=r.user;balance=r.balance;dev=r.dev;return true end
        status(r);waitkey()
      end
    end
  end
  return true
end
local function refresh()
  local res=rpc('ME');if res.ok then balance=res.balance;dev=res.dev end
  return res
end
local function catalog()
  local r=rpc('CATALOG');if not r.ok then status(r);waitkey();return end
  local list=r.games or {}
  while true do
    screen('TIENDA','Saldo: '..balance..' WS$ | Juegos: '..#list)
    if #list==0 then print('Sin juegos. Los desarrolladores pueden subirlos.') end
    for i,g in ipairs(list) do
      print(('%d. %s - %s WS$'):format(i,g.title,g.price))
    end
    print('');local v=ask('Numero / [B] volver: '):lower()
    if v=='b' or v=='' then return end
    local game=list[tonumber(v)]
    if game then
      screen(game.title,'#'..game.id..' | '..game.genre..' | '..game.price..' WS$')
      print('Creado por: '..game.owner);print('');print(game.desc);print('')
      print('[1] Comprar (si ya lo tienes, no se cobra)')
      print('[0] Volver')
      if ask('> ')=='1' then status(rpc('BUY',{id=game.id}));refresh();waitkey() end
    end
  end
end
local function install(game)
  local manifest=rpc('DOWNLOAD_MANIFEST',{id=game.id})
  if not manifest.ok then status(manifest);waitkey();return end
  local target=fs.combine('worldshop_games','ws_'..game.id)
  if not fs.exists(target) then fs.makeDir(target) end
  print('Instalando en /'..target)
  for _,f in ipairs(manifest.files) do
    local path=fs.combine(target,f.path)
    local dir=fs.getDir(path);if not fs.exists(dir) then fs.makeDir(dir) end
    local tmp=path..'.part'
    local file=fs.open(tmp,'w');if not file then printError('No se pudo escribir '..tmp);return end
    local at=0; local err
    while at<f.size do
      local r=rpc('DOWNLOAD_CHUNK',{id=game.id,path=f.path,offset=at},4)
      if not r.ok then err=r.error;break end
      if type(r.data)~='string' or #r.data==0 or (r.size and r.size~=f.size) then err='Descarga incompleta';break end
      file.write(r.data);at=at+#r.data
    end
    file.close()
    if err then printError('Error en '..f.path..': '..tostring(err));return end
    if fs.exists(path) then fs.delete(path) end
    fs.move(tmp,path); print('OK '..f.path..' ('..f.size..' bytes)')
  end
  local marker=fs.open(fs.combine(target,'.worldshop'),'w');marker.write(textutils.serialize({entry=manifest.entry,title=manifest.title}));marker.close()
  col(colors.lime);print('Instalacion completada: '..target);col(colors.white)
end
local function play(game)
  local target=fs.combine('worldshop_games','ws_'..game.id)
  local mark=fs.combine(target,'.worldshop')
  if not fs.exists(mark) then print('Aun no instalado.');return end
  local h=fs.open(mark,'r');local meta=textutils.unserialize(h.readAll());h.close()
  if not meta or not meta.entry then printError('Falta marcador de entrada');return end
  if not fs.exists(fs.combine(target,meta.entry)) then printError('Falta script principal');return end
  print('Iniciando '..game.title..'...')
  local previous=shell.dir();shell.setDir(target)
  local ok,err=pcall(function()shell.run(meta.entry) end)
  shell.setDir(previous)
  if not ok then printError(tostring(err)) end
end
local function library()
  local r=rpc('LIBRARY');if not r.ok then status(r);waitkey();return end
  local arr=r.games or {}
  while true do
    screen('BIBLIOTECA','Juegos adquiridos: '..#arr)
    if #arr==0 then print('Tu biblioteca esta vacia.') end
    for i,g in ipairs(arr) do print(i..'. '..g.title) end
    print('');local sel=ask('Numero / [B] volver: '):lower()
    if sel=='b' or sel=='' then return end
    local game=arr[tonumber(sel)]
    if game then
      screen(game.title,'Selecciona accion')
      print('[1] Instalar/Actualizar')
      print('[2] Jugar en ESTE ordenador')
      print('[3] Ver ruta local')
      print('[0] Volver')
      local action=ask('> ')
      if action=='1' then install(game);waitkey()
      elseif action=='2' then play(game);waitkey()
      elseif action=='3' then print('/worldshop_games/ws_'..game.id);waitkey() end
    end
  end
end
local function gather(folder)
  local files={}
  local function scan(dir,relative)
    for _,name in ipairs(fs.list(dir)) do
      local rel=relative=='' and name or relative..'/'..name
      local path=fs.combine(dir,name)
      if fs.isDir(path) then scan(path,rel)
      else
        if #rel>105 or rel:find('%.%.') then error('Ruta invalida: '..rel) end
        local size=fs.getSize(path)
        if size>0 then files[#files+1]={path=rel,size=size,localFile=path} end
      end
    end
  end
  scan(folder,'')
  table.sort(files,function(a,b)return a.path<b.path end)
  return files
end
local function upload()
  screen('PUBLICAR JUEGO','Solo para desarrolladores')
  local folder=ask('Carpeta de tu juego (ej: mi_juego): ')
  if not fs.exists(folder) or not fs.isDir(folder) then printError('Carpeta inexistente');waitkey();return end
  local ok,files=pcall(gather,folder)
  if not ok then printError(files);waitkey();return end
  local total=0;for _,f in ipairs(files) do total=total+f.size end
  if #files<1 or #files>30 or total>600000 then print('Limite: 30 archivos y 600KB.');waitkey();return end
  print('Archivos: '..#files..' | '..total..' bytes')
  for _,f in ipairs(files) do print('  '..f.path) end
  local entry=ask('Script principal (ej: client.lua): ')
  local title=ask('Titulo del juego: ')
  local desc=ask('Descripcion corta: ')
  local genre=ask('Genero (accion/arcade/etc): ')
  local price=tonumber(ask('Precio WS$ (0 gratis): '))
  if not price then print('Precio invalido');waitkey();return end
  if ask('Enviar para revision? (s/n): '):lower()~='s' then return end
  local specs={};for _,f in ipairs(files) do specs[#specs+1]={path=f.path,size=f.size} end
  local init=rpc('UPLOAD_INIT',{title=title,desc=desc,genre=genre,price=price,entry=entry,files=specs})
  if not init.ok then status(init);waitkey();return end
  local chunk=init.chunk or 1600
  for i,f in ipairs(files) do
    print('['..i..'/'..#files..'] '..f.path)
    local h=fs.open(f.localFile,'r');if not h then printError('No se puede abrir');return end
    local str=h.readAll();h.close()
    local at=0
    while at<#str do
      local part=str:sub(at+1,at+chunk)
      local r=rpc('UPLOAD_CHUNK',{upload=init.upload,path=f.path,offset=at,data=part},5)
      if not r.ok then status(r);waitkey();return end
      at=at+#part
    end
  end
  local done=rpc('UPLOAD_COMMIT',{upload=init.upload},5);status(done)
  if done.ok then print('ID: '..done.id..' | Pendiente aprobacion.') end
  waitkey()
end
local function developers()
  refresh()
  if not dev then
    screen('WORLD DEVELOPERS','Publica juegos en WorldShop')
    print('Para publicar, crea una cuenta de desarrollador.')
    local studio=ask('Nombre del estudio (vacio cancelar): ')
    if studio~='' then status(rpc('BECOME_DEV',{studio=studio}));refresh();waitkey() end
    return
  end
  while true do
    screen('DEV CENTER','Usuario: '..user)
    print('[1] Subir nuevo juego')
    print('[2] Mis publicaciones')
    print('[0] Volver')
    local op=ask('> ')
    if op=='0' or op=='' then return
    elseif op=='1' then upload()
    elseif op=='2' then
      local r=rpc('MY_GAMES');screen('MIS PUBLICACIONES')
      if r.ok then for _,g in ipairs(r.games or {}) do print('#'..g.id..' '..g.title..' - '..g.status) end else status(r) end
      waitkey()
    end
  end
end
local function wallet()
  refresh();screen('CARTERA','Saldo: '..balance..' WS$')
  print('WorldShop utiliza monedas fisicas de Lightman\'s')
  print('Currency para recargar en un cajero WorldShop.')
  print('');print('[1] Generar ticket de deposito (5 min)')
  print('[0] Volver')
  if ask('> ')=='1' then
    local r=rpc('ATM_TICKET')
    if r.ok then
      screen('TICKET DE DEPOSITO','Muestra el codigo en el cajero')
      col(colors.yellow);print('CODIGO: '..r.code);col(colors.white)
      print('Caduca en '..(r.seconds or 300)..' segundos.')
      print('No pongas monedas sin iniciar el deposito.')
    else status(r) end
    waitkey()
  end
end
intro();server=rednet.lookup(P,HOST)
if not login() then term.clear();return end
while true do
  refresh();screen('TIENDA DIGITAL','@'..user..'  |  Saldo '..balance..' WS$')
  print('[1] Explorar tienda')
  print('[2] Mi biblioteca / Jugar')
  print('[3] Recargar saldo (cajero)')
  print('[4] Zona de desarrolladores')
  print('[5] Mi cuenta')
  print('[6] Reconectar al servidor')
  print('[0] Salir')
  print('')
  local v=ask('WorldShop> ')
  if v=='1' then catalog()
  elseif v=='2' then library()
  elseif v=='3' then wallet()
  elseif v=='4' then developers()
  elseif v=='5' then
    screen('MI PERFIL');local r=refresh();if r.ok then print('Usuario: '..r.user);print('Saldo: '..r.balance..' WS$');print('Desarrollador: '..(r.dev and 'SI' or 'NO'));print('Estudio: '..(r.studio or '')) else status(r) end;waitkey()
  elseif v=='6' then server=nil;token=nil;locate();if not login() then break end
  elseif v=='0' then break end
end
bg(colors.black);term.clear();col(colors.white);print('WorldShop cerrado.')
