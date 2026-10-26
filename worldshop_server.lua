-- WorldShop 3.2 | Servidor CC:Tweaked: deployments / rollback + enlace ATM automatico
-- Almacena cuentas, licencias, juegos, tickets y transacciones.
local WORLD_TOR_SOURCE=[==[
-- WorldTor 2D Engine v1.0 | CC:Tweaked | sin dependencias
-- API: loadfile('worldtor_engine.lua')() -> tabla WorldTor
-- Componentes: doble buffer, sprites, texto, figuras, camara, efectos, animacion intro y sonido.
local WT = { version = '1.0.0' }
local palette = '0123456789abcdef'
local fallbackColors = {
    [colors.white]='0', [colors.orange]='1', [colors.magenta]='2',
    [colors.lightBlue]='3', [colors.yellow]='4', [colors.lime]='5',
    [colors.pink]='6', [colors.gray]='7', [colors.lightGray]='8',
    [colors.cyan]='9', [colors.purple]='a', [colors.blue]='b',
    [colors.brown]='c', [colors.green]='d', [colors.red]='e', [colors.black]='f'
}
local function hex(c)
    if type(c)=='string' then
        if #c==1 and palette:find(c,1,true) then return c end
        return '0'
    end
    return fallbackColors[c] or '0'
end
WT.hex = hex
local function clamp(x,a,b) return math.min(b,math.max(a,x)) end
WT.clamp = clamp
function WT.distance(x1,y1,x2,y2) return math.sqrt((x2-x1)^2+(y2-y1)^2) end
function WT.hit(a,b,r) return WT.distance(a.x,a.y,b.x,b.y) <= (r or 1) end
function WT.tween(a,b,t) t=clamp(t,0,1); return a+(b-a)*t end

function WT.new(target)
    local self = { target=target or term.current(), cameraX=0, cameraY=0,
                   particles={}, frame=0, shakeTime=0, shakeSize=1 }
    function self:resize()
        self.w,self.h=self.target.getSize()
        self:clear()
    end
    function self:clear(ch,fg,bg)
        self.chars,self.fore,self.back={}, {}, {}
        ch=(ch or ' '):sub(1,1); fg=hex(fg or colors.white); bg=hex(bg or colors.black)
        for y=1,self.h do
            self.chars[y]={};self.fore[y]={};self.back[y]={}
            for x=1,self.w do self.chars[y][x]=ch;self.fore[y][x]=fg;self.back[y][x]=bg end
        end
    end
    function self:camera(x,y) self.cameraX=x or 0;self.cameraY=y or 0 end
    function self:pixel(x,y,ch,fg,bg,screen)
        if not screen then x=x-self.cameraX; y=y-self.cameraY end
        x=math.floor(x+0.5);y=math.floor(y+0.5)
        if x<1 or x>self.w or y<1 or y>self.h then return end
        self.chars[y][x]=(tostring(ch or ' ')):sub(1,1)
        if fg~=nil then self.fore[y][x]=hex(fg) end
        if bg~=nil then self.back[y][x]=hex(bg) end
    end
    function self:text(x,y,str,fg,bg,screen)
        local cx,cy=x,y
        str=tostring(str or '')
        for i=1,#str do
            local ch=str:sub(i,i)
            if ch=='\n' then cy=cy+1;cx=x else self:pixel(cx,cy,ch,fg,bg,screen);cx=cx+1 end
        end
    end
    function self:center(y,str,fg,bg)
        str=tostring(str or '')
        self:text(math.floor((self.w-#str)/2)+1,y,str,fg,bg,true)
    end
    function self:rect(x,y,w,h,ch,fg,bg,filled)
        w=math.floor(w);h=math.floor(h)
        if w<=0 or h<=0 then return end
        for j=0,h-1 do for i=0,w-1 do
            if filled or i==0 or i==w-1 or j==0 or j==h-1 then
                self:pixel(x+i,y+j,ch or '#',fg,bg)
            end
        end end
    end
    function self:line(x0,y0,x1,y1,ch,fg,bg)
        x0=math.floor(x0+0.5); y0=math.floor(y0+0.5)
        x1=math.floor(x1+0.5); y1=math.floor(y1+0.5)
        local dx=math.abs(x1-x0); local sx=x0<x1 and 1 or -1
        local dy=-math.abs(y1-y0);local sy=y0<y1 and 1 or -1; local err=dx+dy
        for _=1,512 do
            self:pixel(x0,y0,ch or '.',fg,bg)
            if x0==x1 and y0==y1 then break end
            local e2=2*err
            if e2>=dy then err=err+dy;x0=x0+sx end
            if e2<=dx then err=err+dx;y0=y0+sy end
        end
    end
    function self:circle(cx,cy,r,ch,fg,bg,filled)
        r=math.max(0,math.floor(r));
        for y=-r,r do for x=-r,r do
            local d=x*x+y*y
            if (filled and d<=r*r) or (not filled and d<=r*r and d>=(r-1)*(r-1)) then
                self:pixel(cx+x,cy+y,ch or 'o',fg,bg)
            end
        end end
    end
    -- sprite puede ser {' /\\ ', '<oo>'} o un string multilinea.
    -- Los espacios se consideran transparentes, salvo transparent=false.
    function self:sprite(x,y,sprite,fg,bg,transparent)
        if type(sprite)=='string' then local a={};for row in (sprite..'\n'):gmatch('(.-)\n') do a[#a+1]=row end;sprite=a end
        if type(sprite)~='table' then return end
        for dy,row in ipairs(sprite) do for dx=1,#row do
            local ch=row:sub(dx,dx)
            if transparent==false or ch~=' ' then self:pixel(x+dx-1,y+dy-1,ch,fg,bg) end
        end end
    end
    function self:bar(x,y,w,value,maxval,col)
        w=math.max(1,math.floor(w));value=clamp(value or 0,0,maxval or 100)
        local count=math.floor(w*value/(maxval or 100)+0.5)
        for i=0,w-1 do self:pixel(x+i,y,(i<count and '=' or '-'),i<count and (col or colors.lime) or colors.gray) end
    end
    function self:particle(x,y,ch,fg,vx,vy,life)
        self.particles[#self.particles+1]={x=x,y=y,c=ch or '*',fg=fg or colors.orange,
            vx=vx or 0,vy=vy or -0.1,life=life or 8}
    end
    function self:burst(x,y,n,fg)
        for i=1,(n or 8) do
            local a=(i/(n or 8))*math.pi*2
            self:particle(x,y,'.',fg,math.cos(a)*0.35,math.sin(a)*0.28,7)
        end
    end
    function self:updateParticles()
        for i=#self.particles,1,-1 do
            local p=self.particles[i];p.x=p.x+p.vx;p.y=p.y+p.vy;p.life=p.life-1
            if p.life<=0 then table.remove(self.particles,i) end
        end
    end
    function self:drawParticles()
        for _,p in ipairs(self.particles) do self:pixel(p.x,p.y,p.c,p.fg) end
    end
    function self:shake(frames,size) self.shakeTime=frames or 4;self.shakeSize=size or 1 end
    function self:footer()
        local label='WorldTor IN USE'
        for x=1,self.w do self:pixel(x,self.h,' ',colors.lightGray,colors.gray,true) end
        self:center(self.h,label,colors.white,colors.gray)
    end
    function self:flip()
        self.frame=self.frame+1
        -- Renderiza cada fila con una sola llamada term.blit. Bucle con recorte automatico.
        local sx,sy=0,0
        if self.shakeTime>0 then
            self.shakeTime=self.shakeTime-1
            sx=math.random(-self.shakeSize,self.shakeSize)
            sy=math.random(-self.shakeSize,self.shakeSize)
        end
        self.target.setCursorBlink(false)
        for y=1,self.h do
            -- HUD y marca WorldTor no tiemblan aunque el escenario si.
            local rowSX,rowSY=sx,sy
            if y<=2 or y==self.h then rowSX,rowSY=0,0 end
            local cy=y+rowSY
            local chars,fore,back={}, {}, {}
            for x=1,self.w do
                local cx=x+rowSX
                if cx>=1 and cx<=self.w and cy>=1 and cy<=self.h then
                    chars[x]=self.chars[cy][cx];fore[x]=self.fore[cy][cx];back[x]=self.back[cy][cx]
                else chars[x]=' ';fore[x]='0';back[x]='f' end
            end
            self.target.setCursorPos(1,y)
            self.target.blit(table.concat(chars),table.concat(fore),table.concat(back))
        end
    end
    function self:splash(title,subtitle,speaker,enabled)
        title=tostring(title or 'WORLD STUDIOS');subtitle=subtitle or 'PRESENTA'
        local stars={}
        for i=1,math.min(40,self.w) do stars[i]={x=math.random(1,self.w),y=math.random(2,math.max(2,self.h-2))} end
        local top=math.max(2,math.floor(self.h/2)-2)
        for frame=1,math.min(35,#title+19) do
            self:clear(' ',colors.white,colors.black)
            for _,st in ipairs(stars) do self:pixel(st.x,st.y,'.',colors.gray,nil,true) end
            self:center(top,subtitle,colors.lightBlue)
            self:center(top+2,title:sub(1,math.max(0,frame-3)),frame%4==0 and colors.cyan or colors.white)
            if self.h>8 then self:center(top+4,'[ '..string.rep('=',math.floor(frame/2))..' ]',colors.cyan) end
            self:footer();self:flip()
            if speaker and enabled and frame%4==0 then pcall(speaker.playNote,'bit',0.35,math.min(24,6+frame)) end
            sleep(0.055)
        end
        if speaker and enabled then pcall(speaker.playNote,'chime',0.7,16) end
        sleep(0.24)
    end
    self:resize()
    return self
end
-- Se pueden importar funciones de este motor desde cualquier juego con loadfile().
return WT

]==]
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
db.atmAuth=db.atmAuth or {}
db.deployments=db.deployments or {}
db.nextDeployment=db.nextDeployment or 1
db.deployLog=db.deployLog or {}
if not fs.exists(fs.combine(ROOT,'deployments')) then fs.makeDir(fs.combine(ROOT,'deployments')) end
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
local function deployPath(id,file) return fs.combine(fs.combine(ROOT,'deployments/'..id),file) end
local function deploySummary(d)
  if not d then return nil end
  return {id=d.id,gameId=d.gameId,version=d.version,notes=d.notes,status=d.status,
    created=d.created,published=d.published,logs=d.logs,files=#d.files}
end
local function gamePublic(g)
  local release=g.release and db.deployments[g.release]
  local pending=g.pending and db.deployments[g.pending]
  return {id=g.id,title=g.title,desc=g.desc,genre=g.genre,price=g.price,owner=g.owner,
    files=release and #release.files or #g.files,status=g.status,entry=release and release.entry or g.entry,
    version=release and release.version or nil,deployment=release and release.id or nil,
    pendingVersion=pending and pending.version or nil,pendingDeployment=pending and pending.id or nil}
end
local function response(ok,data) data=data or {}; data.ok=ok; return data end
local function semver(str)
  if type(str)~='string' or #str>24 then return nil end
  local a,b,c=str:match('^(%d+)%.(%d+)%.(%d+)$')
  if not a then return nil end
  a,b,c=tonumber(a),tonumber(b),tonumber(c)
  if a>9999 or b>9999 or c>9999 then return nil end
  return {a,b,c}
end
local function greater(a,b)
  a,b=semver(a),semver(b)
  if not a then return false end
  if not b then return true end
  for i=1,3 do if a[i]~=b[i] then return a[i]>b[i] end end
  return false
end
local function checksum(data)
  local a,b=1,0
  for i=1,#data do a=(a+data:byte(i))%65521;b=(b+a)%65521 end
  return string.format('%08x',b*65536+a)
end
local function audit(action,d)
  local log=db.deployLog
  log[#log+1]={action=action,dep=d.id,game=d.gameId,version=d.version,time=now()}
  while #log>120 do table.remove(log,1) end
end
local function publish(depId,rollback)
  local d=db.deployments[tonumber(depId)]
  if not d then return false,'Deployment inexistente' end
  local g=db.games[d.gameId]
  if not g then return false,'Juego inexistente' end
  if rollback then
    if not d.published or (d.status~='archived' and d.status~='production') then return false,'Solo se puede restaurar una version publicada anteriormente' end
  elseif d.status~='pending' then return false,'El deployment no esta pendiente' end
  -- Comprobar integridad del artefacto antes de promocionarlo o restaurarlo.
  for _,f in ipairs(d.files) do
    local h=fs.open(deployPath(d.id,f.path),'r')
    if not h then return false,'Archivo ausente: '..f.path end
    local bytes=h.readAll();h.close()
    if #bytes~=f.size or (f.checksum and checksum(bytes)~=f.checksum) then
      return false,'Archivo danado: '..f.path
    end
  end
  if g.release and db.deployments[g.release] then db.deployments[g.release].status='archived' end
  d.status='production';d.published=true;d.publishedAt=now()
  g.release=d.id;g.version=d.version
  -- Copiar metadatos para evitar referencias repetidas al serializar la base de datos.
  local independentFiles={}
  for i,f in ipairs(d.files) do independentFiles[i]={path=f.path,size=f.size,checksum=f.checksum} end
  g.files=independentFiles;g.entry=d.entry;g.status='approved';g.updated=now()
  if g.pending==d.id then g.pending=nil end
  audit(rollback and 'ROLLBACK' or 'PROMOTE',d)
  persist()
  return true,'Produccion activa: '..d.version
end
local function reject(depId)
  local d=db.deployments[tonumber(depId)]
  if not d or d.status~='pending' then return false,'Deployment no pendiente' end
  d.status='rejected';local g=db.games[d.gameId]
  if g and g.pending==d.id then g.pending=nil end
  if g and not g.release then g.status='rejected' end
  audit('REJECT',d);persist();return true,'Rechazado '..d.version
end
-- Migracion V2 -> V3: conserva IDs, licencias, cuentas y originales V2.
-- Copia artefactos a carpetas inmutables; nunca mueve ni borra los originales.
local migrated=false
for _,g in pairs(db.games) do
  if not g.deployments then
    local depId=db.nextDeployment;local dir=fs.combine(ROOT,'deployments/'..depId)
    local exists=true
    for _,f in ipairs(g.files or {}) do
      if not fs.exists(fs.combine(fs.combine(ROOT,'games/'..g.id),f.path)) then exists=false;break end
    end
    if exists then
      if not fs.exists(dir) then fs.makeDir(dir) end
      local items={}
      for _,f in ipairs(g.files or {}) do
        local from=fs.combine(fs.combine(ROOT,'games/'..g.id),f.path)
        local to=deployPath(depId,f.path)
        local folder=fs.getDir(to);if not fs.exists(folder) then fs.makeDir(folder) end
        if fs.exists(to) then fs.delete(to) end
        fs.copy(from,to)
        local h=fs.open(from,'r');local bytes=h.readAll();h.close()
        items[#items+1]={path=f.path,size=f.size,checksum=checksum(bytes)}
      end
      local wasApproved=g.status=='approved'
      db.deployments[depId]={id=depId,gameId=g.id,owner=g.owner,version='1.0.0',notes='Importacion desde WorldShop 2.0',entry=g.entry,
        files=items,created=g.created or now(),status=wasApproved and 'production' or (g.status or 'pending'),
        published=wasApproved, publishedAt=wasApproved and now() or nil,logs={'Migrado de WorldShop 2.0'}}
      g.release=wasApproved and depId or nil
      g.pending=g.status=='pending' and depId or nil
      g.deployments={depId};g.version=wasApproved and '1.0.0' or nil
      db.nextDeployment=depId+1;migrated=true
    else
      error('WS3: juego V2 #'..g.id..' tiene archivos ausentes. Restaura worldshop_data/games desde tu copia antes de actualizar.')
    end
  end
end
if migrated then persist() end
local function gamePath(id,file) return fs.combine(fs.combine(ROOT,'games/'..id),file) end
local activeTests={}
local launchPreview,closePreview
local function process(sender,q)
  if type(q)~='table' or q.v~=1 or type(q.op)~='string' then return response(false,{error='Protocolo incorrecto'}) end
  if q.op=='PING' then return response(true,{name='WorldShop',version='3.2',server=os.getComputerID()}) end
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
  -- Primer cajero en la red: se autoriza automaticamente UNA SOLA VEZ.
  -- Los cajeros posteriores deben ser autorizados manualmente en el panel.
  -- Rednet no cifra el emparejamiento: utilizar solo en redes de confianza.
  if q.op=='ATM_PAIR' then
    if type(sender)~='number' or sender<1 or sender~=math.floor(sender) then
      return response(false,{error='ID de cajero incorrecto'})
    end
    if cashierCfg.cashierId==0 then
      cashierCfg.cashierId=sender
      saveObj(fs.combine(ROOT,'cashier'),cashierCfg)
      print('WORLDSHOP: cajero emparejado automaticamente (ID '..sender..')')
    elseif cashierCfg.cashierId~=sender then
      return response(false,{error='Ya esta autorizado el cajero ID '..cashierCfg.cashierId..'. En servidor: [3] Cajero > [C] > 0 para emparejar otro.'})
    end
    return response(true,{key=cashierCfg.key,cashierId=cashierCfg.cashierId})
  end
  if q.op=='ATM_LOGIN' then
    if q.key~=cashierCfg.key or cashierCfg.cashierId==0 or sender~=cashierCfg.cashierId then return response(false,{error='Cajero no autorizado'}) end
    local user=type(q.user)=='string' and q.user:lower() or ''
    local acc=db.accounts[user]
    if not acc or type(q.pass)~='string' or acc.pass~=passHash(user,q.pass,acc.salt) then return response(false,{error='Usuario o contrasena incorrectos'}) end
    -- Autorizacion unica persistente para que los depositos pendientes puedan reintentarse.
    local auth=sid();db.atmAuth[auth]={user=user,atm=sender,expires=now()+604800000,used=false}
    persist();return response(true,{user=user,balance=acc.balance,auth=auth})
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
    local t = (type(q.auth)=='string' and db.atmAuth[q.auth]) or nil
    local ticket = not t and db.tickets[q.code] or nil
    if t then
      if t.used or t.expires<now() or t.atm~=sender then return response(false,{error='Autorizacion usada o caducada; revision manual'}) end
    elseif not ticket or ticket.used or ticket.expires<now() then
      return response(false,{error='Autorizacion o ticket vencidos; revision manual'})
    end
    local username=t and t.user or ticket.user
    local acc=db.accounts[username];if not acc then return response(false,{error='Cuenta eliminada'}) end
    if acc.balance+q.amount>1000000000 then return response(false,{error='Limite de saldo'}) end
    acc.balance=acc.balance+q.amount
    if t then t.used=true else ticket.used=true end
    db.receipts[id]={user=username,amount=q.amount,time=now()}
    persist(); return response(true,{user=username,amount=q.amount,balance=acc.balance})
  end
  local acc,err=requireUser(sender,q)
  if not acc then return response(false,{error=err}) end
  if q.op=='TEST_START' then return launchPreview(sender,acc,q) end
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
  if q.op=='DEPLOYMENTS' then
    local g=db.games[tonumber(q.id)]
    if not g or g.owner~=acc.name or not acc.dev then return response(false,{error='Juego no autorizado'}) end
    local arr={};for _,id in ipairs(g.deployments or {}) do
      local d=db.deployments[id];if d then arr[#arr+1]=deploySummary(d) end
    end
    table.sort(arr,function(a,b)return a.id>b.id end)
    return response(true,{game=gamePublic(g),deployments=arr})
  end
  if q.op=='UPLOAD_INIT' then
    if not acc.dev then return response(false,{error='Necesitas cuenta desarrollador'}) end
    local gameId=tonumber(q.gameId)
    local old=gameId and db.games[gameId] or nil
    if q.gameId~=nil and not old then return response(false,{error='Juego original inexistente'}) end
    if old and (old.owner~=acc.name or not old.release or old.pending) then
      return response(false,{error='No eres propietario, no esta publicado o hay otra revision pendiente'})
    end
    local title=old and old.title or q.title
    local desc=old and old.desc or q.desc
    local genre=old and old.genre or q.genre
    local price=old and old.price or q.price
    if type(title)~='string' or #title<3 or #title>36 or type(desc)~='string' or #desc>140 or type(genre)~='string' or #genre>24 then return response(false,{error='Metadatos invalidos'}) end
    if type(price)~='number' or price~=math.floor(price) or price<0 or price>1000000 then return response(false,{error='Precio invalido'}) end
    local version=q.version or '1.0.0'
    if not semver(version) then return response(false,{error='Version invalida. Ejemplo: 1.2.0'}) end
    if old then
      for _,depId in ipairs(old.deployments or {}) do
        local previous=db.deployments[depId]
        if previous and not greater(version,previous.version) then return response(false,{error='Version debe superar '..previous.version..' (historial de deployments)'}) end
      end
    end
    local notes=q.notes or ''
    if type(notes)~='string' or #notes>500 then return response(false,{error='Notas maximo 500 caracteres'}) end
    if type(q.files)~='table' or #q.files<1 or #q.files>30 or not validPath(q.entry) or not q.entry:match('%.lua$') then return response(false,{error='Archivos o script principal invalidos'}) end
    local total,slots={},0;local hasEntry=false
    for _,f in ipairs(q.files) do
      if type(f)~='table' or not validPath(f.path) or type(f.size)~='number' or f.size<1 or f.size>MAX_FILE or total[f.path] then return response(false,{error='Ruta/tamano invalido'}) end
      total[f.path]=f.size;slots=slots+f.size;if f.path==q.entry then hasEntry=true end
    end
    if not hasEntry or slots>MAX_TOTAL then return response(false,{error='Archivo principal no incluido o paquete >600KB'}) end
    local uploadId=sid()
    uploads[uploadId]={owner=acc.name,sender=sender,gameId=old and old.id or nil,version=version,notes=notes,
      title=title,desc=desc,genre=genre,price=price,entry=q.entry,declared=total,data={},time=now()}
    return response(true,{upload=uploadId,chunk=CHUNK,mode=old and 'update' or 'new'})
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
    local up=uploads[q.upload];if not up or up.owner~=acc.name or up.sender~=sender then return response(false,{error='Sin subida activa'}) end
    for path,size in pairs(up.declared) do if not up.data[path] or #up.data[path]~=size then return response(false,{error='Faltan bytes en '..path}) end end
    local gameId=up.gameId or db.nextGame
    if up.gameId then
      local g=db.games[gameId]
      if not g or g.owner~=acc.name or g.pending then return response(false,{error='El juego ya tiene un deployment pendiente'}) end
    end
    local depId=db.nextDeployment
    local logs={'BUILD #D'..depId..' | '..up.version,'Checking uploaded files for syntax'}
    local fail=nil
    for path,content in pairs(up.data) do
      if path:match('%.lua$') then
        local compiled,compileError=load(content,'@build/'..path,'t',{})
        if not compiled then fail='Sintaxis '..path..': '..tostring(compileError):sub(1,140);break end
      end
    end
    logs[#logs+1]=fail and ('FAILED: '..fail) or 'BUILD READY: preview en espera de revision'
    local files={}
    for path,data in pairs(up.data) do
      local fp=deployPath(depId,path);local dir=fs.getDir(fp)
      if not fs.exists(dir) then fs.makeDir(dir) end
      local h=assert(fs.open(fp,'w'));h.write(data);h.close()
      files[#files+1]={path=path,size=#data,checksum=checksum(data)}
    end
    table.sort(files,function(a,b)return a.path<b.path end)
    if not up.gameId then
      db.games[gameId]={id=gameId,title=up.title,desc=up.desc,genre=up.genre,price=up.price,
        owner=acc.name,entry=up.entry,files=(function()
          -- No reutilizar la tabla files del deployment: textutils.serialize rechaza referencias repetidas.
          local copy={}
          for i,f in ipairs(files) do
            copy[i]={path=f.path,size=f.size,checksum=f.checksum}
          end
          return copy
        end)(),status='pending',created=now(),deployments={}}
      db.nextGame=gameId+1
    end
    local g=db.games[gameId]
    local d={id=depId,gameId=gameId,version=up.version,notes=up.notes,owner=up.owner,
      files=files,entry=up.entry,created=now(),status=fail and 'failed' or 'pending',logs=logs,published=false}
    db.deployments[depId]=d;db.nextDeployment=depId+1
    g.deployments[#g.deployments+1]=depId
    if not fail then g.pending=depId end
    if not g.release then g.status=fail and 'failed' or 'pending' end
    uploads[q.upload]=nil;audit(fail and 'BUILD_FAILED' or 'PREVIEW_READY',d);persist()
    return response(true,{id=gameId,deployment=depId,version=up.version,status=d.status,
      message=fail and ('Compilacion fallida: '..fail) or 'Preview lista: deployment #D'..depId..' pendiente de aprobacion'})
  end
  if q.op=='DOWNLOAD_MANIFEST' or q.op=='DOWNLOAD_CHUNK' or q.op=='PREVIEW_MANIFEST' or q.op=='PREVIEW_CHUNK' then
    local preview=(q.op=='PREVIEW_MANIFEST' or q.op=='PREVIEW_CHUNK')
    local dep,game
    if preview then
      dep=db.deployments[tonumber(q.deployment)]
      game=dep and db.games[dep.gameId] or nil
      if not dep or not game or not acc.dev or game.owner~=acc.name or dep.status~='pending' then
        return response(false,{error='Preview privada: solo desarrollador, deployment pendiente'})
      end
    else
      game=db.games[tonumber(q.id)]
      if not game or game.status~='approved' or not own(acc,game) then return response(false,{error='Juego no disponible en tu biblioteca'}) end
      -- El cliente fija un artefacto inmutable incluso si se publica otra version durante la transferencia.
      dep=db.deployments[tonumber(q.deployment) or game.release]
      if not dep or dep.gameId~=game.id or not dep.published or (dep.status~='production' and dep.status~='archived') then
        return response(false,{error='Deployment no disponible'})
      end
    end
    if q.op=='DOWNLOAD_MANIFEST' or q.op=='PREVIEW_MANIFEST' then
      return response(true,{title=game.title,entry=dep.entry,files=dep.files,version=dep.version,
        deployment=dep.id,notes=dep.notes})
    end
    if not validPath(q.path) or type(q.offset)~='number' or q.offset<0 or q.offset~=math.floor(q.offset) then return response(false,{error='Ruta invalida'}) end
    local known=nil;for _,f in ipairs(dep.files) do if f.path==q.path then known=f;break end end
    if not known then return response(false,{error='Archivo desconocido'}) end
    local file=fs.open(deployPath(dep.id,q.path),'r');if not file then return response(false,{error='Archivo perdido en servidor'}) end
    local str=file.readAll();file.close()
    return response(true,{data=str:sub(q.offset+1,q.offset+CHUNK),size=#str})
  end
  return response(false,{error='Operacion no reconocida'})
end
-- WorldShop 3.2 | Motor de previsualizacion aislado (sin acceso a perifericos).
-- La CPU sigue siendo compartida: probar codigo desconocido en un servidor
-- de produccion NO garantiza aislamiento frente a bucles infinitos.
local function createPreviewRunner(depId, width, height)
  local dep=db.deployments[depId]
  if not dep then return nil,'Deployment inexistente' end
  if type(dep.entry)~='string' or not validPath(dep.entry) then return nil,'Entrada invalida' end
  width=math.floor(tonumber(width) or 0);height=math.floor(tonumber(height) or 0)
  if width<20 or height<6 or width>96 or height>40 then return nil,'Resolucion permitida: 20x6 a 96x40' end
  local sourceFiles={}
  for _,f in ipairs(dep.files or {}) do
    if not validPath(f.path) then return nil,'Archivo con ruta invalida' end
    sourceFiles[f.path]=true
  end
  if not sourceFiles[dep.entry] then return nil,'No existe el programa principal' end
  local virtual, dirs={}, {['']=true}
  local usedBytes,virtualMax=0,65536
  local function resolve(path)
    if type(path)~='string' or #path>120 or path:sub(1,1)=='/' or path:find('\\',1,true) then return nil end
    local parts={}
    for part in path:gmatch('[^/]+') do
      if part=='..' then
        if #parts==0 then return nil end
        table.remove(parts)
      elseif part~='.' and part~='' then
        if not part:match('^[%w_%.%-]+$') then return nil end
        parts[#parts+1]=part
      end
    end
    return table.concat(parts,'/')
  end
  local function fileData(path)
    path=resolve(path)
    if not path or path=='' then return nil end
    if virtual[path]~=nil then return virtual[path] end
    if path=='worldtor_engine.lua' and not sourceFiles[path] then return WORLD_TOR_SOURCE end
    if not sourceFiles[path] then return nil end
    local h=fs.open(deployPath(depId,path),'r')
    if not h then return nil end
    local content=h.readAll();h.close()
    return content
  end
  local function hasDir(path)
    if path=='' or dirs[path] then return true end
    local prefix=path..'/'
    for p in pairs(sourceFiles) do if p:sub(1,#prefix)==prefix then return true end end
    for p in pairs(virtual) do if p:sub(1,#prefix)==prefix then return true end end
    return false
  end
  local function setFile(path,data)
    local before=virtual[path] or ''
    local total=usedBytes-#before+#data
    if total>virtualMax or #data>virtualMax then return false,'Disco virtual lleno (64 KB)' end
    local count=0;for _ in pairs(virtual) do count=count+1 end
    if virtual[path]==nil and count>=64 then return false,'Demasiados archivos virtuales' end
    virtual[path]=data;usedBytes=total
    local prefix=''
    for part in path:gmatch('([^/]+)/') do prefix=prefix=='' and part or prefix..'/'..part;dirs[prefix]=true end
    return true
  end
  local hex='0123456789abcdef'
  local function toBlit(c)
    if type(c)=='string' and #c==1 and hex:find(c,1,true) then return c end
    if type(c)=='number' and colors.toBlit then
      local ok,v=pcall(colors.toBlit,c)
      if ok and type(v)=='string' then return v end
    end
    return '0'
  end
  local blank=string.rep(' ',width)
  local fg0=string.rep('0',width)
  local bg0=string.rep('f',width)
  local rows={}
  for y=1,height do rows[y]={blank,fg0,bg0} end
  local tx,ty=1,1
  local foreground,background=colors.white,colors.black
  local blink=false
  local palette={}
  local tty={}
  local function writeCells(text,fore,back)
    text=tostring(text or '')
    if ty<1 or ty>height or tx>width then tx=tx+#text;return end
    local left=math.max(1,tx);local right=math.min(width,tx+#text-1)
    if right>=left then
      local a=left-tx+1;local b=right-tx+1
      local row=rows[ty]
      row[1]=row[1]:sub(1,left-1)..text:sub(a,b)..row[1]:sub(right+1)
      row[2]=row[2]:sub(1,left-1)..fore:sub(a,b)..row[2]:sub(right+1)
      row[3]=row[3]:sub(1,left-1)..back:sub(a,b)..row[3]:sub(right+1)
    end
    tx=tx+#text
  end
  tty.write=function(s)
    s=tostring(s or '');writeCells(s,string.rep(toBlit(foreground),#s),string.rep(toBlit(background),#s))
  end
  tty.blit=function(s,fc,bc)
    if type(s)~='string' or type(fc)~='string' or type(bc)~='string' or #s~=#fc or #s~=#bc then
      error('term.blit: longitudes incorrectas',2)
    end
    if fc:find('[^0-9a-f]') or bc:find('[^0-9a-f]') then error('term.blit: colores invalidos',2) end
    writeCells(s,fc,bc)
  end
  tty.clear=function()
    local f,b=string.rep(toBlit(foreground),width),string.rep(toBlit(background),width)
    for y=1,height do rows[y]={blank,f,b} end
  end
  tty.clearLine=function()
    if ty>=1 and ty<=height then rows[ty]={blank,string.rep(toBlit(foreground),width),string.rep(toBlit(background),width)} end
  end
  tty.scroll=function(n)
    n=math.floor(tonumber(n) or 0)
    if n==0 then return end
    if math.abs(n)>=height then tty.clear();return end
    if n>0 then
      for y=1,height-n do rows[y]=rows[y+n] end
      for y=height-n+1,height do rows[y]={blank,string.rep(toBlit(foreground),width),string.rep(toBlit(background),width)} end
    else
      n=-n
      for y=height,n+1,-1 do rows[y]=rows[y-n] end
      for y=1,n do rows[y]={blank,string.rep(toBlit(foreground),width),string.rep(toBlit(background),width)} end
    end
  end
  tty.getSize=function() return width,height end
  tty.getCursorPos=function() return tx,ty end
  tty.setCursorPos=function(x,y) tx=math.floor(tonumber(x) or 1);ty=math.floor(tonumber(y) or 1) end
  tty.getCursorBlink=function() return blink end
  tty.setCursorBlink=function(v) blink=not not v end
  tty.isColor=function() return true end;tty.isColour=tty.isColor
  tty.getTextColor=function()return foreground end;tty.getTextColour=tty.getTextColor
  tty.getBackgroundColor=function()return background end;tty.getBackgroundColour=tty.getBackgroundColor
  tty.setTextColor=function(c) foreground=c end;tty.setTextColour=tty.setTextColor
  tty.setBackgroundColor=function(c) background=c end;tty.setBackgroundColour=tty.setBackgroundColor
  tty.setPaletteColor=function(c,r,g,b) palette[c]={r,g,b} end;tty.setPaletteColour=tty.setPaletteColor
  tty.getPaletteColor=function(c)
    if palette[c] then return unpack(palette[c]) end
    if colors.getPaletteColor then return colors.getPaletteColor(c) end
    return 0,0,0
  end
  tty.getPaletteColour=tty.getPaletteColor
  tty.current=function()return tty end;tty.native=tty.current
  tty.redirect=function(other)
    if other~=tty then error('No se puede redirigir a una terminal externa',2) end
    return tty
  end
  local env={}
  for _,key in ipairs({'assert','error','ipairs','pairs','next','pcall','xpcall','select',
    'tonumber','tostring','type','unpack','rawequal','rawget','rawset','setmetatable','getmetatable'}) do env[key]=_G[key] end
  local function copyLib(lib)
    local clone={};for k,v in pairs(lib) do clone[k]=v end;return clone
  end
  env._G=env;env._VERSION=_VERSION
  env.math=copyLib(math);env.string=copyLib(string);env.table=copyLib(table)
  -- El random de un juego no debe alterar los tokens ni el cajero del servidor.
  local randomState=(now()+depId*7919)%2147483647
  env.math.randomseed=function(value)
    randomState=(math.floor(tonumber(value) or 1)%2147483646)+1
  end
  env.math.random=function(a,b)
    randomState=(randomState*48271)%2147483647
    local fraction=randomState/2147483647
    if a==nil then return fraction end
    if b==nil then a,b=1,a end
    a=math.floor(tonumber(a) or 1);b=math.floor(tonumber(b) or 1)
    if a>b then error('Intervalo de random invalido',2) end
    return a+math.floor(fraction*(b-a+1))
  end
  env.bit32=bit32 and copyLib(bit32) or nil
  env.colors=copyLib(colors);env.colours=env.colors
  env.keys=copyLib(keys);env.term=tty
  env.coroutine=copyLib(coroutine)
  env.textutils={serialize=textutils.serialize,unserialize=textutils.unserialize,
    serialise=textutils.serialize,unserialise=textutils.unserialize,formatTime=textutils.formatTime}
  env.fs={}
  local vfs=env.fs
  vfs.combine=function(a,b) return resolve(tostring(a or '')..'/'..tostring(b or '')) or '' end
  vfs.getName=function(p) return tostring(p or ''):match('[^/]+$') or '' end
  vfs.getDir=function(p) return tostring(p or ''):match('^(.*)/[^/]*$') or '' end
  vfs.exists=function(p) local n=resolve(p);return n~=nil and (fileData(n)~=nil or hasDir(n)) end
  vfs.isDir=function(p) local n=resolve(p);return n~=nil and hasDir(n) end
  vfs.getSize=function(p) local s=fileData(p);return s and #s or 0 end
  vfs.isReadOnly=function(p) local n=resolve(p);return n==nil or (sourceFiles[n] and virtual[n]==nil) end
  vfs.getFreeSpace=function() return virtualMax-usedBytes end
  vfs.getCapacity=function() return virtualMax end
  vfs.list=function(p)
    local n=resolve(p);if n==nil or (n~='' and not hasDir(n)) then error('No es un directorio',2) end
    local prefix=n=='' and '' or n..'/'
    local seen,arr={},{}
    for _,tbl in ipairs({sourceFiles,virtual,dirs}) do
      for path in pairs(tbl) do
        if path:sub(1,#prefix)==prefix then
          local rest=path:sub(#prefix+1);local part=rest:match('^[^/]+')
          if part and not seen[part] then seen[part]=true;arr[#arr+1]=part end
        end
      end
    end
    if prefix=='' and not seen['worldtor_engine.lua'] then arr[#arr+1]='worldtor_engine.lua' end
    table.sort(arr);return arr
  end
  vfs.makeDir=function(p)
    local n=resolve(p);if not n or n=='' or sourceFiles[n] then return false end
    dirs[n]=true;return true
  end
  vfs.delete=function(p)
    local n=resolve(p);if not n then return false end
    if virtual[n]~=nil then usedBytes=usedBytes-#virtual[n];virtual[n]=nil;return true end
    if dirs[n] and not sourceFiles[n] then dirs[n]=nil;return true end
    return false
  end
  vfs.copy=function(from,to)
    local n=resolve(to);local data=fileData(from)
    if not n or n=='' or not data or sourceFiles[n] then return false end
    return setFile(n,data)
  end
  vfs.move=function(from,to)
    local n=resolve(from);if not n or virtual[n]==nil then return false end
    if vfs.copy(from,to) then vfs.delete(n);return true end
    return false
  end
  vfs.open=function(path,mode)
    local n=resolve(path);mode=mode or 'r'
    if not n or n=='' then return nil,'Ruta no permitida' end
    if mode=='r' or mode=='rb' then
      local data=fileData(n);if not data then return nil,'Archivo inexistente' end
      local pos=1
      return {readAll=function() local s=data:sub(pos);pos=#data+1;return s end,
        readLine=function(withTrailing)
          if pos>#data then return nil end
          local e=data:find('\n',pos,true)
          local line=data:sub(pos,e and (withTrailing and e or e-1) or nil)
          pos=e and e+1 or #data+1;return line
        end,
        read=function(nchars)
          if pos>#data then return nil end
          nchars=math.max(1,math.floor(tonumber(nchars) or 1))
          local str=data:sub(pos,pos+nchars-1);pos=pos+#str;return str
        end,
        close=function() end}
    end
    if mode~='w' and mode~='a' and mode~='wb' and mode~='ab' then return nil,'Modo no permitido' end
    if sourceFiles[n] then return nil,'Solo lectura: deployment' end
    local data=(mode=='a' or mode=='ab') and (virtual[n] or '') or ''
    local closed=false
    local function flush()
      if closed then return end
      local ok,err=setFile(n,data);if not ok then error(err,2) end
    end
    return {write=function(s)
        if closed then error('Archivo cerrado',2) end
        local part=tostring(s or '')
        if #data+#part>virtualMax then error('Archivo virtual demasiado grande',2) end
        data=data..part
      end,
      writeLine=function(s) if closed then error('Archivo cerrado',2) end
        local part=tostring(s or '')..'\n';if #data+#part>virtualMax then error('Archivo virtual demasiado grande',2) end
        data=data..part end,
      flush=flush,
      close=function() flush();closed=true end}
  end
  local timers={}
  local pendingEvents={}
  env.os={clock=os.clock,time=os.time,day=os.day,date=os.date,epoch=os.epoch,
    version=function()return 'WorldShop Preview 3.2' end,
    getComputerID=function()return -1 end,
    getComputerLabel=function()return 'WorldShop PREVIEW' end,
    startTimer=function(t)
      local count=0;for _ in pairs(timers) do count=count+1 end
      if count>=64 then error('Demasiados temporizadores en la prueba',2) end
      local id=os.startTimer(math.max(0,math.min(60,tonumber(t) or 0)))
      timers[id]=true;return id
    end,
    cancelTimer=function(id) timers[id]=nil;os.cancelTimer(id) end,
    queueEvent=function(name,...)
      if type(name)~='string' or #name<1 or #name>64 or #pendingEvents>=64 then
        error('Evento virtual invalido o cola llena',2)
      end
      pendingEvents[#pendingEvents+1]={name,...}
    end,
    shutdown=function()error('Apagado virtual no disponible',2)end,
    reboot=function()error('Reinicio virtual no disponible',2)end}
  local function pull(filter)
    while true do
      local ev
      if #pendingEvents>0 then ev=table.remove(pendingEvents,1)
      else ev={coroutine.yield(filter)} end
      if filter==nil or filter==ev[1] then return unpack(ev) end
    end
  end
  env.os.pullEventRaw=pull
  env.os.pullEvent=function(filter)
    local ev={pull(filter)}
    if ev[1]=='terminate' then error('Terminated',0) end
    return unpack(ev)
  end
  env.sleep=function(t)
    local id=env.os.startTimer(t)
    while true do local _,n=env.os.pullEvent('timer');if n==id then return end end
  end
  env.write=function(str)tty.write(str) end
  env.print=function(...)
    local data={};for i=1,select('#',...) do data[i]=tostring(select(i,...)) end
    local s=table.concat(data,'\t')
    local x,y=tty.getCursorPos();local w,h=tty.getSize()
    if y>h then tty.scroll(y-h);tty.setCursorPos(x,h);y=h end
    tty.write(s);x,y=tty.getCursorPos()
    if y>=h then tty.scroll(1);tty.setCursorPos(1,h)
    else tty.setCursorPos(1,y+1) end
  end
  env.printError=function(...)
    local prev=tty.getTextColor();tty.setTextColor(colors.red);env.print(...);tty.setTextColor(prev)
  end
  env.read=function(replace)
    local chars='';local mask=type(replace)=='string' and replace:sub(1,1) or nil
    while true do
      local ev,a=env.os.pullEvent()
      if ev=='char' and type(a)=='string' and #chars<256 then
        chars=chars..a;tty.write(mask or a)
      elseif ev=='paste' and type(a)=='string' then
        local s=a:sub(1,math.max(0,256-#chars));chars=chars..s
        tty.write(mask and mask:rep(#s) or s)
      elseif ev=='key' and a==keys.backspace and #chars>0 then
        chars=chars:sub(1,-2);local x,y=tty.getCursorPos();tty.setCursorPos(math.max(1,x-1),y)
        tty.write(' ');tty.setCursorPos(math.max(1,x-1),y)
      elseif ev=='key' and a==keys.enter then env.print();return chars end
    end
  end
  local shellDir='';local currentProg=dep.entry
  local function entryPath(path)
    if type(path)~='string' then return nil end
    if path:sub(1,1)=='/' then return nil end
    local n=resolve((shellDir=='' and '' or shellDir..'/')..path)
    return n
  end
  local function safeLoad(path)
    local n=entryPath(path)
    local data=n and fileData(n)
    if not data then return nil,'El archivo no existe en esta preview: '..tostring(path) end
    return load(data,'@preview/'..n,'t',env)
  end
  env.loadfile=safeLoad
  env.dofile=function(path) local f,err=safeLoad(path);if not f then error(err,2) end;return f() end
  local function runFile(path,...)
    local n=entryPath(path)
    local prev=currentProg
    local f,err=safeLoad(path)
    if not f then return false,err end
    currentProg=n
    local ok,res=pcall(f,...)
    currentProg=prev
    if not ok then return false,res end
    return true,res
  end
  env.shell={dir=function()return shellDir end,setDir=function(p)
      local n=entryPath(p);if n and hasDir(n) then shellDir=n end end,
    resolve=function(p)return entryPath(p) end,
    getRunningProgram=function()return currentProg end,
    run=runFile,execute=runFile}
  env.require=(function()
    local loaded={}
    return function(name)
      if type(name)~='string' or not name:match('^[%w_%.]+$') then error('Modulo no permitido',2) end
      local path=name:gsub('%.','/')..'.lua'
      if loaded[name]~=nil then return loaded[name] end
      local chunk,err=safeLoad(path)
      if not chunk then error(err,2) end
      loaded[name]=true
      local result=chunk(name)
      if result~=nil then loaded[name]=result end
      return loaded[name]
    end
  end)()
  env.parallel={}
  local function parallelRun(all,...)
    local funcs={...};local tasks={};local live=#funcs
    for i,f in ipairs(funcs) do
      if type(f)~='function' then error('parallel: se requieren funciones',2) end
      tasks[i]={co=coroutine.create(f),filter=nil}
    end
    local function resumeTask(i,event)
      local task=tasks[i];if not task then return false end
      local ok,res=coroutine.resume(task.co,unpack(event))
      if not ok then error(res,0) end
      if coroutine.status(task.co)=='dead' then tasks[i]=nil;live=live-1;return true end
      task.filter=res;return false
    end
    for i=1,#funcs do if resumeTask(i,{}) and not all then return i end end
    while live>0 do
      local event={env.os.pullEventRaw()}
      for i=1,#funcs do
        local task=tasks[i]
        if task and (task.filter==nil or task.filter==event[1]) then
          if resumeTask(i,event) and not all then return i end
        end
      end
    end
  end
  env.parallel.waitForAny=function(...)return parallelRun(false,...) end
  env.parallel.waitForAll=function(...)return parallelRun(true,...) end
  env.paintutils={}
  env.paintutils.drawPixel=function(x,y,c)
    local color=tty.getBackgroundColor();tty.setCursorPos(x,y)
    if c then tty.setBackgroundColor(c) end;tty.write(' ')
    tty.setBackgroundColor(color)
  end
  env.paintutils.drawLine=function(x1,y1,x2,y2,c)
    x1=math.floor(x1);y1=math.floor(y1);x2=math.floor(x2);y2=math.floor(y2)
    local dx=math.abs(x2-x1);local dy=math.abs(y2-y1)
    local sx=x1<x2 and 1 or -1;local sy=y1<y2 and 1 or -1;local err=dx-dy
    for _=1,400 do
      env.paintutils.drawPixel(x1,y1,c);if x1==x2 and y1==y2 then break end
      local e2=2*err;if e2>-dy then err=err-dy;x1=x1+sx end
      if e2<dx then err=err+dx;y1=y1+sy end
    end
  end
  env.paintutils.drawBox=function(x1,y1,x2,y2,c)
    env.paintutils.drawLine(x1,y1,x2,y1,c);env.paintutils.drawLine(x2,y1,x2,y2,c)
    env.paintutils.drawLine(x2,y2,x1,y2,c);env.paintutils.drawLine(x1,y2,x1,y1,c)
  end
  env.paintutils.drawFilledBox=function(x1,y1,x2,y2,c)
    for y=math.min(y1,y2),math.max(y1,y2) do env.paintutils.drawLine(x1,y,x2,y,c) end
  end
  local runner={rows=rows,timers=timers,finished=false,status='LISTO',width=width,height=height}
  local co=coroutine.create(function()
    local chunk,err=safeLoad(dep.entry)
    if not chunk then error(err,0) end
    return chunk()
  end)
  -- Algunos entornos ofrecen debug.sethook; si no, no hay preempcion de CPU.
  if debug and type(debug.sethook)=='function' then
    pcall(debug.sethook,co,function() error('Limite de instrucciones de la preview',0) end,'',300000)
  end
  runner.filter=nil
  function runner:step(ev)
    if self.finished then return end
    ev=ev or {}
    if ev[1]=='timer' then self.timers[ev[2]]=nil end
    if self.filter and self.filter~=ev[1] then return end
    local ok,res=coroutine.resume(co,unpack(ev))
    if not ok then
      self.finished=true;self.status='ERROR: '..tostring(res):sub(1,95)
    elseif coroutine.status(co)=='dead' then
      self.finished=true;self.status='JUEGO FINALIZADO'
    else self.filter=res;self.status='EN EJECUCION' end
  end
  function runner:draw(target,top)
    for y=1,self.height do
      target.setCursorPos(1,y+top-1)
      target.blit(rows[y][1],rows[y][2],rows[y][3])
    end
  end
  function runner:close()
    for id in pairs(timers) do pcall(os.cancelTimer,id);timers[id]=nil end
    self.finished=true
  end
  return runner
end

-- Previews remotas: un ticket por conexion, acceso solo al desarrollador.
local function sendPreviewRows(session,full)
  local runner=session.runner
  if not runner then return end
  local packet={}
  local function flush()
    if #packet==0 then return end
    rednet.send(session.sender,{v=1,op='TEST_FRAME',sid=session.sid,
      rows=packet,status=runner.status},P)
    packet={}
  end
  for y,row in ipairs(runner.rows) do
    local signature=row[1]..row[2]..row[3]
    if full or session.last[y]~=signature then
      session.last[y]=signature
      packet[#packet+1]={y,row[1],row[2],row[3]}
      if #packet>=5 then flush() end
    end
  end
  flush()
  if runner.finished and not session.sentFinish then
    session.sentFinish=true
    rednet.send(session.sender,{v=1,op='TEST_FINISHED',sid=session.sid,status=runner.status},P)
  end
end
closePreview=function(session)
  if not session then return end
  if session.runner then session.runner:close() end
  activeTests[session.sid]=nil
end
launchPreview=function(sender,acc,q)
  local dep=db.deployments[tonumber(q.deployment)]
  local game=dep and db.games[dep.gameId]
  if not dep or not game or game.owner~=acc.name or not acc.dev or dep.status~='pending' then
    return response(false,{error='Solo el desarrollador puede probar su preview pendiente'})
  end
  local count=0;local replaceSessions={}
  for _,s in pairs(activeTests) do
    if s.sender==sender then replaceSessions[#replaceSessions+1]=s else count=count+1 end
  end
  for _,s in ipairs(replaceSessions) do closePreview(s) end
  if count>=2 then return response(false,{error='Servidor de pruebas ocupado (maximo 2 sesiones)'}) end
  local w,h=tonumber(q.w),tonumber(q.h)
  if not w or not h then return response(false,{error='Faltan dimensiones del terminal'}) end
  w,h=math.floor(w),math.floor(h)
  local runner,err=createPreviewRunner(dep.id,w,h)
  if not runner then return response(false,{error=err}) end
  local ticket=sid()
  local session={sid=ticket,sender=sender,owner=acc.name,runner=runner,
    deadline=now()+180000,last={},sentFinish=false}
  activeTests[ticket]=session
  runner:step({})
  return response(true,{sid=ticket,w=w,h=h,seconds=180,
    title=game.title,version=dep.version,finished=runner.finished,status=runner.status})
end
local allowedTestEvents={char=true,key=true,key_up=true,paste=true,
  mouse_click=true,mouse_up=true,mouse_drag=true,mouse_scroll=true}
local function remoteTestMessage(sender,msg)
  if type(msg)~='table' or msg.v~=1 or type(msg.sid)~='string' then return end
  local session=activeTests[msg.sid]
  if not session or session.sender~=sender then return end
  if msg.op=='TEST_STOP' then closePreview(session);return end
  if msg.op=='TEST_REFRESH' then sendPreviewRows(session,true);return end
  if msg.op~='TEST_INPUT' or now()>session.deadline or session.runner.finished then return end
  local e=msg.event
  if type(e)~='table' or not allowedTestEvents[e[1]] then return end
  if e[1]=='char' then
    if type(e[2])~='string' or #e[2]~=1 then return end
  elseif e[1]=='paste' then
    if type(e[2])~='string' or #e[2]>256 then return end
  elseif e[1]=='key' or e[1]=='key_up' then
    if type(e[2])~='number' or e[2]<1 or e[2]>512 or e[2]~=math.floor(e[2]) then return end
  else
    if type(e[2])~='number' or type(e[3])~='number' or type(e[4])~='number' then return end
    if e[3]<1 or e[3]>session.runner.width or e[4]<1 or e[4]>session.runner.height then return end
    if e[3]~=math.floor(e[3]) or e[4]~=math.floor(e[4]) then return end
  end
  session.runner:step(e)
  sendPreviewRows(session,false)
end

local function send(sender,id,res) res.v=1;res.req=id;rednet.send(sender,res,P) end
local function network()
  rednet.host(P,HOST)
  print('WORLD SHOP SERVER ONLINE - ID '..os.getComputerID())
  print('Protocolo: '..P..' | Previews remotas activas: maximo 2')
  print('Cajero: ID '..cashierCfg.cashierId..' | Enlace automatico')
  local heartbeat=os.startTimer(1)
  while true do
    local ev={os.pullEventRaw()}
    if ev[1]=='rednet_message' and ev[4]==P then
      local sender,q=ev[2],ev[3]
      if type(q)=='table' then
        if q.op=='TEST_INPUT' or q.op=='TEST_REFRESH' or q.op=='TEST_STOP' then
          remoteTestMessage(sender,q)
        elseif type(q.req)=='string' and #q.req<=100 then
          local key=sender..':'..q.req
          local res=cache[key]
          if not res then
            local ok,ret=pcall(process,sender,q)
            res=ok and ret or response(false,{error='Fallo del servidor: '..tostring(ret)})
            cache[key]=res
            local cnt=0;for _ in pairs(cache) do cnt=cnt+1 end
            if cnt>300 then cache={} end
          end
          send(sender,q.req,res)
          if q.op=='TEST_START' and res.ok then
            local test=activeTests[res.sid]
            if test then sendPreviewRows(test,true) end
          end
        end
      end
    elseif ev[1]=='timer' then
      if ev[2]==heartbeat then
        heartbeat=os.startTimer(1)
        for _,test in pairs(activeTests) do
          if now()>=test.deadline then
            rednet.send(test.sender,{v=1,op='TEST_FINISHED',sid=test.sid,status='TIEMPO AGOTADO (180s)'},P)
            closePreview(test)
          end
        end
      end
      for _,test in pairs(activeTests) do
        if test.runner.timers[ev[2]] then
          test.runner:step(ev)
          sendPreviewRows(test,false)
        end
      end
    end
  end
end

-- Moderacion local: exactamente el mismo motor aislado que la prueba remota.
local function reviewGame(depId)
  local dep=db.deployments[depId]
  if not dep then return 'Deployment inexistente' end
  local game=db.games[dep.gameId]
  if not game then return 'Juego inexistente' end
  local target=term.current()
  local w,h=target.getSize()
  if w<30 or h<11 then return 'Terminal demasiado pequena (minimo 30x11)' end
  local runner,err=createPreviewRunner(depId,w,h-3)
  if not runner then return err end
  local function bar()
    target.setBackgroundColor(colors.blue);target.setTextColor(colors.white)
    for y=1,3 do target.setCursorPos(1,y);target.write((' '):rep(w)) end
    target.setCursorPos(2,1)
    target.write(('D'..depId..' '..game.title..' v'..dep.version):sub(1,w-2))
    target.setCursorPos(2,2);target.setBackgroundColor(colors.green);target.write(' APROBAR ')
    target.setBackgroundColor(colors.red);target.write(' RECHAZAR ')
    target.setBackgroundColor(colors.gray);target.write(' SALIR ')
    target.setCursorPos(2,3);target.setBackgroundColor(colors.blue)
    target.write(('F5 aprobar | F6 rechazar | F7 salir | '..runner.status):sub(1,w-2))
    target.setBackgroundColor(colors.black);target.setTextColor(colors.white)
  end
  local function render() bar();runner:draw(target,4) end
  runner:step({});render()
  local reviewTimer=os.startTimer(180)
  while true do
    local ev={os.pullEventRaw()};local kind=ev[1]
    local choice=nil
    if kind=='terminate' then choice='exit'
    elseif kind=='term_resize' then choice='exit'
    elseif kind=='key' then
      if ev[2]==keys.f5 then choice='approve'
      elseif ev[2]==keys.f6 then choice='reject'
      elseif ev[2]==keys.f7 then choice='exit' end
    elseif kind=='monitor_touch' then ev={'mouse_click',1,ev[3],ev[4]};kind='mouse_click' end
    if kind=='mouse_click' and ev[4]==2 then
      if ev[3]>=2 and ev[3]<=10 then choice='approve'
      elseif ev[3]>=11 and ev[3]<=21 then choice='reject'
      elseif ev[3]>=22 and ev[3]<=29 then choice='exit' end
    end
    if kind=='timer' and ev[2]==reviewTimer then choice='timeout' end
    if choice then
      pcall(os.cancelTimer,reviewTimer)
      runner:close()
      target.setBackgroundColor(colors.black);target.setTextColor(colors.white)
      if choice=='approve' then
        if dep.status~='pending' then return 'No es una preview pendiente' end
        local ok,msg=publish(depId,false);return ok and 'approved' or msg
      elseif choice=='reject' then
        if dep.status~='pending' then return 'No es una preview pendiente' end
        local ok,msg=reject(depId);return ok and 'rejected' or msg
      end
      return choice
    end
    if not runner.finished then
      if kind=='timer' then
        if runner.timers[ev[2]] then runner:step(ev);render() end
      elseif kind=='char' or kind=='key' or kind=='key_up' or kind=='paste' then
        runner:step(ev);render()
      elseif kind=='mouse_click' or kind=='mouse_up' or kind=='mouse_drag' or kind=='mouse_scroll' then
        if ev[4]>=4 then ev[4]=ev[4]-3;runner:step(ev);render() end
      end
    end
  end
end

local function admin()
  local view='inicio';local selection=nil;local page=0;local notice='Deployments en linea';local historyGame=nil;local historySelection=nil
  local function pending()
    local arr={};for _,d in pairs(db.deployments) do if d.status=='pending' then arr[#arr+1]=d end end
    table.sort(arr,function(a,b)return a.id<b.id end)
    return arr
  end
  local function counts()
    local n,g,pend,prod,deploys=0,0,0,0,0
    for _ in pairs(db.accounts) do n=n+1 end
    for _,item in pairs(db.games) do g=g+1;if item.status=='approved' then prod=prod+1 end end
    for _,d in pairs(db.deployments) do deploys=deploys+1;if d.status=='pending' then pend=pend+1 end end
    return n,g,pend,prod,deploys
  end
  local function line(y,str,fg,bg)
    local w,h=term.getSize();if y<1 or y>h then return end
    term.setCursorPos(1,y);term.setTextColor(fg or colors.white);term.setBackgroundColor(bg or colors.black)
    local s=tostring(str or '');term.write(s:sub(1,w)..(' '):rep(math.max(0,w-#s)))
  end
  local function draw()
    local w,h=term.getSize();term.setBackgroundColor(colors.black);term.clear()
    local n,g,pend,prod,deploys=counts()
    line(1,'  WORLDSHOP  |  CONTROL CENTRAL',colors.white,colors.blue)
    line(2,'  ID '..os.getComputerID()..'  * REDNET ONLINE  *  '..pend..' PENDIENTES',colors.white,colors.blue)
    line(3,' [1] Panel [2] Previews [3] Cajero [4] Datos [5] Historial',colors.cyan,colors.gray)
    if view=='inicio' then
      line(5,'  RESUMEN DE LA PLATAFORMA',colors.lightBlue)
      line(7,('  CUENTAS: %-8d JUEGOS: %-8d'):format(n,g),colors.white)
      line(9,'  JUEGOS EN REVISION: '..pend,pend>0 and colors.orange or colors.lime)
      line(11,'  PROD: '..prod..'  | DEPLOYMENTS: '..deploys,colors.lime)
      line(13,'  Los juegos se guardan en /'..ROOT,colors.gray)
      line(15,'  [2] Previews pendientes  [5] Historial / Rollback',colors.yellow)
    elseif view=='pendientes' then
      local arr=pending()
      line(5,'  REVISIONES  |  '..#arr..' pendientes',colors.lightBlue)
      local maxRows=math.max(1,h-11)
      for i=1,maxRows do
        local game=arr[page*maxRows+i]
        if game then
          local chosen=selection==game.id
          line(5+i,('  D%d  J%d  %-14s v%s'):format(game.id,game.gameId,db.games[game.gameId].title:sub(1,14),game.version),chosen and colors.black or colors.white,chosen and colors.lightBlue or colors.black)
        end
      end
      if #arr==0 then line(8,'  Todo revisado. No hay pendientes.',colors.lime) end
      local current=selection and db.deployments[selection]
      if current then line(h-5,'  Seleccionado D'..selection..' | '..current.version,colors.yellow) end
      line(h-4,'  [T] Probar  [A] Aprobar  [R] Rechazar',colors.white,colors.blue)
      line(h-3,'  [N] Siguiente  [B] Anterior',colors.white,colors.gray)
    elseif view=='historial' then
      line(5,'  DEPLOYMENTS | historial y rollback',colors.lightBlue)
      local arr={}
      for _,d in pairs(db.deployments) do arr[#arr+1]=d end
      table.sort(arr,function(a,b)return a.id>b.id end)
      local rows=math.max(1,h-11)
      for i=1,rows do
        local d=arr[page*rows+i]
        if d then
          local g=db.games[d.gameId]
          line(5+i,(' D%-4d J%-3d v%-9s %s'):format(d.id,d.gameId,d.version,d.status:upper()),
            historySelection==d.id and colors.black or colors.white,
            historySelection==d.id and colors.lightBlue or colors.black)
        end
      end
      if #arr==0 then line(8,'  Sin deployments',colors.yellow) end
      local selected=historySelection and db.deployments[historySelection]
      if selected then
        local g=db.games[selected.gameId]
        line(h-5,' '..g.title:sub(1,17)..'  '..(selected.notes or ''):sub(1,32),colors.yellow)
      end
      line(h-4,'  [T] Probar [V] Volver a esta version',colors.white,colors.blue)
      line(h-3,'  [N] Siguiente [B] Anterior  [L] Logs',colors.white,colors.gray)
    elseif view=='cajero' then
      line(5,'  CAJERO  |  LIGHTMAN CURRENCY',colors.lightBlue)
      line(7,cashierCfg.cashierId==0 and '  Sin cajero: se vinculara automaticamente' or ('  Cajero autorizado ID: '..cashierCfg.cashierId),colors.white)
      line(9,'  1 barril a la derecha: INGRESO',colors.yellow)
      line(10,'  1 barril abajo: ALMACEN',colors.yellow)
      line(12,'  [C] Cambiar / desvincular cajero',colors.lime)
      line(13,'  [K] Mostrar clave de enlace',colors.orange)
      line(15,'  Advertencia: Rednet sin cifrar',colors.red)
    else
      line(5,'  ESTADISTICAS',colors.lightBlue)
      line(7,'  Usuarios registrados: '..n,colors.white)
      line(9,'  Juegos publicados: '..prod,colors.white)
      line(11,'  Revisiones pendientes: '..pend,colors.orange)
      local deposits=0;for _ in pairs(db.receipts) do deposits=deposits+1 end
      line(13,'  Ingresos procesados: '..deposits,colors.white)
      line(15,'  DB: '..DBFILE,colors.gray)
    end
    line(h-1,'  '..notice:sub(1,w-2),colors.yellow)
    line(h,' [Q] Apagar  |  Pulsa teclas o haz clic',colors.lightGray,colors.gray)
  end
  local function choose(id)
    if id and db.deployments[id] and db.deployments[id].status=='pending' then selection=id;return true end
    return false
  end
  while true do
    draw()
    local e={os.pullEventRaw()}
    if e[1]=='monitor_touch' then e={'mouse_click',1,e[3],e[4]} end
    local action=nil
    if e[1]=='char' then action=tostring(e[2]):lower()
    elseif e[1]=='key' then
      if e[2]==keys.one then action='1' elseif e[2]==keys.two then action='2'
      elseif e[2]==keys.three then action='3' elseif e[2]==keys.four then action='4' elseif e[2]==keys.five then action='5' end
    elseif e[1]=='mouse_click' then
      local x,y=e[3],e[4];local w,h=term.getSize()
      if y==3 then if x<=11 then action='1' elseif x<=24 then action='2' elseif x<=35 then action='3' elseif x<=46 then action='4' else action='5' end
      elseif view=='pendientes' and y>=6 and y<=h-6 then
        local arr=pending();local maxRows=math.max(1,h-11)
        local g=arr[page*maxRows+y-5]
        if g then choose(g.id);notice='Seleccionado #'..g.id end
      elseif view=='historial' and y>=6 and y<=h-6 then
        local arr={};for _,d in pairs(db.deployments) do arr[#arr+1]=d end
        table.sort(arr,function(a,b)return a.id>b.id end)
        local rows=math.max(1,h-11);local d=arr[page*rows+y-5]
        if d then historySelection=d.id end
      elseif view=='historial' and y==h-4 then
        if x<13 then action='t' else action='v' end
      elseif view=='pendientes' and y==h-4 then
        if x<14 then action='t' elseif x<28 then action='a' else action='r' end
      elseif view=='cajero' and y==12 then action='c'
      elseif view=='cajero' and y==13 then action='k' end
    elseif e[1]=='terminate' then return end
    if action=='1' then view='inicio'
    elseif action=='2' then view='pendientes';page=0;local a=pending();selection=a[1] and a[1].id or nil
    elseif action=='3' then view='cajero'
    elseif action=='4' then view='datos'
    elseif action=='5' then view='historial';page=0;historySelection=nil
    elseif action=='q' then return
    elseif view=='pendientes' then
      local arr=pending();local maxRows=math.max(1,select(2,term.getSize())-11)
      if action=='n' then page=math.min(page+1,math.max(0,math.ceil(#arr/maxRows)-1));selection=arr[page*maxRows+1] and arr[page*maxRows+1].id or nil
      elseif action=='b' then page=math.max(0,page-1);selection=arr[page*maxRows+1] and arr[page*maxRows+1].id or nil
      elseif action=='t' and selection then
        local d=db.deployments[selection]
        if d and d.status=='pending' then
          local result=reviewGame(selection);notice='Prueba terminada: '..tostring(result)
          local a=pending();selection=a[1] and a[1].id or nil
        end
      elseif (action=='a' or action=='r') and selection then
        local d=db.deployments[selection]
        if d and d.status=='pending' then
          local ok,msg=action=='a' and publish(selection,false) or reject(selection)
          notice='D'..selection..': '..tostring(msg)
          local a=pending();selection=a[1] and a[1].id or nil
        end
      end
    elseif view=='historial' then
      local arr={};for _,d in pairs(db.deployments) do arr[#arr+1]=d end
      table.sort(arr,function(a,b)return a.id>b.id end)
      local rows=math.max(1,select(2,term.getSize())-11)
      if action=='n' then page=math.min(page+1,math.max(0,math.ceil(#arr/rows)-1));historySelection=nil
      elseif action=='b' then page=math.max(0,page-1);historySelection=nil
      elseif historySelection then
        local d=db.deployments[historySelection]
        if action=='t' and d then
          local res=reviewGame(d.id);notice='Preview D'..d.id..': '..tostring(res)
        elseif action=='l' and d then
          term.clear();term.setCursorPos(1,1)
          print('DEPLOYMENT D'..d.id..' | '..d.version..' | '..d.status)
          print('Notas: '..(d.notes or ''))
          for _,entry in ipairs(d.logs or {}) do print('> '..entry) end
          print('ENTER para volver');read()
        elseif action=='v' and d then
          term.clear();term.setCursorPos(1,1)
          print('RESTAURAR PRODUCCION D'..d.id..' / '..d.version)
          print('Juego: '..db.games[d.gameId].title)
          print('Escribe RESTAURAR para confirmar:')
          local confirmation=read()
          if confirmation=='RESTAURAR' then
            local ok,msg=publish(d.id,true);notice=msg
          else notice='Cancelado' end
        end
      end
    elseif view=='cajero' then
      if action=='c' then
        term.setBackgroundColor(colors.black);term.clear();print('ID servidor: '..os.getComputerID());print('Cajero actual: '..cashierCfg.cashierId)
        write('ID ordenador cajero (0 para desactivar): ')
        local v=tonumber(read());if v and v>=0 and v==math.floor(v) then cashierCfg.cashierId=v;saveObj(fs.combine(ROOT,'cashier'),cashierCfg);notice='Cajero autorizado: '..v end
      elseif action=='k' then
        term.setBackgroundColor(colors.black);term.clear();print('CLAVE SECRETA DEL CAJERO (NO COMPARTIR):')
        print(cashierCfg.key);print('Pulsa ENTER');read();notice='Clave consultada'
      end
    end
  end
end
parallel.waitForAny(network,admin)