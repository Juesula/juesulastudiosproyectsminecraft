-- WorldShop 1.0 | Servidor CC:Tweaked
-- Almacena cuentas, licencias, juegos, tickets y transacciones.
local P, HOST = 'worldshop.v1', 'worldshop'
local ROOT, DBFILE = 'worldshop_data', 'worldshop_data/database'
local CHUNK, MAX_FILE, MAX_TOTAL = 1600, 180000, 600000
local modemCount = 0
for _, n in ipairs(peripheral.getNames()) do
  if peripheral.hasType(n, 'modem') then rednet.open(n); modemCount = modemCount + 1 end
end
if modemCount == 0 then printError('Conecta un modem al servidor.'); return end
if not fs.exists(ROOT) then fs.makeDir(ROOT) end
if not fs.exists(fs.combine(ROOT,'games')) then fs.makeDir(fs.combine(ROOT,'games')) end
local function readObj(path)
  if not fs.exists(path) then return nil end
  local h = fs.open(path,'r'); if not h then return nil end
  local value = textutils.unserialize(h.readAll()); h.close(); return value
end
local function saveObj(path,obj)
  local tmp = path..'.tmp'
  local h = assert(fs.open(tmp,'w')); h.write(textutils.serialize(obj)); h.close()
  if fs.exists(path) then
    if fs.exists(path..'.bak') then fs.delete(path..'.bak') end
    fs.copy(path,path..'.bak'); fs.delete(path)
  end
  fs.move(tmp,path)
end
local db=readObj(DBFILE) or readObj(DBFILE..'.bak') or {
  accounts={}, games={}, tickets={}, receipts={}, nextGame=1, nextTicket=1000
}
local function persist() saveObj(DBFILE,db) end
local function randomCode(n)
  local s=''; for i=1,n do s=s..string.char(math.random(65,90)) end; return s
end
math.randomseed((os.epoch('utc') or 1) % 2147483647 + os.getComputerID())
local cashierCfg=readObj(fs.combine(ROOT,'cashier'))
if not cashierCfg then
  cashierCfg={key=randomCode(18)..tostring(os.getComputerID()), cashierId=0}
  saveObj(fs.combine(ROOT,'cashier'),cashierCfg)
end
local sessions, uploads, cache = {}, {}, {}
local function now() return os.epoch('utc') end
local function passHash(user,pass,salt)
  -- Hash ligero para juego. NO es criptografia fuerte ni protege Rednet.
  local str=user..'|'..salt..'|'..pass
  local a,b=17219,65911
  for i=1,#str do
    local c=str:byte(i); a=(a*131+c)%2147483647; b=(b*257+c*7)%2147483629
  end
  return tostring(a)..'-'..tostring(b)
end
local function validUser(s) return type(s)=='string' and #s>=3 and #s<=16 and s:match('^[%w_]+$') end
local function validPath(s)
  if type(s)~='string' or #s<1 or #s>105 or s:sub(1,1)=='/' or s:find('\\',1,true) or s:find('%.%.') then return false end
  for seg in s:gmatch('[^/]+') do if not seg:match('^[%w_%-%.]+$') or seg=='.' then return false end end
  return not s:find('//',1,true) and s:sub(-1)~='/'
end
local function sid() return randomCode(18)..tostring(math.random(10000,99999)) end
local function requireUser(sender,q)
  local ss=sessions[q.token]
  if not ss or ss.id~=sender or ss.expires<now() then return nil,'Inicia sesion otra vez.' end
  ss.expires=now()+7200000
  return db.accounts[ss.user]
end
local function own(acc,g) return acc and (acc.owned[g.id] or g.owner==acc.name) end
local function gamePublic(g) return {id=g.id,title=g.title,desc=g.desc,genre=g.genre,price=g.price,owner=g.owner,files=#g.files,status=g.status,entry=g.entry} end
local function response(ok,data) data=data or {}; data.ok=ok; return data end
local function gamePath(id,file) return fs.combine(fs.combine(ROOT,'games/'..id),file) end
local function process(sender,q)
  if type(q)~='table' or q.v~=1 or type(q.op)~='string' then return response(false,{error='Protocolo incorrecto'}) end
  if q.op=='PING' then return response(true,{name='WorldShop',version='1.0',server=os.getComputerID()}) end
  if q.op=='REGISTER' then
    if not validUser(q.user) or type(q.pass)~='string' or #q.pass<4 or #q.pass>64 then return response(false,{error='Usuario 3-16 letras/numeros; clave 4-64.'}) end
    local user=q.user:lower(); if db.accounts[user] then return response(false,{error='Nombre ocupado'}) end
    local salt=sid(); db.accounts[user]={name=user,salt=salt,pass=passHash(user,q.pass,salt),balance=0,owned={},dev=false,studio='',joined=now()}
    persist(); return response(true,{message='Cuenta creada'})
  end
  if q.op=='LOGIN' then
    local user=type(q.user)=='string' and q.user:lower() or ''
    local acc=db.accounts[user]
    if not acc or type(q.pass)~='string' or acc.pass~=passHash(user,q.pass,acc.salt) then return response(false,{error='Datos incorrectos'}) end
    local token=sid(); sessions[token]={user=user,id=sender,expires=now()+7200000}
    return response(true,{token=token,user=user,dev=acc.dev,balance=acc.balance})
  end
  if q.op=='ATM_VERIFY' or q.op=='ATM_CREDIT' then
    if q.key~=cashierCfg.key or cashierCfg.cashierId==0 or sender~=cashierCfg.cashierId then return response(false,{error='Cajero no autorizado'}) end
    if q.op=='ATM_VERIFY' then
      local t=db.tickets[q.code]
      if not t or t.used or t.expires<now() then return response(false,{error='Codigo inexistente, usado o caducado'}) end
      return response(true,{user=t.user,expires=t.expires})
    end
    local id=tostring(q.tx or '')
    if #id<5 or #id>75 or type(q.amount)~='number' or q.amount~=math.floor(q.amount) or q.amount<1 or q.amount>100000000 then return response(false,{error='Transaccion invalida'}) end
    local old=db.receipts[id]
    if old then return response(true,{message='Transaccion ya registrada',user=old.user,amount=old.amount}) end
    local t=db.tickets[q.code]
    if not t or t.used or t.expires<now() then return response(false,{error='Ticket vencido; requiere revision manual'}) end
    local acc=db.accounts[t.user]; if not acc then return response(false,{error='Cuenta eliminada'}) end
    if acc.balance+q.amount>1000000000 then return response(false,{error='Limite de saldo'}) end
    acc.balance=acc.balance+q.amount; t.used=true; db.receipts[id]={user=t.user,amount=q.amount,time=now()}
    persist(); return response(true,{user=t.user,amount=q.amount,balance=acc.balance})
  end
  local acc,err=requireUser(sender,q)
  if not acc then return response(false,{error=err}) end
  if q.op=='ME' then return response(true,{user=acc.name,balance=acc.balance,dev=acc.dev,studio=acc.studio}) end
  if q.op=='CATALOG' then
    local g={}; for _,item in pairs(db.games) do if item.status=='approved' then g[#g+1]=gamePublic(item) end end
    table.sort(g,function(a,b) return a.title:lower()<b.title:lower() end)
    return response(true,{games=g})
  end
  if q.op=='LIBRARY' then
    local g={}; for _,item in pairs(db.games) do if own(acc,item) and item.status=='approved' then g[#g+1]=gamePublic(item) end end
    table.sort(g,function(a,b)return a.title<b.title end)
    return response(true,{games=g})
  end
  if q.op=='BUY' then
    local game=db.games[tonumber(q.id)]
    if not game or game.status~='approved' then return response(false,{error='Juego no publicado'}) end
    if own(acc,game) then return response(true,{message='Ya tienes este juego',balance=acc.balance}) end
    if acc.balance<game.price then return response(false,{error='Saldo insuficiente'}) end
    acc.balance=acc.balance-game.price; acc.owned[game.id]=true
    -- El ingreso se atribuye al desarrollador en la economia interna.
    local owner=db.accounts[game.owner]; if owner then owner.balance=math.min(1000000000,owner.balance+game.price) end
    persist(); return response(true,{message='Comprado: '..game.title,balance=acc.balance})
  end
  if q.op=='ATM_TICKET' then
    local code=tostring(db.nextTicket)..randomCode(4); db.nextTicket=db.nextTicket+1
    db.tickets[code]={user=acc.name,expires=now()+300000,used=false}
    persist(); return response(true,{code=code,seconds=300})
  end
  if q.op=='BECOME_DEV' then
    if type(q.studio)~='string' or #q.studio<3 or #q.studio>28 then return response(false,{error='Nombre estudio: 3-28 caracteres'}) end
    acc.studio=q.studio; acc.dev=true; persist(); return response(true,{message='Cuenta de desarrollador activada'})
  end
  if q.op=='MY_GAMES' then
    local g={};for _,game in pairs(db.games) do if game.owner==acc.name then g[#g+1]=gamePublic(game) end end
    table.sort(g,function(a,b)return a.id>b.id end);return response(true,{games=g})
  end
  if q.op=='UPLOAD_INIT' then
    if not acc.dev then return response(false,{error='Necesitas cuenta desarrollador'}) end
    if type(q.title)~='string' or #q.title<3 or #q.title>36 or type(q.desc)~='string' or #q.desc>140 or type(q.genre)~='string' or #q.genre>24 then return response(false,{error='Metadatos invalidos'}) end
    if type(q.price)~='number' or q.price~=math.floor(q.price) or q.price<0 or q.price>1000000 then return response(false,{error='Precio invalido'}) end
    if type(q.files)~='table' or #q.files<1 or #q.files>30 or not validPath(q.entry) then return response(false,{error='Archivos o entrada invalidos'}) end
    local total,slots={},0; local hasEntry=false
    for _,f in ipairs(q.files) do
      if type(f)~='table' or not validPath(f.path) or type(f.size)~='number' or f.size<1 or f.size>MAX_FILE or total[f.path] then return response(false,{error='Ruta/tamano invalido'}) end
      total[f.path]=f.size; slots=slots+f.size; if f.path==q.entry then hasEntry=true end
    end
    if not hasEntry or slots>MAX_TOTAL then return response(false,{error='Archivo principal no incluido o paquete >600KB'}) end
    local uploadId=sid(); uploads[uploadId]={owner=acc.name,sender=sender,title=q.title,desc=q.desc,genre=q.genre,price=q.price,entry=q.entry,declared=total,data={},time=now()}
    return response(true,{upload=uploadId,chunk=CHUNK})
  end
  if q.op=='UPLOAD_CHUNK' then
    local up=uploads[q.upload]
    if not up or up.owner~=acc.name or up.sender~=sender or now()-up.time>600000 then return response(false,{error='Subida expirada'}) end
    if not up.declared[q.path] or type(q.data)~='string' or #q.data>CHUNK or type(q.offset)~='number' then return response(false,{error='Trozo invalido'}) end
    local str=up.data[q.path] or ''
    if #str==q.offset then
      if #str+#q.data>up.declared[q.path] then return response(false,{error='Exceso de datos'}) end
      up.data[q.path]=str..q.data
    elseif #str>=q.offset+#q.data and str:sub(q.offset+1,q.offset+#q.data)==q.data then
      -- Retry, already committed.
    else return response(false,{error='Offset incorrecto'}) end
    up.time=now(); return response(true,{offset=#up.data[q.path]})
  end
  if q.op=='UPLOAD_COMMIT' then
    local up=uploads[q.upload]; if not up or up.owner~=acc.name or up.sender~=sender then return response(false,{error='Sin subida activa'}) end
    for path,size in pairs(up.declared) do if not up.data[path] or #up.data[path]~=size then return response(false,{error='Faltan bytes en '..path}) end end
    local id=db.nextGame; db.nextGame=id+1
    local files={}; for path,data in pairs(up.data) do
      local fp=gamePath(id,path); local dir=fs.getDir(fp); if not fs.exists(dir) then fs.makeDir(dir) end
      local h=assert(fs.open(fp,'w')); h.write(data); h.close(); files[#files+1]={path=path,size=#data}
    end
    table.sort(files,function(a,b)return a.path<b.path end)
    db.games[id]={id=id,title=up.title,desc=up.desc,genre=up.genre,price=up.price,owner=acc.name,entry=up.entry,files=files,status='pending',created=now()}
    uploads[q.upload]=nil;persist();return response(true,{id=id,message='Subido: pendiente de aprobacion del administrador'})
  end
  if q.op=='DOWNLOAD_MANIFEST' or q.op=='DOWNLOAD_CHUNK' then
    local game=db.games[tonumber(q.id)]
    if not game or game.status~='approved' or not own(acc,game) then return response(false,{error='Juego no disponible en tu biblioteca'}) end
    if q.op=='DOWNLOAD_MANIFEST' then return response(true,{title=game.title,entry=game.entry,files=game.files}) end
    if not validPath(q.path) or type(q.offset)~='number' or q.offset<0 or q.offset~=math.floor(q.offset) then return response(false,{error='Ruta invalida'}) end
    local allowed=false; for _,f in ipairs(game.files) do if f.path==q.path then allowed=true end end
    if not allowed then return response(false,{error='Archivo desconocido'}) end
    local file=fs.open(gamePath(game.id,q.path),'r'); if not file then return response(false,{error='Archivo perdido en servidor'}) end
    local str=file.readAll();file.close()
    return response(true,{data=str:sub(q.offset+1,q.offset+CHUNK),size=#str})
  end
  return response(false,{error='Operacion no reconocida'})
end
local function send(sender,id,res) res.v=1;res.req=id;rednet.send(sender,res,P) end
local function network()
  rednet.host(P,HOST)
  print('WORLD SHOP SERVER ONLINE - ID '..os.getComputerID())
  print('Protocolo: '..P)
  print('Caja: ID '..cashierCfg.cashierId..' | Clave: '..cashierCfg.key)
  while true do
    local sender,q=rednet.receive(P)
    if type(q)=='table' and type(q.req)=='string' and #q.req<=100 then
      local key=sender..':'..q.req
      local res=cache[key]
      if not res then
        local ok,ret=pcall(process,sender,q)
        res=ok and ret or response(false,{error='Fallo del servidor: '..tostring(ret)})
        cache[key]=res
        local cnt=0;for _ in pairs(cache) do cnt=cnt+1 end;if cnt>300 then cache={} end
      end
      send(sender,q.req,res)
    end
  end
end
local function admin()
  while true do
    print('\n[A]probar [R]echazar [P]endientes [C]ajero [E]stadisticas [Q]salir')
    write('worldshop> '); local cmd=(read() or ''):lower()
    if cmd=='p' then
      for id,g in pairs(db.games) do if g.status=='pending' then print('#'..id..' '..g.title..' por '..g.owner..' ('..g.price..')') end end
    elseif cmd=='a' or cmd=='r' then
      write('ID juego: ');local id=tonumber(read());local g=id and db.games[id]
      if g then g.status=(cmd=='a' and 'approved' or 'rejected');persist(); print('Ahora: '..g.status) else print('No existe') end
    elseif cmd=='c' then
      print('ID de este servidor: '..os.getComputerID()); print('Clave cajero: '..cashierCfg.key)
      write('ID computadora cajero (0=ninguno): '); local id=tonumber(read());if id and id>=0 and id==math.floor(id) then cashierCfg.cashierId=id;saveObj(fs.combine(ROOT,'cashier'),cashierCfg);print('Cajero asociado: '..id) end
    elseif cmd=='e' then
      local n,g=0,0;for _ in pairs(db.accounts) do n=n+1 end;for _ in pairs(db.games) do g=g+1 end
      print('Usuarios: '..n..' | Juegos: '..g)
    elseif cmd=='q' then print('Cerrando servidor.'); return end
  end
end
parallel.waitForAny(network,admin)
