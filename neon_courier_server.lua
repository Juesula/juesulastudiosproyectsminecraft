-- NEON COURIER 2.0 | WORLD STUDIOS | Servidor autoritativo CC:Tweaked
-- WorldTor es el motor grafico del CLIENTE; el servidor no necesita renderizar el juego.
-- Coop / PvP / evento MMO; cuentas por nombre, scores, anuncios, bosses, editor, rankings.
local PROTO, HOST = 'neoncourier.v2', 'neon-courier'
local W, FRAME, MAX = 51, 0.12, 8
local DIR='neon_server_data'
if not fs.exists(DIR) then fs.makeDir(DIR) end
local function path(n) return fs.combine(DIR,n..'.dat') end
local function load(n,def)
  if not fs.exists(path(n)) then return def end
  local h=fs.open(path(n),'r');if not h then return def end
  local raw=h.readAll();h.close()
  local ok,value=pcall(textutils.unserialize,raw)
  return ok and type(value)=='table' and value or def
end
local function save(n,v)
  local h=fs.open(path(n),'w');if h then h.write(textutils.serialize(v));h.close() end
end
local scores=load('scores',{})
local ann=load('announcement',{enabled=false,text=''})
local cfg=load('settings',{mode='NORMAL',difficulty='EASY'})
local boss=load('boss',{name='DRON ALFA',art={' /\\ ','[##]',' \\/ '},damage=1})
local modems=0
for _,side in ipairs(peripheral.getNames()) do
  if peripheral.hasType(side,'modem') then
    if not rednet.isOpen(side) then rednet.open(side) end
    modems=modems+1
  end
end
if modems==0 then error('Conecta un modem al servidor Neon Courier.') end
pcall(rednet.host,PROTO,HOST)
math.randomseed((os.epoch and os.epoch('utc') or math.floor(os.clock()*1000000)) % 2147483647)
local C,round,host,gameMode,diff={},'IDLE',nil,'COOP','EASY'
local state=nil
local tick,spawnCooldown,shutdownTicks,shutdownText=0,12,0,'Servidor detenido'
local acceptEvent=true
local uiMessage='Listo para conexiones.'
local function send(id,msg) pcall(rednet.send,id,msg,PROTO) end
local function broadcast(msg) for id in pairs(C) do send(id,msg) end end
local function countClients()local n=0;for _ in pairs(C) do n=n+1 end;return n end
local function msg(id,s) send(id,{type='NOTICE',text=s}) end
local function resetIfIdle()
  if countClients()==0 then state=nil;host=nil;round='IDLE' end
end
local function saveScore(p)
  if not p or not p.user then return end
  local old=scores[p.user]
  if type(old)~='table' then old={best=tonumber(old) or 0,runs=0,total=0} end
  old.best=math.max(old.best or 0,math.floor(p.score or 0))
  old.total=(old.total or 0)+math.floor(p.score or 0)
  old.runs=(old.runs or 0)+1
  scores[p.user]=old
end
local function endClient(id)
  local client=C[id]
  if not client then return end
  if state and state.players[id] then saveScore(state.players[id]);state.players[id]=nil end
  C[id]=nil
  if host==id then
    host=nil
    if round=='LOBBY' then broadcast({type='CANCEL',text='El anfitrion abandono la sala'});C={};round='IDLE' end
  end
  save('scores',scores)
  resetIfIdle()
end
local function newPlayer(id,idx)
  local c=C[id]
  local p={id=id,user=c.user,x=12+((idx-1)%4)*2,air=0,vy=0,duck=false,
    hp=(diff=='HARD' and 2 or 3),shield=0,energy=0,score=0,best=0,
    alive=true,invul=0,stun=0,respawn=0,coins=0,jumps=0,revives=0}
  state.players[id]=p
  return p
end
local function addClientToGame(id)
  local idx=1;for k in pairs(state.players) do if k~=id then idx=idx+1 end end
  newPlayer(id,idx)
end
local function startMatch()
  tick=0
  round='RUNNING'
  state={w=W,players={},objects={},effects={},mode=gameMode,difficulty=diff,
    ticks=0,distance=0,speed=0.72,level=1,paused=false,bossTime=0,
    bossArt=boss.art,bossName=boss.name,bossDamage=boss.damage,announcement=ann.enabled and ann.text or '',
    notice='INICIO',countdown=20}
  spawnCooldown=18
  local idx=0
  for id in pairs(C) do idx=idx+1;newPlayer(id,idx) end
  broadcast({type='START',mode=gameMode,diff=diff})
end
local function accept(id,matchmode)
  send(id,{type='ACCEPT',pid=id,round=round,mode=matchmode or gameMode,
    host=host,players=countClients()})
end
local function join(id,p)
  local username=tostring(p.user or ''):gsub('[^%w_%-]',''):sub(1,16)
  if username=='' then msg(id,'Usuario invalido');return end
  local request=tostring(p.mode or '')
  for other,c in pairs(C) do
    if other~=id and c.user:lower()==username:lower() then
      msg(id,'Ese usuario ya esta conectado');return
    end
  end
  if C[id] then accept(id);return end
  if cfg.mode=='EVENT' then
    if request~='EVENT' or not acceptEvent then msg(id,'Evento cerrado');return end
    if countClients()>=MAX then msg(id,'Evento completo (8 jugadores)');return end
    C[id]={user=username,last=tick,keys={}}
    if round~='RUNNING' then diff='HARD';gameMode='EVENT';startMatch()
    else addClientToGame(id) end
    accept(id,'EVENT');return
  end
  if round=='RUNNING' or round=='OVER' then msg(id,'Hay una partida en curso');return end
  local n=countClients()
  if n==0 and (request=='HOST' or request=='SINGLE') then
    C[id]={user=username,last=tick,keys={}}
    host=id
    diff=p.diff=='HARD' and 'HARD' or 'EASY'
    gameMode=p.diff=='PVP' and 'PVP' or (request=='SINGLE' and 'SOLO' or 'COOP')
    if gameMode=='PVP' then diff='HARD' end
    round='LOBBY'
    if request=='SINGLE' then startMatch() end
    accept(id)
  elseif n>=1 and n<4 and request=='JOIN' and round=='LOBBY' then
    C[id]={user=username,last=tick,keys={}}
    accept(id)
    if host then send(host,{type='PLAYER_JOINED',user=username,players=countClients()}) end
  else msg(id,'No hay sala libre. Crea o espera una partida.') end
end
local function spawn(typ)
  if not state then return end
  local object={x=W+2,typ=typ or 'box',id=tick}
  if object.typ=='battery' then object.alt=math.random(0,1)
  elseif object.typ=='boss' then object.alt=0
  end
  state.objects[#state.objects+1]=object
end
local function bump(p,damage)
  if p.invul>0 or not p.alive then return end
  if p.shield>0 then p.shield=p.shield-1;p.invul=8
  else p.hp=p.hp-(damage or 1);p.invul=15 end
  state.effects[#state.effects+1]={x=p.x,y=p.air,c='*',life=6}
  if p.hp<=0 then
    p.alive=false
    p.respawn=gameMode=='EVENT' and 38 or 0
  end
end
local function collision(p,o)
  if o.typ=='battery' then
    if o.alt==0 or p.air>0.6 then
      p.energy=math.min(p.energy+1,9);p.coins=p.coins+1;p.score=p.score+25
      if p.coins%4==0 then p.shield=math.min(p.shield+1,3) end
      return 'pick'
    end
    return nil
  end
  if o.typ=='drone' then
    if not p.duck and p.air<3.0 then bump(p) end
  elseif o.typ=='tall' then
    if p.air<2.25 then bump(p) end
  elseif o.typ=='boss' then
    if p.air<3.0 or not p.duck then bump(p,math.max(1,tonumber(state.bossDamage) or 1)) end
  else
    if p.air<1.3 then bump(p) end
  end
  return nil
end
local function gameEnd()
  round='OVER'
  local winners={}
  local top=-1
  for id,p in pairs(state.players) do
    saveScore(p)
    if p.score>top then winners={p.user};top=p.score
    elseif p.score==top then winners[#winners+1]=p.user end
  end
  save('scores',scores)
  local bestName=table.concat(winners,', ')
  broadcast({type='GAME_OVER',winner=bestName,reason='Carrera terminada',scores=(function()
    local t={};for _,p in pairs(state.players) do t[#t+1]={user=p.user,score=p.score,alive=p.alive} end
    table.sort(t,function(a,b)return a.score>b.score end);return t
  end)()})
  state.overTicks=70
end
local function update()
  if not state or state.paused then return end
  local s=state
  s.ticks=s.ticks+1
  s.distance=s.distance+s.speed
  s.level=1+math.floor(s.distance/110)
  s.speed=math.min(diff=='HARD' and 2.1 or 1.75,0.72+s.distance/680)
  s.announcement=ann.enabled and ann.text or ''
  if s.countdown>0 then s.countdown=s.countdown-1 end
  local alive,count=0,0
  for id,p in pairs(s.players) do
    count=count+1
    if not p.alive and gameMode=='EVENT' then
      p.respawn=p.respawn-1
      if p.respawn<=0 then p.alive=true;p.hp=1;p.air=0;p.vy=0;p.invul=24;p.shield=1 end
    end
    if p.alive then
      alive=alive+1
      p.score=p.score+math.ceil(s.speed*1.4)
      p.air=math.max(0,p.air+p.vy)
      if p.air>0 then p.vy=p.vy-0.36 else p.air=0;p.vy=0 end
      p.duck=C[id] and (C[id].keys[keys.down] or C[id].keys[keys.s]) or false
      p.invul=math.max(0,p.invul-1);p.stun=math.max(0,p.stun-1)
    end
  end
  spawnCooldown=spawnCooldown-1
  if spawnCooldown<=0 then
    local r=math.random(100)
    local typ=(r<=12 and 'battery') or (r<=34 and 'drone') or (r<=56 and 'tall') or 'box'
    if s.level>=4 and r>91 then typ='boss' end
    spawn(typ)
    spawnCooldown=math.max(7,math.floor(14-s.speed*1.9))+math.random(0,5)
  end
  for i=#s.objects,1,-1 do
    local o=s.objects[i];o.x=o.x-s.speed
    for _,p in pairs(s.players) do
      o.touched=o.touched or {}
      if p.alive and not o.touched[p.id] and math.abs(o.x-p.x)<0.85 then
        local result=collision(p,o)
        -- Cada objeto afecta a cada jugador como maximo una vez.
        o.touched[p.id]=true
        if result=='pick' then o.collected=true end
      end
    end
    if o.x < 0 or o.collected then table.remove(s.objects,i) end
  end
  for i=#s.effects,1,-1 do local e=s.effects[i];e.life=e.life-1;if e.life<=0 then table.remove(s.effects,i) end end
  if gameMode=='PVP' and count>=2 and alive<=1 then gameEnd();return end
  if gameMode~='EVENT' and alive==0 then gameEnd();return end
end
local function special(id,p,kind)
  if not state or not p or not p.alive then return end
  if kind=='EMP' and gameMode=='PVP' and p.energy>=3 then
    p.energy=p.energy-3
    for other,opp in pairs(state.players) do if other~=id and opp.alive then opp.stun=12 end end
    state.notice=p.user..' lanzo pulso EMP!';state.countdown=13
  elseif kind=='REVIVE' and gameMode=='COOP' and p.energy>=3 then
    for other,opp in pairs(state.players) do
      if other~=id and not opp.alive then
        p.energy=p.energy-3;opp.alive=true;opp.hp=1;opp.air=0;opp.vy=0;opp.invul=22
        p.revives=p.revives+1;state.notice=p.user..' rescato a '..opp.user;state.countdown=16
        break
      end
    end
  elseif kind=='SHIELD' and p.energy>=2 then
    p.energy=p.energy-2;p.shield=math.min(p.shield+1,3)
  end
end
local function handle(id,p)
  if type(p)~='table' or type(p.type)~='string' then return end
  if p.type=='DISCOVER' then
    send(id,{type='INFO',mode=cfg.mode,round=round,players=countClients(),announcement=ann});return
  end
  if p.type=='REQ_LEADERBOARD' then send(id,{type='LEADERBOARD',scores=scores});return end
  if p.type=='REQ_ANNOUNCEMENT' then send(id,{type='ANNOUNCEMENT',data=ann});return end
  if p.type=='JOIN' then join(id,p);return end
  if not C[id] then return end
  C[id].last=tick
  if p.type=='PING' then return end
  if p.type=='LEAVE' then endClient(id);return end
  if p.type=='START' and id==host and round=='LOBBY' then
    if gameMode=='PVP' and countClients()<2 then msg(id,'PvP necesita al menos 2 jugadores')
    else startMatch() end
    return
  end
  if p.type=='PAUSE' and round=='RUNNING' and cfg.mode=='NORMAL' and (id==host or gameMode=='SOLO') then
    state.paused=not state.paused;broadcast({type='PAUSE',value=state.paused});return
  end
  local player=state and state.players[id]
  if not player or round~='RUNNING' then return end
  if p.type=='KEY' and type(p.key)=='number' then
    if p.down==true and not C[id].keys[p.key] then
      if (p.key==keys.space or p.key==keys.up or p.key==keys.w) and player.alive and player.air==0 and player.stun==0 then
        player.vy=2.05;player.air=0.15;player.jumps=player.jumps+1
      elseif p.key==keys.f then special(id,player,'EMP')
      elseif p.key==keys.e then special(id,player,'REVIVE')
      elseif p.key==keys.x then special(id,player,'SHIELD') end
    end
    C[id].keys[p.key]=p.down==true
  elseif p.type=='ACTION' and type(p.action)=='string' then
    if p.action=='JUMP' and player.alive and player.air==0 and player.stun==0 then player.vy=2.05;player.air=0.15
    elseif p.action=='DUCK' then C[id].keys[keys.down]=p.down==true
    elseif p.action=='EMP' or p.action=='REVIVE' or p.action=='SHIELD' then special(id,player,p.action) end
  end
end
local function banner(lines)
  term.setBackgroundColor(colors.black);term.setTextColor(colors.cyan);term.clear();term.setCursorPos(1,1)
  print('NEON COURIER // SERVIDOR 2.0')
  term.setTextColor(colors.white)
  for _,l in ipairs(lines) do print(l) end
end
local function ask(title)
  banner({title,'Escribe y pulsa ENTER:'});return read() or ''
end
local function announceEdit()
  local a=ask('Anuncio (vacio para desactivar):')
  ann.text=a:sub(1,85);ann.enabled=ann.text~='';save('announcement',ann)
  uiMessage=ann.enabled and 'Anuncio actualizado' or 'Anuncio desactivado'
end
local function bossEdit()
  local rows={}
  for i=1,3 do
    local s=ask('Jefe: dibujo fila '..i..' (3 caracteres):');rows[i]=(s..'   '):sub(1,3)
  end
  boss.art=rows;boss.name=(ask('Nombre del jefe:') or ''):sub(1,20)
  if boss.name=='' then boss.name='DRON ALFA' end
  boss.damage=math.max(1,math.min(3,tonumber(ask('Dano del jefe 1-3:')) or 1))
  save('boss',boss);uiMessage='Jefe personalizado guardado'
end
local function drawAdmin()
  local scoresNum=0;for _ in pairs(scores) do scoresNum=scoresNum+1 end
  banner({'', 'Modo servidor: '..cfg.mode,'Sala: '..round..' | Tipo: '..gameMode,
    'Jugadores: '..countClients()..'/'..MAX,'Usuarios puntuados: '..scoresNum,
    state and ('Distancia: '..math.floor(state.distance)..'  Nivel: '..state.level) or 'Esperando jugadores...',
    '', '[1] NORMAL   [2] EVENTO MMO', '[A] Anuncio  [D] Editor de jefe',
    '[B] Ataque jefe  [N] Oleada  [H] Ayuda',
    '[X] Activar/cerrar acceso MMO', '[Y] Cierre programado [U] Cancelar',
    '', 'Acceso MMO: '..(acceptEvent and 'ABIERTO' or 'CERRADO'),
    'Anuncio: '..(ann.enabled and ann.text or '-'),
    '', uiMessage})
end
local function adminKey(k)
  if k==keys.one and countClients()==0 then
    cfg.mode='NORMAL';save('settings',cfg);uiMessage='Modo NORMAL activado'
  elseif k==keys.two and countClients()==0 then
    cfg.mode='EVENT';save('settings',cfg);uiMessage='Modo EVENTO activado'
  elseif k==keys.one or k==keys.two then uiMessage='Espera a que salga toda la sala para cambiar modo'
  elseif k==keys.a then announceEdit()
  elseif k==keys.d then bossEdit()
  elseif k==keys.x then acceptEvent=not acceptEvent;uiMessage='Acceso MMO: '..tostring(acceptEvent)
  elseif k==keys.b and state and round=='RUNNING' then
    spawn('boss');state.notice=boss.name..' aparece!';state.countdown=23
  elseif k==keys.n and state and round=='RUNNING' then
    for _=1,3 do spawn(math.random(2)==1 and 'tall' or 'box') end
    state.notice='OLEADA EXTRA';state.countdown=20
  elseif k==keys.h and state and round=='RUNNING' then
    for _,p in pairs(state.players) do if p.alive then p.hp=3;p.shield=math.max(1,p.shield) end end
    state.notice='BONUS ADMINISTRADOR';state.countdown=20
  elseif k==keys.y then
    local seconds=tonumber(ask('Cierre en cuantos segundos? (0 cancela):')) or 0
    shutdownTicks=math.max(0,math.floor(seconds/FRAME));uiMessage='Cierre programado: '..seconds..' s'
  elseif k==keys.u then shutdownTicks=0;uiMessage='Cierre cancelado'
  end
end
print('NEON COURIER SERVER: Iniciando...')
local timer=os.startTimer(FRAME)
local drawCounter=0
while true do
  local event={os.pullEvent()}
  if event[1]=='rednet_message' and event[4]==PROTO then handle(event[2],event[3])
  elseif event[1]=='key' then adminKey(event[2]);drawAdmin()
  elseif event[1]=='timer' and event[2]==timer then
    timer=os.startTimer(FRAME);tick=tick+1;drawCounter=drawCounter+1
    if shutdownTicks>0 then shutdownTicks=shutdownTicks-1
      if shutdownTicks==0 then
        broadcast({type='SHUTDOWN',text=shutdownText});save('scores',scores)
        term.setBackgroundColor(colors.black);term.clear();print('Neon Courier server detenido.');break
      end
    end
    if round=='RUNNING' then
      update()
      if round=='RUNNING' and tick%2==0 then
        state.shutdown=shutdownTicks>0 and math.ceil(shutdownTicks*FRAME) or 0
        for id in pairs(C) do send(id,{type='STATE',state=state}) end
      end
      if state and state.countdown and state.countdown<=0 then state.notice='' end
    elseif round=='OVER' and state then
      state.overTicks=state.overTicks-1
      if state.overTicks<=0 then broadcast({type='RETURN_MENU'});C={};host=nil;state=nil;round='IDLE' end
    end
    if tick%90==0 then
      local lost={};for id,c in pairs(C) do if tick-c.last>140 then lost[#lost+1]=id end end
      for _,id in ipairs(lost) do endClient(id) end
    end
    if tick%260==0 then save('scores',scores) end
    if drawCounter>=9 then drawCounter=0;drawAdmin() end
  end
end
