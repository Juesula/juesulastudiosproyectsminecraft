-- CLASSIC DUNGEONS 1.1 | Edicion autoinstalable OFFLINE
-- Bibliotecas incluidas en el propio archivo: no necesita HTTP ni pastebin.
-- Solo escribe en la carpeta classic_dungeons_runtime_1_1/ junto al ejecutable.
local LIB
 do
  local root=fs.getDir(shell.getRunningProgram())
  local dest=fs.combine(root, 'classic_dungeons_runtime_1_1')
  local bundled={
    ['classic_dungeons_core.lua']=[=[
-- CLASSIC DUNGEONS 1.0 | WORLD STUDIOS | Logica pura y autoritativa
-- Sin term/peripheral/rednet: toda simulacion ocurre en el servidor.
local M={VERSION='1.0.0',PROTO='classicdungeons.v1',HOST='classic-dungeons'}
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
    p.x,p.y,p.a=s.start.x,s.start.y,0;p.keys={};p.invul=2
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
      movePlayer(s,p,dt);living[#living+1]=p
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
      score=p.score,kills=p.kills,coins=p.coins,combo=p.combo,relics=p.relics,revives=p.revives,
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
    ['classic_dungeons_renderer.lua']=[=[
-- CLASSIC DUNGEONS | Adaptador de escenas para WorldTor 3 (CC: Graphics)
-- Solo renderiza; nunca simula dano, IA ni botin (todo en servidor).
local R={}
local max,floor=math.max,math.floor
local function texture(fn)
  local t={}
  for y=0,15 do local r={};for x=0,15 do r[x+1]=fn(x,y) end;t[y+1]=r end
  return t
end
local function abs(v) return math.abs(v) end
local function spriteBody(x,y,main,edge,eyes)
  if y<2 or y>14 then return nil end
  if (x-7)^2/37+(y-7)^2/49>1 then return nil end
  if y>=6 and y<=8 and (x==5 or x==10) then return eyes end
  if x<3 or x>12 or y==2 or y==14 then return edge end
  if y>=11 and (x+y)%5==0 then return edge end
  return main
end
local TEXTURES={
  G=texture(function(x,y) return spriteBody(x,y,'#5BC17D','#235843','#F6EF99') end), -- rata
  S=texture(function(x,y)
    if y<2 or y>14 or x<2 or x>13 then return nil end
    if y<9 then
      if (x-7)^2+(y-5)^2>26 then return nil end
      if y>=5 and y<=6 and (x==5 or x==10) then return '#101923' end
      return '#E9DFCB'
    end
    if x==7 or x==8 or y==11 then return '#E9DFCB' end
    if (x==5 or x==10) and y>=10 and y<=13 then return '#C9C1B3' end
    return nil
  end),
  V=texture(function(x,y) return spriteBody(x,y,'#9E509F','#462353','#F5DF72') end), -- sectario
  W=texture(function(x,y)
    if y<2 or y>14 then return nil end
    local xx=x-7.5;local yy=y-7.5
    if xx*xx/35+yy*yy/52>1 then return nil end
    if y>=5 and y<=7 and (x==5 or x==10) then return '#D9F8F8' end
    return (x+y)%4==0 and '#6E87E6' or '#5164AC'
  end),
  B=texture(function(x,y)
    if x<1 or x>14 or y<1 or y>14 then return nil end
    if y<3 and (x<4 or x>11) then return nil end
    if y>=5 and y<=7 and (x==5 or x==10) then return '#FFE371' end
    return (x%4==0 and '#75432F') or '#AF6240'
  end),
  Z=texture(function(x,y)
    if y<1 or y>15 then return nil end
    if x<2 or x>13 then return nil end
    if (x==3 or x==12) and y<5 then return '#D6A354' end
    if y>=6 and y<=8 and (x==5 or x==10) then return '#EAF3A7' end
    return (x+y)%5==0 and '#8B2551' or '#C43E63'
  end),
  R=texture(function(x,y)
    local dx,dy=x-7.5,y-7.5
    if dx*dx+dy*dy>58 or dx*dx+dy*dy<16 then return nil end
    return (x+y)%4==0 and '#FCE9A5' or '#43CCEA'
  end),
  K=texture(function(x,y)
    if x<2 or x>13 or y<6 or y>13 then return nil end
    if y==6 or y==9 or y==13 or x==2 or x==13 then return '#D7B575' end
    if x==7 or x==8 then return '#FFF6BE' end
    return '#80512E'
  end),
  P=texture(function(x,y)
    if x<4 or x>11 or y<3 or y>13 then return nil end
    if y<7 then return '#EAC8AF' end
    if y==7 or y==8 then return '#FBE4A9' end
    return '#B52F47'
  end),
  N=texture(function(x,y)
    if x<4 or x>11 or y<3 or y>13 then return nil end
    return y<8 and '#9FF9E6' or '#226F9A'
  end),
  T=texture(function(x,y)
    if y<4 or y>13 or x<3 or x>12 then return nil end
    return (x+y)%4==0 and '#FFDD81' or '#D6A236'
  end),
  A=texture(function(x,y)
    if y<1 or y>14 or x<3 or x>12 then return nil end
    if y>=5 and y<=7 and (x==5 or x==10) then return '#FCF9C3' end
    return '#45A6CA'
  end),
}
local MOB_TEX={rat='G',skeleton='S',cultist='V',wraith='W',brute='B',boss='Z'}
local LOOT_TEX={potion='P',mana='N',coin='T',chest='K'}
local function safeTxt(g,x,y,msg,col)
  if x<1 or y<1 or x>g.w or y>g.h then return end
  local n=math.max(0,math.floor((g.w-x)/5.9))
  if n<1 then return end
  g:text(x,y,tostring(msg or ''):sub(1,n),col or '#ECF0F4',1,true)
end
function R.open(root,scale)
  local WT=assert(loadfile(fs.combine(root,'worldtor3.lua')))()
  local gfx,err=WT.new({backend='graphics',mode=2,scale=scale or 3,background='#11151D'})
  if not gfx then return nil,err end
  local self={WT=WT,gfx=gfx,world=nil,floor=nil,snapshot=nil,myId=nil,
    quality=2,autotune=true,scale=scale or 3,mini=false,frame=0,showFPS=0,
    camera=nil,sprites={},swing=0}
  function self:setFloor(data)
    if type(data)~='table' or type(data.map)~='table' then return false end
    local level={map=data.map,x=data.x or 2.5,y=data.y or 2.5,angle=0,
      far=16,lights=data.lights or {}}
    local w=WT.new3D(self.gfx,level)
    for k,v in pairs(TEXTURES) do w.textures[k]=v end
    w:prepareTextures()
    w.quality=self.quality
    w:setAutotune(self.autotune)
    w.minimap=self.mini
    w.beforeFlip=function(world,fps) self:overlay(world,fps) end
    self.world=w;self.floor=data.floor;self.frame=0;self.snapshot=nil
    self.camera=nil;self.sprites={}
    return true
  end
  function self:setState(snapshot,id)
    if type(snapshot)~='table' then return end
    self.snapshot=snapshot;self.myId=tostring(id)
    if not self.world or self.floor~=snapshot.floor then return end
    local me=snapshot.players and snapshot.players[self.myId]
    if me then
      self.targetCamera={x=me.x,y=me.y,a=me.a}
      if not self.camera then self.camera={x=me.x,y=me.y,a=me.a} end
      if self.world.player.hp>me.hp then self.world.hitFlash=.24 end
      self.world.player.hp=me.hp;self.world.player.ammo=me.mana
      self.world.player.kills=me.kills or 0
      self.world.lost=false
      self.world.won=false
    end
    local entities={}
    local liveSprites={}
    local function insertSprite(entity,id)
      local k=tostring(id)
      local old=self.sprites[k]
      if old then entity.x=old.x;entity.y=old.y end
      entity.tx=entity.targetX or entity.x
      entity.ty=entity.targetY or entity.y
      entity.targetX=nil;entity.targetY=nil
      entities[#entities+1]=entity;liveSprites[k]=entity
    end
    for _,e in ipairs(snapshot.enemies or {}) do
      insertSprite({kind='enemy',texture=MOB_TEX[e.kind] or 'M',x=e.x,y=e.y,
        targetX=e.x,targetY=e.y,hp=e.hp,hurt=e.hurt or 0,elite=e.elite,kindName=e.kind},
        'enemy'..e.id)
    end
    for _,item in ipairs(snapshot.loot or {}) do
      insertSprite({kind='item',texture=LOOT_TEX[item.kind] or 'T',x=item.x,y=item.y,
        targetX=item.x,targetY=item.y,hp=1},'loot'..item.id)
    end
    if snapshot.runes and not snapshot.puzzleDone then
      for _,r in ipairs(snapshot.runes) do
        if not (snapshot.runeActivated or {})[r.n] then
          insertSprite({kind='rune',texture='R',x=r.x,y=r.y,targetX=r.x,targetY=r.y,hp=1},'rune'..r.n)
        end
      end
    end
    for pid,p in pairs(snapshot.players or {}) do
      if tostring(pid)~=self.myId and p.alive then
        insertSprite({kind='ally',texture='A',x=p.x,y=p.y,targetX=p.x,targetY=p.y,hp=1},'ally'..pid)
      end
    end
    self.world.entities=entities
    self.sprites=liveSprites
  end
  function self:overlay(world,fps)
    local g=self.gfx;local s=self.snapshot
    if not s then return end
    local p=s.players and s.players[self.myId]
    if not p then return end
    local w,h=g.w,g.h
    g:fill(1,1,w,11,'#101720',true)
    safeTxt(g,3,2,'CLASSIC DUNGEONS  |  PISO '..s.floor..'  '..(s.theme or ''),'#FADEA9')
    safeTxt(g,3,7,('HP %d/%d  MANA %d/%d  POC %d  K %d'):format(p.hp,p.maxhp,p.mana,p.maxmana,p.potions,p.kills),'#BDE7C3')
    local progress=s.puzzleDone and 'RUNAS OK' or
      ('RUNAS '..(s.runeIndex or 1)..'/'..#(s.runes or {})..'  '..table.concat(s.runeOrder or {},'-'))
    local floorText=progress..(s.bossAlive and ' | JEFE VIVO' or '')
    g:fill(1,h-15,w,15,'#101720',true)
    safeTxt(g,3,h-13,('PTS %d  x%d  REL %d'):format(p.score or 0,p.combo or 0,p.relics or 0),'#FCE5A6')
    safeTxt(g,3,h-8,floorText,'#8EDDEE')
    if w>=95 then safeTxt(g,3,h-3,'ESP GOLPE | F HECHIZO | E USAR | H POCION | R RESCATE','#A3AEBB') end
    safeTxt(g,max(2,w-27),3,'FPS '..floor(fps or 0)..' Q'..world.quality,'#ACF3D5')
    if s.runes and not s.puzzleDone then
      for _,r in ipairs(s.runes) do
        local dd=math.sqrt((p.x-r.x)^2+(p.y-r.y)^2)
        if dd<1.65 then
          safeTxt(g,3,24,('ALTAR %d  [E] ACTIVAR  ORDEN: %d'):format(r.n,(s.runeOrder or {})[s.runeIndex or 1] or 0),'#F6E89F')
          break
        end
      end
    end
    if s.exit and math.sqrt((p.x-s.exit.x)^2+(p.y-s.exit.y)^2)<1.5 then
      safeTxt(g,3,33,'PORTAL [E] - '..(s.puzzleDone and not s.bossAlive and 'ABIERTO' or 'SELLADO'),'#78E6D0')
    end
    if s.notice and s.notice~='' then
      g:fill(1,13,w,9,'#3E273B',true)
      safeTxt(g,3,15,s.notice,'#FFF0BB')
    end
    if self.swing>0 then
      local mx=math.floor(w/2)
      g:line(mx-12,math.floor(h*.60),mx+9,math.floor(h*.38),'#F7E5BB',true)
      g:line(mx-8,math.floor(h*.61),mx+12,math.floor(h*.40),'#73C8E0',true)
    end
    if not p.alive then
      g:fill(2,math.floor(h*.34),w-4,25,'#331927',true)
      g:center(math.floor(h*.34)+5,'HAS CAIDO','#FFC5B5',1)
      g:center(math.floor(h*.34)+13,s.mode=='EVENT' and 'REAPARECERAS PRONTO' or 'ESPERA RESCATE','#F4E2B0',1)
    end
    if s.paused then g:center(math.floor(h*.27),'PARTIDA PAUSADA','#FFE9AC',1) end
    -- Minimap: se reusa el motor base y solo se dibuja al activarlo.
  end
  function self:render(fps)
    if not self.world then return true end
    self.world.age=self.world.age+.16
    self.world.messageTime=0
    self.world.flash=math.max(0,(self.world.flash or 0)-.16)
    self.swing=math.max(0,(self.swing or 0)-.16)
    self.world.hitFlash=math.max(0,(self.world.hitFlash or 0)-.16)
    if self.targetCamera and self.camera then
      local c,t=self.camera,self.targetCamera
      c.x=c.x+(t.x-c.x)*.7;c.y=c.y+(t.y-c.y)*.7
      local angle=(t.a-c.a+math.pi)%(math.pi*2)-math.pi
      c.a=(c.a+angle*.7)%(math.pi*2)
      self.world.player.x=c.x;self.world.player.y=c.y;self.world.player.a=c.a
    end
    for _,e in ipairs(self.world.entities or {}) do
      if e.tx then e.x=e.x+(e.tx-e.x)*.68;e.y=e.y+(e.ty-e.y)*.68 end
    end
    return self.world:render(fps or 0)
  end
  function self:effect(sound)
    if sound=='hit' or sound=='attack' then self.swing=.32 end
    if sound=='rune' or sound=='chest' then self.world.flash=.20 end
  end
  function self:qualityLevel(q)
    self.quality=math.max(1,math.min(3,q or 2))
    if self.world then self.world:qualityLevel(self.quality);self.world:setAutotune(false) end
    self.autotune=false
  end
  function self:toggleAuto()
    self.autotune=not self.autotune
    if self.world then self.world:setAutotune(self.autotune) end
  end
  function self:toggleMap()
    self.mini=not self.mini
    if self.world then self.world.minimap=self.mini end
  end
  function self:resize()
    if self.gfx then self.gfx:resize() end
  end
  function self:close()
    if self.gfx then pcall(function() self.gfx:close() end);self.gfx=nil end
  end
  return self
end
return R
]=],
    ['worldtor_engine.lua']=[=[
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
-- ================================================================
-- WorldTor 2.1 | CC: Graphics renderer and scene engine
-- Compatibilidad: WT.new(term.current()) sigue siendo WorldTor v1.
-- WT.new({ backend='auto'|'graphics'|'terminal', mode=2, scale=3 })
-- CC: Graphics uses term.*; no GPU peripheral is required.
-- ================================================================
WT.version = '3.0.0'
WT.graphicsProvider = 'CC: Graphics (CraftOS-PC graphics API)'
local oldNew = WT.new
local floor,abs,min,max = math.floor,math.abs,math.min,math.max
local unpackValues = table.unpack or unpack
local paletteBits={colors.white,colors.orange,colors.magenta,colors.lightBlue,
    colors.yellow,colors.lime,colors.pink,colors.gray,colors.lightGray,
    colors.cyan,colors.purple,colors.blue,colors.brown,colors.green,
    colors.red,colors.black}
local paletteRGB={0xf0f0f0,0xf2b233,0xe57fd8,0x99b2f2,0xdede6c,0x7fcc19,
    0xf2b2cc,0x4c4c4c,0x999999,0x4c99b2,0xb266e5,0x3366cc,
    0x7f664c,0x57a64e,0xcc4c4c,0x111111}
local bitIndex={}
for i,v in ipairs(paletteBits) do bitIndex[v]=i-1 end
local nameColors={white=0,orange=1,magenta=2,lightblue=3,yellow=4,
    lime=5,pink=6,gray=7,grey=7,lightgray=8,cyan=9,purple=10,
    blue=11,brown=12,green=13,red=14,black=15}
function WT.rgb(r,g,b)
    return string.format('#%02X%02X%02X',max(0,min(255,floor(r or 0))),
        max(0,min(255,floor(g or 0))),max(0,min(255,floor(b or 0))))
end
local function rgbParts(n)
    return floor(n/65536)%256,floor(n/256)%256,n%256
end
local function colorIndex(c, mode)
    if c==nil then return 15 end
    local rgb
    if type(c)=='string' then
        local s=c:lower()
        if nameColors[s] then return nameColors[s] end
        if s:sub(1,1)=='#' then rgb=tonumber(s:sub(2),16) end
        if not rgb then return 15 end
    elseif type(c)=='number' then
        if bitIndex[c] then return bitIndex[c] end
        if c>=0 and c<=255 and floor(c)==c then
            if c==0 then return 15 end
            return mode==2 and c or 15
        end
        if c>255 then rgb=c end
    end
    if not rgb then return 15 end
    local r,g,b=rgbParts(rgb)
    if mode==2 then
        return 16+floor((r/255)*5+.5)*36+floor((g/255)*5+.5)*6+floor((b/255)*5+.5)
    end
    local best,dist=15,math.huge
    for i,cval in ipairs(paletteRGB) do
        local pr,pg,pb=rgbParts(cval)
        local d=(r-pr)^2+(g-pg)^2+(b-pb)^2
        if d<dist then best=i-1;dist=d end
    end
    return best
end
WT.colorIndex=colorIndex
function WT.aabb(a,b)
    return a.x < b.x+(b.w or 1) and a.x+(a.w or 1)>b.x and
        a.y < b.y+(b.h or 1) and a.y+(a.h or 1)>b.y
end
function WT.lerp(a,b,t) return a+(b-a)*min(1,max(0,t)) end

-- Font bitmap compacto (letras, numeros y signos) a 3x5 px. No requiere term.write.
local FONT={
 A={'010','101','111','101','101'},B={'110','101','110','101','110'},
 C={'011','100','100','100','011'},D={'110','101','101','101','110'},
 E={'111','100','110','100','111'},F={'111','100','110','100','100'},
 G={'011','100','101','101','011'},H={'101','101','111','101','101'},
 I={'111','010','010','010','111'},J={'001','001','001','101','010'},
 K={'101','101','110','101','101'},L={'100','100','100','100','111'},
 M={'101','111','111','101','101'},N={'101','111','111','111','101'},
 O={'010','101','101','101','010'},P={'110','101','110','100','100'},
 Q={'010','101','101','111','011'},R={'110','101','110','101','101'},
 S={'011','100','010','001','110'},T={'111','010','010','010','010'},
 U={'101','101','101','101','111'},V={'101','101','101','101','010'},
 W={'101','101','111','111','101'},X={'101','101','010','101','101'},
 Y={'101','101','010','010','010'},Z={'111','001','010','100','111'},
 ['0']={'111','101','101','101','111'},['1']={'010','110','010','010','111'},
 ['2']={'110','001','111','100','111'},['3']={'110','001','011','001','110'},
 ['4']={'101','101','111','001','001'},['5']={'111','100','110','001','110'},
 ['6']={'011','100','110','101','010'},['7']={'111','001','010','010','010'},
 ['8']={'010','101','010','101','010'},['9']={'010','101','011','001','110'},
 [' ']={'000','000','000','000','000'},['.']={'000','000','000','000','010'},
 [':']={'000','010','000','010','000'},['-']={'000','000','111','000','000'},
 ['/']={'001','001','010','100','100'},['!']={'010','010','010','000','010'},
 ['?']={'110','001','010','000','010'},['+']={'000','010','111','010','000'},
 ['=']={'000','111','000','111','000'},['(']={'001','010','010','010','001'},
 [')']={'100','010','010','010','100'},['_']={'000','000','000','000','111'},
 ['%']={'101','001','010','100','101'},['[']={'110','100','100','100','110'},
 [']']={'011','001','001','001','011'},['@']={'111','101','111','100','111'}
}

local function enableGraphics(target,requested)
    if type(target.setGraphicsMode)~='function' or type(target.drawPixels)~='function' then
        return nil,'CC: Graphics no disponible: faltan term.setGraphicsMode/drawPixels'
    end
    local modes=requested==1 and {1} or {2,1}
    for _,mode in ipairs(modes) do
        local ok=pcall(target.setGraphicsMode,mode)
        if ok then
            local good,w,h=pcall(target.getSize,mode)
            if good and type(w)=='number' and type(h)=='number' and w>3 and h>3 then
                return {mode=mode,w=floor(w),h=floor(h)}
            end
            pcall(target.setGraphicsMode,false)
        end
    end
    return nil,'El modo grafico no se ha podido activar'
end

local function createEngine(options)
    options=options or {}
    -- En CC: Graphics algunas versiones exponen el modo grafico en el proxy
    -- global `term` pero no en term.current(). Se prueban ambos sin adivinar.
    local target=options.target or
        ((type(term.setGraphicsMode)=='function' and type(term.drawPixels)=='function')
         and term or term.current())
    local kind=options.backend or 'auto'
    local g,err
    if kind~='terminal' then g,err=enableGraphics(target,options.mode or 2) end
    if kind=='graphics' and not g then return nil,err end
    local isGraphics=g~=nil
    if isGraphics then
        if type(target.clear)=='function' then pcall(target.clear) end
        if g.mode==2 and type(target.setPaletteColor)=='function' then
            -- 216 colores RGB (cubo 6x6x6), mas 24 grises.
            for r=0,5 do for gg=0,5 do for b=0,5 do
                pcall(target.setPaletteColor,16+r*36+gg*6+b,r/5,gg/5,b/5)
            end end end
            for i=0,23 do pcall(target.setPaletteColor,232+i,i/23,i/23,i/23) end
        end
    end
    local scale=isGraphics and max(1,min(6,floor(tonumber(options.scale) or 3))) or 1
    local pw,ph
    if isGraphics then pw,ph=g.w,g.h else pw,ph=target.getSize() end
    local self={backend=isGraphics and 'ccgraphics' or 'terminal',target=target,
        mode=isGraphics and g.mode or 0,scale=scale,pixelWidth=pw,pixelHeight=ph,
        w=max(1,floor(pw/scale)),h=max(1,floor(ph/scale)),
        cameraX=0,cameraY=0,frame=0,front={},rows={},buf={},
        drawCalls=0,skippedRows=0,sceneStats={}, _closed=false}
    local function resolve(c) return colorIndex(c,self.mode) end
    local stretch={}
    for c=0,255 do stretch[c]=string.rep(string.char(c),scale) end
    function self:camera(x,y) self.cameraX=x or 0;self.cameraY=y or 0 end
    function self:resize()
        if self.backend=='ccgraphics' then
            local ok,w,h=pcall(self.target.getSize,self.mode)
            if ok and w and h then self.pixelWidth=w;self.pixelHeight=h end
        else self.pixelWidth,self.pixelHeight=self.target.getSize() end
        self.w=max(1,floor(self.pixelWidth/self.scale));self.h=max(1,floor(self.pixelHeight/self.scale))
        self.front={};self.buf={};self.rows={}
        self:clear(options.background or colors.black)
    end
    function self:clear(color)
        local v=resolve(color or colors.black)
        for y=1,self.h do
            local row=self.buf[y] or {};self.buf[y]=row
            for x=1,self.w do row[x]=v end
        end
    end
    function self:point(x,y,color,screen)
        if not screen then x=x-self.cameraX;y=y-self.cameraY end
        x=floor(x+0.5);y=floor(y+0.5)
        if x>=1 and x<=self.w and y>=1 and y<=self.h then
            self.buf[y][x]=resolve(color or colors.white)
        end
    end
    function self:fill(x,y,w,h,color,screen)
        if not screen then x=x-self.cameraX;y=y-self.cameraY end
        x=floor(x+0.5);y=floor(y+0.5);w=floor(w);h=floor(h)
        local x1,y1,x2,y2=max(1,x),max(1,y),min(self.w,x+w-1),min(self.h,y+h-1)
        if x1>x2 or y1>y2 then return end
        local c=resolve(color)
        for yy=y1,y2 do local row=self.buf[yy];for xx=x1,x2 do row[xx]=c end end
    end
    function self:box(x,y,w,h,color,screen)
        self:fill(x,y,w,1,color,screen);self:fill(x,y+h-1,w,1,color,screen)
        self:fill(x,y,1,h,color,screen);self:fill(x+w-1,y,1,h,color,screen)
    end
    function self:line(x0,y0,x1,y1,color,screen)
        if not screen then x0=x0-self.cameraX;y0=y0-self.cameraY;x1=x1-self.cameraX;y1=y1-self.cameraY end
        x0=floor(x0+.5);y0=floor(y0+.5);x1=floor(x1+.5);y1=floor(y1+.5)
        local dx=abs(x1-x0);local sx=x0<x1 and 1 or -1
        local dy=-abs(y1-y0);local sy=y0<y1 and 1 or -1;local e=dx+dy
        -- Permitimos lineas largas pero sin bloquear en segmentos fuera de pantalla enormes.
        for _=1,min(4096,dx-dy+1) do
            if x0>=1 and x0<=self.w and y0>=1 and y0<=self.h then self.buf[y0][x0]=resolve(color) end
            if x0==x1 and y0==y1 then break end
            local e2=2*e
            if e2>=dy then e=e+dy;x0=x0+sx end
            if e2<=dx then e=e+dx;y0=y0+sy end
        end
    end
    function self:circle(cx,cy,r,color,filled,screen)
        if not screen then cx=cx-self.cameraX;cy=cy-self.cameraY end
        cx=floor(cx+.5);cy=floor(cy+.5);r=max(0,floor(r))
        if cx+r<1 or cy+r<1 or cx-r>self.w or cy-r>self.h then return end
        local x1,x2=max(-r,1-cx),min(r,self.w-cx)
        for yy=max(-r,1-cy),min(r,self.h-cy) do
            for xx=x1,x2 do
                local d=xx*xx+yy*yy
                if (filled and d<=r*r) or (not filled and d<=r*r and d>(r-1)*(r-1)) then
                    self.buf[cy+yy][cx+xx]=resolve(color)
                end
            end
        end
    end
    -- Sprite pixel-art: sprite = { ' 11 ', '1221' }, pal={['1']='#22AAFF', ['2']=colors.white}
    function self:sprite(x,y,sprite,pal,scaleSprite,screen)
        pal=pal or {};scaleSprite=max(1,floor(scaleSprite or 1))
        for yy,row in ipairs(sprite or {}) do
            if type(row)=='string' then
                for xx=1,#row do
                    local key=row:sub(xx,xx)
                    local color=pal[key]
                    if key~=' ' and color~=nil and color~=false then
                        self:fill(x+(xx-1)*scaleSprite,y+(yy-1)*scaleSprite,
                            scaleSprite,scaleSprite,color,screen)
                    end
                end
            end
        end
    end
    function self:text(x,y,message,color,zoom,screen)
        zoom=max(1,min(5,floor(zoom or 1)))
        local startX=x
        message=tostring(message or '')
        for i=1,#message do
            local ch=message:sub(i,i)
            if ch=='\n' then y=y+6*zoom;x=startX
            else
                local glyph=FONT[ch:upper()] or FONT['?']
                for ry=1,5 do
                    for rx=1,3 do
                        if glyph[ry]:sub(rx,rx)=='1' then
                            self:fill(x+(rx-1)*zoom,y+(ry-1)*zoom,zoom,zoom,color,screen)
                        end
                    end
                end
                x=x+4*zoom
            end
        end
    end
    function self:center(y,s,c,zoom)
        zoom=zoom or 1
        self:text(floor((self.w-#tostring(s)*4*zoom)/2)+1,y,s,c,zoom,true)
    end
    function self:bar(x,y,w,value,maxval,color,background,screen)
        maxval=max(1,maxval or 100)
        self:fill(x,y,w,3,background or '#303040',screen)
        self:fill(x,y,floor(w*min(max((value or 0)/maxval,0),1)+.5),3,color or colors.lime,screen)
    end
    function self:visible(x,y,w,h,margin)
        local m=margin or 0
        return x+w>self.cameraX-m and x<self.cameraX+self.w+m and
            y+h>self.cameraY-m and y<self.cameraY+self.h+m
    end
    function self:flip()
        if self._closed then return false,'Motor cerrado' end
        self.frame=self.frame+1
        local skips=0;local calls=0
        local drawn={}
        local ok,err=pcall(function()
            for y=1,self.h do
                local row=self.buf[y];local raw=string.char(unpackValues(row,1,self.w))
                if raw~=self.front[y] then
                    drawn[y]=raw
                else skips=skips+1 end
            end
            if self.backend=='ccgraphics' then
                if type(self.target.setFrozen)=='function' then pcall(self.target.setFrozen,true) end
                local batch,by={},nil
                local function flush()
                    if by and #batch>0 then self.target.drawPixels(0,(by-1)*self.scale,batch);calls=calls+1 end
                    batch={};by=nil
                end
                local function expand(raw)
                    if self.scale==1 then return raw end
                    local t={};for x=1,#raw do t[x]=stretch[raw:byte(x)] end
                    return table.concat(t)
                end
                for y=1,self.h do
                    if drawn[y] then
                        if not by then by=y elseif (y-1)*self.scale~=((by-1)*self.scale+#batch) then flush();by=y end
                        local line=expand(drawn[y])
                        for _=1,self.scale do batch[#batch+1]=line end
                    else flush() end
                end
                flush()
            else
                local codes='0123456789abcdef'
                for y=1,self.h do
                    if drawn[y] then
                        local hexes={}
                        -- color indices are converted to CC blit digits below
                        for x=1,self.w do local idx=self.buf[y][x]+1;hexes[x]=codes:sub(idx,idx) end
                        local str=table.concat(hexes)
                        self.target.setCursorPos(1,y)
                        self.target.blit(string.rep(' ',self.w),string.rep('0',self.w),str)
                        calls=calls+1
                    end
                end
            end
        end)
        if self.backend=='ccgraphics' and type(self.target.setFrozen)=='function' then
            pcall(self.target.setFrozen,false)
        end
        if not ok then return false,'Error dibujando CC: Graphics: '..tostring(err) end
        for y,raw in pairs(drawn) do self.front[y]=raw end
        self.drawCalls=calls;self.skippedRows=skips
        return true
    end
    function self:stats()
        return {backend=self.backend,mode=self.mode,frame=self.frame,
            drawCalls=self.drawCalls,skippedRows=self.skippedRows,w=self.w,h=self.h}
    end
    function self:close()
        if self._closed then return end
        self._closed=true
        if self.backend=='ccgraphics' then
            if type(self.target.setFrozen)=='function' then pcall(self.target.setFrozen,false) end
            pcall(self.target.setGraphicsMode,false)
            if type(self.target.clear)=='function' then
                pcall(self.target.setCursorPos,1,1);pcall(self.target.clear)
            end
        end
    end
    self:clear(options.background or colors.black)
    return self
end

-- Scene graph owns visibility, camera, movement, collisions, animation and drawing.
function WT.scene(gfx,opts)
    opts=opts or {}
    local sc={gfx=gfx,objects={},particles={},cameraX=0,cameraY=0,
        gravity=opts.gravity or 0,background=opts.background or '#101728',
        map=nil,followTarget=nil,followEase=opts.followEase or 10,
        stats={visible=0,culled=0,collisions=0},time=0}
    function sc:add(obj)
        obj.x=obj.x or 1;obj.y=obj.y or 1;obj.w=obj.w or 1;obj.h=obj.h or 1
        obj.vx=obj.vx or 0;obj.vy=obj.vy or 0;obj.z=obj.z or 0
        obj.visible=obj.visible~=false
        self.objects[#self.objects+1]=obj
        return obj
    end
    function sc:remove(obj)
        for i=#self.objects,1,-1 do if self.objects[i]==obj then table.remove(self.objects,i);return true end end
        return false
    end
    function sc:setTiles(grid,colorsByTile,size)
        self.map={grid=grid,palette=colorsByTile or {},tileSize=max(1,size or 8)}
    end
    function sc:follow(obj) self.followTarget=obj end
    function sc:emit(x,y,color,n)
        for i=1,min(48,n or 8) do
            local a=(i/(n or 8))*math.pi*2
            self.particles[#self.particles+1]={x=x,y=y,vx=math.cos(a)*20,
                vy=math.sin(a)*20,age=0,life=.25+math.random()*.4,color=color or colors.yellow}
        end
    end
    function sc:step(dt)
        dt=max(0,min(dt or .05,.1));self.time=self.time+dt
        local collisions=0
        for _,o in ipairs(self.objects) do
            if o.update then o:update(dt,self) end
            if o.dynamic then
                o.vy=o.vy+(o.gravity or self.gravity)*dt
                local nx=o.x+o.vx*dt
                local box={x=nx,y=o.y,w=o.w,h=o.h}
                for _,wall in ipairs(self.objects) do
                    if wall~=o and wall.solid and WT.aabb(box,wall) then
                        collisions=collisions+1
                        if o.vx>0 then nx=wall.x-o.w elseif o.vx<0 then nx=wall.x+wall.w end
                        o.vx=0;box.x=nx
                        if o.onCollision then o:onCollision(wall,'x') end
                    end
                end
                o.x=nx
                local ny=o.y+o.vy*dt
                box={x=o.x,y=ny,w=o.w,h=o.h}
                o.onGround=false
                for _,wall in ipairs(self.objects) do
                    if wall~=o and wall.solid and WT.aabb(box,wall) then
                        collisions=collisions+1
                        if o.vy>0 then ny=wall.y-o.h;o.onGround=true elseif o.vy<0 then ny=wall.y+wall.h end
                        o.vy=0;box.y=ny
                        if o.onCollision then o:onCollision(wall,'y') end
                    end
                end
                o.y=ny
            end
            if o.animation and type(o.animation)=='table' and #o.animation>0 then
                local step=o.animationSpeed or 6
                o.animationFrame=1+floor(self.time*step)%#o.animation
            end
        end
        for i=#self.particles,1,-1 do
            local p=self.particles[i];p.age=p.age+dt
            p.x=p.x+p.vx*dt;p.y=p.y+p.vy*dt;p.vy=p.vy+20*dt
            if p.age>p.life then table.remove(self.particles,i) end
        end
        self.stats.collisions=collisions
        if self.followTarget then
            local tx=self.followTarget.x+self.followTarget.w/2-self.gfx.w/2
            local ty=self.followTarget.y+self.followTarget.h/2-self.gfx.h/2
            local smoothing=min(1,dt*self.followEase)
            self.cameraX=WT.lerp(self.cameraX,tx,smoothing)
            self.cameraY=WT.lerp(self.cameraY,ty,smoothing)
        end
    end
    function sc:render(hud)
        local gfx=self.gfx
        gfx:camera(self.cameraX,self.cameraY)
        gfx:clear(self.background)
        local visible,culled=0,0
        if self.map then
            local tile=self.map.tileSize
            local x1=max(1,floor(self.cameraX/tile)+1)
            local y1=max(1,floor(self.cameraY/tile)+1)
            local x2=floor((self.cameraX+gfx.w)/tile)+2
            local y2=floor((self.cameraY+gfx.h)/tile)+2
            for gy=y1,min(y2,#self.map.grid) do
                local row=self.map.grid[gy]
                for gx=x1,min(x2,#row) do
                    local color=self.map.palette[row[gx]]
                    if color then gfx:fill((gx-1)*tile+1,(gy-1)*tile+1,tile,tile,color) end
                end
            end
        end
        local list={}
        for _,o in ipairs(self.objects) do
            if o.visible and gfx:visible(o.x,o.y,o.w,o.h,1) then
                list[#list+1]=o;visible=visible+1
            else culled=culled+1 end
        end
        table.sort(list,function(a,b)
            if a.z==b.z then return (a.y or 0)<(b.y or 0) end
            return a.z<b.z
        end)
        for _,o in ipairs(list) do
            if o.draw then o:draw(gfx,self)
            elseif o.animation and o.animation[o.animationFrame or 1] and o.palette then
                gfx:sprite(o.x,o.y,o.animation[o.animationFrame or 1],o.palette,o.pixelScale or 1)
            elseif o.sprite and o.palette then
                gfx:sprite(o.x,o.y,o.sprite,o.palette,o.pixelScale or 1)
            elseif o.shape=='circle' then
                gfx:circle(o.x+o.w/2,o.y+o.h/2,min(o.w,o.h)/2,o.color,true)
            else gfx:fill(o.x,o.y,o.w,o.h,o.color or colors.white) end
        end
        for _,p in ipairs(self.particles) do gfx:fill(p.x,p.y,2,2,p.color) end
        gfx:camera(0,0)
        if hud then hud(gfx,self) end
        self.stats.visible=visible;self.stats.culled=culled
        return gfx:flip()
    end
    return sc
end

-- Event loop without busy-wait. Handles key events even when frames run slower.
function WT.run(scene,options)
    options=options or {}
    local fps=max(1,min(20,floor(options.fps or 15)))
    local frameTime=1/fps
    local timer=os.startTimer(frameTime)
    local time=(os.epoch and os.epoch('utc')/1000) or os.clock()
    local acc=0
    local running=true
    local function now() return (os.epoch and os.epoch('utc')/1000) or os.clock() end
    local function loop()
        while running do
            local e={os.pullEvent()}
            if e[1]=='timer' and e[2]==timer then
                local t=now();local elapsed=min(.2,max(0,t-time));time=t
                acc=acc+elapsed
                local steps=0
                while acc>=.05 and steps<3 do
                    scene:step(.05);acc=acc-.05;steps=steps+1
                end
                if steps==3 then acc=0 end
                if options.update then options.update(scene,elapsed) end
                local ok,err=scene:render(options.hud)
                if not ok then error(err) end
                timer=os.startTimer(frameTime)
            else
                if e[1]=='term_resize' or e[1]=='monitor_resize' then scene.gfx:resize() end
                if options.event and options.event(scene,unpackValues(e))==false then running=false end
                if e[1]=='terminate' then running=false end
            end
        end
    end
    local ok,err=pcall(loop)
    scene.gfx:close()
    if not ok then error(err,0) end
end

WT.new=function(target,opts)
    -- WorldTor 1 calls: WT.new(term.current()) or WT.new()
    if target==nil or type(target)~='table' or type(target.getSize)=='function' then
        return oldNew(target)
    end
    -- WorldTor 2 calls: WT.new({backend='auto',...})
    return createEngine(target)
end
WT.newCanvas=createEngine
return WT
]=],
    ['worldtor3.lua']=[=[
-- WorldTor 3.0 | entrada oficial del motor. Compatible con la API 2D anterior.
local dir = (shell and shell.getRunningProgram and fs and fs.getDir and fs.combine and fs.combine(fs.getDir(shell.getRunningProgram()), 'classic_dungeons_runtime_1_1')) or ''
local function filepath(name)
  if fs and fs.combine then return fs.combine(dir,name) end
  return name
end
local wtFile,why=loadfile(filepath('worldtor_engine.lua'))
assert(wtFile,'WorldTor 3: falta worldtor_engine.lua: '..tostring(why))
local WT=wtFile()
local module,err=loadfile(filepath('worldtor3_3d.lua'))
assert(module,'WorldTor 3: falta worldtor3_3d.lua: '..tostring(err))
WT=module()(WT)
WT.version='3.0.0'
WT.name='WorldTor 3 / CC: Graphics'
return WT
]=],
    ['worldtor3_3d.lua']=[=[
-- WorldTor 3.0 | renderer 3D 2.5D de texturas para CC: Graphics.
-- API: local WT=assert(loadfile('worldtor3.lua'))(); local world=WT.new3D(gfx,opts)
-- Motor: DDA, profundidad, paredes texturizadas, suelos/techos, billboards,
-- puertas, fog/lights, colisiones, movimiento, AI y HUD. Sin perifericos extra.
return function(WT)
  local sin,cos,abs,sqrt,floor,ceil,min,max,pi=math.sin,math.cos,math.abs,math.sqrt,math.floor,math.ceil,math.min,math.max,math.pi
  local function limit(x,low,high) return min(high,max(low,x)) end
  local function dist(x,y) return sqrt(x*x+y*y) end
  local function RGB(hex) return tonumber(hex:sub(2),16) end
  local function mixColor(c,f)
    local r=floor(c/65536)%256;local g=floor(c/256)%256;local b=c%256
    return string.format('#%02X%02X%02X',limit(floor(r*f+.5),0,255),limit(floor(g*f+.5),0,255),limit(floor(b*f+.5),0,255))
  end
  local function tex(fn)
    local out={}
    for y=0,15 do
      local row={}
      for x=0,15 do row[x+1]=fn(x,y) end
      out[y+1]=row
    end
    return out
  end
  local function builtinTextures()
    return {
      ['1']=tex(function(x,y)
        local joint=y%8==0 or ((x+(floor(y/8)%2)*8)%16)==0
        local grain=((x*13+y*17)%7)*3
        if joint then return '#453844' end
        return string.format('#%02X%02X%02X',110+grain,48+floor(grain/2),51+floor(grain/3))
      end),
      ['2']=tex(function(x,y)
        if x%8==0 or y%8==0 then return '#182B39' end
        if (x%8==1 and y%8==1) or (x%8==6 and y%8==6) then return '#B7D8D5' end
        local n=(x*5+y*11)%21
        return string.format('#%02X%02X%02X',57+n,87+n,105+n)
      end),
      ['3']=tex(function(x,y)
        if y%6==0 or x%9==0 then return '#343038' end
        local noise=(x*29+y*13)%23
        return string.format('#%02X%02X%02X',81+noise,79+noise,86+noise)
      end),
      D=tex(function(x,y)
        if x==0 or x==15 or y==0 or y==15 then return '#493927' end
        if x==7 or x==8 then return '#EEE0A3' end
        if (y==3 or y==12) then return '#6F532D' end
        return ((x+y)%5==0) and '#9E7642' or '#BB9151'
      end),
      F=tex(function(x,y)
        if x%8==0 or y%8==0 then return '#30353F' end
        return ((x+y)%5==0) and '#626875' or '#515965'
      end),
      C=tex(function(x,y)
        if x%8==0 or y%8==0 then return '#1E2F41' end
        if (x%8==3 and y%8==3) then return '#B0DBEA' end
        return '#33495B'
      end),
      X=tex(function(x,y)
        return (x==7 or x==8 or y==7 or y==8) and '#A0FFB5' or '#145E42'
      end),
      M=tex(function(x,y)
        if y<3 and x>3 and x<12 then return '#FAA065' end
        if (x>=3 and x<=5 or x>=10 and x<=12) and y<8 then return '#FFE19A' end
        if x<2 or x>13 or y>13 then return nil end
        return ((x+y)%4==0) and '#A74659' or '#D76A66'
      end),
      H=tex(function(x,y)
        if x<2 or x>13 or y<2 or y>13 then return nil end
        if x==7 or x==8 or y==7 or y==8 then return '#FFFFFF' end
        return '#38CFA2'
      end),
      A=tex(function(x,y)
        if x<3 or x>12 or y<4 or y>12 then return nil end
        if y<=6 then return '#FFF0A0' end
        return '#C18B32'
      end)
    }
  end
  WT.textures3D = builtinTextures
  function WT.new3D(gfx,opts)
    opts=opts or {}
    assert(gfx and gfx.backend=='ccgraphics','WorldTor 3 requiere CC: Graphics')
    assert(type(opts.map)=='table' and #opts.map>=3,'WorldTor 3: mapa sin filas')
    local width=#opts.map[1]
    for i,row in ipairs(opts.map) do
      assert(type(row)=='string' and #row==width,'WorldTor 3: ancho incorrecto en fila '..i)
    end
    local world={gfx=gfx,map=opts.map,width=width,height=#opts.map,
      player={x=opts.x or 2.5,y=opts.y or 2.5,a=opts.angle or 0,hp=100,ammo=32,kills=0},
      textures=opts.textures or builtinTextures(), doors={}, entities={},lights=opts.lights or {},
      fov=opts.fov or pi/3,quality=2,far=opts.far or 20,
      age=0,flash=0,hitFlash=0,message='',messageTime=0,won=false,lost=false,
      minimap=false,rays=0,visibleSprites=0,lastDepth={},shots=0,
      autotune=false,lastQualityChange=0}
    local quality={ [1]={wall=1,floor=1},[2]={wall=2,floor=2},[3]={wall=3,floor=3} }
    for y,row in ipairs(world.map) do
      for x=1,#row do
        if row:sub(x,x)=='D' then world.doors[(x-1)..':'..(y-1)]=false end
      end
    end
    for _,entity in ipairs(opts.entities or {}) do
      local e={}
      for k,v in pairs(entity) do e[k]=v end
      e.hp=e.hp or (e.kind=='enemy' and 3 or 1)
      e.cooldown=0;e.speed=e.speed or .65;e.picked=false
      world.entities[#world.entities+1]=e
    end
    local function sample(mat,x,y,shade)
      local t=world._shaded[mat] or world._shaded['1']
      local yy=(floor(y)%16)+1;local xx=(floor(x)%16)+1
      return t[shade+1][yy][xx]
    end
    function world:prepareTextures()
      self._shaded={}
      for name,pixels in pairs(self.textures) do
        local variants={}
        for shade=0,7 do
          local rows={}
          for y=1,16 do
            rows[y]={}
            for x=1,16 do
              local col=pixels[y] and pixels[y][x]
              if col then
                local factor=max(.12,1-shade*.115)
                rows[y][x]=WT.colorIndex(mixColor(RGB(col),factor),self.gfx.mode)
              else rows[y][x]=nil end
            end
          end
          variants[shade+1]=rows
        end
        self._shaded[name]=variants
      end
    end
    world:prepareTextures()
    function world:qualityLevel(level)
      self.quality=limit(floor(level or 2),1,3)
      return self.quality
    end
    function world:setTexture(name,texture)
      assert(type(name)=='string' and type(texture)=='table' and #texture==16,
        'WorldTor3: la textura necesita 16 filas')
      for _,r in ipairs(texture) do assert(type(r)=='table' and #r==16,
        'WorldTor3: cada fila debe tener 16 colores') end
      self.textures[name]=texture
      self:prepareTextures()
    end
    function world:setAutotune(enabled)
      self.autotune=enabled==true
      self.lastQualityChange=self.age
    end
    function world:tile(x,y)
      local xi,yi=floor(x)+1,floor(y)+1
      if xi<1 or yi<1 or xi>self.width or yi>self.height then return '1' end
      return self.map[yi]:sub(xi,xi)
    end
    function world:solid(x,y)
      local t=self:tile(x,y)
      if t=='D' then return not self.doors[floor(x)..':'..floor(y)] end
      return t~='.' and t~='X' and t~=' ' and t~='H' and t~='A'
    end
    function world:canStand(x,y,r)
      r=r or .22
      return not (self:solid(x-r,y-r) or self:solid(x+r,y-r) or
                  self:solid(x-r,y+r) or self:solid(x+r,y+r))
    end
    function world:move(obj,dx,dy,r)
      local nx=obj.x+dx
      if self:canStand(nx,obj.y,r) then obj.x=nx end
      local ny=obj.y+dy
      if self:canStand(obj.x,ny,r) then obj.y=ny end
    end
    function world:ray(x,y,dx,dy,range)
      range=range or self.far
      local mx,my=floor(x),floor(y)
      local deltaX=dx==0 and 1e30 or abs(1/dx)
      local deltaY=dy==0 and 1e30 or abs(1/dy)
      local stepx,stepy,sx,sy
      if dx<0 then stepx=-1;sx=(x-mx)*deltaX else stepx=1;sx=(mx+1-x)*deltaX end
      if dy<0 then stepy=-1;sy=(y-my)*deltaY else stepy=1;sy=(my+1-y)*deltaY end
      local side=0
      for i=1,64 do
        if sx<sy then mx=mx+stepx;sx=sx+deltaX;side=0
        else my=my+stepy;sy=sy+deltaY;side=1 end
        local dd=side==0 and sx-deltaX or sy-deltaY
        if dd>range then return range,nil,side,0 end
        if self:solid(mx+.5,my+.5) then
          local hit=side==0 and (y+dd*dy) or (x+dd*dx)
          hit=hit-floor(hit)
          if (side==0 and dx>0) or (side==1 and dy<0) then hit=1-hit end
          return max(.025,dd),self:tile(mx+.5,my+.5),side,hit
        end
      end
      return range,nil,side,0
    end
    function world:shade(x,y,distValue,side)
      local v=limit(floor(distValue*.52+(side or 0)*.85),0,7)
      local light=0
      for _,l in ipairs(self.lights) do
        local d=dist(x-l.x,y-l.y)
        local r=l.radius or 4
        if d<r then light=max(light,(1-d/r)*(l._power or l.power or 3)) end
      end
      return limit(floor(v-light+.5),0,7)
    end
    function world:visible(x,y,tx,ty)
      local dx,dy=tx-x,ty-y
      local length=dist(dx,dy)
      if length<.1 then return true end
      local d=self:ray(x,y,dx/length,dy/length,length)
      return d>=length-.1
    end
    function world:action()
      for step=.25,1.6,.15 do
        local p=self.player
        local px=p.x+cos(p.a)*step;local py=p.y+sin(p.a)*step
        if self:tile(px,py)=='D' then
          local k=floor(px)..':'..floor(py)
          self.doors[k]=true
          self.message='PUERTA ABIERTA';self.messageTime=1.3
          return true
        elseif self:solid(px,py) then break end
      end
      self.message='NO HAY PUERTA';self.messageTime=.7
      return false
    end
    function world:fire()
      if self.won or self.lost or self.flash>0 then return false end
      if self.player.ammo<=0 then self.message='SIN MUNICION';self.messageTime=.9;return false end
      self.player.ammo=self.player.ammo-1;self.shots=self.shots+1;self.flash=.18
      local p=self.player
      local dx,dy=cos(p.a),sin(p.a)
      local wall=self:ray(p.x,p.y,dx,dy,15)
      local target,distance=nil,1e20
      for _,e in ipairs(self.entities) do
        if e.kind=='enemy' and e.hp>0 then
          local vx,vy=e.x-p.x,e.y-p.y
          local z=vx*dx+vy*dy
          local spread=abs(vx*dy-vy*dx)
          if z>0 and z<wall+.03 and spread<.30+z*.012 and z<distance then
            target=e;distance=z
          end
        end
      end
      if target then
        target.hp=target.hp-1;target.hurt=.22
        self.message='IMPACTO';self.messageTime=.4
        if target.hp<=0 then p.kills=p.kills+1;self.message='ENEMIGO ELIMINADO';self.messageTime=1 end
      end
      return target~=nil
    end
    function world:step(dt,input)
      dt=limit(dt or .05,0,.12);input=input or {}
      self.age=self.age+dt
      -- Luces intermitentes calculadas una vez por tick, no por pixel.
      for i,l in ipairs(self.lights) do
        l._power=(l.power or 3)*(.88+.12*sin(self.age*3.2+i*2.1))
      end
      self.flash=max(0,self.flash-dt);self.hitFlash=max(0,self.hitFlash-dt)
      self.messageTime=max(0,self.messageTime-dt)
      if self.won or self.lost then return end
      local p=self.player
      local turn=((input.d or input.right) and 1 or 0)-((input.a or input.left) and 1 or 0)
      p.a=(p.a+turn*dt*2.25)%(2*pi)
      local forward=((input.w or input.up) and 1 or 0)-((input.s or input.down) and 1 or 0)
      local lateral=(input.f and 1 or 0)-(input.q and 1 or 0)
      local norm=max(1,dist(forward,lateral))
      local speed=2.45*dt/norm
      self:move(p,(cos(p.a)*forward-sin(p.a)*lateral)*speed,
                 (sin(p.a)*forward+cos(p.a)*lateral)*speed,.23)
      if self:tile(p.x,p.y)=='X' then self.won=true;self.message='NIVEL COMPLETADO';return end
      for _,e in ipairs(self.entities) do
        if e.kind=='enemy' and e.hp>0 then
          e.hurt=max(0,(e.hurt or 0)-dt)
          e.cooldown=max(0,(e.cooldown or 0)-dt)
          local dx,dy=p.x-e.x,p.y-e.y
          local r=dist(dx,dy)
          if r<7 and self:visible(e.x,e.y,p.x,p.y) then
            if r>.75 then self:move(e,dx/max(r,.01)*e.speed*dt,dy/max(r,.01)*e.speed*dt,.20)
            elseif e.cooldown<=0 then
              p.hp=max(0,p.hp-8);e.cooldown=1.2;self.hitFlash=.3
              if p.hp==0 then self.lost=true;self.message='GAME OVER' end
            end
          end
        elseif e.kind=='medkit' and not e.picked and dist(p.x-e.x,p.y-e.y)<.48 then
          p.hp=min(100,p.hp+30);e.picked=true;self.message='BOTIQUIN';self.messageTime=.85
        elseif e.kind=='ammo' and not e.picked and dist(p.x-e.x,p.y-e.y)<.48 then
          p.ammo=p.ammo+12;e.picked=true;self.message='MUNICION';self.messageTime=.85
        end
      end
    end
    -- Escribe colores ya cuantizados directamente en el framebuffer del motor:
    -- evita miles de conversiones RGB / llamadas a la API del terminal por frame.
    local function paint(gfx,x,y,bw,bh,color)
      if color==nil then return end
      local x2=min(gfx.w,x+bw-1);local y2=min(gfx.h,y+bh-1)
      for yy=max(1,y),y2 do
        local row=gfx.buf[yy]
        for xx=max(1,x),x2 do row[xx]=color end
      end
    end
    local function renderFloor(self,p,dx,dy,planeX,planeY,w,h,horizon,spacing)
      local ray0x,ray0y=dx-planeX,dy-planeY
      local ray1x,ray1y=dx+planeX,dy+planeY
      for y=horizon+1,h,spacing do
        local depth=(h*.5)/max(1,y-horizon)
        for x=1,w,spacing do
          local t=(x-1)/max(1,w-1)
          local worldx=p.x+depth*(ray0x+(ray1x-ray0x)*t)
          local worldy=p.y+depth*(ray0y+(ray1y-ray0y)*t)
          local shade=self:shade(worldx,worldy,depth,0)
          local floorMaterial=self:tile(worldx,worldy)=='X' and 'X' or 'F'
          local ix=floor(worldx*16);local iy=floor(worldy*16)
          local floorColor=sample(floorMaterial,ix,iy,shade)
          local ceilingColor=sample('C',ix,iy,shade)
          local blockH=min(spacing,h-y+1)
          paint(self.gfx,x,y,min(spacing,w-x+1),blockH,floorColor)
          local ceilingY=h-y-blockH+2
          paint(self.gfx,x,ceilingY,min(spacing,w-x+1),blockH,ceilingColor)
        end
      end
    end
    local function renderWalls(self,p,dx,dy,planeX,planeY,w,h,horizon,step)
      self.rays=0
      for x=1,w,step do
        local camx=2*((x-1+.5*step)/w)-1
        local rx,ry=dx+planeX*camx,dy+planeY*camx
        local d,material,side,u=self:ray(p.x,p.y,rx,ry,self.far)
        local height=min(h*5,max(1,floor(h/max(.07,d))))
        local top=floor(horizon-height/2)
        local bottom=top+height-1
        if material then
          local hx=p.x+d*rx;local hy=p.y+d*ry
          local shade=self:shade(hx,hy,d,side)
          local colX=limit(floor(u*16),0,15)
          local y0=max(1,top);local y1=min(h,bottom)
          for y=y0,y1 do
            local texY=limit(floor(((y-top)/height)*16),0,15)
            local c=sample(material,colX,texY,shade)
            paint(self.gfx,x,y,min(step,w-x+1),1,c)
          end
        end
        for off=0,step-1 do if x+off<=w then self.lastDepth[x+off]=d end end
        self.rays=self.rays+1
      end
    end
    local function renderEntities(self,p,dx,dy,planeX,planeY,w,h,horizon)
      local det=planeX*dy-dx*planeY
      if abs(det)<.00001 then return end
      local inv=1/det
      local arr={}
      for _,e in ipairs(self.entities) do
        if not e.picked and (e.kind~='enemy' or e.hp>0) then
          local vx,vy=e.x-p.x,e.y-p.y
          local z=inv*(-planeY*vx+planeX*vy)
          if z>.15 and z<self.far then
            local sx=inv*(dy*vx-dx*vy)
            local center=floor((w/2)*(1+sx/z))
            local size=max(1,min(h*4,floor(h/z*.72)))
            if center+size/2>=1 and center-size/2<=w then
              arr[#arr+1]={e=e,z=z,cx=center,size=size,dist2=vx*vx+vy*vy}
            end
          end
        end
      end
      table.sort(arr,function(a,b) return a.dist2>b.dist2 end)
      self.visibleSprites=0
      for _,o in ipairs(arr) do
        local texName=o.e.texture or (o.e.kind=='enemy' and 'M' or o.e.kind=='medkit' and 'H' or 'A')
        local width=max(1,floor(o.size*.7))
        local x0=floor(o.cx-width/2)
        local y0=floor(horizon-o.size/2)
        local shade=self:shade(o.e.x,o.e.y,o.z,0)
        for x=max(1,x0),min(w,x0+width-1) do
          if o.z<(self.lastDepth[x] or 1e20)-.04 then
            local tx=limit(floor((x-x0)/width*16),0,15)
            for y=max(1,y0),min(h,y0+o.size-1) do
              local ty=limit(floor((y-y0)/o.size*16),0,15)
              local c=sample(texName,tx,ty,shade)
              if c then
                if o.e.hurt and o.e.hurt>0 then c=WT.colorIndex('#F5D4C7',self.gfx.mode) end
                paint(self.gfx,x,y,1,1,c)
              end
            end
          end
        end
        self.visibleSprites=self.visibleSprites+1
      end
    end
    function world:render(fps)
      if self.autotune and (self.age-self.lastQualityChange)>3 then
        if (fps or 0)<6.5 and self.quality<3 then
          self:qualityLevel(self.quality+1)
        elseif (fps or 0)>9.5 and self.quality>1 then
          self:qualityLevel(self.quality-1)
        end
        self.lastQualityChange=self.age
      end
      local gfx=self.gfx;local w,h=gfx.w,gfx.h
      if w<24 or h<22 then
        gfx:clear('#121823');gfx:text(2,3,'AMPLIA LA PANTALLA','#F7C385',1,true)
        return gfx:flip()
      end
      gfx:camera(0,0)
      gfx:clear('#17283F')
      local p=self.player
      local dx,dy=cos(p.a),sin(p.a)
      local planeX,planeY=-dy*math.tan(self.fov/2),dx*math.tan(self.fov/2)
      local horizon=floor(h/2)
      local q=quality[self.quality]
      renderFloor(self,p,dx,dy,planeX,planeY,w,h,horizon,q.floor)
      renderWalls(self,p,dx,dy,planeX,planeY,w,h,horizon,q.wall)
      renderEntities(self,p,dx,dy,planeX,planeY,w,h,horizon)
      -- HUD + crosshair + arma calculados por WorldTor.
      gfx:fill(1,1,w,8,'#101A2B',true)
      gfx:text(2,2,w>=85 and 'WORLDTOR 3' or 'WT3','#A5EBFE',1,true)
      gfx:text(max(2,w-27),2,'FPS'..floor(fps or 0),'#81E5CD',1,true)
      local mx,my=floor(w/2),floor(h/2)
      gfx:line(mx-3,my,mx-1,my,'#EDF2DF',true);gfx:line(mx+1,my,mx+3,my,'#EDF2DF',true)
      gfx:line(mx,my-3,mx,my-1,'#EDF2DF',true);gfx:line(mx,my+1,mx,my+3,'#EDF2DF',true)
      gfx:fill(mx-5,h-9,10,9,'#434C5C',true)
      gfx:fill(mx-2,h-11,4,10,'#ABB2BB',true)
      if self.flash>.07 then gfx:circle(mx,h-14,4,'#FFE484',true,true) end
      gfx:fill(1,h-12,w,12,'#0F1B2A',true)
      gfx:text(2,h-11,'HP '..p.hp..' A '..p.ammo,'#F6DCA1',1,true)
      gfx:text(2,h-5,'K '..p.kills..' Q'..self.quality..(self.autotune and ' AUTO' or ''),'#81E5CD',1,true)
      if self.messageTime>0 then gfx:center(11,self.message,'#FFE6A0',1) end
      if self.hitFlash>0 then gfx:box(1,9,w,h-17,'#D74763',true) end
      if self.minimap then
        local tiles=3;local span=9
        local sx=max(2,w-span*tiles-2);local sy=12
        gfx:fill(sx-1,sy-1,span*tiles+2,span*tiles+2,'#101925',true)
        for yy=0,span-1 do for xx=0,span-1 do
          local wx=floor(p.x)+xx-4;local wy=floor(p.y)+yy-4
          local cell=self:tile(wx+.5,wy+.5)
          local color=(cell=='1' or cell=='2' or cell=='3') and '#8397A3' or cell=='D' and '#C49A55' or cell=='X' and '#6DFFC4' or '#263746'
          gfx:fill(sx+xx*tiles,sy+yy*tiles,2,2,color,true)
        end end
        gfx:fill(sx+4*tiles,sy+4*tiles,2,2,'#FFE9A5',true)
      end
      if self.won or self.lost then
        gfx:fill(2,floor(h*.3),w-4,23,'#132039',true)
        gfx:center(floor(h*.3)+3,self.won and (w<75 and 'GANASTE' or 'NIVEL COMPLETADO') or 'GAME OVER',self.won and '#6AFFC2' or '#FF8B9B',1)
        gfx:center(floor(h*.3)+12,'R = REINICIAR','#FDE4B7',1)
      end
      if self.beforeFlip then self:beforeFlip(fps) end
      return gfx:flip()
    end
    function world:stats()
      return {rays=self.rays,sprites=self.visibleSprites,quality=self.quality,frame=self.gfx.frame,autotune=self.autotune}
    end
    assert(world:canStand(world.player.x,world.player.y,.2),'WorldTor3: jugador dentro de pared')
    return world
  end
  return WT
end
]=],
  }
  if fs.exists(dest) and not fs.isDir(dest) then
    error('Classic Dungeons: la ruta de librerias ya existe y no es una carpeta: '..dest,0)
  end
  if not fs.exists(dest) then fs.makeDir(dest) end
  local installed, repaired=0,0
  for filename,data in pairs(bundled) do
    local target=fs.combine(dest,filename)
    local previous=nil
    if fs.exists(target) then
      if fs.isDir(target) then error('Classic Dungeons: conflicto con carpeta '..target,0) end
      local original=fs.open(target,'r')
      if not original then error('Classic Dungeons: no se puede leer '..target,0) end
      previous=original.readAll(); original.close()
    end
    if previous~=data then
      local tmp=target..'.writing'
      if fs.exists(tmp) then
        if fs.isDir(tmp) then error('Classic Dungeons: ruta temporal ocupada '..tmp,0) end
        fs.delete(tmp)
      end
      local output=fs.open(tmp,'w')
      if not output then error('Classic Dungeons: sin permiso o espacio para '..tmp,0) end
      output.write(data);output.close()
      local check=fs.open(tmp,'r')
      if not check then error('Classic Dungeons: no se pudo verificar '..tmp,0) end
      local valid=check.readAll()==data;check.close()
      if not valid then error('Classic Dungeons: escritura incompleta de '..filename,0) end
      if previous~=nil then
        local backup=target..'.backup'
        local n=1
        while fs.exists(backup) do
          n=n+1; backup=target..'.backup'..n
        end
        fs.copy(target,backup)
        if not fs.exists(backup) then error('Classic Dungeons: no se pudo crear backup de '..filename,0) end
        fs.delete(target)
        repaired=repaired+1
      else installed=installed+1 end
      fs.move(tmp,target)
    end
  end
  LIB=dest
  if installed>0 or repaired>0 then
    print(('[Classic Dungeons] Librerias: %d instaladas, %d reparadas.'):format(installed,repaired))
  end
 end

-- CLASSIC DUNGEONS | Cliente World Studios + WorldTor 3 + CC: Graphics
-- Cuenta local, amigos, partidas SOLO/COOP/PVP/EVENT, ranking, sonido, ajustes.
local ROOT=fs.getDir(shell.getRunningProgram())
local C=assert(loadfile(fs.combine(LIB,'classic_dungeons_core.lua')))()
local PROTO=C.PROTO
local function path(n) return fs.combine(ROOT,n) end
local function load(name,def)
  local h=fs.open(path(name),'r');if not h then return def end
  local v=h.readAll();h.close()
  local ok,t=pcall(textutils.unserialize,v)
  return ok and type(t)=='table' and t or def
end
local function save(name,obj)
  local h=fs.open(path(name),'w');if h then h.write(textutils.serialize(obj));h.close() end
end
local account=load('classic_account.dat',{})
local username=account.user or ''
local friends=load('classic_friends.dat',{})
local localStats=load('classic_local.dat',{runs=0,best=0,last=0,kills=0,floor=0})
local opts=load('classic_options.dat',{music=true,sfx=true,auto=true,minimap=false,scale=3,quality=2})
local speaker=(peripheral and peripheral.find) and peripheral.find('speaker') or nil
local modems={}
if peripheral and rednet and peripheral.getNames then
  for _,side in ipairs(peripheral.getNames()) do
    if peripheral.hasType(side,'modem') then
      modems[#modems+1]=side
      if not rednet.isOpen(side) then rednet.open(side) end
    end
  end
end
local serverId=nil;local serverInfo=nil
local renderer=nil
local function stopGraphics()
  if renderer then pcall(function() renderer:close() end);renderer=nil end
  if type(term.setGraphicsMode)=='function' then pcall(term.setGraphicsMode,false) end
  term.setBackgroundColor(colors.black);term.setTextColor(colors.white)
end
local function textScreen(title,rows,note)
  stopGraphics()
  term.setBackgroundColor(colors.black);term.setTextColor(colors.white);term.clear()
  local w,h=term.getSize()
  term.setBackgroundColor(colors.blue);term.setTextColor(colors.white)
  term.setCursorPos(1,1);term.write(string.rep(' ',w))
  term.setCursorPos(2,1);term.write(('CLASSIC DUNGEONS / WORLD STUDIOS'):sub(1,math.max(1,w-2)))
  term.setBackgroundColor(colors.black);term.setTextColor(colors.cyan)
  term.setCursorPos(math.max(1,math.floor((w-#title)/2)+1),3);print(title)
  term.setTextColor(colors.lightGray)
  for i,v in ipairs(rows or {}) do
    local y=4+i;if y>=h-2 then break end
    local textValue=type(v)=='table' and tostring(v[1]) or tostring(v)
    term.setTextColor(type(v)=='table' and (v[2] or colors.white) or colors.lightGray)
    term.setCursorPos(2,y);term.write(textValue:sub(1,math.max(1,w-3)))
  end
  term.setTextColor(colors.yellow)
  if note then term.setCursorPos(2,h-1);term.write(note:sub(1,math.max(1,w-3))) end
  term.setCursorPos(1,h);term.setBackgroundColor(colors.gray);term.setTextColor(colors.white)
  term.write((' WorldTor 3 / CC: Graphics '):sub(1,w)..string.rep(' ',math.max(0,w-27)))
  term.setBackgroundColor(colors.black);term.setTextColor(colors.white)
end
local function ask(title,prompt)
  textScreen(title,{prompt,'','Escribe y pulsa ENTER:'})
  term.setCursorPos(2,9)
  return read() or ''
end
local function keyInput()
  while true do
    local event,k=os.pullEventRaw()
    if event=='terminate' then return keys.escape end
    if event=='key' then return k end
  end
end
local function ensureAccount()
  if username~='' then return end
  local v=ask('CUENTA DE AVENTURERO','Nombre (max 16):'):gsub('[^%w_%-]',''):sub(1,16)
  username=v~='' and v or ('Aventurero'..os.getComputerID())
  save('classic_account.dat',{user=username})
end
local function beep(which)
  if not opts.sfx or not speaker then return end
  local sounds={hit={'bass',.42,8},attack={'hat',.12,16},heal={'chime',.55,19},rune={'chime',.4,23},
    chest={'harp',.6,24},floor={'chime',.75,22},trap={'basedrum',.65,7},empty={'hat',.15,4},
    ready={'harp',.5,17},revive={'chime',.7,22},fail={'bass',.45,6}}
  local a=sounds[which] or sounds.attack
  pcall(function() speaker.playNote(a[1],a[2],a[3]) end)
end
local function send(m)
  if serverId and rednet then pcall(rednet.send,serverId,m,PROTO) end
end
local function discover()
  serverId=nil;serverInfo=nil
  if #modems==0 then return false end
  rednet.broadcast({type='DISCOVER'},PROTO)
  local timer=os.startTimer(1.35)
  while true do
    local event,a,b,c=os.pullEventRaw()
    if event=='rednet_message' and c==PROTO and type(b)=='table' and b.type=='INFO' then
      serverId=a;serverInfo=b;return true
    elseif event=='timer' and a==timer or event=='terminate' then return false end
  end
end
local function request(m,reply,time)
  if not serverId then return nil,'Servidor desconectado' end
  send(m)
  local timer=os.startTimer(time or 3)
  while true do
    local ev,a,b,c=os.pullEventRaw()
    if ev=='timer' and a==timer then return nil,'Tiempo de espera agotado' end
    if ev=='terminate' then return nil,'Cancelado' end
    if ev=='rednet_message' and a==serverId and c==PROTO and type(b)=='table' then
      if b.type==reply then return b end
      if b.type=='NOTICE' or b.type=='REJECT' then return nil,b.text or 'Rechazado' end
    end
  end
end
local function leaderBoard()
  textScreen('RANKING MUNDIAL',{'Consultando servidor...'})
  if not serverId then discover() end
  local msg=request({type='REQ_LEADERBOARD'},'LEADERBOARD',2.2)
  local lines={}
  if msg and type(msg.scores)=='table' then
    local list={}
    for name,v in pairs(msg.scores) do
      if type(name)=='string' then
        list[#list+1]={name=name,score=type(v)=='table' and (v.best or 0) or (tonumber(v) or 0),
          floor=type(v)=='table' and (v.bestFloor or 0) or 0}
      end
    end
    table.sort(list,function(a,b) return a.score>b.score end)
    for i=1,math.min(9,#list) do
      local p=list[i]
      lines[#lines+1]={('%d. %-16s  %d pts  P%d'):format(i,p.name,p.score,p.floor),
        p.name==username and colors.cyan or (friends[p.name] and colors.lime or colors.white)}
    end
    if #lines==0 then lines={'Aun no hay registros.'} end
  else lines={'No se pudo consultar el ranking.'} end
  lines[#lines+1]='';lines[#lines+1]='Pulsa una tecla.'
  textScreen('RANKING MUNDIAL',lines);keyInput()
end
local function friendMenu()
  while true do
    local names={};for n in pairs(friends) do names[#names+1]=n end;table.sort(names)
    local lines={'Amigos locales: '..#names}
    for i=1,math.min(#names,7) do lines[#lines+1]='* '..names[i] end
    if #names==0 then lines[#lines+1]='Lista vacia' end
    lines[#lines+1]='';lines[#lines+1]='[A] Anadir  [B] Borrar  [ESC] Volver'
    textScreen('AMIGOS',lines)
    local k=keyInput()
    if k==keys.escape then return end
    if k==keys.a or k==keys.b then
      local name=ask(k==keys.a and 'ANADIR AMIGO' or 'BORRAR AMIGO','Nombre exacto:')
        :gsub('[^%w_%-]',''):sub(1,16)
      if name~='' then friends[name]=k==keys.a or nil;save('classic_friends.dat',friends) end
    end
  end
end
local function settings()
  while true do
    textScreen('CONFIGURACION',{
      '[M] Musica: '..(opts.music and 'SI' or 'NO'),
      '[S] Sonido: '..(opts.sfx and 'SI' or 'NO'),
      '[T] Calidad automatica: '..(opts.auto and 'SI' or 'NO'),
      '[V] Minimap inicial: '..(opts.minimap and 'SI' or 'NO'),
      '[2] Escala 2 (mas nitida)',
      '[3] Escala 3 (equilibrada)',
      '[4] Escala 4 (mas rapida)',
      'Escala actual: '..(opts.scale or 3),
      '','[ESC] Volver'
    })
    local k=keyInput()
    if k==keys.escape then return end
    if k==keys.m then opts.music=not opts.music
    elseif k==keys.s then opts.sfx=not opts.sfx
    elseif k==keys.t then opts.auto=not opts.auto
    elseif k==keys.v then opts.minimap=not opts.minimap
    elseif k==keys.two then opts.scale=2
    elseif k==keys.three then opts.scale=3
    elseif k==keys.four then opts.scale=4 end
    save('classic_options.dat',opts)
  end
end
local function mainMenu()
  while true do
    discover()
    local online=serverId and ('ONLINE #'..serverId..' ['..(serverInfo.mode or '-')..']') or 'SERVIDOR OFFLINE'
    local announce=serverInfo and serverInfo.announcement or nil
    local notice=announce and announce.enabled and announce.text or 'Cada piso sera diferente'
    textScreen('MENU PRINCIPAL',{
      {'@'..username..'  '..online,colors.lightBlue},'',
      {'[1] SUPERVIVENCIA EN SOLITARIO',colors.lime},
      {'[2] CREAR SALA COOP / PVP',colors.lime},
      {'[3] UNIRSE A UNA SALA',colors.lime},
      {'[4] EVENTO GLOBAL (HASTA 8)',colors.yellow},
      {'[5] SALIR',colors.red},'',
      '[L] Clasificacion  [F] Amigos  [O] Ajustes',
      '[U] Cambiar nombre  [R] Reconectar',
      'Mejor marca: '..(localStats.best or 0)..' / Piso '..(localStats.floor or 0)
    },notice)
    local k=keyInput()
    if k==keys.one then return 'SINGLE'
    elseif k==keys.two then return 'HOST'
    elseif k==keys.three then return 'JOIN'
    elseif k==keys.four then return 'EVENT'
    elseif k==keys.five or k==keys.escape then return 'EXIT'
    elseif k==keys.l then leaderBoard()
    elseif k==keys.f then friendMenu()
    elseif k==keys.o then settings()
    elseif k==keys.u then username='';ensureAccount()
    end
  end
end
local function characterSelect()
  textScreen('ELIGE TU CLASE',{
    '[1] GUERRERO - espada potente, 100 vida',
    '[2] CAZADOR  - velocidad y mana',
    '[3] MAGO    - magia potente, menos vida',
    '','Todas las clases son jugables en cooperativo.',
    '[ESC] Cancelar'
  })
  while true do
    local k=keyInput()
    if k==keys.one then return 'GUERRERO'
    elseif k==keys.two then return 'CAZADOR'
    elseif k==keys.three then return 'MAGO'
    elseif k==keys.escape then return nil end
  end
end
local function difficultySelect()
  textScreen('DIFICULTAD / TIPO',{
    '[A] NORMAL - enemigos equilibrados',
    '[B] HARD   - mas duros y letales',
    '[C] PVP    - mazmorra competitiva',
    '', 'PvP necesita al menos 2 aventureros',
    '[ESC] Cancelar'
  })
  while true do
    local k=keyInput()
    if k==keys.a then return 'NORMAL'
    elseif k==keys.b then return 'HARD'
    elseif k==keys.c then return 'PVP'
    elseif k==keys.escape then return nil end
  end
end
local currentFloor=nil
local function drawFallback(s,id)
  local me=s.players and s.players[tostring(id)]
  local map=currentFloor and currentFloor.map
  if not me or not map then return end
  local w,h=term.getSize()
  term.setBackgroundColor(colors.black);term.setTextColor(colors.white);term.clear()
  term.setCursorPos(1,1);term.setTextColor(colors.cyan)
  print('CLASSIC DUNGEONS - MODO TEXTO')
  term.setTextColor(colors.white)
  print(('P%d HP%d M%d | %s'):format(s.floor,me.hp,me.mana,me.user))
  local cx,cy=math.floor(me.x)+1,math.floor(me.y)+1
  local height=math.max(3,math.min(#map,h-6))
  local width=math.max(3,math.min(#map[1],w-2))
  for y=1,height do
    local my=cy+ y-math.floor(height/2)-1
    local row={}
    for x=1,width do
      local mx=cx+x-math.floor(width/2)-1
      local t=map[my] and map[my]:sub(mx,mx) or '#'
      local chr=t=='X' and '>' or t=='.' and ' ' or '#'
      if mx==cx and my==cy then chr='@' end
      for _,e in ipairs(s.enemies or {}) do
        if math.floor(e.x)+1==mx and math.floor(e.y)+1==my then chr='m' end
      end
      for _,r in ipairs(s.runes or {}) do
        if math.floor(r.x)+1==mx and math.floor(r.y)+1==my then chr=tostring(r.n) end
      end
      row[#row+1]=chr
    end
    term.setCursorPos(1,2+y);term.write(table.concat(row))
  end
  term.setCursorPos(1,h);term.write(('WASD Q/C ESP F E H R ESC'):sub(1,w))
end
local function play(pid,active,isHost)
  local state=nil;local running=true;local started=active
  local ticker=os.startTimer(.16);local ping=os.startTimer(1.4);local melody=os.startTimer(.75)
  local notes={12,15,17,15,10,12,8,10};local note=0
  local lastHp=nil;local lastFloor=0
  local pressed={}
  local mappings={[keys.w]='w',[keys.up]='w',[keys.s]='s',[keys.down]='s',
    [keys.a]='a',[keys.left]='a',[keys.d]='d',[keys.right]='d',[keys.q]='q',[keys.c]='c'}
  local rendererAPI=nil
  local lastRender=nil
  local graphicsFailed=false
  currentFloor=nil
  local renderFile=loadfile(fs.combine(LIB,'classic_dungeons_renderer.lua'))
  if renderFile then local ok,res=pcall(renderFile);if ok and type(res)=='table' then rendererAPI=res end end
  if not started then
    textScreen('SALA MULTIJUGADOR',{
      isHost and 'SALA CREADA - espera a tus amigos' or 'Esperando al anfitrion...',
      isHost and '[ENTER] COMENZAR LA EXPEDICION' or 'El anfitrion inicia la expedicion',
      '[ESC] Salir de la sala','', 'Cada jugador necesita un ordenador y modem.'})
  end
  local function beginGraphics()
    if renderer or not rendererAPI or graphicsFailed then return end
    local ok,r,err=pcall(rendererAPI.open,LIB,opts.scale or 3)
    if ok and r then
      renderer=r
      if currentFloor then renderer:setFloor(currentFloor) end
      renderer.mini=opts.minimap
      if renderer.world then renderer.world.minimap=opts.minimap end
      if state then renderer:setState(state,pid) end
      if not opts.auto then renderer:qualityLevel(opts.quality or 2) end
    else
      graphicsFailed=true
      stopGraphics()
      textScreen('CC: GRAPHICS NO DISPONIBLE',{
        'Se usara el mapa de caracteres.',
        'Instala CC: Graphics para jugar en 3D.',
        'Error: '..tostring(err or r):sub(1,38)})
    end
  end
  while running do
    local ev,a,b,c=os.pullEventRaw()
    if ev=='terminate' then running=false
    elseif ev=='timer' and a==ping then
      send({type='PING'});ping=os.startTimer(1.4)
    elseif ev=='timer' and a==ticker then
      ticker=os.startTimer(.16)
      if started and state and currentFloor then
        if renderer then
          local now=(os.epoch and os.epoch('utc')/1000) or os.clock()
          local fps=lastRender and (1/math.max(.03,now-lastRender)) or 0
          lastRender=now
          local ok,success,err=pcall(function() return renderer:render(fps) end)
          if not ok or success==false then
            local reason=not ok and success or err
            graphicsFailed=true
            stopGraphics()
            textScreen('ERROR GRAFICO - MODO TEXTO',{'WorldTor 3: '..tostring(reason):sub(1,42)})
          end
        else drawFallback(state,pid) end
      end
    elseif ev=='timer' and a==melody then
      melody=os.startTimer(.75)
      if started and opts.music and speaker then
        note=note%#notes+1
        pcall(function() speaker.playNote('harp',.07,notes[note]) end)
      end
    elseif ev=='rednet_message' and a==serverId and c==PROTO and type(b)=='table' then
      if b.type=='START' then started=true;beep('ready')
      elseif b.type=='FLOOR' then
        currentFloor=b
        if not renderer and started then beginGraphics() end
        if renderer then
          local ok,reason=pcall(function() renderer:setFloor(b) end)
          if not ok then graphicsFailed=true;stopGraphics();textScreen('ERROR DE MAPA',{tostring(reason)}) end
        end
        lastFloor=b.floor;beep('floor')
        if renderer and state and state.floor==b.floor then renderer:setState(state,pid) end
      elseif b.type=='STATE' then
        state=b;started=true
        if currentFloor and currentFloor.floor==state.floor then
          if not renderer then beginGraphics() end
          if renderer then renderer:setState(state,pid) end
        end
        local me=state.players and state.players[tostring(pid)]
        if me and lastHp and me.hp<lastHp then beep('hit') end
        if me then lastHp=me.hp end
      elseif b.type=='PAUSE' then if state then state.paused=b.paused end
      elseif b.type=='ANNOUNCEMENT' then if serverInfo then serverInfo.announcement=b.data end
      elseif b.type=='SFX' then
        beep(b.sound)
        if renderer then renderer:effect(b.sound) end
      elseif b.type=='NOTICE' then
        if not started then textScreen('AVISO',{b.text or 'Aviso'}) end
      elseif b.type=='GAME_OVER' then
        stopGraphics()
        local entries=b.results or {}
        local mine=state and state.players and state.players[tostring(pid)]
        local score=mine and mine.score or 0
        localStats.runs=(localStats.runs or 0)+1
        localStats.last=score;localStats.best=math.max(localStats.best or 0,score)
        localStats.kills=(localStats.kills or 0)+(mine and mine.kills or 0)
        localStats.floor=math.max(localStats.floor or 0,b.floor or 1)
        save('classic_local.dat',localStats)
        local rows={'Piso alcanzado: '..(b.floor or 1),'Puntos: '..score,
          'Motivo: '..tostring(b.reason or 'Expedicion terminada'),''}
        for i=1,math.min(#entries,5) do rows[#rows+1]=i..'. '..entries[i].user..' / '..entries[i].score end
        rows[#rows+1]='';rows[#rows+1]='Pulsa una tecla para volver'
        textScreen('FIN DE EXPEDICION',rows);keyInput();running=false
      elseif b.type=='RETURN_MENU' or b.type=='CANCEL' or b.type=='SHUTDOWN' then
        stopGraphics()
        if b.type=='SHUTDOWN' then textScreen('SERVIDOR CERRADO',{b.text or 'Desconectado'});keyInput() end
        running=false
      end
    elseif ev=='key' then
      if a==keys.escape then running=false
      elseif not started then
        if isHost and a==keys.enter then send({type='START'}) end
      else
        if mappings[a] and not pressed[mappings[a]] then
          pressed[mappings[a]]=true;send({type='KEY',key=mappings[a],down=true})
        elseif a==keys.space then send({type='ACTION',action='MELEE'})
        elseif a==keys.f then send({type='ACTION',action='SPELL'})
        elseif a==keys.e then send({type='ACTION',action='INTERACT'})
        elseif a==keys.h then send({type='ACTION',action='POTION'})
        elseif a==keys.r then send({type='ACTION',action='REVIVE'})
        elseif a==keys.p then send({type='PAUSE'})
        elseif a==keys.m and renderer then renderer:toggleMap()
        elseif a==keys.one and renderer then renderer:qualityLevel(1)
        elseif a==keys.two and renderer then renderer:qualityLevel(2)
        elseif a==keys.three and renderer then renderer:qualityLevel(3)
        elseif a==keys.t and renderer then renderer:toggleAuto()
        end
      end
    elseif ev=='key_up' and started then
      if mappings[a] and pressed[mappings[a]] then
        pressed[mappings[a]]=nil;send({type='KEY',key=mappings[a],down=false})
      end
    elseif ev=='mouse_click' and started then
      if a==1 then send({type='ACTION',action='MELEE'})
      elseif a==2 then send({type='ACTION',action='SPELL'}) end
    elseif ev=='term_resize' and renderer then
      local ok=pcall(function() renderer:resize() end)
      if not ok then stopGraphics() end
    end
  end
  stopGraphics()
  send({type='LEAVE'})
end
local function main()
  ensureAccount()
  while true do
    local gameMode=mainMenu()
    if gameMode=='EXIT' then break end
    local class=characterSelect()
    if class then
      local diff='NORMAL'
      if gameMode=='SINGLE' or gameMode=='HOST' then diff=difficultySelect() end
      if diff then
        if not serverId then discover() end
        if not serverId then
          textScreen('NO HAY SERVIDOR',{'Classic Dungeons necesita su servidor.',
            'En otro ordenador ejecuta:','classic_dungeons_server',
            'Conecta modems a ambos ordenadores.','', 'Pulsa una tecla para volver.'})
          keyInput()
        else
          textScreen('CONECTANDO',{'Jugador: '..username,'Clase: '..class,'Modo: '..gameMode})
          local result,err=request({type='JOIN',mode=gameMode,user=username,class=class,diff=diff},'ACCEPT',3.5)
          if result then
            play(result.pid,result.round=='RUNNING',gameMode=='HOST')
          else
            textScreen('NO SE PUDO ENTRAR',{tostring(err or 'Error desconocido'),'',
              'Verifica el modo NORMAL/EVENTO.', 'Pulsa una tecla.'});keyInput()
          end
        end
      end
    end
  end
  textScreen('WORLD STUDIOS',{'Gracias por jugar a CLASSIC DUNGEONS!',
    'Powered by WorldTor 3'})
end
local ok,reason=xpcall(main,function(err)
  if debug and debug.traceback then return debug.traceback(err,2) end
  return tostring(err)
end)
stopGraphics()
if not ok then term.clear();term.setCursorPos(1,1);printError('CLASSIC DUNGEONS: '..tostring(reason)) end
