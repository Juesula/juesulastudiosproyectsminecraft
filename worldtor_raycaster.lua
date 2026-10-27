-- WorldTor 2.1 | Modulo de raycasting 2.5D para CC: Graphics
-- El motor se ocupa de DDA, profundidad, sprites, IA, colisiones, disparos, puertas y render.
-- API: local Ray = assert(loadfile('worldtor_raycaster.lua'))()(WorldTor)
--      local game=Ray.new(gfx, config);game:update(dt,pressed);game:draw(fps)
return function(WT)
  assert(type(WT)=='table' and type(WT.newCanvas)=='function', 'Requiere WorldTor 2.1')
  local floor,ceil,abs,min,max,sqrt=math.floor,math.ceil,math.abs,math.min,math.max,math.sqrt
  local sin,cos,tan,pi=math.sin,math.cos,math.tan,math.pi
  local TWO_PI=pi*2
  local function clamp(v,a,b) return min(b,max(a,v)) end
  local function len(dx,dy) return sqrt(dx*dx+dy*dy) end
  local function copyEntities(list)
    local out={}
    for _,e in ipairs(list or {}) do
      local b={}
      for k,v in pairs(e) do b[k]=v end
      out[#out+1]=b
    end
    return out
  end
  local COLORS={
    ['1']={'#8993A7','#65728A','#445267','#253345'},
    ['2']={'#C69162','#A06C43','#785033','#473327'},
    ['3']={'#608EA1','#466F83','#304F68','#20374C'},
    D={'#B7AB73','#867947','#63572F','#443C24'}
  }
  local function new(gfx,config)
    config=config or {}
    assert(gfx and gfx.backend=='ccgraphics', 'WorldTor DOOM necesita CC: Graphics (modo grafico)')
    assert(type(config.map)=='table' and #config.map>=3, 'Mapa invalido')
    local width=#config.map[1]
    for i,r in ipairs(config.map) do assert(#r==width,'Fila '..i..' tiene longitud distinta') end
    local self={gfx=gfx, original=config.map, map={}, doors={}, entities=copyEntities(config.entities),
      player={x=config.x or 2.5,y=config.y or 2.5,angle=config.angle or 0,
        hp=100,ammo=24,score=0,kills=0},
      fov=pi/3, rays=0, renderStep=max(1,min(4,config.renderStep or 2)),
      time=0,attack=0,damageFlash=0,msg='',messageUntil=0,
      mapVisible=false, state='playing', hitDistance=22, speed=2.65, turnSpeed=2.5,
      killsRequired=0, lastDepth={}, nearCount=0, frame=0}
    for row,chars in ipairs(self.original) do
      self.map[row]=chars
      for col=1,#chars do if chars:sub(col,col)=='D' then self.doors[(col-1)..','..(row-1)]=false end end
    end
    for _,e in ipairs(self.entities) do
      if e.kind=='enemy' then
        e.hp=e.hp or 2;e.speed=e.speed or .58;e.cooldown=0;e.radius=.25
        self.killsRequired=self.killsRequired+1
      end
    end
    function self:tile(x,y)
      local ix,iy=floor(x)+1,floor(y)+1
      if iy<1 or iy>#self.map or ix<1 or ix>width then return '1' end
      return self.map[iy]:sub(ix,ix)
    end
    function self:solid(x,y)
      local t=self:tile(x,y)
      if t=='D' then return not self.doors[floor(x)..','..floor(y)] end
      return t~='.' and t~='X' and t~=' ' and t~='H' and t~='A'
    end
    function self:canStand(x,y,rad)
      rad=rad or .23
      return not (self:solid(x-rad,y-rad) or self:solid(x+rad,y-rad) or
         self:solid(x-rad,y+rad) or self:solid(x+rad,y+rad))
    end
    function self:move(obj,dx,dy,rad)
      local x,y=obj.x,obj.y
      if self:canStand(x+dx,y,rad) then obj.x=x+dx end
      if self:canStand(obj.x,y+dy,rad) then obj.y=y+dy end
    end
    function self:ray(x,y,dirX,dirY,maxDistance)
      maxDistance=maxDistance or 24
      local mapX,mapY=floor(x),floor(y)
      local deltaX=dirX==0 and 1e30 or abs(1/dirX)
      local deltaY=dirY==0 and 1e30 or abs(1/dirY)
      local stepX,stepY,sideX,sideY
      if dirX<0 then stepX=-1;sideX=(x-mapX)*deltaX
      else stepX=1;sideX=(mapX+1-x)*deltaX end
      if dirY<0 then stepY=-1;sideY=(y-mapY)*deltaY
      else stepY=1;sideY=(mapY+1-y)*deltaY end
      local side=0
      for _=1,48 do
        if sideX<sideY then sideX=sideX+deltaX;mapX=mapX+stepX;side=0
        else sideY=sideY+deltaY;mapY=mapY+stepY;side=1 end
        local distance=(side==0 and sideX-deltaX or sideY-deltaY)
        if distance>maxDistance then return maxDistance,nil,side,0 end
        if self:solid(mapX+.5,mapY+.5) then
          local hit=side==0 and (y+distance*dirY) or (x+distance*dirX)
          hit=hit-floor(hit)
          return max(.05,distance),self:tile(mapX+.5,mapY+.5),side,hit
        end
      end
      return maxDistance,nil,0,0
    end
    function self:lineOfSight(x1,y1,x2,y2)
      local dx,dy=x2-x1,y2-y1
      local distance=len(dx,dy)
      if distance<.01 then return true end
      local wall=self:ray(x1,y1,dx/distance,dy/distance,distance+.02)
      return wall>=distance-.06
    end
    function self:interaction()
      if self.state~='playing' then return end
      local p=self.player
      for dist=.25,1.5,.20 do
        local x=p.x+cos(p.angle)*dist
        local y=p.y+sin(p.angle)*dist
        if self:tile(x,y)=='D' then
          self.doors[floor(x)..','..floor(y)]=true
          self.msg='PUERTA ABIERTA';self.messageUntil=self.time+1.7
          return
        elseif self:solid(x,y) then break end
      end
      self.msg='NO HAY PUERTA';self.messageUntil=self.time+.8
    end
    function self:shoot()
      if self.state~='playing' then return end
      local p=self.player
      if p.ammo<=0 then
        self.msg='SIN MUNICION';self.messageUntil=self.time+.8;return
      end
      if self.attack>0 then return end
      p.ammo=p.ammo-1;self.attack=.21
      local wallDist=self:ray(p.x,p.y,cos(p.angle),sin(p.angle),23)
      local best,bestDist
      for _,e in ipairs(self.entities) do
        if e.kind=='enemy' and e.hp>0 then
          local dx,dy=e.x-p.x,e.y-p.y
          local depth=dx*cos(p.angle)+dy*sin(p.angle)
          local side=abs(-dx*sin(p.angle)+dy*cos(p.angle))
          if depth>.1 and depth<wallDist+.05 and side<.23+depth*.015
                and (not bestDist or depth<bestDist) then
            best=e;bestDist=depth
          end
        end
      end
      if best then
        best.hp=best.hp-1;best.hurt=.2
        self.msg='IMPACTO';self.messageUntil=self.time+.45
        if best.hp<=0 then p.kills=p.kills+1;p.score=p.score+100;self.msg='ENEMIGO ELIMINADO' end
      end
    end
    function self:update(dt,pressed)
      dt=clamp(dt or .05,0,.11)
      pressed=pressed or {}
      self.time=self.time+dt
      if self.attack>0 then self.attack=max(0,self.attack-dt) end
      if self.damageFlash>0 then self.damageFlash=max(0,self.damageFlash-dt) end
      if self.state~='playing' then return end
      local p=self.player
      local ang=p.angle
      local turn=0
      if pressed.left or pressed.a then turn=turn-1 end
      if pressed.right or pressed.d then turn=turn+1 end
      p.angle=(ang+turn*dt*self.turnSpeed)%TWO_PI
      local movement=0;local strafe=0
      if pressed.w or pressed.up then movement=movement+1 end
      if pressed.s or pressed.down then movement=movement-1 end
      if pressed.q then strafe=strafe-1 end
      if pressed.f then strafe=strafe+1 end
      if movement~=0 or strafe~=0 then
        local norm=max(1,len(movement,strafe))
        local vel=self.speed*dt/norm
        local ca,sa=cos(p.angle),sin(p.angle)
        self:move(p,(ca*movement-sa*strafe)*vel,(sa*movement+ca*strafe)*vel,.22)
      end
      if self:tile(p.x,p.y)=='X' and p.kills>=self.killsRequired then
        self.state='won';self.msg='MISIÓN COMPLETADA';return
      elseif self:tile(p.x,p.y)=='X' then
        self.msg='ELIMINA A TODOS LOS ENEMIGOS';self.messageUntil=self.time+1.2
      end
      for _,e in ipairs(self.entities) do
        if e.kind=='enemy' and e.hp>0 then
          e.cooldown=max(0,(e.cooldown or 0)-dt)
          e.hurt=max(0,(e.hurt or 0)-dt)
          local dx,dy=p.x-e.x,p.y-e.y
          local distance=len(dx,dy)
          if distance<6.5 and self:lineOfSight(e.x,e.y,p.x,p.y) then
            if distance>.70 then
              self:move(e,dx/max(distance,.01)*e.speed*dt,dy/max(distance,.01)*e.speed*dt,.24)
            elseif e.cooldown==0 then
              p.hp=max(0,p.hp-10)
              e.cooldown=1.15;self.damageFlash=.28
              self.msg='TE HAN GOLPEADO';self.messageUntil=self.time+.7
              if p.hp<=0 then self.state='lost';self.msg='HAS MUERTO' end
            end
          end
        elseif e.kind=='medkit' and not e.picked and len(e.x-p.x,e.y-p.y)<.52 then
          p.hp=min(100,p.hp+30);e.picked=true;self.msg='BOTIQUIN +30';self.messageUntil=self.time+1
        elseif e.kind=='ammo' and not e.picked and len(e.x-p.x,e.y-p.y)<.52 then
          p.ammo=p.ammo+12;e.picked=true;self.msg='MUNICION +12';self.messageUntil=self.time+1
        end
      end
    end
    -- Profundidad y proyeccion 3D administradas por el motor.
    function self:project(entity,cx,cy,dirX,dirY,planeX,planeY,w,h)
      local relX,relY=entity.x-self.player.x,entity.y-self.player.y
      local determinant=planeX*dirY-dirX*planeY
      if abs(determinant)<.00001 then return nil end
      local inv=1/determinant
      local transX=inv*(dirY*relX-dirX*relY)
      local transY=inv*(-planeY*relX+planeX*relY)
      if transY<=.12 then return nil end
      local screenX=floor((w/2)*(1+transX/transY))
      local spriteH=max(1, floor(h/transY*.72))
      local spriteW=max(1,floor(spriteH*.52))
      if screenX+spriteW<1 or screenX-spriteW>w then return nil end
      return {x=screenX,y=floor((h-spriteH)/2),w=spriteW,h=spriteH,depth=transY,entity=entity}
    end
    function self:draw(fps)
      local gfx=self.gfx
      if self.state~='playing' and self.state~='won' and self.state~='lost' then return end
      local w,h=gfx.w,gfx.h
      local horizon=floor(h*.49)
      gfx:camera(0,0)
      gfx:clear('#161C2D')
      gfx:fill(1,1,w,max(1,floor(horizon*.42)),'#11182A',true)
      gfx:fill(1,floor(horizon*.42),w,horizon-floor(horizon*.42)+1,'#26364E',true)
      gfx:fill(1,horizon+1,w,h-horizon,'#302A31',true)
      gfx:fill(1,horizon+floor((h-horizon)*.42),w,ceil((h-horizon)*.58),'#252228',true)
      local p=self.player
      local dirX,dirY=cos(p.angle),sin(p.angle)
      local planeX,planeY=-dirY*tan(self.fov/2),dirX*tan(self.fov/2)
      local step=self.renderStep
      self.rays=0
      for x=1,w,step do
        local cameraX=2*((x+min(step,w-x+1)*.5-1)/w)-1
        local rayX,rayY=dirX+planeX*cameraX,dirY+planeY*cameraX
        local distance,hit,side,wallX=self:ray(p.x,p.y,rayX,rayY,self.hitDistance)
        local wallH=min(h*3,max(1,floor(h/max(.10,distance))))
        local top=floor((h-wallH)/2)
        local shade=distance<2.6 and 1 or distance<4.7 and 2 or distance<7.5 and 3 or 4
        local colors=COLORS[hit] or COLORS['1']
        if side==1 then shade=min(4,shade+1) end
        local fill=colors[shade]
        if hit then
          gfx:fill(x,max(1,top),min(step,w-x+1),min(h,top+wallH-1)-max(1,top)+1,fill,true)
          if wallX<.075 or wallX>.925 then
            local edge=COLORS['1'][min(4,shade+1)]
            gfx:fill(x,max(1,top),1,min(h,top+wallH-1)-max(1,top)+1,edge,true)
          end
          if hit=='D' then
            local yline=max(1,top+floor(wallH*.28))
            if yline<=h then gfx:fill(x,yline,min(step,w-x+1),1,'#E1C378',true) end
          end
        end
        for off=0,step-1 do if x+off<=w then self.lastDepth[x+off]=distance end end
        self.rays=self.rays+1
      end
      local sorted={}
      for _,e in ipairs(self.entities) do
        if not e.picked and (e.kind~='enemy' or e.hp>0) then
          local dx=e.x-p.x;local dy=e.y-p.y
          sorted[#sorted+1]={entity=e,dist=dx*dx+dy*dy}
        end
      end
      table.sort(sorted,function(a,b) return a.dist>b.dist end)
      for _,item in ipairs(sorted) do
        local obj=self:project(item.entity,nil,nil,dirX,dirY,planeX,planeY,w,h)
        if obj then
          local e=obj.entity
          local x0=max(1,floor(obj.x-obj.w/2))
          local x1=min(w,ceil(obj.x+obj.w/2))
          local y0=max(1,obj.y);local y1=min(h,obj.y+obj.h)
          for x=x0,x1 do
            if obj.depth<(self.lastDepth[x] or 100)-.06 then
              local tex=(x-(obj.x-obj.w/2))/max(1,obj.w)
              if tex>.05 and tex<.95 then
                if e.kind=='enemy' then
                  local hurt=(e.hurt or 0)>0
                  local face=hurt and '#FFFFFF' or '#AA4D67'
                  local body=hurt and '#FFDDDD' or '#6E244B'
                  gfx:fill(x,max(1,obj.y),1,max(1,floor(obj.h*.35)),face,true)
                  gfx:fill(x,max(1,obj.y+floor(obj.h*.35)),1,max(1,floor(obj.h*.55)),body,true)
                  if tex>.26 and tex<.38 or tex>.62 and tex<.74 then
                    gfx:fill(x,max(1,obj.y+floor(obj.h*.18)),1,max(1,floor(obj.h*.09)),'#FFED68',true)
                  end
                else
                  local color=e.kind=='medkit' and '#64D9A3' or '#EED171'
                  gfx:fill(x,max(1,obj.y+floor(obj.h*.36)),1,max(1,floor(obj.h*.45)),color,true)
                  if e.kind=='medkit' and tex>.42 and tex<.58 then
                    gfx:fill(x,max(1,obj.y+floor(obj.h*.46)),1,max(1,floor(obj.h*.22)),'#FFFFFF',true)
                  end
                end
              end
            end
          end
        end
      end
      -- Mano y arma en primer plano: el jugador no necesita dibujar la UI.
      local gunW=max(9,floor(w*.24))
      local gx=floor((w-gunW)/2)
      local gunY=max(1,h-floor(h*.24))
      local flash=self.attack>.08
      gfx:fill(gx+floor(gunW*.22),gunY+2, floor(gunW*.55),h-gunY,'#31333F',true)
      gfx:fill(gx+floor(gunW*.36),gunY, max(2,floor(gunW*.26)),h-gunY,'#727F8D',true)
      gfx:fill(gx+floor(gunW*.45),gunY, max(1,floor(gunW*.09)),max(2,floor(h*.07)),'#D8D4B0',true)
      if flash then
        gfx:circle(floor(w/2),max(2,gunY-4),max(2,floor(w*.035)),'#FFE76C',true,true)
      end
      local mx,my=floor(w/2),floor(h/2)
      gfx:line(mx-3,my,mx-1,my,'#ECE5C7',true)
      gfx:line(mx+1,my,mx+3,my,'#ECE5C7',true)
      gfx:line(mx,my-3,mx,my-1,'#ECE5C7',true)
      gfx:line(mx,my+1,mx,my+3,'#ECE5C7',true)
      gfx:fill(1,1,w,8,'#111824',true)
      gfx:text(2,2,'WORLD DOOM', '#E69A71',1,true)
      gfx:fill(1,h-8,w,8,'#111824',true)
      gfx:text(2,h-7,'HP'..p.hp..' A'..p.ammo..' K'..p.kills..'/'..self.killsRequired,
        '#EAD9BE',1,true)
      if w>=75 then gfx:text(w-26,2,'FPS '..floor(fps or 0), '#8CE0D7',1,true) end
      if self.msg~='' and self.time<self.messageUntil then
        gfx:fill(1,10,w,8,'#111824',true)
        gfx:center(11,self.msg,'#F4CF8A',1)
      end
      if self.damageFlash>0 then
        gfx:box(1,9,w,h-17,'#FF3344',true)
      end
      if self.mapVisible then
        local tiles=3
        local size=min(10,#self.map)
        local px=floor(p.x);local py=floor(p.y)
        local startX=max(1,w-size*tiles-2)
        local startY=10
        gfx:fill(startX-1,startY-1,size*tiles+2,size*tiles+2,'#091019',true)
        for gy=0,size-1 do
          for gx=0,size-1 do
            local wx=px+gx-floor(size/2);local wy=py+gy-floor(size/2)
            local t=self:tile(wx+.5,wy+.5)
            local c=(t=='1' or t=='2' or t=='3') and '#71818B' or t=='D' and '#C79A47' or t=='X' and '#4CE6A4' or '#26354A'
            gfx:fill(startX+gx*tiles,startY+gy*tiles,tiles-1,tiles-1,c,true)
          end
        end
        gfx:fill(startX+floor(size/2)*tiles,startY+floor(size/2)*tiles,2,2,'#F6C46B',true)
      end
      if self.state~='playing' then
        local panelTop=max(2,floor(h*.18))
        gfx:fill(3,panelTop,w-6,min(h-panelTop,max(24,floor(h*.72))),'#101626',true)
        gfx:center(panelTop+3,self.state=='won' and 'VICTORIA' or 'GAME OVER',
          self.state=='won' and '#60E9B4' or '#F17979',2)
        gfx:center(panelTop+16,'R REINICIAR', '#EED6AA',1)
        gfx:center(panelTop+23,'ESC SALIR', '#EED6AA',1)
      end
      self.frame=self.frame+1
      return gfx:flip()
    end
    function self:reset()
      local fresh=new(gfx,config)
      for k,v in pairs(fresh) do self[k]=v end
    end
    assert(self:canStand(self.player.x,self.player.y,.22),'Jugador empieza dentro de una pared')
    return self
  end
  return {new=new}
end
