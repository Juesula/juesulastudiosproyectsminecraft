-- NEON COURIER 2.0 | World Studios / CC:Tweaked / WorldShop
-- WorldTor Engine viene EMBEBIDO en este archivo. NO requiere otro ordenador ni otro motor.
local WT=(function()
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
end)()
local g=WT.new(term.current())
local PROTO='neoncourier.v2'
local ROOT=fs.getDir(shell.getRunningProgram())
local function file(n) return fs.combine(ROOT,n) end
local function get(n,def)
  local h=fs.open(file(n),'r');if not h then return def end
  local raw=h.readAll();h.close()
  local ok,v=pcall(textutils.unserialize,raw)
  return ok and type(v)=='table' and v or def
end
local function put(n,obj)
  local h=fs.open(file(n),'w');if h then h.write(textutils.serialize(obj));h.close() end
end
local usernameData=get('neon_account.dat',{})
local username=usernameData.user or ''
local friends=get('neon_friends.dat',{})
local opts=get('neon_options.dat',{music=true,sfx=true,stars=true,particles=true,shake=true})
local localRecords=get('neon_local.dat',{runs=0,last=0,best=0})
-- Los perifericos son opcionales en la preview de WorldShop.
-- En CC:Tweaked real el comportamiento del juego se mantiene intacto.
local speaker=(peripheral and peripheral.find) and peripheral.find('speaker') or nil
local modemNames={}
if peripheral and rednet and peripheral.getNames and peripheral.hasType
    and rednet.isOpen and rednet.open then
  for _,name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name,'modem') then
      modemNames[#modemNames+1]=name
      if not rednet.isOpen(name) then rednet.open(name) end
    end
  end
end
math.randomseed((os.epoch and os.epoch('utc') or math.floor(os.clock()*1000000)) % 2147483647)
local serverId,serverInfo=nil,nil
local frame=0
local stars={}
for i=1,40 do stars[#stars+1]={x=math.random(1,51),y=math.random(5,15),s=(math.random(3)==1 and 2 or 1)} end
local function tone(kind)
  if not (speaker and opts.sfx) then return end
  local a=({jump={'hat',.22,18},hit={'bass',.5,9},point={'chime',.35,22},
    emp={'bit',.55,13},fail={'basedrum',.6,8},ready={'chime',.4,16},
    boss={'didgeridoo',.6,7},revive={'chime',.8,24}})[kind]
  if a then pcall(speaker.playNote,a[1],a[2],a[3]) end
end
local function textRow(y,label,fg)
  if y>3 and y<g.h-1 then g:text(2,y,label:sub(1,math.max(1,g.w-3)),fg or colors.white,nil,true) end
end
local function screen(title,lines,notice)
  g:camera(0,0);g:clear()
  for x=1,g.w do g:pixel(x,1,' ',colors.white,colors.blue,true) end
  g:text(2,1,'NEON COURIER  /  WORLD STUDIOS',colors.white,colors.blue,true)
  g:center(2,title,colors.cyan)
  for x=1,g.w do g:pixel(x,3,'-',colors.gray,nil,true) end
  for i,line in ipairs(lines or {}) do
    if type(line)=='table' then textRow(i+3,tostring(line[1] or ''),line[2])
    else textRow(i+3,tostring(line)) end
  end
  if notice then g:center(g.h-2,notice:sub(1,g.w),colors.yellow) end
  g:footer();g:flip()
end
local function ask(title,prompt)
  screen(title,{prompt,'','Escribe y pulsa ENTER'},'')
  term.setCursorPos(2,7);term.setBackgroundColor(colors.black);term.setTextColor(colors.white)
  return read() or ''
end
local function ensureAccount()
  if username~='' then return end
  local name=ask('CUENTA LOCAL','Tu nombre de jugador (max 16):'):gsub('[^%w_%-]',''):sub(1,16)
  username=name~='' and name or ('Robot'..os.getComputerID())
  put('neon_account.dat',{user=username})
end
local function send(payload)
  if serverId then rednet.send(serverId,payload,PROTO) end
end
local function findServer()
  serverId=nil;serverInfo=nil
  if #modemNames==0 then return nil end
  rednet.broadcast({type='DISCOVER'},PROTO)
  local timer=os.startTimer(1.2)
  while true do
    local e={os.pullEvent()}
    if e[1]=='rednet_message' and e[4]==PROTO and type(e[3])=='table' and e[3].type=='INFO' then
      serverId=e[2];serverInfo=e[3];return serverId
    elseif e[1]=='timer' and e[2]==timer then return nil end
  end
end
local function request(packet,answer,timeout)
  if not serverId then return nil,'No hay servidor' end
  send(packet)
  local timer=os.startTimer(timeout or 3)
  while true do
    local e={os.pullEvent()}
    if e[1]=='timer' and e[2]==timer then return nil,'Servidor sin respuesta' end
    if e[1]=='rednet_message' and e[2]==serverId and e[4]==PROTO and type(e[3])=='table' then
      local m=e[3]
      if m.type==answer then return m end
      if m.type=='REJECT' or m.type=='NOTICE' then return nil,m.reason or m.text or 'Rechazado' end
    end
  end
end
local function leaderboard()
  screen('RANKING MUNDIAL',{'Cargando...'},'')
  if not serverId then findServer() end
  local res=request({type='REQ_LEADERBOARD'},'LEADERBOARD',2)
  local lines={}
  if res and type(res.scores)=='table' then
    local entries={}
    for user,v in pairs(res.scores) do
      entries[#entries+1]={user=user,score=type(v)=='table' and (v.best or 0) or (tonumber(v) or 0)}
    end
    table.sort(entries,function(a,b)return a.score>b.score end)
    for i=1,math.min(9,#entries) do
      local e=entries[i]
      lines[#lines+1]={('%02d. %-16s %6d'):format(i,e.user,e.score),
        e.user==username and colors.cyan or (friends[e.user] and colors.lime or colors.white)}
    end
    if #entries==0 then lines={'Nadie ha registrado puntos todavia.'} end
  else lines={'No se ha podido consultar el servidor.'} end
  lines[#lines+1]='';lines[#lines+1]='Pulsa cualquier tecla para volver.'
  screen('RANKING MUNDIAL',lines)
  os.pullEvent('key')
end
local function friendScreen()
  while true do
    local names={};for name in pairs(friends) do names[#names+1]=name end
    table.sort(names)
    local rows={{'Tus amigos ('..#names..'):',colors.lightBlue}}
    for i=1,math.min(7,#names) do rows[#rows+1]=' * '..names[i] end
    if #names==0 then rows[#rows+1]='No tienes amigos guardados.' end
    rows[#rows+1]='';rows[#rows+1]='[A] Anadir   [B] Borrar'
    rows[#rows+1]='[ESC] Volver'
    screen('AMIGOS',rows)
    local _,k=os.pullEvent('key')
    if k==keys.escape then return end
    if k==keys.a or k==keys.b then
      local name=ask(k==keys.a and 'ANADIR AMIGO' or 'BORRAR AMIGO','Nombre exacto:'):gsub('[^%w_%-]',''):sub(1,16)
      if name~='' then friends[name]=k==keys.a or nil;put('neon_friends.dat',friends) end
    end
  end
end
local function configScreen()
  while true do
    screen('AJUSTES',{
      '[M] Musica: '..(opts.music and 'ON' or 'OFF'),
      '[S] Sonidos: '..(opts.sfx and 'ON' or 'OFF'),
      '[V] Estrellas: '..(opts.stars and 'ON' or 'OFF'),
      '[T] Particulas: '..(opts.particles and 'ON' or 'OFF'),
      '[K] Temblor de pantalla: '..(opts.shake and 'ON' or 'OFF'),
      '','[ESC] Volver'
    },'WorldTor Engine integrado')
    local _,k=os.pullEvent('key')
    if k==keys.escape then return end
    local names={[keys.m]='music',[keys.s]='sfx',[keys.v]='stars',
                 [keys.t]='particles',[keys.k]='shake'}
    if names[k] then opts[names[k]]=not opts[names[k]];put('neon_options.dat',opts) end
  end
end
local function mainMenu()
  while true do
    findServer()
    local server=serverId and ('ONLINE  #'..serverId..'  '..(serverInfo.mode or '')) or 'SERVIDOR OFFLINE'
    local headline=serverInfo and serverInfo.announcement
    local notice=headline and headline.enabled and headline.text or 'Runner 2D | Powered by WorldTor Engine'
    screen('MENU PRINCIPAL',{
      {'@'..username..'   '..server,colors.lightBlue},
      '',
      {'[1] UN JUGADOR / SUPERVIVENCIA',colors.lime},
      {'[2] CREAR SALA COOPERATIVA / PVP',colors.lime},
      {'[3] UNIRSE A UNA SALA',colors.lime},
      {'[4] EVENTO MUNDIAL MMO (8)',colors.yellow},
      {'[5] SALIR',colors.red},
      '',
      '[L] Ranking  [F] Amigos  [O] Ajustes',
      '[U] Cambiar nombre  [R] Reconectar',
      '','Record local: '..tostring(localRecords.best or 0)
    },notice)
    local _,k=os.pullEvent('key')
    if k==keys.one then return 'SINGLE'
    elseif k==keys.two then return 'HOST'
    elseif k==keys.three then return 'JOIN'
    elseif k==keys.four then return 'EVENT'
    elseif k==keys.five or k==keys.escape then return 'EXIT'
    elseif k==keys.l then leaderboard()
    elseif k==keys.f then friendScreen()
    elseif k==keys.o then configScreen()
    elseif k==keys.u then username='';ensureAccount()
    end
  end
end
local function difficulty()
  screen('SELECCIONAR PARTIDA',{
    {'[A] NORMAL - ciudad de neones',colors.lime},
    {'[B] DIFICIL - drones mas rapidos',colors.orange},
    {'[C] PVP - duelo de supervivencia',colors.red},
    '',
    'Coop: recoge baterias y salva amigos.',
    'PvP: pulsa F para un pulso EMP.',
    '',
    'Pulsa A, B o C.'
  })
  while true do
    local _,k=os.pullEvent('key')
    if k==keys.a then return 'EASY' end
    if k==keys.b then return 'HARD' end
    if k==keys.c then return 'PVP' end
    if k==keys.escape then return nil end
  end
end
local lastHp,lastCoins,lastNotice=nil,0,nil
local function drawRunner(s,myId)
  if not s then return end
  local ww,hh=g.w,g.h
  local ground=hh-4
  if hh<13 or ww<30 then
    screen('PANTALLA DEMASIADO PEQUENA',{'Amplia el terminal o el monitor.'});return
  end
  g:camera(0,0);g:clear()
  frame=frame+1
  local me=s.players and (s.players[myId] or s.players[tostring(myId)])
  if me and lastHp and me.hp<lastHp then tone('hit');if opts.shake then g:shake(3,1) end end
  if me and me.coins>lastCoins then tone('point') end
  if me then lastHp=me.hp;lastCoins=me.coins end
  if s.notice~=lastNotice and s.notice and s.notice~='' and s.countdown>0 then
    if s.notice:find('DRON') then tone('boss') end
    lastNotice=s.notice
  end
  g:rect(1,1,ww,2,' ',colors.white,colors.blue,true)
  local hud=('NEON COURIER   %s   NIVEL %d'):format(s.mode or 'COOP',s.level or 1)
  g:text(2,1,hud:sub(1,ww-2),colors.white,colors.blue,true)
  local second=('PTS %d   VIDA %d   BATERIAS %d   ESCUDO %d'):format(
    me and (me.score or 0) or 0,me and me.hp or 0,me and me.energy or 0,me and me.shield or 0)
  g:text(2,2,second:sub(1,ww-2),colors.yellow,colors.blue,true)
  if opts.stars then
    for i,st in ipairs(stars) do
      local x=1+((st.x-math.floor((s.distance or 0)*(0.13+st.s*.04)))%ww)
      local y=4+(st.y%(math.max(2,ground-6)))
      g:pixel(x,y,'.',colors.gray,nil,true)
    end
  end
  for x=1,ww do
    local roof=ground-5+((math.floor((x+(s.distance or 0)*.11)/7)*11)%4)
    for y=roof,ground-1 do
      if (x*5+y*3)%13==0 then g:pixel(x,y,':',colors.lightBlue,nil,true)
      else g:pixel(x,y,' ',colors.gray,colors.black,true) end
    end
    g:pixel(x,ground+1,'=',colors.lightGray,nil,true)
    if (x+math.floor(s.distance or 0))%8<4 then g:pixel(x,ground+2,'-',colors.yellow,nil,true) end
  end
  for _,o in ipairs(s.objects or {}) do
    local x=math.floor((o.x or 0)+.5)
    if x>1 and x<=ww then
      if o.typ=='box' then g:sprite(x-1,ground-1,{'[X]'},colors.orange)
      elseif o.typ=='tall' then g:sprite(x-1,ground-2,{' | ','[H]'},colors.red)
      elseif o.typ=='drone' then g:sprite(x-1,ground-3,{'[=]',' / '},colors.pink)
      elseif o.typ=='battery' then g:pixel(x,ground-1-(o.alt==1 and 2 or 0),'+',colors.lime)
      elseif o.typ=='boss' then g:sprite(x-1,ground-4,s.bossArt or {' /\\ ','[##]',' \\/ '},colors.red) end
    end
  end
  for _,p in pairs(s.players or {}) do
    local x=math.floor((p.x or 11)+.5)
    local y=ground-math.floor((p.air or 0)+.5)
    local mine=tonumber(p.id)==myId
    local fg=mine and colors.cyan or (friends[p.user] and colors.lime or colors.orange)
    if p.alive then
      if p.duck then
        g:sprite(x-1,y-1,{'[oo]'},fg)
      else
        g:sprite(x-1,y-2,{'[oo]',' /| '},fg)
      end
      if p.shield and p.shield>0 then g:pixel(x+2,y-2,'O',colors.lightBlue) end
      if p.stun and p.stun>0 then g:pixel(x+2,y-1,'!',colors.red) end
    else g:pixel(x,y,'X',colors.red) end
    if y>5 then g:text(x-1,y-3,tostring(p.user or '?'):sub(1,7),fg) end
  end
  if opts.particles then
    for _,e in ipairs(s.effects or {}) do
      g:pixel(e.x,ground-(e.y or 0),'*',colors.yellow)
    end
  end
  local controls='ESP/ARRIBA SALTO  ABAJO AGACHAR  X ESCUDO  E RESCATE  F EMP  P PAUSA  ESC SALIR'
  g:text(1,hh-2,string.rep(' ',ww),colors.white,colors.black,true)
  g:text(1,hh-2,controls:sub(1,ww),colors.lightGray,nil,true)
  if s.announcement and s.announcement~='' then g:center(3,('* '..s.announcement..' *'):sub(1,ww),colors.orange) end
  if s.notice and s.notice~='' and s.countdown and s.countdown>0 then g:center(4,s.notice:sub(1,ww),colors.yellow) end
  if s.paused then g:center(math.floor(hh/2),'= PAUSADO =',colors.yellow) end
  if not me or not me.alive then g:center(6,'SIN VIDA - ESPERANDO RESULTADO / RESCATE',colors.red) end
  if s.shutdown and s.shutdown>0 then g:center(5,'CIERRE EN '..s.shutdown..' S',colors.red) end
  g:footer();g:flip()
end
local function play(server,pid,active,isHost)
  local run=true
  local current=nil
  local ping=os.startTimer(1)
  local notes={12,15,19,22,24,19,15,10}
  local mi=0
  local musicTimer=os.startTimer(.6)
  local numPlayers=1
  lastHp,lastCoins,lastNotice=nil,0,nil
  if not active then screen(isHost and 'SALA CREADA' or 'UNIENDOSE A SALA',{
    isHost and 'Esperando amigos...' or 'Esperando que el anfitrion empiece...',
    isHost and '[ENTER] EMPEZAR LA CARRERA' or 'El host controla el inicio.',
    '[ESC] Abandonar sala',
    '','Un jugador necesita su propio ordenador.'
  }) end
  while run do
    local e={os.pullEvent()}
    if e[1]=='timer' and e[2]==ping then
      send({type='PING'});ping=os.startTimer(1)
    elseif e[1]=='timer' and e[2]==musicTimer then
      musicTimer=os.startTimer(.6)
      if active and speaker and opts.music then
        mi=(mi%#notes)+1;pcall(speaker.playNote,'harp',.11,notes[mi])
      end
    elseif e[1]=='term_resize' then g:resize();if current then drawRunner(current,pid) end
    elseif e[1]=='rednet_message' and e[2]==server and e[4]==PROTO and type(e[3])=='table' then
      local m=e[3]
      if m.type=='START' then active=true;tone('ready')
      elseif m.type=='STATE' then
        active=true;current=m.state
        if type(current)=='table' then drawRunner(current,pid) end
      elseif m.type=='PLAYER_JOINED' then
        numPlayers=m.players or numPlayers+1
        if not active then screen('SALA',{'Se unio: '..tostring(m.user or '?'),
            'Jugadores: '..numPlayers,'[ENTER] Empezar  [ESC] Salir'}) end
      elseif m.type=='NOTICE' then
        if not active then screen('AVISO DEL SERVIDOR',{tostring(m.text),'[ESC] Salir'}) end
      elseif m.type=='PAUSE' then
        if current then current.paused=m.value;drawRunner(current,pid) end
      elseif m.type=='GAME_OVER' then
        local me=current and current.players and (current.players[pid] or current.players[tostring(pid)])
        local score=me and math.floor(me.score or 0) or 0
        localRecords.runs=(localRecords.runs or 0)+1
        localRecords.last=score
        localRecords.best=math.max(localRecords.best or 0,score)
        put('neon_local.dat',localRecords)
        tone('fail')
        local rows={'Tu puntuacion: '..score,'Record personal: '..localRecords.best,
          'Mejor de la partida: '..tostring(m.winner or '?'),''}
        if type(m.scores)=='table' then
          for i=1,math.min(#m.scores,6) do
            local p=m.scores[i];rows[#rows+1]=i..'. '..tostring(p.user)..' - '..tostring(p.score)
          end
        end
        rows[#rows+1]='';rows[#rows+1]='Pulsa una tecla para volver'
        screen('FINAL DE CARRERA',rows)
        os.pullEvent('key');run=false
      elseif m.type=='SHUTDOWN' then
        screen('SERVIDOR DESCONECTADO',{m.text or 'Servidor apagado'});sleep(1.5);run=false
      elseif m.type=='RETURN_MENU' or m.type=='CANCEL' then run=false end
    elseif e[1]=='key' then
      local key=e[2]
      if key==keys.escape then send({type='LEAVE'});return end
      if not active then if isHost and key==keys.enter then send({type='START'}) end
      else
        if key==keys.p then send({type='PAUSE'}) else send({type='KEY',key=key,down=true}) end
      end
    elseif e[1]=='key_up' and active then
      send({type='KEY',key=e[2],down=false})
    elseif e[1]=='mouse_click' and active then
      if e[2]==1 then send({type='ACTION',action='JUMP'})
      elseif e[2]==2 then send({type='ACTION',action='DUCK',down=true}) end
    elseif e[1]=='mouse_up' and active then
      if e[2]==2 then send({type='ACTION',action='DUCK',down=false}) end
    elseif e[1]=='monitor_touch' and active then
      send({type='ACTION',action='JUMP'})
    end
  end
  send({type='LEAVE'})
end
local function main()
  g:splash('WORLD STUDIOS','PRESENTA',speaker,opts.sfx)
  ensureAccount()
  while true do
    local mode=mainMenu()
    if mode=='EXIT' then break end
    local selected=nil
    if mode=='HOST' or mode=='SINGLE' then selected=difficulty() end
    if (mode~='HOST' and mode~='SINGLE') or selected then
      if not serverId then findServer() end
      if not serverId then
        screen('NO HAY SERVIDOR',{'Neon Courier online necesita servidor.',
          'En otro ordenador ejecuta:',
          'neon_courier_server.lua',
          'Conecta modems en ambos ordenadores.',
          '','Pulsa una tecla para volver.'})
        os.pullEvent('key')
      else
        screen('CONECTANDO',{'Jugador: '..username,'Servidor: #'..serverId,
          'Modo: '..mode,'Dificultad: '..tostring(selected or '-')})
        local res,err=request({type='JOIN',user=username,mode=mode,diff=selected or 'EASY'},'ACCEPT',3)
        if res then
          play(serverId,res.pid or os.getComputerID(),res.round=='RUNNING',mode=='HOST')
        else
          screen('NO SE PUDO ENTRAR',{tostring(err or 'Error desconocido'),
            'Comprueba el modo NORMAL/EVENTO.', '', 'Pulsa una tecla para volver.'})
          os.pullEvent('key')
        end
      end
    end
  end
  screen('WORLD STUDIOS',{'Gracias por jugar a NEON COURIER',
    'WorldTor Engine v'..tostring(WT.version),'WorldTor IN USE'})
end
local ok,err=xpcall(main,debug.traceback)
term.setBackgroundColor(colors.black);term.setTextColor(colors.white)
if not ok then term.clear();term.setCursorPos(1,1);printError('NEON COURIER ERROR: '..tostring(err)) end
