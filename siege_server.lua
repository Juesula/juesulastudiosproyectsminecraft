-- SIEGE PROTOCOL / servidor CC:Tweaked 1.21.1 (motor WorldTor independiente)
-- Servidor autoritativo: coop, solo, PvP, evento MMO, bosses, oleadas, editor, clasificacion.
local PROTO, W, H = 'WORLDTOR_SIEGE_V1', 51, 19
local modems={peripheral.find('modem')}
if #modems==0 then error('Conecta un modem (inalambrico o por cable) al servidor.') end
for _,m in ipairs(modems) do rednet.open(peripheral.getName(m)) end
pcall(rednet.host,PROTO,'siege-protocol')
math.randomseed((os.epoch and os.epoch('utc') or os.clock()*100000)%2147483647)

local function loadTable(path,def)
    if not fs.exists(path) then return def end
    local f=fs.open(path,'r');local ok,res=pcall(textutils.unserialize,f.readAll());f.close()
    return ok and type(res)=='table' and res or def
end
local function save(path,v)
    local f=fs.open(path,'w');f.write(textutils.serialize(v));f.close()
end
local lb=loadTable('worldtor_scores.txt',{})
local ann=loadTable('worldtor_announcement.txt',{enabled=false,text=''})
local cfg=loadTable('worldtor_settings.txt',{mode='NORMAL'})
local closed=false
local closing=0
local shutdownText='Apagando servidor en'
local access=true
local custom={art={' /#\\ ', '[###]', ' \\#/ '}, hp=28, dmg=2, score=250}
local C={}
local round='IDLE';local match='EASY';local gameMode='COOP';local host=nil
local state=nil;local tick=0;local nextWave=0;local spawned=0;local spawnBudget=0;local lastSave=0
local function send(id,pack) rednet.send(id,pack,PROTO) end
local function broadcast(pack) for id in pairs(C) do send(id,pack) end end
local function saveScores()save('worldtor_scores.txt',lb) end
local function sayScreen(lines)
    term.setBackgroundColor(colors.black);term.setTextColor(colors.cyan);term.clear()
    term.setCursorPos(1,1); print('SIEGE PROTOCOL  //  SERVIDOR  v1.0.1')
    term.setTextColor(colors.white)
    for _,line in ipairs(lines) do print(line) end
end
local function announceEditor()
    sayScreen({'ANUNCIOS', 'Activado: '..tostring(ann.enabled),'Texto: '..tostring(ann.text),'', '[A] Cambiar ON/OFF', '[T] Escribir anuncio','[ENTER] Terminar'})
    while true do
        local _,k=os.pullEvent('key')
        if k==keys.enter then break
        elseif k==keys.a then ann.enabled=not ann.enabled; save('worldtor_announcement.txt',ann)
        elseif k==keys.t then
            term.setCursorPos(1,11);term.clearLine(); term.write('Mensaje: ')
            ann.text=read():sub(1,80);ann.enabled=ann.text~=''; save('worldtor_announcement.txt',ann)
        end
        sayScreen({'ANUNCIOS', 'Activado: '..tostring(ann.enabled),'Texto: '..tostring(ann.text),'', '[A] Cambiar ON/OFF', '[T] Escribir anuncio','[ENTER] Terminar'})
    end
end
local function editBoss()
    local grid={{' ',' ',' '},{' ','#',' '},{' ',' ',' '}}
    local x,y=2,2
    while true do
        sayScreen({'EDITOR JEFE 3X3','Flechas: mover | Espacio: pintar | ENTER: guardar', ''})
        for j=1,3 do
            term.setCursorPos(11,j+4)
            for i=1,3 do
                term.setBackgroundColor(x==i and y==j and colors.gray or colors.black)
                term.write(grid[j][i]==' ' and '.' or grid[j][i])
            end
        end
        term.setBackgroundColor(colors.black)
        local _,key=os.pullEvent('key')
        if key==keys.left then x=math.max(1,x-1)
        elseif key==keys.right then x=math.min(3,x+1)
        elseif key==keys.up then y=math.max(1,y-1)
        elseif key==keys.down then y=math.min(3,y+1)
        elseif key==keys.space then grid[y][x]=grid[y][x]==' ' and '#' or ' '
        elseif key==keys.enter then break end
    end
    custom.art={table.concat(grid[1]),table.concat(grid[2]),table.concat(grid[3])}
    sayScreen({'Editor: vida del jefe:'});custom.hp=math.max(1,tonumber(read()) or 28)
    sayScreen({'Editor: dano del jefe:'});custom.dmg=math.max(1,tonumber(read()) or 2)
end
local function blankState()
    return {players={},enemies={},shots={},obstacles={},items={},fx={},sounds={},
            tick=0,w=W,h=H,wave=1,kills=0,status='READY',paused=false,
            waveNotice=0,mode=gameMode, difficulty=match }
end
local function createObstacles()
    state.obstacles={}
    for i=1,10 do
        local x=math.random(6,45);local y=math.random(6,14)
        if math.abs(x-14)>4 and math.abs(x-37)>4 then
            state.obstacles[#state.obstacles+1]={x=x,y=y,hp=5}
        end
    end
end
local function collides(x,y)
    if x<2 or x>W-1 or y<4 or y>H-2 then return true end
    for _,o in ipairs(state.obstacles) do
        if o.hp>0 and math.abs(x-o.x)<0.85 and math.abs(y-o.y)<0.85 then return true end
    end
    return false
end
local function fx(x,y,kind) state.fx[#state.fx+1]={x=x,y=y,c=kind or '*',life=5} end
local function snd(s) state.sounds[#state.sounds+1]=s end
local function norm(dx,dy)
    local l=math.sqrt(dx*dx+dy*dy)
    if l<0.001 then return 0,-1 end
    return dx/l,dy/l
end
local function addPlayer(id,idx)
    local c=C[id];if not c then return end
    local x=idx%2==1 and 13 or 38
    local y=idx<=2 and 15 or 6
    state.players[id]={x=x,y=y,hp=100,maxHp=100,score=0,kills=0,ammo=14,maxAmmo=14,
        weapon=1,reload=0,grenades=3,dash=0,cool=0,aimX=0,aimY=-1,
        invul=0,respawn=0,user=c.user,pid=idx,shield=0,rapid=0,color=idx%2==1 and colors.cyan or colors.lime}
end
local function startRound()
    tick=0;state=blankState();round='RUNNING';spawnBudget=7;spawned=0;nextWave=0
    createObstacles()
    local i=0
    for id in pairs(C) do i=i+1;addPlayer(id,i) end
    broadcast({type='START',mode=gameMode,diff=match})
end
local function winner(id)
    local p=state and state.players[id]
    if p and p.user then lb[p.user]=math.max(tonumber(lb[p.user]) or 0,p.score or 0) end
end
local function removeClient(id)
    winner(id);saveScores();C[id]=nil
    if state then state.players[id]=nil end
    if host==id then
        host=nil
        if round=='LOBBY' then round='IDLE';broadcast({type='CANCEL',reason='Host desconectado.'}) end
    end
end
local function info(id)
    send(id,{type='INFO',mode=cfg.mode,round=round,announcement=ann,players=(function()local n=0;for _ in pairs(C) do n=n+1 end;return n end)()})
end
local function reject(id,reason)send(id,{type='REJECT',reason=reason})end
local function join(id,msg)
    local name=tostring(msg.user or ''):gsub('[^%w_%-]',''):sub(1,16)
    if #name<1 then return reject(id,'Nombre no valido') end
    for other,client in pairs(C) do if other~=id and client.user:lower()==name:lower() then return reject(id,'Usuario ya conectado') end end
    if C[id] then
        send(id,{type='ACCEPT',pid=id,w=W,h=H,round=round,mode=gameMode});return
    end
    local req=tostring(msg.mode or '')
    if cfg.mode=='EVENT' then
        if req~='EVENT' then return reject(id,'Servidor en modo EVENTO') end
        if not access then return reject(id,'Acceso evento desactivado') end
        local count=0;for _ in pairs(C) do count=count+1 end
        if count>=8 then return reject(id,'Servidor lleno (8 jugadores)') end
        C[id]={user=name,keys={},last=tick}
        if round~='RUNNING' then gameMode='COOP';match='HARD';startRound()
        else local idx=0;for _ in pairs(C) do idx=idx+1 end;addPlayer(id,idx) end
        send(id,{type='ACCEPT',pid=id,w=W,h=H,round='RUNNING',mode='EVENT'})
        return
    end
    if round=='RUNNING' or round=='OVER' then return reject(id,'Partida en curso') end
    local count=0;for _ in pairs(C) do count=count+1 end
    if count==0 and (req=='HOST' or req=='SINGLE') then
        C[id]={user=name,keys={},last=tick};host=id
        match=(msg.diff=='HARD' or msg.diff=='PVP') and msg.diff or 'EASY'
        gameMode=match=='PVP' and 'PVP' or 'COOP'
        round='LOBBY'
        send(id,{type='ACCEPT',pid=id,w=W,h=H,round=round,mode=gameMode})
        if req=='SINGLE' then startRound() end
    elseif count==1 and req=='JOIN' and round=='LOBBY' then
        C[id]={user=name,keys={},last=tick}
        send(id,{type='ACCEPT',pid=id,w=W,h=H,round='LOBBY',mode=gameMode})
        send(host,{type='PLAYER_JOINED',user=name})
    else reject(id,'No hay lobby disponible; crea una partida') end
end
local function direction(p,dx,dy) p.aimX,p.aimY=norm(dx,dy) end
local function fire(id,p)
    if p.hp<=0 or p.cool>0 or p.reload>0 or p.ammo<=0 then return end
    local settings={{speed=1.45,damage=2,cd=3,count=1,spread=0,ammo=1},
                    {speed=1.30,damage=1,cd=8,count=5,spread=.6,ammo=2},
                    {speed=1.8,damage=5,cd=10,count=1,spread=0,ammo=3}}
    local spec=settings[p.weapon] or settings[1]
    if p.ammo<spec.ammo then return end
    p.ammo=p.ammo-spec.ammo;p.cool=p.rapid>0 and math.max(1,math.floor(spec.cd/2)) or spec.cd
    for i=1,spec.count do
        local offset=(i-(spec.count+1)/2)*spec.spread
        local dx,dy=norm(p.aimX-p.aimY*offset,p.aimY+p.aimX*offset)
        state.shots[#state.shots+1]={x=p.x+dx,y=p.y+dy,vx=dx*spec.speed,vy=dy*spec.speed,
                                      dmg=spec.damage,from=id,life=24,c=spec.count>1 and '*' or (p.weapon==3 and '=' or '.')}
    end
    snd(p.weapon==3 and 'laser' or 'shoot')
    if #state.shots>160 then table.remove(state.shots,1) end
end
local function grenade(id,p)
    if p.hp<=0 or p.grenades<=0 then return end
    p.grenades=p.grenades-1
    local x,y=p.x+p.aimX*6,p.y+p.aimY*5
    fx(x,y,'@');snd('boom')
    for i=#state.enemies,1,-1 do
        local e=state.enemies[i]
        if (e.x-x)^2+(e.y-y)^2<=32 then
            e.hp=e.hp-12
            if e.hp<=0 then p.score=p.score+(e.score or 10);p.kills=p.kills+1;table.remove(state.enemies,i) end
        end
    end
    for _,q in pairs(state.players) do
        if gameMode=='PVP' and q~=p and (q.x-x)^2+(q.y-y)^2<=14 then q.hp=math.max(0,q.hp-35) end
    end
end
local function damage(p,amount)
    if not p or p.hp<=0 or p.invul>0 then return false end
    local actual=p.shield>0 and math.ceil(amount/2) or amount
    p.hp=math.max(0,p.hp-actual);p.invul=8
    snd('hit');fx(p.x,p.y,'X')
    if p.hp==0 then p.respawn=45;snd('death') end
    return p.hp==0
end
local function spawnEnemy(typ)
    if #state.enemies>65 then return end
    typ=typ or 'grunt'
    local x,y
    if math.random(2)==1 then x=math.random(2,W-1);y=math.random(2)==1 and 4 or H-2
    else x=math.random(2)==1 and 2 or W-1;y=math.random(4,H-2) end
    local stats={grunt={hp=3,spd=.24,dmg=9,score=15,c='z'},
        ranger={hp=5,spd=.14,dmg=11,score=30,c='r'},
        hunter={hp=3,spd=.36,dmg=7,score=25,c='h'},
        tank={hp=16,spd=.12,dmg=16,score=65,c='T'},
        boss={hp=110,spd=.16,dmg=20,score=400,c='B'},
        custom={hp=custom.hp,spd=.2,dmg=custom.dmg,score=custom.score,c='C'}}
    local s=stats[typ] or stats.grunt
    state.enemies[#state.enemies+1]={x=x,y=y,hp=s.hp,maxHp=s.hp,vx=0,vy=0,spd=s.spd,
        dmg=s.dmg,score=s.score,typ=typ,c=s.c,cd=math.random(4,16),art=typ=='custom' and custom.art or nil}
    if typ=='boss' or typ=='custom' then snd('boss');state.waveNotice=28 end
end
local function drop(x,y)
    if math.random()<0.21 then
        local types={'heal','ammo','shield','grenade','rapid'}
        local typeName=types[math.random(#types)]
        state.items[#state.items+1]={x=x,y=y,typ=typeName,life=200}
    end
end
local function killEnemy(i,attacker)
    local e=state.enemies[i];if not e then return end
    fx(e.x,e.y,'*');snd(e.typ=='boss' and 'boom' or 'hit')
    if attacker and state.players[attacker] then
        local p=state.players[attacker]
        p.score=p.score+e.score;p.kills=p.kills+1;state.kills=state.kills+1
        lb[p.user]=math.max(tonumber(lb[p.user]) or 0,p.score)
    end
    drop(e.x,e.y);table.remove(state.enemies,i)
end
local function nearest(x,y)
    local best,dist=nil,1e9
    for _,p in pairs(state.players) do
        if p.hp>0 then local d=(x-p.x)^2+(y-p.y)^2;if d<dist then best=p;dist=d end end
    end
    return best,math.sqrt(dist)
end
local function updateGame()
    if not state or round~='RUNNING' then return end
    state.tick=tick
    if state.paused then return end
    for id,p in pairs(state.players) do
        if p.cool>0 then p.cool=p.cool-1 end
        if p.invul>0 then p.invul=p.invul-1 end
        if p.shield>0 then p.shield=p.shield-1 end
        if p.rapid>0 then p.rapid=p.rapid-1 end
        if p.reload>0 then p.reload=p.reload-1;if p.reload==0 then p.ammo=p.maxAmmo;snd('reload') end end
        if p.hp<=0 then
            if cfg.mode=='EVENT' or gameMode=='COOP' then
                p.respawn=p.respawn-1
                if p.respawn<=0 then p.hp=100;p.x=math.random(12,39);p.y=math.random(8,15);p.invul=20 end
            end
        else
            local kd=C[id] and C[id].keys or {}
            local dx=((kd[keys.d] or kd[keys.right]) and 1 or 0)-((kd[keys.a] or kd[keys.left]) and 1 or 0)
            local dy=((kd[keys.s] or kd[keys.down]) and 1 or 0)-((kd[keys.w] or kd[keys.up]) and 1 or 0)
            if dx~=0 or dy~=0 then dx,dy=norm(dx,dy) end
            local speed=p.dash>0 and 1.0 or .65
            if p.dash>0 then p.dash=p.dash-1 end
            if not collides(p.x+dx*speed,p.y) then p.x=p.x+dx*speed end
            if not collides(p.x,p.y+dy*speed) then p.y=p.y+dy*speed end
            local ax=((kd[keys.l]) and 1 or 0)-((kd[keys.j]) and 1 or 0)
            local ay=((kd[keys.k]) and 1 or 0)-((kd[keys.i]) and 1 or 0)
            if ax~=0 or ay~=0 then direction(p,ax,ay) end
            if kd[keys.space] then fire(id,p) end
            for idx=#state.items,1,-1 do
                local it=state.items[idx]
                if math.abs(p.x-it.x)<1.2 and math.abs(p.y-it.y)<1.2 then
                    if it.typ=='heal' then p.hp=math.min(100,p.hp+35)
                    elseif it.typ=='ammo' then p.ammo=p.maxAmmo;p.reload=0
                    elseif it.typ=='shield' then p.shield=120
                    elseif it.typ=='grenade' then p.grenades=math.min(6,p.grenades+2)
                    elseif it.typ=='rapid' then p.rapid=100 end
                    table.remove(state.items,idx);snd('pick')
                end
            end
        end
    end
    for i=#state.items,1,-1 do local a=state.items[i];a.life=a.life-1;if a.life<=0 then table.remove(state.items,i) end end
    for i=#state.fx,1,-1 do local a=state.fx[i];a.life=a.life-1;if a.life<=0 then table.remove(state.fx,i) end end
    if gameMode~='PVP' then
        if spawnBudget>0 and tick%8==0 then
            local r=math.random(100)
            local typ=(state.wave>3 and r>94) and 'tank' or (r>74 and 'ranger' or (r>48 and 'hunter' or 'grunt'))
            if state.wave%4==0 and spawnBudget==1 then typ='boss' end
            spawnEnemy(typ);spawnBudget=spawnBudget-1
        end
        if spawnBudget==0 and #state.enemies==0 then
            if nextWave==0 then nextWave=36;state.waveNotice=35 end
            nextWave=nextWave-1
            if nextWave<=0 then
                state.wave=state.wave+1;spawnBudget=7+state.wave*3
                if state.wave%4==0 then spawnBudget=spawnBudget+1 end
                nextWave=0;state.waveNotice=30;snd('wave')
            end
        end
    end
    if state.waveNotice>0 then state.waveNotice=state.waveNotice-1 end
    for i=#state.enemies,1,-1 do
        local e=state.enemies[i];local target,dist=nearest(e.x,e.y)
        if target then
            local dx,dy=norm(target.x-e.x,target.y-e.y)
            local speed=e.spd*((match=='HARD' or cfg.mode=='EVENT') and 1.3 or 1)
            if not collides(e.x+dx*speed,e.y) then e.x=e.x+dx*speed end
            if not collides(e.x,e.y+dy*speed) then e.y=e.y+dy*speed end
            e.cd=e.cd-1
            if dist<1.7 then if tick%9==0 then damage(target,e.dmg) end end
            if e.cd<=0 and (e.typ=='ranger' or e.typ=='tank' or e.typ=='boss' or e.typ=='custom') and dist<22 then
                e.cd=e.typ=='boss' and 9 or (e.typ=='ranger' and 19 or 28)
                local n=e.typ=='boss' and 3 or 1
                for s=1,n do
                    local spread=(s-(n+1)/2)*.3
                    local vx,vy=norm(dx-dy*spread,dy+dx*spread)
                    state.shots[#state.shots+1]={x=e.x,y=e.y,vx=vx*.65,vy=vy*.65,dmg=e.dmg,from=-1,life=34,c='!'}
                end
                snd('enemy')
            end
        end
    end
    for i=#state.shots,1,-1 do
        local b=state.shots[i];b.x=b.x+b.vx;b.y=b.y+b.vy;b.life=b.life-1
        local hit=b.life<=0 or collides(b.x,b.y)
        if not hit and b.from==-1 then
            for _,p in pairs(state.players) do
                if p.hp>0 and (p.x-b.x)^2+(p.y-b.y)^2<1.2 then damage(p,b.dmg);hit=true;break end
            end
        elseif not hit then
            if gameMode=='PVP' then
                for id,p in pairs(state.players) do
                    if id~=b.from and p.hp>0 and (p.x-b.x)^2+(p.y-b.y)^2<1.1 then
                        local died=damage(p,b.dmg*7)
                        if died and state.players[b.from] then
                            state.players[b.from].score=state.players[b.from].score+150
                            state.players[b.from].kills=state.players[b.from].kills+1
                        end
                        hit=true;break
                    end
                end
            else
                for j=#state.enemies,1,-1 do
                    local e=state.enemies[j]
                    if (e.x-b.x)^2+(e.y-b.y)^2<(e.typ=='boss' and 3 or 1) then
                        e.hp=e.hp-b.dmg;hit=true;if e.hp<=0 then killEnemy(j,b.from) end;break
                    end
                end
            end
        end
        if hit then fx(b.x,b.y,'.');table.remove(state.shots,i) end
    end
    if #state.shots>180 then while #state.shots>180 do table.remove(state.shots,1) end end
    if cfg.mode=='NORMAL' then
        local alive=0
        for _,p in pairs(state.players) do if p.hp>0 then alive=alive+1 end end
        if (gameMode=='PVP' and alive<=1) or (gameMode=='COOP' and alive==0) then
            round='OVER';state.status='GAME_OVER'
            for id in pairs(C) do winner(id) end;saveScores()
            broadcast({type='GAME_OVER',scores=lb});nextWave=45
        end
    end
end
local function handle(id,msg)
    if type(msg)~='table' or type(msg.type)~='string' then return end
    if msg.type=='DISCOVER' then info(id);return end
    if msg.type=='REQ_LEADERBOARD' then send(id,{type='LEADERBOARD',scores=lb});return end
    if msg.type=='REQ_ANNOUNCEMENT' then send(id,{type='ANNOUNCEMENT',data=ann});return end
    if msg.type=='JOIN' then join(id,msg);return end
    if not C[id] then return end
    C[id].last=tick
    if msg.type=='PING' then return end
    if msg.type=='LEAVE' then removeClient(id);return end
    if msg.type=='START' and id==host and round=='LOBBY' then
        local count=0;for _ in pairs(C) do count=count+1 end
        if gameMode=='PVP' and count<2 then send(id,{type='NOTICE',text='El modo PVP requiere 2 jugadores.'})
        else startRound() end
        return
    end
    if msg.type=='PAUSE' and cfg.mode=='NORMAL' and (id==host or gameMode=='COOP') and state then
        state.paused=not state.paused;broadcast({type='PAUSE',value=state.paused});return
    end
    local p=state and state.players[id]
    if not p then return end
    if msg.type=='KEY' and type(msg.key)=='number' then
        C[id].keys[msg.key]=msg.down==true
        if msg.down then
            if msg.key==keys.one then p.weapon=1;p.maxAmmo=14;p.ammo=math.min(p.ammo,14)
            elseif msg.key==keys.two then p.weapon=2;p.maxAmmo=8;p.ammo=math.min(p.ammo,8)
            elseif msg.key==keys.three then p.weapon=3;p.maxAmmo=5;p.ammo=math.min(p.ammo,5)
            elseif msg.key==keys.r and p.reload<=0 and p.ammo<p.maxAmmo then p.reload=17
            elseif msg.key==keys.g then grenade(id,p)
            elseif msg.key==keys.leftShift or msg.key==keys.rightShift then p.dash=3 end
        end
    elseif msg.type=='FIRE_AT' and type(msg.x)=='number' and type(msg.y)=='number' then
        direction(p,msg.x-p.x,msg.y-p.y);fire(id,p)
    end
end
local function bootMenu()
    while true do
        sayScreen({'', '1 - NORMAL (solo / 2 jugadores / PvP)',
                   '2 - EVENTO MMO (hasta 8 jugadores)',
                   '3 - Configurar anuncios',
                   '', 'Guardado: '..tostring(cfg.mode),'', 'Selecciona con el teclado.'})
        local _,k=os.pullEvent('key')
        if k==keys.one then cfg.mode='NORMAL';break
        elseif k==keys.two then cfg.mode='EVENT';break
        elseif k==keys.three then announceEditor() end
    end
    save('worldtor_settings.txt',cfg)
end
bootMenu()
if cfg.mode=='EVENT' then round='IDLE' end
local timer=os.startTimer(.1)
local logTimer=0
while not closed do
    local ev={os.pullEvent()}
    if ev[1]=='rednet_message' and ev[4]==PROTO then handle(ev[2],ev[3])
    elseif ev[1]=='timer' and ev[2]==timer then
        timer=os.startTimer(.1);tick=tick+1
        if closing>0 then closing=closing-1;if closing<=0 then broadcast({type='SHUTDOWN',text=shutdownText});closed=true end end
        if round=='RUNNING' then
            updateGame()
            if tick%2==0 then
                state.serverClosing=closing>0 and math.ceil(closing/10) or 0
                state.announcement=ann.enabled and ann.text or nil
                for id in pairs(C) do send(id,{type='STATE',state=state}) end
            end
            state.sounds={}
        elseif round=='OVER' then
            nextWave=nextWave-1
            if nextWave<=0 then
                for id in pairs(C) do send(id,{type='RETURN_MENU'}) end
                C={};host=nil;state=nil;round='IDLE'
            end
        end
        if tick%50==0 then
            for id,c in pairs(C) do if tick-c.last>120 then removeClient(id) end end
            saveScores()
        end
        if tick%10==0 then
            logTimer=logTimer+1
            local n=0;for _ in pairs(C) do n=n+1 end
            sayScreen({'Modo: '..cfg.mode,'Estado: '..round,'Jugadores: '..n,
                      'Ola: '..tostring(state and state.wave or '-'),
                      'Enemigos: '..tostring(state and #state.enemies or 0),
                      '', 'A: Anuncio | Y: Cierre | U: Cancelar',
                      'EVENTO -> B: Boss | H: Curar | N: Ola',
                      '           C: Jefe custom | D: Editor | X: Acceso',
                      'Acceso MMO: '..tostring(access),
                      closing>0 and ('CIERRE: '..math.ceil(closing/10)..'s') or ''})
        end
    elseif ev[1]=='key' then
        local k=ev[2]
        if k==keys.a then announceEditor()
        elseif k==keys.y then
            sayScreen({'Texto para el cierre:'});local t=read();if t~='' then shutdownText=t end
            sayScreen({'Segundos hasta cierre:'});closing=math.max(1,math.floor((tonumber(read()) or 60)*10))
        elseif k==keys.u then closing=0
        elseif cfg.mode=='EVENT' then
            if k==keys.x then access=not access
            elseif k==keys.d then editBoss()
            elseif state and round=='RUNNING' then
                if k==keys.b then spawnEnemy('boss')
                elseif k==keys.c then spawnEnemy('custom')
                elseif k==keys.h then for _,p in pairs(state.players) do p.hp=100;p.ammo=p.maxAmmo end;snd('pick')
                elseif k==keys.n then spawnBudget=spawnBudget+12;state.wave=state.wave+1;state.waveNotice=30 end
            end
        end
    end
end
saveScores();term.clear();print('Siege Protocol Server detenido.')
