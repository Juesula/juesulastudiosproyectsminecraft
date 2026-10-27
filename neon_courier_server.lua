-- CLASSIC DUNGEONS 1.5 | Servidor autoritativo con posiciones validadas
-- Solo el Core integrado, auto instalacion offline.
local LIB
 do
  local root=fs.getDir(shell.getRunningProgram())
  local dest=fs.combine(root,'classic_dungeons_runtime_1_5')
  local bundled={
    ['classic_dungeons_core.lua']=[=[
-- CLASSIC DUNGEONS 1.0 | WORLD STUDIOS | Logica pura y autoritativa
-- Sin term/peripheral/rednet. Movimiento compartido; combate y mundo en servidor.
local M={VERSION='1.5.0',PROTO='classicdungeons.v1',HOST='classic-dungeons'}
local floor,abs,min,max,sqrt,cos,sin,pi=math.floor,math.abs,math.min,math.max,math.sqrt,math.cos,math.sin,math.pi
local function clamp(v,a,b) return max(a,min(b,v)) end
local function dst(a,b) return sqrt((a.x-b.x)^2+(a.y-b.y)^2) end
local function rnd(a,b) return math.random(a,b) end
local function key(x,y) return x..':'..y end
local DIR={{1,0},{-1,0},{0,1},{0,-1}}
local MOBS={rat={hp=3,damage=5,speed=1.7,score=25},skeleton={hp=5,damage=8,speed=1.1,score=45},
  cultist={hp=4,damage=10,speed=1.1,score=55},brute={hp=12,damage=15,speed=.65,score=95},
  wraith={hp=6,damage=12,speed=1.5,score=75},boss={hp=45,damage=19,speed=.85,score=500}}
local THEMES={{name='CRIPTAS',wall='3'},{name='FORJA',wall='1'},{name='CATEDRAL',wall='2'}}
M.MOBS=MOBS
local function within(s,x,y) return x>=1 and y>=1 and x<=s.w and y<=s.h end
local function tile(s,x,y)
  x,y=floor(x)+1,floor(y)+1
  if not within(s,x,y) then return '1' end
  return s.grid[y][x]
end
-- Recrea una colision de mundo desde un FLOOR en el cliente, sin generar mapa.
function M.mapFromPacket(packet)
  local rows=packet and packet.map or {}
  local grid={}
  for y,line in ipairs(rows) do
    grid[y]={}
    for x=1,#line do grid[y][x]=line:sub(x,x) end
  end
  return {w=rows[1] and #rows[1] or 0,h=#rows,grid=grid}
end
function M.solid(s,x,y)
  local t=tile(s,x,y)
  return t~='.' and t~='X' and t~=' '
end
local function canMove(s,x,y,r)
  r=r or .19
  return not (M.solid(s,x-r,y-r) or M.solid(s,x+r,y-r) or M.solid(s,x-r,y+r) or M.solid(s,x+r,y+r))
end
function M.move(s,obj,dx,dy,r)
  local nx=obj.x+dx
  if canMove(s,nx,obj.y,r) then obj.x=nx end
  local ny=obj.y+dy
  if canMove(s,obj.x,ny,r) then obj.y=ny end
end
function M.visible(s,x,y,tx,ty)
  local dx,dy=tx-x,ty-y;local n=sqrt(dx*dx+dy*dy)
  if n<.001 then return true end
  local steps=math.ceil(n/.12)
  for i=1,steps-1 do
    local t=i/steps
    if M.solid(s,x+dx*t,y+dy*t) then return false end
  end
  return true
end
local function bfs(s,starts)
  local queue,head,distances={},1,{}
  for _,p in ipairs(starts) do
    local x,y=floor(p.x)+1,floor(p.y)+1
    local k=key(x,y)
    if within(s,x,y) and not distances[k] then
      queue[#queue+1]={x,y};distances[k]=0
    end
  end
  while head<=#queue do
    local a=queue[head];head=head+1
    for _,d in ipairs(DIR) do
      local x,y=a[1]+d[1],a[2]+d[2];local k=key(x,y)
      if within(s,x,y) and (s.grid[y][x]=='.' or s.grid[y][x]=='X') and distances[k]==nil then
        distances[k]=distances[key(a[1],a[2])]+1
        queue[#queue+1]={x,y}
      end
    end
  end
  return distances,queue
end
local function setNotice(s,msg,time)
  s.notice=tostring(msg or ''):sub(1,92);s.noticeTime=time or 2.7
end
M.notice=setNotice
local function newMob(s,kind,x,y,elite)
  local spec=MOBS[kind] or MOBS.rat
  s.seq=s.seq+1
  local hp=math.ceil(spec.hp*(1+(s.floor-1)*.16)*(elite and 1.65 or 1)*(s.diff=='HARD' and 1.35 or 1))
  local e={id=s.seq,kind=kind,x=x,y=y,hp=hp,maxhp=hp,cooldown=rnd(3,10)*.1,
    speed=spec.speed*(elite and 1.12 or 1),elite=elite or false,damage=spec.damage}
  s.enemies[#s.enemies+1]=e
  return e
end
local function randomWalkable(s,near,exclude)
  local candidates={}
  for y=2,s.h-1 do for x=2,s.w-1 do
    if s.grid[y][x]=='.' then
      local dx,dy=x-.5-(near and near.x or 2.5),y-.5-(near and near.y or 2.5)
      if dx*dx+dy*dy>=(exclude or 0)^2 then candidates[#candidates+1]={x=x-.5,y=y-.5} end
    end
  end end
  if #candidates==0 then return {x=2.5,y=2.5} end
  return candidates[rnd(1,#candidates)]
end
local function addLoot(s,x,y,kind)
  s.seq=s.seq+1;s.loot[#s.loot+1]={id=s.seq,x=x,y=y,kind=kind,claimed=false}
end
function M.generate(s)
  local W,H=27,27
  s.w,s.h=W,H;s.seq=0;s.enemies={};s.loot={};s.runes={};s.runeIndex=1;s.puzzleDone=false
  s.grid={};local theme=THEMES[(s.floor-1)%#THEMES+1];s.theme=theme.name
  for y=1,H do s.grid[y]={};for x=1,W do s.grid[y][x]=theme.wall end end
  local visited={[key(3,3)]=true};local stack={{3,3}};s.grid[3][3]='.'
  while #stack>0 do
    local c=stack[#stack];local options={}
    for _,d in ipairs(DIR) do
      local nx,ny=c[1]+d[1]*2,c[2]+d[2]*2
      if nx>=3 and nx<=W-2 and ny>=3 and ny<=H-2 and not visited[key(nx,ny)] then
        options[#options+1]={nx,ny,d[1],d[2]}
      end
    end
    if #options==0 then table.remove(stack)
    else
      local p=options[rnd(1,#options)];visited[key(p[1],p[2])]=true
      s.grid[c[2]+p[4]][c[1]+p[3]]='.'
      s.grid[p[2]][p[1]]='.'
      stack[#stack+1]={p[1],p[2]}
    end
  end
  -- Ciclos y pequenas camaras. Conecta siempre con el laberinto inicial.
  for _=1,52 do
    local x,y=rnd(3,W-2),rnd(3,H-2)
    if s.grid[y][x]~= '.' then
      if s.grid[y-1][x]=='.' and s.grid[y+1][x]=='.' or
         s.grid[y][x-1]=='.' and s.grid[y][x+1]=='.' then
        if rnd(1,100)<=65 then s.grid[y][x]='.' end
      end
    end
  end
  for _=1,5 do
    local x,y=rnd(4,W-5),rnd(4,H-5)
    for dy=-1,1 do for dx=-1,1 do s.grid[y+dy][x+dx]='.' end end
  end
  s.start={x=2.5,y=2.5}
  local distances,reachable=bfs(s,{s.start})
  local far={x=3,y=3,d=-1}
  for _,cell in ipairs(reachable) do
    local d=distances[key(cell[1],cell[2])] or 0
    if d>far.d then far={x=cell[1],y=cell[2],d=d} end
  end
  s.exit={x=far.x-.5,y=far.y-.5}
  s.grid[far.y][far.x]='X'
  -- Altares repartidos por distancias: son un rompecabezas exploratorio sencillo.
  local count=s.floor%3==0 and 3 or 2
  local spots={}
  for _,cell in ipairs(reachable) do
    local d=distances[key(cell[1],cell[2])] or 0
    if d>=9 and d<=far.d-4 then spots[#spots+1]={x=cell[1]-.5,y=cell[2]-.5,d=d} end
  end
  for i=1,count do
    local candidates={}
    for _,p in ipairs(spots) do
      local valid=true
      for _,q in ipairs(s.runes) do if dst(p,q)<5 then valid=false;break end end
      if valid then candidates[#candidates+1]=p end
    end
    if #candidates==0 then break end
    local target=far.d*(i/(count+1));table.sort(candidates,function(a,b) return abs(a.d-target)<abs(b.d-target) end)
    local pick=candidates[rnd(1,min(5,#candidates))]
    s.runes[#s.runes+1]={x=pick.x,y=pick.y,n=i}
  end
  s.runeOrder={};s.runeActivated={}
  for i=1,#s.runes do s.runeOrder[i]=i end
  for i=#s.runeOrder,2,-1 do
    local j=rnd(1,i);s.runeOrder[i],s.runeOrder[j]=s.runeOrder[j],s.runeOrder[i]
  end
  if #s.runes==0 then s.puzzleDone=true end
  s.bossAlive=s.floor%3==0
  local mobs=min(20,5+floor(s.floor*1.65))
  local kinds={'rat','rat','skeleton','cultist','wraith','brute'}
  for i=1,mobs do
    local loc=randomWalkable(s,s.start,4)
    local kind=kinds[rnd(1,min(#kinds,3+floor(s.floor/2)))]
    newMob(s,kind,loc.x,loc.y,(s.floor>=3 and rnd(1,9)==1))
  end
  if s.bossAlive then
    local loc=randomWalkable(s,s.start,9)
    newMob(s,'boss',loc.x,loc.y,true)
  end
  for i=1,7 do
    local loc=randomWalkable(s,s.start,3)
    addLoot(s,loc.x,loc.y,({'potion','coin','mana','chest','coin','potion','mana'})[i])
  end
  s.time=0;s.waveTimer=23;s.eventTimer=38;s.combatCounter=0;s.puzzlePenaltyCD=0
  s.pathDist=nil;s.pathTimer=0
  setNotice(s,'PISO '..s.floor..' | '..s.theme..' | SECUENCIA '..table.concat(s.runeOrder,'-'),6)
end
local function allPlayers(s)
  local out={};for _,p in pairs(s.players) do out[#out+1]=p end;return out
end
function M.addPlayer(s,id,user,class)
  local list=allPlayers(s)
  local p={id=tostring(id),user=user,class=class or 'GUERRERO',x=s.start.x+.15*(#list%2),y=s.start.y+.15*(floor(#list/2)%2),
    a=0,hp=100,maxhp=100,mana=8,maxmana=12,potions=2,score=0,kills=0,
    coins=0,combo=0,comboTime=0,damageBonus=0,armor=0,level=1,alive=true,respawn=0,
    invul=0,meleeCD=0,spellCD=0,keys={},relics=0,revives=0,shield=0}
  if p.class=='CAZADOR' then p.mana=12;p.maxmana=16
  elseif p.class=='MAGO' then p.mana=18;p.maxmana=20;p.hp=85;p.maxhp=85 end
  p.moveSeq=0 -- Ultima posicion validada por el servidor
  s.players[p.id]=p
  return p
end
function M.newRun(mode,diff,roster)
  local s={mode=mode or 'SOLO',diff=diff or 'NORMAL',players={},floor=1,seq=0,
    paused=false,over=false,notice='',noticeTime=0,elapsed=0,events=0,roundKills=0}
  M.generate(s)
  for _,entry in ipairs(roster or {}) do M.addPlayer(s,entry.id,entry.user,entry.class) end
  return s
end
local function award(p,points)
  if not p then return end
  p.score=p.score+floor(points*(1+min(1.6,p.combo*.05)))
end
local function dead(s,p,attacker)
  if p.hp>0 then return end
  p.hp=0;p.alive=false;p.respawn=s.mode=='EVENT' and 9 or 0
  p.keys={}
  setNotice(s,p.user..' HA CAIDO',3)
  if attacker and attacker.id~=p.id then award(attacker,150) end
end
local function hurt(s,p,damage,attacker)
  if not p.alive or p.invul>0 then return false end
  local dmg=max(1,floor(damage*(1-min(.45,p.armor*.08))))
  if p.shield>0 then p.shield=p.shield-1;dmg=max(1,floor(dmg*.25)) end
  p.hp=max(0,p.hp-dmg);p.invul=.55
  p.combo=0;p.comboTime=0
  if p.hp<=0 then dead(s,p,attacker) end
  return true
end
function M.attack(s,p,ranged)
  if not p or not p.alive or s.paused then return false,'fail' end
  local range=ranged and 6 or 1.55
  if ranged then
    if p.spellCD>0 or p.mana<2 then return false,'empty' end
    p.spellCD=p.class=='MAGO' and .55 or .85;p.mana=p.mana-2
  else
    if p.meleeCD>0 then return false,'fail' end
    p.meleeCD=p.class=='GUERRERO' and .33 or .48
  end
  local best,dbest=nil,range+.01
  local bestType='enemy'
  local function check(v,typ)
    if (typ~='player' or v.id~=p.id) and (typ~='player' or s.mode=='PVP') and
       (typ~='enemy' or v.hp>0) and (typ~='player' or v.alive) then
      local d=dst(p,v)
      if d<dbest and d>0.02 then
        local dx,dy=(v.x-p.x)/d,(v.y-p.y)/d
        local dot=cos(p.a)*dx+sin(p.a)*dy
        if dot>(ranged and .95 or .62) and M.visible(s,p.x,p.y,v.x,v.y) then
          best=v;dbest=d;bestType=typ
        end
      end
    end
  end
  for _,e in ipairs(s.enemies) do check(e,'enemy') end
  if s.mode=='PVP' then for _,other in pairs(s.players) do check(other,'player') end end
  if best then
    local base=(ranged and (p.class=='MAGO' and 5 or 3) or (p.class=='GUERRERO' and 4 or 2))+p.damageBonus
    if p.combo>=8 then base=base+1 end
    if bestType=='player' then hurt(s,best,base*3,p)
    else
      best.hp=best.hp-base;best.hurt=.22
      if best.hp<=0 then
        p.kills=p.kills+1;p.combo=p.combo+1;p.comboTime=5;s.roundKills=s.roundKills+1
        award(p,(MOBS[best.kind] or MOBS.rat).score*(best.elite and 2 or 1))
        p.mana=min(p.maxmana,p.mana+1);p.coins=p.coins+1
        if best.kind=='boss' then s.bossAlive=false;setNotice(s,'JEFE DERROTADO! PORTAL DESBLOQUEABLE',5) end
        if rnd(1,100)<=19 then addLoot(s,best.x,best.y,(rnd(1,2)==1) and 'potion' or 'mana') end
      end
    end
    return true,'hit'
  end
  return true,'attack'
end
local function runeNear(s,p)
  local nearest,d=nil,1.5
  for _,r in ipairs(s.runes) do
    local dd=dst(p,r)
    if dd<d then nearest=r;d=dd end
  end
  return nearest
end
function M.interact(s,p)
  if not p or not p.alive then return 'fail' end
  local r=runeNear(s,p)
  if r and not s.puzzleDone and s.runeActivated[r.n] then
    setNotice(s,'RUNA YA ACTIVADA. BUSCA LA '..(s.runeOrder[s.runeIndex] or '?'),2)
    return 'used'
  end
  if r and not s.puzzleDone then
    if r.n==s.runeOrder[s.runeIndex] then
      s.runeActivated[r.n]=true;s.runeIndex=s.runeIndex+1;award(p,90)
      if s.runeIndex>#s.runes then s.puzzleDone=true;setNotice(s,'SELLO ROTO! BUSCA LA SALIDA',5)
      else setNotice(s,'RUNA '..r.n..' ACTIVADA | SIGUIENTE '..s.runeOrder[s.runeIndex],3) end
      return 'rune'
    else
      s.runeIndex=1;s.runeActivated={};setNotice(s,'ORDEN INCORRECTO! EMBOSCADA',4)
      if s.puzzlePenaltyCD<=0 then
        s.puzzlePenaltyCD=7
        for i=1,math.min(3,math.max(0,32-#s.enemies)) do
          local at=randomWalkable(s,p,3);newMob(s,'wraith',at.x,at.y,false)
        end
      end
      return 'trap'
    end
  end
  for _,item in ipairs(s.loot) do
    if not item.claimed and item.kind=='chest' and dst(p,item)<1.4 then
      item.claimed=true;p.relics=p.relics+1;p.damageBonus=p.damageBonus+1
      p.maxhp=p.maxhp+8;p.hp=min(p.maxhp,p.hp+20)
      award(p,120);setNotice(s,p.user..' OBTIENE RELIQUIA (+DANO, +VIDA)',4)
      return 'chest'
    end
  end
  if dst(p,s.exit)<1.45 then
    if not s.puzzleDone then setNotice(s,'SECUENCIA DE RUNAS: '..table.concat(s.runeOrder,'-'),3);return 'locked' end
    if s.bossAlive then setNotice(s,'DERROTA AL GUARDIAN DEL PISO',3);return 'locked' end
    M.advance(s);return 'floor'
  end
  setNotice(s,'BUSCA ALTARES, COFRES O LA SALIDA',2)
  return 'fail'
end
function M.advance(s)
  s.floor=s.floor+1
  M.generate(s)
  for _,p in pairs(s.players) do
    p.x,p.y,p.a=s.start.x,s.start.y,0;p.keys={};p.moveSeq=0;p.invul=2
    if not p.alive and s.mode~='PVP' then p.alive=true;p.hp=max(35,floor(p.maxhp*.4)) end
    p.hp=min(p.maxhp,p.hp+18);p.mana=min(p.maxmana,p.mana+5)
    p.potions=min(7,p.potions+1);award(p,400+s.floor*45)
    -- Mejora aleatoria permanente por piso.
    local choice=rnd(1,3)
    if choice==1 then p.damageBonus=p.damageBonus+1
    elseif choice==2 then p.maxhp=p.maxhp+12;p.hp=p.hp+12
    else p.armor=p.armor+1 end
  end
end
function M.revive(s,p)
  if not p or not p.alive or s.mode=='PVP' then return false end
  for _,ally in pairs(s.players) do
    if ally~=p and not ally.alive and dst(ally,p)<1.5 and p.mana>=4 then
      p.mana=p.mana-4;ally.alive=true;ally.hp=max(35,floor(ally.maxhp*.35));ally.invul=2
      ally.x,ally.y=p.x,p.y;p.revives=p.revives+1;award(p,120)
      setNotice(s,p.user..' RESUCITO A '..ally.user,3);return true
    end
  end
  return false
end
function M.potion(s,p)
  if not p or not p.alive or p.potions<1 or p.hp>=p.maxhp then return false end
  p.potions=p.potions-1;p.hp=min(p.maxhp,p.hp+40);return true
end
local function movePlayer(s,p,dt)
  local k=p.keys or {}
  local turn=(k.d and 1 or 0)-(k.a and 1 or 0)
  p.a=(p.a+turn*dt*2.5)%(2*pi)
  local forward=(k.w and 1 or 0)-(k.s and 1 or 0)
  local lateral=(k.c and 1 or 0)-(k.q and 1 or 0)
  local norm=max(1,sqrt(forward*forward+lateral*lateral))
  local speed=(p.class=='CAZADOR' and 2.85 or 2.45)*dt/norm
  M.move(s,p,(cos(p.a)*forward-sin(p.a)*lateral)*speed,
      (sin(p.a)*forward+cos(p.a)*lateral)*speed,.21)
end
M.stepMovement=movePlayer  -- Identica logica y colisiones para la prediccion del cliente.
local function moveMob(s,e,target,dt)
  local dx,dy=target.x-e.x,target.y-e.y;local d=sqrt(dx*dx+dy*dy)
  if d<.75 then
    if e.cooldown<=0 then
      local damage=(e.damage or 5)*(s.diff=='HARD' and 1.22 or 1)
      hurt(s,target,damage,nil)
      e.cooldown=e.kind=='boss' and .65 or (e.kind=='rat' and .8 or 1.15)
    end
    return
  end
  if d<6 and M.visible(s,e.x,e.y,target.x,target.y) then
    if (e.kind=='cultist' or e.kind=='boss') and d>1.6 and d<5.2 then
      -- Ataque arcano a distancia; no se limita a perseguir al jugador.
      if e.cooldown<=0 then
        hurt(s,target,(e.kind=='boss' and 13 or 6)*(s.diff=='HARD' and 1.22 or 1),nil)
        e.cooldown=e.kind=='boss' and 1.5 or 2.3
        if e.kind=='boss' and rnd(1,3)==1 and #s.enemies<32 then
          local at=randomWalkable(s,target,3);newMob(s,'rat',at.x,at.y,false)
          setNotice(s,'EL GUARDIAN INVOCA UNA HORDA!',3)
        end
      end
    else M.move(s,e,dx/d*e.speed*dt,dy/d*e.speed*dt,.20) end
  else
    -- Navegacion sobre rejilla: elegir celda vecina mas cercana al jugador.
    local bx,by=floor(e.x),floor(e.y)
    local best,bestD=nil,1e20
    for _,dir in ipairs(DIR) do
      local tx,ty=bx+dir[1]+.5,by+dir[2]+.5
      if not M.solid(s,tx,ty) then
        local metric=(s.pathDist and s.pathDist[key(floor(tx)+1,floor(ty)+1)])
          or (abs(tx-target.x)+abs(ty-target.y)+1000)
        if metric<bestD then best,bestD={x=tx,y=ty},metric end
      end
    end
    if best then
      local vx,vy=best.x-e.x,best.y-e.y;local n=sqrt(vx*vx+vy*vy)
      if n>.06 then M.move(s,e,vx/n*e.speed*dt,vy/n*e.speed*dt,.20) end
    end
  end
end
function M.tick(s,dt)
  if s.paused or s.over then return end
  dt=clamp(dt or .12,.02,.2);s.elapsed=s.elapsed+dt;s.time=s.time+dt
  s.noticeTime=max(0,s.noticeTime-dt)
  s.puzzlePenaltyCD=max(0,(s.puzzlePenaltyCD or 0)-dt)
  local living={}
  for _,p in pairs(s.players) do
    p.invul=max(0,p.invul-dt);p.meleeCD=max(0,p.meleeCD-dt)
    p.spellCD=max(0,p.spellCD-dt)
    p.comboTime=max(0,p.comboTime-dt);if p.comboTime==0 then p.combo=0 end
    if p.alive then
      -- La posicion llega del cliente y la valida el servidor en mensajes MOVE.
      living[#living+1]=p
      p.mana=min(p.maxmana,p.mana+dt*.13)
      for _,item in ipairs(s.loot) do
        if not item.claimed and dst(p,item)<.47 and item.kind~='chest' then
          item.claimed=true
          if item.kind=='potion' then p.potions=min(8,p.potions+1)
          elseif item.kind=='mana' then p.mana=min(p.maxmana,p.mana+6)
          else p.coins=p.coins+8;award(p,70) end
        end
      end
    elseif s.mode=='EVENT' then
      p.respawn=p.respawn-dt
      if p.respawn<=0 then p.alive=true;p.hp=max(35,floor(p.maxhp*.5));p.invul=2
        p.x,p.y=s.start.x,s.start.y;living[#living+1]=p end
    end
  end
  s.pathTimer=(s.pathTimer or 0)-dt
  if s.pathTimer<=0 and #living>0 then
    s.pathDist=bfs(s,living);s.pathTimer=.6
  end
  for i=#s.enemies,1,-1 do
    local e=s.enemies[i]
    if e.hp<=0 then table.remove(s.enemies,i)
    else
      e.cooldown=max(0,e.cooldown-dt);e.hurt=max(0,(e.hurt or 0)-dt)
      local nearest,d=nil,1e9
      for _,p in ipairs(living) do
        local t=dst(p,e)
        if t<d then nearest,d=p,t end
      end
      if nearest and d<11 then moveMob(s,e,nearest,dt) end
    end
  end
  s.waveTimer=s.waveTimer-dt;s.eventTimer=s.eventTimer-dt
  if s.waveTimer<=0 and #living>0 then
    s.waveTimer=max(11,24-s.floor*.55)+rnd(0,7)
    local count=min(6,2+floor(s.floor/3))
    for i=1,math.min(count,math.max(0,32-#s.enemies)) do
      local where=randomWalkable(s,living[rnd(1,#living)],5)
      newMob(s,({'rat','skeleton','cultist','wraith','brute'})[rnd(1,min(5,2+floor(s.floor/2)))],where.x,where.y,rnd(1,7)==1)
    end
    setNotice(s,'OLEADA DE MONSTRUOS! ('..count..')',4)
  end
  if s.eventTimer<=0 then
    s.eventTimer=42+rnd(0,17)
    local roll=rnd(1,3)
    if roll==1 then
      for i=1,2 do local at=randomWalkable(s,s.start,3);addLoot(s,at.x,at.y,'chest') end
      setNotice(s,'EVENTO: TESOROS PERDIDOS!',5)
    elseif roll==2 then
      for _,p in pairs(s.players) do if p.alive then p.mana=min(p.maxmana,p.mana+5) end end
      setNotice(s,'EVENTO: LLUVIA ARCANA (+MANA)',5)
    else
      for i=1,math.min(3,math.max(0,32-#s.enemies)) do
        local at=randomWalkable(s,s.start,5);newMob(s,'brute',at.x,at.y,false)
      end
      setNotice(s,'EVENTO: ASALTO DE LOS BRUTOS',5)
    end
  end
  local alive=0;for _,p in pairs(s.players) do if p.alive then alive=alive+1 end end
  if alive==0 and s.mode~='EVENT' then s.over=true;s.reason='El grupo ha caido'
  elseif s.mode=='PVP' and #allPlayers(s)>1 and alive<=1 then s.over=true;s.reason='Ultimo superviviente' end
end
function M.floorPacket(s)
  local rows={}
  for y=1,s.h do rows[y]=table.concat(s.grid[y]) end
  return {type='FLOOR',floor=s.floor,map=rows,x=s.start.x,y=s.start.y,theme=s.theme,
    lights={{x=s.start.x,y=s.start.y,radius=7,power=2.7},{x=s.exit.x,y=s.exit.y,radius=5,power=2.4}},
    exit=s.exit,runes=s.runes,runeOrder=s.runeOrder}
end
function M.snapshot(s)
  local players={};for id,p in pairs(s.players) do
    players[id]={id=p.id,user=p.user,class=p.class,x=p.x,y=p.y,a=p.a,hp=p.hp,maxhp=p.maxhp,
      mana=floor(p.mana),maxmana=p.maxmana,potions=p.potions,alive=p.alive,respawn=p.respawn,
      score=p.score,kills=p.kills,coins=p.coins,combo=p.combo,relics=p.relics,revives=p.revives,moveSeq=p.moveSeq or 0,
      shield=p.shield,armor=p.armor,damageBonus=p.damageBonus}
  end
  local enemies={};for _,e in ipairs(s.enemies) do
    enemies[#enemies+1]={id=e.id,x=e.x,y=e.y,kind=e.kind,hp=e.hp,maxhp=e.maxhp,elite=e.elite,hurt=e.hurt}
  end
  local loot={};for _,o in ipairs(s.loot) do if not o.claimed then loot[#loot+1]={id=o.id,x=o.x,y=o.y,kind=o.kind} end end
  return {type='STATE',floor=s.floor,mode=s.mode,diff=s.diff,players=players,enemies=enemies,loot=loot,
    runes=s.runes,runeIndex=s.runeIndex,runeOrder=s.runeOrder,runeActivated=s.runeActivated,
    puzzleDone=s.puzzleDone,bossAlive=s.bossAlive,
    notice=s.noticeTime>0 and s.notice or '',wave=floor(max(0,s.waveTimer)),time=floor(s.elapsed),
    over=s.over,reason=s.reason or '',paused=s.paused,theme=s.theme,exit=s.exit}
end
return M

]=],
  }
  if fs.exists(dest) and not fs.isDir(dest) then
    error('Classic Dungeons: la ruta de bibliotecas existe y no es carpeta: '..dest,0)
  end
  if not fs.exists(dest) then fs.makeDir(dest) end
  for name,source in pairs(bundled) do
    local file=fs.combine(dest,name)
    local previous=nil
    if fs.exists(file) then
      if fs.isDir(file) then error('Classic Dungeons: conflicto con '..file,0) end
      local f=fs.open(file,'r')
      if f then previous=f.readAll();f.close() end
    end
    if previous~=source then
      local tmp=file..'.writing'
      if fs.exists(tmp) then fs.delete(tmp) end
      local h=fs.open(tmp,'w')
      if not h then error('No se pudo escribir '..tmp,0) end
      h.write(source);h.close()
      local check=fs.open(tmp,'r')
      if not check then error('No se pudo verificar '..tmp,0) end
      local good=check.readAll()==source;check.close()
      if not good then error('Escritura incompleta '..name,0) end
      if previous~=nil then
        local backup=file..'.backup'
        local i=1
        while fs.exists(backup) do i=i+1;backup=file..'.backup'..i end
        fs.copy(file,backup)
        fs.delete(file)
      end
      fs.move(tmp,file)
    end
  end
  LIB=dest
 end


-- CLASSIC DUNGEONS | Servidor autoritativo World Studios
-- Rednet + lobby + normal/PvP/Evento MMO + ranking + herramientas admin.
local ROOT=fs.getDir(shell.getRunningProgram())
local CORE=assert(loadfile(fs.combine(LIB,'classic_dungeons_core.lua')))()
local PROTO,HOST=CORE.PROTO,CORE.HOST
local FRAME=.12;local MAX_NORMAL,MAX_EVENT=4,8
local NET_VERSION=2 -- Cliente predice movimiento, servidor valida posiciones
local DATA=fs.combine(ROOT,'classic_server_data')
if not fs.exists(DATA) then fs.makeDir(DATA) end
local function readData(name,def)
  local path=fs.combine(DATA,name..'.dat')
  if not fs.exists(path) then return def end
  local h=fs.open(path,'r');if not h then return def end
  local v=h.readAll();h.close()
  local ok,t=pcall(textutils.unserialize,v)
  return ok and type(t)=='table' and t or def
end
local function saveData(name,t)
  local h=fs.open(fs.combine(DATA,name..'.dat'),'w')
  if h then h.write(textutils.serialize(t));h.close() end
end
local scores=readData('scores',{})
local config=readData('settings',{mode='NORMAL'})
local announcement=readData('announcement',{enabled=false,text=''})
local bossCfg=readData('boss',{name='EL CARCELERO',damage=19})
local opened=0
if not rednet or not peripheral then error('Se necesita CC:Tweaked y Rednet') end
for _,side in ipairs(peripheral.getNames()) do
  if peripheral.hasType(side,'modem') then
    if not rednet.isOpen(side) then rednet.open(side) end
    opened=opened+1
  end
end
if opened==0 then error('Conecta un modem al servidor Classic Dungeons') end
pcall(rednet.host,PROTO,HOST)
math.randomseed((os.epoch and os.epoch('utc') or math.floor(os.clock()*100000))%2147483647)
local clients,host,round,game,mode,diff={},nil,'IDLE',nil,'COOP','NORMAL'
local tick,shutTicks,acceptEvent=0,0,true
local info='Servidor listo. Esperando clientes.'
local function count()
  local n=0;for _ in pairs(clients) do n=n+1 end;return n
end
local function send(id,payload) pcall(rednet.send,id,payload,PROTO) end
local function all(msg) for id in pairs(clients) do send(id,msg) end end
local function say(id,text) send(id,{type='NOTICE',text=text}) end
local function broadcastFloor()
  if not game then return end
  for _,e in ipairs(game.enemies) do if e.kind=='boss' then e.damage=bossCfg.damage end end
  local packet=CORE.floorPacket(game);packet.bossName=bossCfg.name
  all(packet)
  all(CORE.snapshot(game))
end
local function savePlayer(p)
  local user=p and p.user
  if not user then return end
  local record=scores[user]
  if type(record)~='table' then record={best=tonumber(record) or 0,total=0,runs=0,kills=0,bestFloor=0} end
  record.best=math.max(record.best or 0,p.score or 0)
  record.total=(record.total or 0)+(p.score or 0)
  record.runs=(record.runs or 0)+1
  record.kills=(record.kills or 0)+(p.kills or 0)
  record.bestFloor=math.max(record.bestFloor or 0,game and game.floor or 1)
  scores[user]=record
end
local function clear()
  clients={};host=nil;game=nil;round='IDLE';mode='COOP';diff='NORMAL'
end
local function finish(reason)
  if not game or round~='RUNNING' then return end
  game.over=true;round='OVER';game.reason=reason or game.reason or 'Partida terminada'
  local entries={}
  for id,p in pairs(game.players) do
    savePlayer(p)
    entries[#entries+1]={user=p.user,score=p.score,kills=p.kills,floor=game.floor,alive=p.alive}
  end
  table.sort(entries,function(a,b) return a.score>b.score end)
  saveData('scores',scores)
  all({type='GAME_OVER',reason=game.reason,results=entries,floor=game.floor})
  game.endTimer=12
end
local function start()
  local entries={}
  for id,c in pairs(clients) do entries[#entries+1]={id=id,user=c.user,class=c.class} end
  mode=(config.mode=='EVENT' and 'EVENT') or mode
  game=CORE.newRun(mode,diff,entries)
  for _,client in pairs(clients) do client.moveCredit=.45;client.turnCredit=.42 end
  round='RUNNING';tick=0
  all({type='START',mode=mode,diff=diff})
  broadcastFloor()
end
local function disconnect(id)
  local c=clients[id]
  if not c then return end
  if game and game.players[tostring(id)] then
    savePlayer(game.players[tostring(id)]);game.players[tostring(id)]=nil;saveData('scores',scores)
  end
  clients[id]=nil
  if count()==0 then clear();return end
  if id==host and round=='LOBBY' then
    all({type='CANCEL',text='El anfitrion abandono la sala'});clear();return
  elseif id==host then
    for newId in pairs(clients) do host=newId;break end
    all({type='NOTICE',text='Nuevo anfitrion: '..clients[host].user})
  end
  if game and round=='RUNNING' then
    local living=0;for _,p in pairs(game.players) do if p.alive then living=living+1 end end
    if living==0 and mode~='EVENT' then finish('Sin aventureros') end
  end
end
local function accept(id)
  send(id,{type='ACCEPT',pid=tostring(id),host=host,round=round,mode=mode,
    players=count(),diff=diff,announcement=announcement,netVersion=NET_VERSION})
end
local function join(id,m)
  local name=tostring(m.user or ''):gsub('[^%w_%-]',''):sub(1,16)
  if name=='' then say(id,'Usuario invalido');return end
  local class=({GUERRERO=true,CAZADOR=true,MAGO=true})[m.class] and m.class or 'GUERRERO'
  for other,c in pairs(clients) do
    if other~=id and c.user:lower()==name:lower() then say(id,'Nombre en uso');return end
  end
  if clients[id] then accept(id);if game then local packet=CORE.floorPacket(game);packet.bossName=bossCfg.name;send(id,packet);send(id,CORE.snapshot(game)) end;return end
  local req=tostring(m.mode or '')
  if config.mode=='EVENT' then
    if req~='EVENT' or not acceptEvent or count()>=MAX_EVENT then say(id,'Evento cerrado/lleno');return end
    clients[id]={user=name,class=class,last=tick,keys={},moveCredit=.45,turnCredit=.42}
    if not host then host=id end
    accept(id)
    if round~='RUNNING' then mode='EVENT';diff='HARD';start()
    else CORE.addPlayer(game,id,name,class);local packet=CORE.floorPacket(game);packet.bossName=bossCfg.name;send(id,packet);all(CORE.snapshot(game)) end
    return
  end
  if round=='RUNNING' or round=='OVER' then say(id,'Partida en curso');return end
  local n=count()
  if n==0 and (req=='SINGLE' or req=='HOST') then
    clients[id]={user=name,class=class,last=tick,keys={},moveCredit=.45,turnCredit=.42}
    host=id;diff=m.diff=='HARD' and 'HARD' or 'NORMAL'
    mode=m.diff=='PVP' and 'PVP' or (req=='SINGLE' and 'SOLO' or 'COOP')
    if mode=='PVP' then diff='HARD' end
    round='LOBBY';accept(id)
    if req=='SINGLE' then start() end
  elseif req=='JOIN' and n>=1 and n<MAX_NORMAL and round=='LOBBY' then
    clients[id]={user=name,class=class,last=tick,keys={},moveCredit=.45,turnCredit=.42}
    accept(id);send(host,{type='PLAYER_JOINED',user=name,players=count()})
  else say(id,'No hay sala disponible. Crea una primero.') end
end
local validKeys={w=true,s=true,a=true,d=true,q=true,c=true}
local function validNum(v)
  return type(v)=='number' and v==v and v>-10000 and v<10000
end
local function acceptMove(id,msg,p)
  local client=clients[id]
  if not client or not game or game.paused or not p.alive then return end
  if msg.floor~=game.floor then return end
  local seq=msg.seq
  if type(seq)~='number' or seq%1~=0 or seq<= (p.moveSeq or 0) or seq>100000000 then return end
  if not(validNum(msg.x) and validNum(msg.y) and validNum(msg.a)) then return end
  local dx,dy=msg.x-p.x,msg.y-p.y
  local distance=math.sqrt(dx*dx+dy*dy)
  local allowance=(client.moveCredit or .40)+.025
  -- Freno contra teleportaciones, velocidad excesiva y atravesar muros.
  local fraction=distance>0 and math.min(1,allowance/distance) or 1
  dx=dx*fraction;dy=dy*fraction
  local steps=math.max(1,math.ceil(math.sqrt(dx*dx+dy*dy)/.09))
  local startX,startY=p.x,p.y
  for _=1,steps do CORE.move(game,p,dx/steps,dy/steps,.21) end
  local moved=math.sqrt((p.x-startX)^2+(p.y-startY)^2)
  client.moveCredit=math.max(0,(client.moveCredit or .40)-moved)
  local rot=(msg.a-p.a+math.pi)%(math.pi*2)-math.pi
  local turnLimit=(client.turnCredit or .42)+.035
  local usedAngle=math.max(-turnLimit,math.min(turnLimit,rot))
  p.a=(p.a+usedAngle)%(math.pi*2)
  client.turnCredit=math.max(0,(client.turnCredit or .42)-math.abs(usedAngle))
  p.moveSeq=seq -- Se refleja en STATE para reconciliar sin lag visual.
end
local function handle(id,m)
  if type(m)~='table' or type(m.type)~='string' then return end
  if m.type=='DISCOVER' then
    send(id,{type='INFO',mode=config.mode,round=round,players=count(),announcement=announcement,open=acceptEvent,netVersion=NET_VERSION})
    return
  elseif m.type=='REQ_LEADERBOARD' then send(id,{type='LEADERBOARD',scores=scores});return
  elseif m.type=='JOIN' then join(id,m);return end
  if not clients[id] then return end
  clients[id].last=tick
  if m.type=='PING' then return
  elseif m.type=='LEAVE' then disconnect(id);return
  elseif m.type=='START' and id==host and round=='LOBBY' then
    if mode=='PVP' and count()<2 then say(id,'PvP requiere al menos 2 jugadores')
    else start() end
    return
  elseif m.type=='PAUSE' and id==host and round=='RUNNING' and config.mode=='NORMAL' then
    game.paused=not game.paused;all({type='PAUSE',paused=game.paused});return
  end
  if round~='RUNNING' or not game or not game.players[tostring(id)] then return end
  local p=game.players[tostring(id)]
  if m.type=='MOVE' then
    acceptMove(id,m,p)
  elseif m.type=='KEY' and validKeys[m.key] and type(m.down)=='boolean' then
    p.keys[m.key]=m.down
  elseif m.type=='ACTION' then
    if tick-(clients[id].lastAction or -100)<1 then return end
    clients[id].lastAction=tick
    local a=m.action
    if a=='MELEE' or a=='SPELL' then
      local _,snd=CORE.attack(game,p,a=='SPELL');send(id,{type='SFX',sound=snd})
    elseif a=='INTERACT' then
      local prev=game.floor;local sound=CORE.interact(game,p);send(id,{type='SFX',sound=sound})
      if game.floor~=prev then broadcastFloor() end
    elseif a=='POTION' then
      if CORE.potion(game,p) then send(id,{type='SFX',sound='heal'}) end
    elseif a=='REVIVE' then
      if CORE.revive(game,p) then all({type='SFX',sound='revive'}) end
    end
    all(CORE.snapshot(game))
  end
end
local function banner(lines)
  if type(term.setGraphicsMode)=='function' then pcall(term.setGraphicsMode,false) end
  term.setBackgroundColor(colors.black);term.setTextColor(colors.cyan);term.clear();term.setCursorPos(1,1)
  print('CLASSIC DUNGEONS / SERVIDOR 1.0')
  term.setTextColor(colors.white)
  for _,line in ipairs(lines) do print(line) end
end
local function ask(prompt)
  banner({prompt,'Escribe y pulsa Enter:'});return read() or ''
end
local function adminUI()
  local n=0;for _ in pairs(scores) do n=n+1 end
  banner({'', 'MODO '..config.mode..' | SALA '..round..' | '..mode,
    'Jugadores '..count()..'/'..(config.mode=='EVENT' and MAX_EVENT or MAX_NORMAL),
    'Ranking: '..n..' cuentas | Modems '..opened,
    game and ('Piso '..game.floor..' | '..game.theme..' | Enemigos '..#game.enemies) or 'Esperando jugadores...',
    '', '[1] NORMAL  [2] EVENTO MMO',
    '[A] Anuncio [B] Boss [N] Oleada [H] Curar',
    '[X] Acceso evento [P] Pausar/reanudar',
    '[Y] Cierre programado [U] Cancelar cierre',
    '', 'EVENTO '..(acceptEvent and 'ABIERTO' or 'CERRADO'),
    'Anuncio '..(announcement.enabled and announcement.text or '-'),
    'Cierre '..(shutTicks>0 and tostring(math.ceil(shutTicks*FRAME))..' s' or '-'),'',info})
end
local function adminKey(k)
  if k==keys.one and count()==0 then config.mode='NORMAL';saveData('settings',config);info='Modo normal'
  elseif k==keys.two and count()==0 then config.mode='EVENT';saveData('settings',config);info='Modo evento'
  elseif k==keys.a then
    local txt=ask('Nuevo anuncio (vacio para desactivar):')
    announcement={enabled=txt~='',text=txt:sub(1,90)};saveData('announcement',announcement)
    all({type='ANNOUNCEMENT',data=announcement});info='Anuncio actualizado'
  elseif k==keys.b then
    local name=ask('Nombre nuevo del guardian:'):sub(1,24)
    local dam=tonumber(ask('Dano guardian (5 a 50):'))
    if name~='' then bossCfg.name=name end
    if dam then bossCfg.damage=math.max(5,math.min(50,floor(dam))) end
    saveData('boss',bossCfg)
    if game then
      for _,e in ipairs(game.enemies) do if e.kind=='boss' then e.damage=bossCfg.damage end end
      CORE.notice(game,bossCfg.name..' DESPIERTA!',5)
    end
    info='Guardian actualizado'
  elseif k==keys.n and game and round=='RUNNING' then
    for i=1,4 do
      local p=game.start;local x,y=math.random(3,game.w-3)+.5,math.random(3,game.h-3)+.5
      if not CORE.solid(game,x,y) then
        game.seq=game.seq+1
        game.enemies[#game.enemies+1]={id=game.seq,kind='skeleton',x=x,y=y,hp=7,maxhp=7,
          cooldown=0,speed=1.25,elite=false,damage=10}
      end
    end
    CORE.notice(game,'OLEADA EXTRA DEL ADMINISTRADOR!',4)
    info='Oleada lanzada'
  elseif k==keys.h and game and round=='RUNNING' then
    for _,p in pairs(game.players) do if p.alive then p.hp=p.maxhp;p.mana=p.maxmana;p.shield=1 end end
    CORE.notice(game,'BENDICION DEL ADMINISTRADOR',4);info='Grupo curado'
  elseif k==keys.x then acceptEvent=not acceptEvent;info='Evento abierto '..tostring(acceptEvent)
  elseif k==keys.p and game and round=='RUNNING' then
    game.paused=not game.paused;all({type='PAUSE',paused=game.paused});info='Pausa '..tostring(game.paused)
  elseif k==keys.y then
    local seconds=math.max(0,tonumber(ask('Cerrar servidor en N segundos (0 cancela):')) or 0)
    shutTicks=math.ceil(seconds/FRAME);info='Cierre en '..seconds..' segundos'
  elseif k==keys.u then shutTicks=0;info='Cierre cancelado' end
  adminUI()
end
local timer=os.startTimer(FRAME)
local redraw=0
adminUI()
while true do
  local event,a,b,c=os.pullEventRaw()
  if event=='rednet_message' and c==PROTO then handle(a,b)
  elseif event=='key' then adminKey(a)
  elseif event=='timer' and a==timer then
    timer=os.startTimer(FRAME);tick=tick+1;redraw=redraw+1
    -- Credito de velocidad calculado en servidor, no confiamos en dt enviado.
    for _,client in pairs(clients) do
      client.moveCredit=math.min(.78,(client.moveCredit or .45)+2.85*FRAME)
      client.turnCredit=math.min(.72,(client.turnCredit or .42)+2.5*FRAME)
    end
    if shutTicks>0 then
      shutTicks=shutTicks-1
      if shutTicks<=0 then
        all({type='SHUTDOWN',text='Servidor cerrado por el administrador'})
        if game then for _,p in pairs(game.players) do savePlayer(p) end end
        saveData('scores',scores);break
      end
    end
    if round=='RUNNING' and game then
      local wasFloor=game.floor
      CORE.tick(game,FRAME)
      if game.floor~=wasFloor then broadcastFloor() end
      if game.over then finish(game.reason) end
      if tick%2==0 and round=='RUNNING' then all(CORE.snapshot(game)) end
    elseif round=='OVER' and game then
      game.endTimer=game.endTimer-FRAME
      if game.endTimer<=0 then all({type='RETURN_MENU'});clear() end
    end
    if tick%45==0 then
      local gone={};for id,c in pairs(clients) do if tick-c.last>200 then gone[#gone+1]=id end end
      for _,id in ipairs(gone) do disconnect(id) end
    end
    if tick%240==0 then saveData('scores',scores) end
    if redraw>=9 then redraw=0;adminUI() end
  elseif event=='terminate' then
    all({type='SHUTDOWN',text='Servidor detenido'})
    if game then for _,p in pairs(game.players) do savePlayer(p) end end
    saveData('scores',scores);break
  end
end
term.setBackgroundColor(colors.black);term.clear();term.setCursorPos(1,1)
print('CLASSIC DUNGEONS: Servidor detenido.')
