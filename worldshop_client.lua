-- WorldShop 3.3 | Tienda / Deployments
-- Motor integrado. Se copia automaticamente cuando un juego lo necesita.
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
local function ensureWorldTor(folder)
  local path=fs.combine(folder,'worldtor_engine.lua')
  if fs.exists(path) then return true end
  local needed=false
  for _,name in ipairs(fs.list(folder)) do
    if name:match('%.lua$') then
      local f=fs.open(fs.combine(folder,name),'r')
      if f then local code=f.readAll() or '';f.close()
        if code:find('worldtor_engine.lua',1,true) then needed=true;break end
      end
    end
  end
  if not needed then return true end
  local h=fs.open(path,'w')
  if not h then return false,'No se pudo instalar WorldTor Engine' end
  h.write(WORLD_TOR_SOURCE);h.close()
  return true
end

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
local function line(y,str,c,b)
  local w,h=term.getSize();if y<1 or y>h then return end
  term.setCursorPos(1,y);bg(b or colors.black);col(c or colors.white)
  str=tostring(str or '')
  term.write(str:sub(1,w)..string.rep(' ',math.max(0,w-#str)))
end
local function screen(title,sub)
  local w,h=term.getSize();bg(colors.black);term.clear()
  line(1,'  W  WORLDSHOP  /  WORLD STUDIOS',colors.white,colors.blue)
  line(2,'  '..tostring(title or 'TIENDA')..'  |  Conexion Rednet',colors.cyan,colors.gray)
  line(3,string.rep('-',w),colors.lightBlue)
  if sub then line(4,' '..sub,colors.yellow) else line(4,'',colors.white) end
  line(h,'  WorldShop v3.2  -  World Studios',colors.lightGray)
  term.setCursorPos(1,5);col(colors.white);bg(colors.black)
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
      col(colors.lightBlue);write('Contrasena: ');col(colors.white);local pass=read('*')
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
local function checksum(data)
  local a,b=1,0
  for i=1,#data do a=(a+data:byte(i))%65521;b=(b+a)%65521 end
  return string.format('%08x',b*65536+a)
end
local function localMeta(id)
  local file=fs.combine('worldshop_games/ws_'..id,'.worldshop')
  if not fs.exists(file) then return nil end
  local h=fs.open(file,'r');if not h then return nil end
  local ok,r=pcall(textutils.unserialize,h.readAll());h.close()
  return ok and type(r)=='table' and r or nil
end
local function latest(game)
  local meta=localMeta(game.id)
  if not meta then return 'No instalado' end
  if meta.deployment==game.deployment then return 'Actualizado '..tostring(meta.version) end
  return 'ACTUALIZACION: '..tostring(meta.version or '?')..' -> '..tostring(game.version)
end
local function install(game,preview)
  local manifest=preview and rpc('PREVIEW_MANIFEST',{deployment=preview.id}) or rpc('DOWNLOAD_MANIFEST',{id=game.id})
  if not manifest.ok then status(manifest);waitkey();return end
  local root=preview and 'worldshop_previews' or 'worldshop_games'
  if not fs.exists(root) then fs.makeDir(root) end
  local dirname=preview and ('preview_D'..preview.id) or ('ws_'..game.id)
  local target=fs.combine(root,dirname)
  local stage=fs.combine(root,'.'..dirname..'_staging')
  local backup=fs.combine(root,'.'..dirname..'_previous')
  if fs.exists(stage) then fs.delete(stage) end
  fs.makeDir(stage)
  print('Deployment D'..tostring(manifest.deployment)..' / '..tostring(manifest.version))
  print('Descargando a un directorio temporal...')
  local success=true
  for i,f in ipairs(manifest.files or {}) do
    local path=fs.combine(stage,f.path)
    local dir=fs.getDir(path);if not fs.exists(dir) then fs.makeDir(dir) end
    local file=fs.open(path,'w')
    if not file then printError('Sin espacio/permiso para '..f.path);success=false;break end
    local at=0;local data={}
    while at<f.size do
      local r=rpc(preview and 'PREVIEW_CHUNK' or 'DOWNLOAD_CHUNK',{id=game.id,deployment=manifest.deployment,path=f.path,offset=at},4)
      if not r.ok or type(r.data)~='string' or #r.data==0 or r.size~=f.size then
        printError('Fallo descargando '..f.path..': '..tostring(r.error or 'incompleto'))
        success=false;break
      end
      file.write(r.data);data[#data+1]=r.data;at=at+#r.data
    end
    file.close()
    if not success then break end
    if at~=f.size or (f.checksum and checksum(table.concat(data))~=f.checksum) then
      printError('Integridad incorrecta: '..f.path);success=false;break
    end
    print(('%d/%d OK %s'):format(i,#manifest.files,f.path))
  end
  if success then
    -- Preserva las carpetas de partidas y datos personales, nunca borra el ultimo juego sano hasta terminar.
    if fs.exists(target) then
      for _,folder in ipairs({'saves','userdata'}) do
        local old=fs.combine(target,folder)
        local new=fs.combine(stage,folder)
        if fs.exists(old) and not fs.exists(new) then fs.copy(old,new) end
      end
    end
    local okEngine,erEngine=ensureWorldTor(stage)
    if not okEngine then printError(erEngine);success=false end
  end
  if success then
    local marker=fs.open(fs.combine(stage,'.worldshop'),'w')
    if not marker then printError('No se pudo escribir la version');success=false
    else
      marker.write(textutils.serialize({entry=manifest.entry,title=manifest.title,
        version=manifest.version,deployment=manifest.deployment,notes=manifest.notes}))
      marker.close()
    end
  end
  if not success then
    if fs.exists(stage) then fs.delete(stage) end
    printError('Actualizacion cancelada. La version instalada no se ha modificado.')
    return
  end
  if fs.exists(backup) then fs.delete(backup) end
  if fs.exists(target) then fs.move(target,backup) end
  local ok,moveError=pcall(fs.move,stage,target)
  if not ok then
    if fs.exists(backup) and not fs.exists(target) then fs.move(backup,target) end
    printError('No se pudo activar la version: '..tostring(moveError));return
  end
  print('INSTALADO: '..tostring(manifest.version)..' | D'..tostring(manifest.deployment))
  print('Copia anterior: /'..backup)
  return true
end
local function play(game,preview)
  local target=preview and fs.combine('worldshop_previews','preview_D'..preview.id) or fs.combine('worldshop_games','ws_'..game.id)
  local mark=fs.combine(target,'.worldshop')
  if not fs.exists(mark) then print('Aun no instalado.');return end
  local h=fs.open(mark,'r');local meta=textutils.unserialize(h.readAll());h.close()
  if not meta or not meta.entry then printError('Falta marcador de entrada');return end
  if not fs.exists(fs.combine(target,meta.entry)) then printError('Falta script principal');return end
  local okEngine,erEngine=ensureWorldTor(target)
  if not okEngine then printError(erEngine);return end
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
    for i,g in ipairs(arr) do print(i..'. '..g.title..' v'..tostring(g.version or '?')) end
    print('');local sel=ask('Numero / [B] volver: '):lower()
    if sel=='b' or sel=='' then return end
    local game=arr[tonumber(sel)]
    if game then
      screen(game.title,'Produccion v'..tostring(game.version or '?'))
      print(latest(game));print('')
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
local function bumpPatch(str)
  local a,b,c=tostring(str or ''):match('^(%d+)%.(%d+)%.(%d+)$')
  return a and (a..'.'..b..'.'..(tonumber(c)+1)) or '1.0.1'
end
local function upload(existing)
  screen(existing and 'NUEVO DEPLOYMENT' or 'NUEVO JUEGO',existing and ('Juego #'..existing.id..' '..existing.title) or 'World Developers')
  if existing then
    print('Produccion: '..tostring(existing.version))
    if existing.pendingDeployment then
      printError('Hay un deployment pendiente D'..existing.pendingDeployment)
      waitkey();return
    end
  end
  local folder=ask('Carpeta del juego: ')
  if not fs.exists(folder) or not fs.isDir(folder) then printError('Carpeta inexistente');waitkey();return end
  local ok,files=pcall(gather,folder)
  if not ok then printError(files);waitkey();return end
  local total=0;for _,f in ipairs(files) do total=total+f.size end
  if #files<1 or #files>30 or total>600000 then printError('Limite: 30 archivos, 600KB');waitkey();return end
  print('Archivos: '..#files..' | '..total..' bytes')
  local entry=ask('Script principal',existing and existing.entry or 'main.lua')
  local title,desc,genre,price
  if existing then
    title,desc,genre,price=existing.title,existing.desc,existing.genre,existing.price
    print('ID, titulo, precio y licencias se conservaran.')
  else
    title=ask('Titulo: ')
    desc=ask('Descripcion: ')
    genre=ask('Genero: ')
    price=tonumber(ask('Precio WS$ (0=gratis): '))
    if not price then printError('Precio invalido');waitkey();return end
  end
  local version=ask('Version semver: ',existing and bumpPatch(existing.version) or '1.0.0')
  local notes=ask('Notas de despliegue: ','Primer lanzamiento')
  if ask('Crear preview y enviar a revision? (s/n): '):lower()~='s' then return end
  local specs={};for _,f in ipairs(files) do specs[#specs+1]={path=f.path,size=f.size} end
  local init=rpc('UPLOAD_INIT',{gameId=existing and existing.id or nil,title=title,desc=desc,
    genre=genre,price=price,entry=entry,version=version,notes=notes,files=specs})
  if not init.ok then status(init);waitkey();return end
  local chunk=init.chunk or 1600
  for i,f in ipairs(files) do
    print('['..i..'/'..#files..'] '..f.path)
    local h=fs.open(f.localFile,'r');if not h then printError('No se puede leer archivo');return end
    local data=h.readAll();h.close()
    local at=0
    while at<#data do
      local part=data:sub(at+1,at+chunk)
      local r=rpc('UPLOAD_CHUNK',{upload=init.upload,path=f.path,offset=at,data=part},5)
      if not r.ok then status(r);waitkey();return end
      at=at+#part
    end
  end
  local done=rpc('UPLOAD_COMMIT',{upload=init.upload},7)
  status(done)
  if done.ok then
    print('Juego #J'..done.id..' | Deployment #D'..done.deployment)
    print('v'..done.version..'  Estado: '..done.status)
    if done.status=='pending' then print('Preview lista; pendiente de aprobacion.') end
  end
  waitkey()
end
-- Vista remota: el juego se ejecuta en el servidor; solo se envian teclas y filas.
local function testOnServer(game,dep)
  local host=term.current()
  local w,h=host.getSize()
  if w<30 or h<11 then
    printError('Necesitas un terminal de al menos 30x11 para probar en servidor.')
    waitkey();return
  end
  local start=rpc('TEST_START',{deployment=dep.id,w=w,h=h-3},6)
  if not start.ok then
    status(start)
    print('Comprueba que SERVIDOR y CLIENTE usan WorldShop 3.3.')
    waitkey();return
  end
  local ticket=start.sid
  if type(ticket)~='string' then
    printError('El servidor devolvio una sesion de prueba invalida.');waitkey();return
  end
  local result=start.status or 'Iniciando'
  local started=os.epoch('utc')
  local alive=true
  local function titleBar()
    host.setBackgroundColor(colors.blue);host.setTextColor(colors.white)
    for y=1,3 do host.setCursorPos(1,y);host.write((' '):rep(w)) end
    host.setCursorPos(2,1)
    host.write(('D'..dep.id..'  '..game.title..'  v'..dep.version):sub(1,w-2))
    host.setCursorPos(2,2);host.setBackgroundColor(colors.red)
    host.write(' [X] SALIR ')
    host.setBackgroundColor(colors.blue)
    host.write('  PRUEBA REMOTA / SERVIDOR')
    host.setCursorPos(2,3)
    local left=math.max(0,180-math.floor((os.epoch('utc')-started)/1000))
    host.write(('F7 salir | '..left..'s | '..result):sub(1,w-2))
    host.setBackgroundColor(colors.black);host.setTextColor(colors.white)
  end
  local function renderRow(row)
    if type(row)~='table' or type(row[1])~='number' or row[1]<1 or row[1]>h-3 then return end
    local text,fg,bg=row[2],row[3],row[4]
    if type(text)~='string' or type(fg)~='string' or type(bg)~='string' then return end
    if #text~=w or #fg~=w or #bg~=w or fg:find('[^0-9a-f]') or bg:find('[^0-9a-f]') then return end
    host.setCursorPos(1,row[1]+3)
    host.blit(text,fg,bg)
  end
  host.setBackgroundColor(colors.black);host.clear()
  titleBar()
  local function inputs()
    local allowed={char=true,key=true,key_up=true,paste=true,
      mouse_click=true,mouse_drag=true,mouse_up=true,mouse_scroll=true}
    while alive do
      local ev={os.pullEventRaw()}
      if ev[1]=='terminate' or ev[1]=='term_resize' then
        result='Desconectado';return
      end
      if ev[1]=='key' and ev[2]==keys.f7 then result='Prueba cerrada';return end
      if ev[1]=='mouse_click' and ev[4]==2 and ev[3]>=2 and ev[3]<=12 then
        result='Prueba cerrada';return
      end
      if allowed[ev[1]] then
        if ev[1]:sub(1,5)=='mouse' then
          if type(ev[4])=='number' and ev[4]>=4 and ev[4]<=h then
            ev[4]=ev[4]-3
          else ev=nil end
        elseif ev[1]=='paste' and type(ev[2])=='string' then ev[2]=ev[2]:sub(1,256) end
        if ev then rednet.send(server,{v=1,op='TEST_INPUT',sid=ticket,event=ev},P) end
      end
    end
  end
  local function screenEvents()
    while alive do
      local sid,msg=rednet.receive(P,1)
      if sid==server and type(msg)=='table' and msg.v==1 and msg.sid==ticket then
        if msg.op=='TEST_FRAME' and type(msg.rows)=='table' then
          for _,row in ipairs(msg.rows) do renderRow(row) end
          if type(msg.status)=='string' then result=msg.status end
        elseif msg.op=='TEST_FINISHED' then
          result=tostring(msg.status or 'Juego terminado')
          titleBar()
          sleep(2)
          return
        end
      end
    end
  end
  local function heartbeat()
    while alive do
      titleBar()
      -- Refrescar la pantalla (se pudieron perder los frames del arranque).
      rednet.send(server,{v=1,op='TEST_REFRESH',sid=ticket},P)
      sleep(2)
    end
  end
  local ok,err=pcall(function() parallel.waitForAny(inputs,screenEvents,heartbeat) end)
  alive=false
  rednet.send(server,{v=1,op='TEST_STOP',sid=ticket},P)
  host.setBackgroundColor(colors.black);host.setTextColor(colors.white)
  host.clear();host.setCursorPos(1,1)
  if not ok then printError('Fallo en la vista remota: '..tostring(err))
  else print('Preview D'..dep.id..' | '..result) end
  waitkey()
end

local function runPreview(game,d)
  screen('PREVIEW / D'..d.id,'Solo para el desarrollador')
  print('Version: '..d.version)
  print('Estado: '..d.status)
  if d.status=='failed' then
    printError('Este build fallo. Corrige los errores antes de probarlo.');waitkey();return
  end
  print('')
  print('[1] Probar EN EL SERVIDOR (no se descarga)')
  if d.status=='pending' then
    print('[2] Descargar y ejecutar en mi PC (sin aislamiento)')
  end
  print('[0] Volver')
  local option=ask('> ')
  if option=='1' then
    testOnServer(game,d)
  elseif option=='2' and d.status=='pending' then
    print('ADVERTENCIA: el juego accede a tu ordenador local.')
    if ask('Continuar? (SI/no): '):upper()~='SI' then return end
    local installed=install(game,d)
    if installed and ask('Ejecutar la preview? (s/n): '):lower()=='s' then play(game,d) end
    waitkey()
  end
end
local function deploymentHistory(game)
  local r=rpc('DEPLOYMENTS',{id=game.id})
  if not r.ok then status(r);waitkey();return end
  local arr=r.deployments or {};local page=0
  while true do
    screen('DEPLOYMENTS / '..game.title,'Produccion: v'..tostring(r.game.version))
    print('ID del juego: #J'..game.id..'  |  '..#arr..' deployments')
    local start=page*5+1
    for i=start,math.min(#arr,start+4) do
      local d=arr[i]
      print(('D%-4d v%-9s %s'):format(d.id,d.version,d.status:upper()))
      print('  '..(d.notes or ''):sub(1,35))
    end
    print('')
    print('[N] Mas [P] Anterior [R] Recargar')
    print('[T] Probar preview [0] Salir')
    local action=ask('> '):lower()
    if action=='0' or action=='' then return
    elseif action=='n' then page=math.min(page+1,math.max(0,math.ceil(#arr/5)-1))
    elseif action=='p' then page=math.max(0,page-1)
    elseif action=='r' then r=rpc('DEPLOYMENTS',{id=game.id});if r.ok then arr=r.deployments or {} end;page=0
    elseif action=='t' then
      local selected=tonumber(ask('ID de deployment (sin D): '))
      local d=nil
      for _,item in ipairs(arr) do if item.id==selected then d=item;break end end
      if d then runPreview(game,d) else printError('Deployment no encontrado');waitkey() end
    end
  end
end
local function updateGame()
  local r=rpc('MY_GAMES')
  if not r.ok then status(r);waitkey();return end
  local arr=r.games or {}
  screen('ELEGIR JUEGO','El ID del juego se conserva')
  if #arr==0 then print('Aun no has publicado juegos.');waitkey();return end
  for i,g in ipairs(arr) do
    print(i..'. #J'..g.id..' '..g.title..' ('..(g.version or g.status)..')')
  end
  local selectNum=tonumber(ask('Numero / 0 cancelar: '))
  if selectNum and arr[selectNum] then upload(arr[selectNum]) end
end
-- Acceso directo a pruebas remotas de cualquiera de tus versiones publicadas.
local function testMyGame()
  local r=rpc('MY_GAMES')
  if not r.ok then status(r);waitkey();return end
  local arr=r.games or {}
  screen('PROBAR JUEGOS EN SERVIDOR','No se descarga nada al cliente')
  if #arr==0 then print('Aun no tienes juegos.');waitkey();return end
  for i,g in ipairs(arr) do
    print(i..'. #J'..g.id..' '..g.title..' ['..g.status..']')
  end
  local n=tonumber(ask('Numero del juego / 0 cancelar: '))
  if not n or not arr[n] then return end
  local g=arr[n]
  local d=rpc('DEPLOYMENTS',{id=g.id})
  if not d.ok then status(d);waitkey();return end
  local valid={}
  for _,item in ipairs(d.deployments or {}) do
    if item.status~='failed' then valid[#valid+1]=item end
  end
  screen('ELEGIR VERSION / '..g.title,'Pruebas en el servidor WorldShop')
  if #valid==0 then print('No hay deployments ejecutables.');waitkey();return end
  for i,item in ipairs(valid) do
    print(i..'. D'..item.id..' v'..item.version..' ['..item.status..']')
  end
  local chosen=tonumber(ask('Numero de version / 0 cancelar: '))
  if chosen and valid[chosen] then testOnServer(g,valid[chosen]) end
end

-- Eliminacion irreversible y exclusiva del propietario; revalidada en el servidor.
local function deleteMyGame()
  local r=rpc('MY_GAMES')
  if not r.ok then status(r);waitkey();return end
  local arr=r.games or {}
  screen('ELIMINAR UNO DE MIS JUEGOS','Solo tu puedes eliminar tus juegos')
  if #arr==0 then print('No tienes juegos.');waitkey();return end
  for i,g in ipairs(arr) do
    print(i..'. #J'..g.id..' '..g.title..' ['..g.status..']')
  end
  local n=tonumber(ask('Numero del juego / 0 cancelar: '))
  if not n or not arr[n] then return end
  local g=arr[n]
  screen('ELIMINACION DEFINITIVA','Juego #J'..g.id..' | '..g.title)
  print('Se retira de tienda y bibliotecas, elimina deployments')
  print('y revoca licencias. NO se reembolsan compras.')
  print('Esta operacion NO se puede deshacer desde WorldShop.')
  print('Haz una copia de seguridad si quieres conservarlo.')
  print('')
  local confirmation=ask('Escribe el TITULO EXACTO para confirmar: ')
  if confirmation~=g.title then
    print('Titulo incorrecto: cancelado.');waitkey();return
  end
  if ask('Escribe ELIMINAR para confirmar: ')~='ELIMINAR' then
    print('Cancelado.');waitkey();return
  end
  local res=rpc('DELETE_GAME',{id=g.id,confirm=confirmation},8)
  status(res)
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
    screen('DEV CENTER','Deployments estilo Vercel')
    print('[1] Nuevo juego / Primer deployment')
    print('[2] Publicar actualizacion')
    print('[3] Historial de deployments')
    print('[4] Mis juegos y estados')
    print('[5] Probar juego EN EL SERVIDOR')
    print('[6] Eliminar uno de mis juegos')
    print('[0] Volver')
    local op=ask('> ')
    if op=='0' or op=='' then return
    elseif op=='1' then upload(nil)
    elseif op=='2' then updateGame()
    elseif op=='3' then
      local r=rpc('MY_GAMES')
      if not r.ok then status(r);waitkey()
      else
        screen('SELECCIONAR JUEGO','Historial')
        for i,g in ipairs(r.games or {}) do print(i..'. #J'..g.id..' '..g.title) end
        local n=tonumber(ask('Numero / 0 cancelar: '))
        if n and (r.games or {})[n] then deploymentHistory(r.games[n]) end
      end
    elseif op=='5' then testMyGame()
    elseif op=='6' then deleteMyGame()
    elseif op=='4' then
      local r=rpc('MY_GAMES');screen('MIS PUBLICACIONES')
      if r.ok then
        for _,g in ipairs(r.games or {}) do
          print('#J'..g.id..' '..g.title..' / '..g.status)
          print('  PROD v'..tostring(g.version or '-')..'  PREVIEW '..tostring(g.pendingVersion or '-'))
        end
      else status(r) end
      waitkey()
    end
  end
end
local function wallet()
  refresh();screen('CARTERA','Saldo: '..balance..' WS$')
  print('Ve al cajero WorldShop, inicia sesion')
  print('e inserta monedas en el barril DERECHO.')
  print('El cajero las guarda en el barril ABAJO.')
  print('');print('[1] Ticket antiguo (opcional)')
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
local function dashboard()
  refresh()
  screen('PANEL PRINCIPAL','@'..user..'  |  SALDO '..balance..' WS$')
  local w,h=term.getSize()
  local function card(x,y,ww,hh,title,subtitle,color)
    for k=0,hh-1 do
      term.setCursorPos(x,y+k);bg(color);col(colors.white)
      term.write((' '):rep(math.min(ww,w-x+1)))
    end
    term.setCursorPos(x+1,y);term.write(tostring(title):sub(1,ww-2))
    term.setCursorPos(x+1,y+1);col(colors.white);term.write(tostring(subtitle):sub(1,ww-2))
    bg(colors.black)
  end
  local mid=math.floor(w/2)
  local bw=math.max(13,mid-2)
  card(2,6,bw,3,'1  TIENDA','Explorar juegos',colors.blue)
  card(mid+1,6,w-mid-1,3,'2  BIBLIOTECA','Jugar / Instalar',colors.purple)
  card(2,10,bw,3,'3  CARTERA','Recargar saldo',colors.green)
  card(mid+1,10,w-mid-1,3,'4  DEV CENTER','Publicar juegos',colors.brown)
  if h>=18 then
    card(2,14,bw,3,'5  MI CUENTA','Perfil y saldo',colors.gray)
    card(mid+1,14,w-mid-1,3,'6  CONEXION','Reiniciar sesion',colors.gray)
  else
    line(h-2,'  [5] Perfil   [6] Reconectar',colors.lightGray)
  end
  line(h-1,'  [0] Salir  |  Haz clic en las tarjetas',colors.yellow)
  while true do
    local ev,a,x,y=os.pullEvent()
    if ev=='monitor_touch' then ev,a,x,y='mouse_click',1,x,y end
    if ev=='char' then
      if a:match('[0-6]') then return a end
    elseif ev=='key' then
      if a==keys.zero then return '0' end
    elseif ev=='mouse_click' then
      local left=x<=mid
      if y>=6 and y<=8 then return left and '1' or '2'
      elseif y>=10 and y<=12 then return left and '3' or '4'
      elseif y>=14 and y<=16 and h>=18 then return left and '5' or '6'
      elseif y==h-1 then return '0' end
    end
  end
end
intro();server=rednet.lookup(P,HOST)
if not login() then term.clear();return end
while true do
  local v=dashboard()
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