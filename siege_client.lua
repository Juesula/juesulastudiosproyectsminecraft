-- SIEGE PROTOCOL / cliente CC:Tweaked (motor WorldTor)
-- Instala worldtor_engine.lua en la MISMA carpeta que este archivo.
local enginePath=fs.combine(fs.getDir(shell.getRunningProgram()),'worldtor_engine.lua')
local WT=loadfile(enginePath)
if not WT then error('Falta worldtor_engine.lua junto a siege_client.lua.') end
local Engine=WT()
local g=Engine.new(term.current())
local PROTO='WORLDTOR_SIEGE_V1'
local modems={peripheral.find('modem')}
if #modems==0 then
    g:clear();g:center(5,'NECESITAS UN MODEM',colors.red);g:center(7,'Conecta un modem al ordenador',colors.white);g:footer();g:flip();return
end
for _,m in ipairs(modems) do rednet.open(peripheral.getName(m)) end
math.randomseed((os.epoch and os.epoch('utc') or os.clock()*100000)%2147483647)
local speaker=peripheral.find('speaker')
local function fileRead(path,default)
    if not fs.exists(path) then return default end
    local f=fs.open(path,'r');local text=f.readAll();f.close();return text
end
local function fileWrite(path,s)
    local f=fs.open(path,'w');f.write(s);f.close()
end
local function tableRead(path,default)
    local raw=fileRead(path,'');local ok,v=pcall(textutils.unserialize,raw)
    return ok and type(v)=='table' and v or default
end
local opts=tableRead('worldtor_options.txt',{music=true,sfx=true,stars=true,particles=true,shake=true})
local friends=tableRead('amigos.txt',{})
local username=fileRead('worldtor_user.txt',fileRead('user.txt','')):gsub('[\r\n]','')
local serverId=nil;local serverInfo=nil
local frame=0
local previousHP=nil
local sparks={}
for i=1,48 do sparks[i]={x=math.random(1,51),y=math.random(4,17),speed=(math.random(3)==1) and 2 or 1} end
local function tone(kind)
    if not (opts.sfx and speaker) then return end
    local sounds={shoot={'snare',.3,16},enemy={'hat',.3,5},laser={'bit',.3,19},
        hit={'bass',.6,6},boss={'didgeridoo',1,5},wave={'chime',1,17},
        pick={'chime',.5,22},reload={'bit',.2,12},boom={'bass',1,3},death={'basedrum',1,3}}
    local a=sounds[kind]
    if a then pcall(speaker.playNote,a[1],a[2],a[3]) end
end
local function screen(title,rows,notice)
    g:camera(0,0);g:clear(' ',colors.white,colors.black)
    local ww,hh=g.w,g.h
    for i=1,math.min(ww,51) do g:pixel(i,1,'=',colors.cyan,nil,true) end
    g:center(2,title,colors.yellow)
    for i=1,math.min(ww,51) do g:pixel(i,3,'=',colors.cyan,nil,true) end
    for i,row in ipairs(rows or {}) do
        local y=i+4
        if y<hh-2 then
            if type(row)=='table' then g:text(2,y,row[1] or '',row[2] or colors.white,nil,true)
            else g:text(2,y,row,colors.white,nil,true) end
        end
    end
    if notice and notice~='' and hh>6 then
        g:text(2,hh-2,tostring(notice):sub(1,math.max(0,ww-3)),colors.orange,nil,true)
    end
    g:footer();g:flip()
end
local function ask(title,label)
    screen(title,{{label,colors.cyan}},'Escribe y pulsa ENTER')
    term.setCursorPos(2,7);term.setBackgroundColor(colors.black);term.setTextColor(colors.white)
    return (read() or '')
end
if username=='' then
    g:splash('SIEGE PROTOCOL','WORLD STUDIOS PRESENTA',speaker,opts.sfx)
    username=ask('IDENTIFICACION','Tu nombre de usuario (max. 16):'):gsub('[^%w_%-]',''):sub(1,16)
    if username=='' then username='Jugador'..os.getComputerID() end
    fileWrite('worldtor_user.txt',username)
else
    g:splash('SIEGE PROTOCOL','WORLD STUDIOS PRESENTA',speaker,opts.sfx)
end

local function packetTo(id,packet)
    if id then rednet.send(id,packet,PROTO) else rednet.broadcast(packet,PROTO) end
end
local function locateServer()
    rednet.broadcast({type='DISCOVER'},PROTO)
    local timer=os.startTimer(1.2)
    while true do
        local ev={os.pullEvent()}
        if ev[1]=='rednet_message' and ev[4]==PROTO and type(ev[3])=='table' and ev[3].type=='INFO' then
            serverId,serverInfo=ev[2],ev[3];return serverId
        elseif ev[1]=='timer' and ev[2]==timer then return serverId end
    end
end
local function networkRequest(msg,answer,timeout)
    packetTo(serverId,msg)
    local t=os.startTimer(timeout or 2)
    while true do
        local ev={os.pullEvent()}
        if ev[1]=='rednet_message' and ev[4]==PROTO and type(ev[3])=='table'
          and (serverId==nil or ev[2]==serverId) and ev[3].type=='REJECT' then
            return nil, ev[3].reason or 'Conexion rechazada'
        elseif ev[1]=='rednet_message' and ev[4]==PROTO and type(ev[3])=='table'
          and (serverId==nil or ev[2]==serverId) and ev[3].type==answer then
            if not serverId then serverId=ev[2] end
            return ev[3]
        elseif ev[1]=='timer' and ev[2]==t then return nil end
    end
end
local function ranking()
    screen('WORLD LEADERBOARD',{'Cargando clasificacion...'},'')
    locateServer()
    local res=networkRequest({type='REQ_LEADERBOARD'},'LEADERBOARD',2)
    local lines={}
    if res and type(res.scores)=='table' then
        local arr={}
        for k,v in pairs(res.scores) do arr[#arr+1]={name=tostring(k),score=tonumber(v) or 0} end
        table.sort(arr,function(a,b)return a.score>b.score end)
        if #arr==0 then lines={'Todavia no hay puntos registrados.'} end
        for i=1,math.min(10,#arr) do
            local row=arr[i]
            lines[#lines+1]={string.format('%2d. %-18s %d pts',i,row.name,row.score),
                row.name==username and colors.yellow or (friends[row.name] and colors.lime or colors.white)}
        end
    else lines={'Servidor no encontrado.'} end
    lines[#lines+1]=''
    lines[#lines+1]='Cualquier tecla para volver.'
    screen('WORLD LEADERBOARD',lines)
    os.pullEvent('key')
end
local function bgDots()
    if not opts.stars then return end
    for _,st in ipairs(sparks) do
        st.x=st.x-st.speed*.22
        if st.x<1 then st.x=51;st.y=math.random(4,17) end
        g:pixel(st.x,st.y,'.',colors.gray)
    end
end
local function drawGame(state,myId)
    frame=frame+1
    g:clear();g:camera(0,0)
    local self=state.players and (state.players[myId] or state.players[tostring(myId)])
    if self and previousHP and self.hp<previousHP and opts.shake then g:shake(3,1) end
    if self then previousHP=self.hp end
    local mapW,mapH=tonumber(state.w) or 51,tonumber(state.h) or 19
    local cameraX,cameraY=0,0
    if self then
        cameraX=math.max(0,math.min(mapW-g.w,math.floor(self.x-g.w/2)))
        cameraY=math.max(0,math.min(mapH-g.h,math.floor(self.y-g.h/2)))
    end
    g:camera(cameraX,cameraY)
    if opts.stars then
        for x=1,mapW do for y=4,mapH-2 do
            if (x*7+y*11)%17==0 then g:pixel(x,y,'.',colors.gray) end
        end end
    end
    for y=3,mapH-1 do g:pixel(1,y,'|',colors.gray);g:pixel(mapW,y,'|',colors.gray) end
    for x=1,mapW do g:pixel(x,3,'-',colors.gray);g:pixel(x,mapH-1,'-',colors.gray) end
    for _,o in ipairs(state.obstacles or {}) do if o.hp==nil or o.hp>0 then g:pixel(o.x,o.y,'#',colors.brown) end end
    local icons={heal={'+',colors.lime},ammo={'A',colors.yellow},
                 shield={'S',colors.lightBlue},grenade={'G',colors.orange},rapid={'R',colors.pink}}
    for _,it in ipairs(state.items or {}) do
        local spec=icons[it.typ] or {'?',colors.white}
        g:pixel(it.x,it.y,spec[1],spec[2])
    end
    for _,b in ipairs(state.shots or {}) do
        g:pixel(b.x,b.y,b.c or '.',b.from==-1 and colors.red or (b.c=='=' and colors.cyan or colors.yellow))
    end
    for _,e in ipairs(state.enemies or {}) do
        if e.typ=='boss' then
            g:sprite(e.x-1,e.y-1,{'/W\\','[B]','\\_/'},colors.red)
            g:bar(e.x-3,e.y-2,7,math.max(0,e.hp or 0),e.maxHp or 110,colors.red)
        elseif e.typ=='custom' and type(e.art)=='table' then
            g:sprite(e.x-1,e.y-1,e.art,colors.magenta)
            g:bar(e.x-2,e.y-2,5,math.max(0,e.hp or 0),e.maxHp or 30,colors.magenta)
        else
            local col=({grunt=colors.orange,hunter=colors.yellow,ranger=colors.pink,tank=colors.red})[e.typ] or colors.white
            g:pixel(e.x,e.y,e.c or 'z',col)
        end
    end
    for id,p in pairs(state.players or {}) do
        if p.hp>0 then
            local col=(tonumber(id)==myId) and colors.cyan or colors.lime
            if p.shield and p.shield>0 then g:pixel(p.x,p.y,'O',colors.lightBlue) end
            if p.invul==0 or frame%2==0 then g:pixel(p.x,p.y,(tonumber(id)==myId and '@' or '&'),col) end
            g:pixel(p.x+p.aimX,p.y+p.aimY,'+',col)
            local uname=tostring(p.user or ''):sub(1,9)
            g:text(p.x-math.floor(#uname/2),p.y-1,uname,col)
        else
            g:pixel(p.x,p.y,'X',colors.red)
        end
    end
    if opts.particles then
        for _,fx in ipairs(state.fx or {}) do g:pixel(fx.x,fx.y,fx.c or '*',colors.orange) end
    end
    g:camera(0,0)
    local hud=string.format('WAVE:%02d  KILLS:%d  %s',state.wave or 1,state.kills or 0,state.paused and 'PAUSA' or state.mode or 'COOP')
    g:text(1,1,string.rep(' ',g.w),colors.white,colors.blue,true)
    g:text(2,1,hud,colors.white,colors.blue,true)
    if self then
        local st=string.format('HP:%3d  SCORE:%d  WEAPON:%s  AMMO:%d/%d  G:%d',
            self.hp or 0,self.score or 0,({[1]='PISTOL',[2]='SHOTGUN',[3]='LASER'})[self.weapon] or 'PISTOL',
            self.ammo or 0,self.maxAmmo or 0,self.grenades or 0)
        g:text(1,2,string.rep(' ',g.w),colors.white,colors.gray,true)
        g:text(2,2,st:sub(1,g.w-2),colors.white,colors.gray,true)
    end
    local bottom=string.format('WASD mover | IJKL apuntar | ESP disparar | R recargar | G granada | P pausa')
    g:text(1,g.h-1,string.rep(' ',g.w),colors.white,colors.black,true)
    if g.w>43 then g:text(1,g.h-1,bottom:sub(1,g.w),colors.lightGray,nil,true)
    else g:text(1,g.h-1,'WASD MOVER  ESP FUEGO  G GRANADA  ESC',colors.lightGray,nil,true) end
    if state.waveNotice and state.waveNotice>0 then g:center(math.max(5,math.floor(g.h/2)-5),'[ OLEADA '..tostring(state.wave)..' ]',colors.yellow) end
    if state.paused then g:center(math.floor(g.h/2),'== PAUSADO ==',colors.yellow) end
    if state.serverClosing and state.serverClosing>0 then g:center(4,'CIERRE EN '..state.serverClosing..'s',colors.red) end
    if state.announcement and state.announcement~='' then
        g:center(3,('* '..state.announcement..' *'):sub(1,g.w),colors.orange)
    end
    g:footer()
    g:flip()
end
local function saveOptions()fileWrite('worldtor_options.txt',textutils.serialize(opts))end
local function mainMenu()
    while true do
        locateServer()
        local serverLabel=serverId and ('ONLINE #'..serverId..' / '..(serverInfo and serverInfo.mode or '??')) or 'SIN CONEXION'
        local rows={
            {'Usuario: '..username..'  |  '..serverLabel,colors.lightBlue},
            {'',colors.white},
            {'[1] Un jugador / Supervivencia',colors.lime},
            {'[2] Hostear cooperativo / PvP',colors.lime},
            {'[3] Unirse a un amigo',colors.lime},
            {'[4] EVENTO MUNDIAL (MMO)',colors.yellow},
            {'[5] Salir',colors.red},
            {'',colors.white},
            {'[L] Leaderboard   [F] Agregar amigo',colors.white},
            {'[M] Musica: '..(opts.music and 'ON' or 'OFF')..'   [S] Sonidos: '..(opts.sfx and 'ON' or 'OFF'),colors.cyan},
            {'[V] Estrellas: '..(opts.stars and 'ON' or 'OFF')..' [T] Particulas: '..(opts.particles and 'ON' or 'OFF'),colors.cyan},
            {'[K] Shake: '..(opts.shake and 'ON' or 'OFF')..'   [R] Reconectar',colors.lightGray},
        }
        screen('S I E G E   P R O T O C O L',rows,
            serverInfo and serverInfo.announcement and serverInfo.announcement.enabled and ('* '..(serverInfo.announcement.text or '')) or 'Shooter 2D / WorldTor Engine')
        local _,k=os.pullEvent('key')
        if k==keys.one then return 'SINGLE'
        elseif k==keys.two then return 'HOST'
        elseif k==keys.three then return 'JOIN'
        elseif k==keys.four then return 'EVENT'
        elseif k==keys.five or k==keys.escape then return 'EXIT'
        elseif k==keys.l then ranking()
        elseif k==keys.f then
            local name=ask('AGREGAR AMIGO','Nombre de usuario:'):gsub('[^%w_%-]',''):sub(1,16)
            if name~='' then friends[name]=true;fileWrite('amigos.txt',textutils.serialize(friends)) end
        elseif k==keys.m then opts.music=not opts.music;saveOptions()
        elseif k==keys.s then opts.sfx=not opts.sfx;saveOptions()
        elseif k==keys.v then opts.stars=not opts.stars;saveOptions()
        elseif k==keys.t then opts.particles=not opts.particles;saveOptions()
        elseif k==keys.k then opts.shake=not opts.shake;saveOptions()
        end
    end
end
local function difficulty()
    screen('DIFICULTAD',{'[A] EASY / Oleadas', '[B] HARD / Invasion intensa',
        '[C] PVP / Enfrentamiento', '', 'Pulsa A, B o C.'})
    while true do
        local _,k=os.pullEvent('key')
        if k==keys.a then return 'EASY' elseif k==keys.b then return 'HARD'
        elseif k==keys.c then return 'PVP' end
    end
end
local function playGame(id,myId,alreadyRunning,host)
    local active=alreadyRunning;local running=true;local state=nil
    local ping=os.startTimer(1)
    local musicTimer=os.startTimer(.65)
    local melody={12,15,19,22,19,15,10,15}
    local musicStep=0
    if not active then
        screen(host and 'SALA DE ESPERA / HOST' or 'UNIENDOSE A SALA',
            host and {'Esperando al jugador 2...', '[ENTER] Iniciar aunque estes solo', '[ESC] Cancelar'} or
                {'Espera a que el host inicie la partida.','[ESC] Cancelar'})
    end
    while running do
        local ev={os.pullEvent()}
        if ev[1]=='timer' and ev[2]==ping then
            packetTo(id,{type='PING'});ping=os.startTimer(1)
        elseif ev[1]=='timer' and ev[2]==musicTimer then
            musicTimer=os.startTimer(.65)
            if active and opts.music and speaker then
                musicStep=musicStep%#melody+1
                pcall(speaker.playNote,'harp',.15,melody[musicStep])
            end
        elseif ev[1]=='term_resize' then
            g:resize();if state and active then drawGame(state,myId) end
        elseif ev[1]=='rednet_message' and ev[2]==id and ev[4]==PROTO and type(ev[3])=='table' then
            local m=ev[3]
            if m.type=='START' then active=true
            elseif m.type=='STATE' then
                state=m.state;active=true
                if type(state)=='table' then
                    if state.sounds then for _,s in ipairs(state.sounds) do tone(s) end end
                    drawGame(state,myId)
                end
            elseif m.type=='NOTICE' then
                screen('AVISO DEL SERVIDOR',{tostring(m.text or 'Aviso'), '[ESC] Volver / Esperando en lobby'})
            elseif m.type=='PLAYER_JOINED' then
                screen('JUGADOR CONECTADO',{'Se unio: '..tostring(m.user),'Pulsa ENTER para iniciar.'})
            elseif m.type=='PAUSE' then if active and state then state.paused=m.value;drawGame(state,myId) end
            elseif m.type=='GAME_OVER' then
                local myp=state and state.players and state.players[myId]
                tone('death')
                screen('G A M E   O V E R',{
                    'Partida terminada.',
                    'Puntos conseguidos: '..tostring(myp and myp.score or 0),
                    'Bajas: '..tostring(myp and myp.kills or 0),
                    '', 'Pulsa cualquier tecla para volver.'})
                os.pullEvent('key');running=false
            elseif m.type=='SHUTDOWN' then
                screen('SERVIDOR APAGADO',{tostring(m.text or 'Servidor desconectado')});sleep(2);running=false
            elseif m.type=='RETURN_MENU' or m.type=='CANCEL' then running=false end
        elseif ev[1]=='key' then
            local k=ev[2]
            if k==keys.escape then
                packetTo(id,{type='LEAVE'});return
            elseif not active then
                if host and k==keys.enter then packetTo(id,{type='START'}) end
            else
                if k==keys.p then packetTo(id,{type='PAUSE'}) end
                packetTo(id,{type='KEY',key=k,down=true})
            end
        elseif ev[1]=='key_up' and active then
            packetTo(id,{type='KEY',key=ev[2],down=false})
        elseif ev[1]=='mouse_click' and active then
            local button,x,y=ev[2],ev[3],ev[4]
            if button==1 then packetTo(id,{type='FIRE_AT',x=x,y=y}) end
        elseif ev[1]=='mouse_drag' and active then
            local button,x,y=ev[2],ev[3],ev[4]
            if button==1 then packetTo(id,{type='FIRE_AT',x=x,y=y}) end
        end
    end
    packetTo(id,{type='LEAVE'})
end

while true do
    local mode=mainMenu()
    if mode=='EXIT' then break end
    if not serverId then locateServer() end
    if not serverId then
        screen('ERROR DE CONEXION',{'No se detecta servidor Siege Protocol.',
            'Comprueba que siege_server este encendido.',
            'Ambos ordenadores necesitan modems.','', 'Pulsa una tecla para volver.'})
        os.pullEvent('key')
    else
        local diff=(mode=='HOST' or mode=='SINGLE') and difficulty() or 'EASY'
        screen('CONECTANDO',{'Conectando al servidor #'..serverId,
            'Jugador: '..username,'Modo: '..mode,'', 'Comprobando disponibilidad...'})
        local accepted,reason=networkRequest({type='JOIN',user=username,mode=mode,diff=diff},'ACCEPT',3)
        if accepted then
            previousHP=nil
            if opts.music and speaker then
                for _,n in ipairs({12,17,19,24}) do pcall(speaker.playNote,'harp',.25,n) end
            end
            playGame(serverId,accepted.pid or os.getComputerID(),accepted.round=='RUNNING',mode=='HOST')
        else
            screen('NO SE PUDO ENTRAR',{tostring(reason or 'Servidor ocupado, fuera de alcance o modo incompatible.'),
                'Pulsa una tecla para volver al menu.'})
            os.pullEvent('key')
        end
    end
end
screen('WORLD STUDIOS',{'Gracias por jugar a Siege Protocol.'},'WorldTor Engine v1.0')
