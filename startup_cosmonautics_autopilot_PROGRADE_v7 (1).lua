--[[
COSMONAUTICS AUTOPILOT v8 - revision of PROGRADE_v7, 2026-09-27
Minecraft 1.21.1 / Cosmonautics tag 26.08.307, commit
53730e0c5e3d03db4666cb5b844b276862bea7c8.

DIAGNOSTICO (fuente oficial, no conjeturas sobre velocidades):
* SpaceTransitionHandler: warp al superar Y=20000; posicion inicial con
  Y+1000. DeepSpaceHelper: v_orbita = rot(v_Sable) + r x omega.
* PlanetDefinitionBuilder: mu=(11+omega^2*R)*R^2. Los 11 m/s2 NO son
  la gravedad orbital total. Sputnik.gravity permite obtener mu=g*r^2.
* SubLevelPhysicsSystemMixin: NO transfiere continuamente toda la fuerza
  a la orbita. Si 2*(distancia_al_centro+diagonal_nave)<=lado_caja,
  solo registra masa. Fuera: cancela velocidad saliente y media transversal;
  DeepSpaceInstance suma ese delta-v, ponderado por las masas registradas.
* ThrustBehaviour: impulso=-direccion_escape*F*dt, aplicado en un punto.
  Motores descentrados generan torque; LEFT/RIGHT deben TRASLADAR, no girar.
* DeepSpaceInstance: en CUBE, reentrada por distancia al CUBO ROTADO <20000.
  Sputnik.distanceToPlanet devuelve max(0,|r|-R), incluso en modo CUBE.
  Pe=23000 NO garantiza seguridad. Usamos envolvente sqrt(3)*R+20000+margen.
  Es conservadora para cualquier plano, rotacion y para SPHERE tambien.
* v7 LEFT/RIGHT ignoraba power; podia encender laterales fuertes al pedir
  correcciones pequenas. Ademas no contaba el delta-v local pendiente,
  conservaba datos obsoletos y podia atascar la recuperacion tras reentrada.

USO:
1. Guardar como startup.lua en el ordenador PRINCIPAL. Se mantiene el
   protocolo SPACECRAFT_THRUSTER y el DOWN local en front de v7.
2. Revisar CHANNEL: nombres de comandos significan FUERZA de la nave,
   no direccion de la tobera. +X RIGHT, -X LEFT, +Y UP, -Y DOWN,
   +Z FORWARD, -Z BACKWARD son la convencion heredada, NO una propiedad
   que Cosmonautics garantice. Adaptar a tu secundario si es diferente.
   Cada grupo debe dar traslacion sin torque (simetrico respecto al CoM).
3. Secundario: potencia persistente 0..1 por comando, STOP apaga TODO,
   HEARTBEAT responde {type='ACK'} por el mismo protocolo, watchdog >=1s.
   Min thrust=0 y control analogico proporcional. No usar comandos de giro.
4. CUBE es el valor predeterminado oficial. SPHERE permite aparcamiento
   bajo SOLO si has configurado realmente SPHERE en el servidor.
5. Transferencia lunar presupone universo ESTANDAR, tiempo espacial x1,
   una sola nave rigida por instancia y seis ejes con empuje suficiente.
   El API Sputnik NO expone forma, ephemeris arbitrarias ni caja/CoM.
   No puede garantizarse vuelo con un datapack distinto o hardware desconocido.
6. Registro flight_v8.log: transiciones, r,v,mu,Pe y velocidad local.
   Se conserva un archivo anterior al alcanzar 1 MiB.
7. A=parada manual, L=arrancar/reanudar, M=manual/auto, Q=salir,
   U=activar/desactivar autolanzamiento. No hay abortos automaticos.

VALIDACION: pruebas de Lua y simulacion reducida (Kepler + caja + redstone),
NO ejecutado en Minecraft ni verificado con el ordenador secundario del usuario.
Resultados del banco reducido: entradas a 80 y 650 m/s, grupos de motores
20 y 40 m/s2, caja de 64 m y diagonal de nave de 16 m: aparcamiento
Overworld sin cruzar d_cubo=20000; radio objetivo 5426 km. Transferencia
completa desde aparcamiento a captura lunar: Pe=1468.9 km desde el centro,
e=0.00595. Lambert contrastado por integracion independiente: error <1 m
en un caso de 6000 s. Tambien probados perdida de datos/enlace, reentrada
desde transferencia, >999 reintentos y error Lua recuperable.
Estos resultados NO certifican otro empuje, caja, nave o latencia del servidor.
Una estimacion de fuerza no sustituye a motores con empuje suficiente.

FUENTES: https://github.com/CosmonauticsTeam/Create-Cosmonautics/tree/
53730e0c5e3d03db4666cb5b844b276862bea7c8/src/main/java/dev/devce/rocketnautics/
 content/physics/SpaceTransitionHandler.java
 api/orbit/DeepSpaceHelper.java
 mixin/SubLevelPhysicsSystemMixin.java
 content/orbit/DeepSpaceInstance.java
 content/orbit/universe/StandardUniverseProvider.java
 content/orbit/universe/builder/PlanetDefinitionBuilder.java
 compat/computercraft/SputnikPeripheral.java
 content/blocks/SputnikBlockEntity.java; content/blocks/ThrustBehaviour.java
]]

local C = {
    SHAPE = "CUBE", -- CUBE conservador; SPHERE solo con servidor esferico
    MAIN_DOWN_SIDE = "front", SECONDARY_ID = nil,
    PROTOCOL = "SPACECRAFT_THRUSTER", HEARTBEAT = 0.25, LINK_TIMEOUT = 1.5,
    AUTO_LAUNCH = true, LAUNCH_DELAY = 3, TICK = 0.1,
    CHANNEL = {xp="RIGHT", xn="LEFT", yp="UP", yn="DOWN",
               zp="FORWARD", zn="BACKWARD"},
    -- Aceleracion inicial a potencia 1; aprende durante quemas estables.
    -- Ajustar si F/m conocido. Unidades m/s2, no N.
    ACCEL = {xp=20,xn=20,yp=20,yn=20,zp=20,zn=20},
    LEARN_ACCEL = true, CONTROL_TIME = 4, MAX_RADIAL_SPEED = 1200,
    TRANSITION = 20000, MARGIN = 30000, PARKING_CLEARANCE = 180000,
    MOON_PARKING_CLEARANCE = 120000, ORBIT_DV_TOL = 3,
    STABLE_SECONDS = 20, DATA_GRACE = 1.5,
    MOON_PERIOD = 28800, MOON_RADIUS = 750000, OW_RADIUS = 3000000,
    OW_DAY = 1200, OW_SURFACE_G = 11,
    -- Se apunta fuera de la envolvente lunar pero dentro de su SOI estandar.
    MOON_AIM_RADIUS = 1460000,
    TRANSFER_REPLAN = 8, MIDCOURSE_TOL = 8,
    LOG_FILE = "flight_v8.log", LOG_INTERVAL = 2,
}
local function finite(x) return type(x)=="number" and x==x and math.abs(x)<math.huge end
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
local function V(x,y,z) return {x=x or 0,y=y or 0,z=z or 0} end
local function add(a,b) return V(a.x+b.x,a.y+b.y,a.z+b.z) end
local function sub(a,b) return V(a.x-b.x,a.y-b.y,a.z-b.z) end
local function mul(a,s) return V(a.x*s,a.y*s,a.z*s) end
local function dot(a,b) return a.x*b.x+a.y*b.y+a.z*b.z end
local function cross(a,b) return V(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x) end
local function norm(a) return math.sqrt(dot(a,a)) end
local function unit(a) local n=norm(a); return n>1e-12 and mul(a,1/n) or V() end
local function vector(a) return type(a)=="table" and finite(a.x) and finite(a.y) and finite(a.z) end
local function rotate(q,v)
    local u=cross(V(q.x,q.y,q.z),v)
    return add(v,mul(add(mul(u,q.w),cross(V(q.x,q.y,q.z),u)),2))
end
local function localVector(q,v) return rotate({w=q.w,x=-q.x,y=-q.y,z=-q.z},v) end
local function quaternion(q)
    if type(q)~="table" or not finite(q.w) or not vector(q) then return nil end
    local n=math.sqrt(q.w*q.w+q.x*q.x+q.y*q.y+q.z*q.z)
    if n<1e-10 then return nil end
    return {w=q.w/n,x=q.x/n,y=q.y/n,z=q.z/n}
end
local function moonBody(body) return body and (body:lower():find("moon",1,true) or body:lower():find("luna",1,true)) end
local function overworld(body) return body and body:lower():find("overworld",1,true) end
local function envelope(R) return (C.SHAPE=="SPHERE" and R or math.sqrt(3)*R) end
local function safeRadius(R) return envelope(R)+C.TRANSITION+C.MARGIN end
local function goalRadius(R,lunar)
    return safeRadius(R)+(lunar and C.MOON_PARKING_CLEARANCE or C.PARKING_CLEARANCE)
end
local function elements(r,v,mu)
    local d=norm(r); if d<1 or not finite(mu) or mu<=0 then return nil end
    local h=cross(r,v)
    local evec=sub(mul(cross(v,h),1/mu),mul(r,1/d))
    local e=norm(evec); local energy=dot(v,v)/2-mu/d
    local p=dot(h,h)/mu; local pe=p/(1+e)
    return {e=e,pe=pe,ap=e<1 and p/(1-e) or math.huge,
            a=energy<0 and -mu/(2*energy) or -math.huge,h=unit(h),bound=energy<0 and e<1}
end
local function standardMu()
    local w=2*math.pi/C.OW_DAY
    return (C.OW_SURFACE_G+w*w*C.OW_RADIUS)*C.OW_RADIUS^2
end
local function moonAt(t,mu)
    local n=2*math.pi/C.MOON_PERIOD
    local r=(mu/(n*n))^(1/3); local a=n*t
    -- Hipparchus PLUS_J.orthogonal() = MINUS_K; v = PLUS_J cross r.
    return V(-r*math.sin(a),0,-r*math.cos(a)),V(-r*n*math.cos(a),0,r*n*math.sin(a)),r
end

-- Lambert universal variables, zero-revolution, explicit transfer orientation.
-- Replan from CURRENT state, so finite burns do not pretend to be impulses.
local function stumpff(z)
    if math.abs(z)<1e-5 then return .5-z/24+z*z/720,1/6-z/120+z*z/5040 end
    if z>0 then local s=math.sqrt(z); return (1-math.cos(s))/z,(s-math.sin(s))/(s^3) end
    local s=math.sqrt(-z)
    local sh=(math.exp(s)-math.exp(-s))/2
    local ch=(math.exp(s)+math.exp(-s))/2
    return (ch-1)/(-z),(sh-s)/(s^3)
end
local function lambert(r1,r2,tof,mu,normal)
    local a,b=norm(r1),norm(r2)
    if a<1 or b<1 or tof<=0 then return nil end
    local co=clamp(dot(r1,r2)/(a*b),-1,1)
    local si=math.sqrt(math.max(0,1-co*co))
    if dot(cross(r1,r2),normal)<0 then si=-si end
    if math.abs(si)<1e-6 then return nil end
    local A=si*math.sqrt(a*b/(1-co))
    local function sample(z)
        local c,s=stumpff(z)
        if c<=0 then return nil end
        local y=a+b+A*(z*s-1)/math.sqrt(c)
        if y<0 then return nil end
        return ((y/c)^1.5*s+A*math.sqrt(y))/math.sqrt(mu),y
    end
    local lo,hi,prevZ,prevT
    for i=0,120 do
        local z=-4*math.pi^2+(8*math.pi^2-1e-5)*i/120
        local t=sample(z)
        if t and finite(t) then
            if prevT and prevT<=tof and t>=tof then lo,hi=prevZ,z; break end
            prevZ,prevT=z,t
        end
    end
    if not lo then return nil end
    local y
    for _=1,55 do
        local z=(lo+hi)/2; local t,yy=sample(z)
        if not t then lo=z elseif t<tof then lo=z else hi=z end
        y=yy or y
    end
    local _,yy=sample((lo+hi)/2); y=yy or y
    if not y then return nil end
    local f=1-y/a; local g=A*math.sqrt(y/mu)
    if math.abs(g)<1e-8 then return nil end
    local v=mul(sub(r2,mul(r1,f)),1/g)
    return vector(v) and v or nil
end

local T={valid=false,deep=false,knownDimension=false}
local F={state="READY",auto=true,attempts=0,next="WAITING",stable=0,
         lastCommand={},accel={},armed=C.AUTO_LAUNCH,transfer=nil}
for k,v in pairs(C.ACCEL) do F.accel[k]=v end
local HW={sputnik=nil,modem=nil,target=C.SECONDARY_ID,lastAck=-1e9,lastBeat=-1e9}
local now=0
local function log(message)
    if not fs then return end
    pcall(function()
        if fs.exists(C.LOG_FILE) and fs.getSize(C.LOG_FILE)>1048576 then
            if fs.exists(C.LOG_FILE..".1") then fs.delete(C.LOG_FILE..".1") end
            fs.move(C.LOG_FILE,C.LOG_FILE..".1")
        end
        local h=fs.open(C.LOG_FILE,"a")
        if h then h.writeLine(string.format("%.2f %s",now,message)); h.close() end
    end)
end
local function state(s,why)
    if F.state~=s then log(F.state.." -> "..s.." "..(why or "")); F.stable=0 end
    F.state=s; F.next=why or s
end
local function scan()
    HW.sputnik=nil; HW.modem=nil
    for _,name in ipairs(peripheral.getNames()) do
        local methods=peripheral.getMethods(name) or {}
        local m={}; for _,v in ipairs(methods) do m[v]=true end
        if m.getPhysics and m.getDeepSpaceData then HW.sputnik=name end
        if peripheral.hasType and peripheral.hasType(name,"modem") or peripheral.getType(name)=="modem" then
            HW.modem=name
        end
    end
    if HW.modem then pcall(rednet.open,HW.modem) end
end
local function send(command,power)
    if not HW.modem then return end
    local msg={command=command,power=power}
    if HW.target then rednet.send(HW.target,msg,C.PROTOCOL) else rednet.broadcast(msg,C.PROTOCOL) end
end
local function channel(key,power)
    power=math.floor(clamp(power or 0,0,1)*15+.5)/15
    local command=C.CHANNEL[key]
    if command=="DOWN" then redstone.setAnalogOutput(C.MAIN_DOWN_SIDE,math.floor(power*15+.5))
    else send(command,power) end
    F.lastCommand[key]=power
end
local function stop()
    F.saturated=false
    redstone.setAnalogOutput(C.MAIN_DOWN_SIDE,0); send("STOP")
    for k in pairs(C.CHANNEL) do F.lastCommand[k]=0 end
end
-- Exact OW surface barrier for StandardUniverseProvider's rotation (-J rate,
-- Orekit active rotation +J). Sputnik's spherical altitude is NOT used here.
-- For d=distance to rotating convex cube, curvature contributes nonnegative
-- d''. Dropping it gives a conservative lower bound on clearance acceleration.
local function surfaceBarrier(a)
    if not T.valid or not T.deep or not overworld(T.body) then return a end
    if norm(T.r)>safeRadius(T.R) then return a end
    local omega=2*math.pi/C.OW_DAY
    local angle=omega*T.time; local co,si=math.cos(angle),math.sin(angle)
    local p=V(co*T.r.x-si*T.r.z,T.r.y,si*T.r.x+co*T.r.z)
    local outside=V()
    for _,ax in ipairs({"x","y","z"}) do
        outside[ax]=(p[ax]>=0 and 1 or -1)*math.max(0,math.abs(p[ax])-T.R)
    end
    local d=norm(outside)
    local n
    if C.SHAPE=="SPHERE" then d=norm(T.r)-T.R; n=unit(T.r)
    elseif d>1e-6 then
        local localN=unit(outside)
        n=V(co*localN.x+si*localN.z,localN.y,-si*localN.x+co*localN.z)
    else return a end
    T.surfaceDistance=d
    local w=V(0,omega,0)
    local relative=C.SHAPE=="SPHERE" and T.effective or sub(T.effective,cross(w,T.r))
    local rate=dot(n,relative)
    local desiredRate=clamp((C.TRANSITION+100000-d)/25,-500,3500)
    local required=(desiredRate-rate)/4
    local grav=mul(unit(T.r),-T.mu/norm(T.r)^2)
    local rotatingAccel=add(sub(grav,mul(cross(w,T.effective),2)),cross(w,cross(w,T.r)))
    if C.SHAPE=="SPHERE" then
        local vt=sub(T.effective,mul(n,dot(n,T.effective)))
        rotatingAccel=add(grav,mul(n,dot(vt,vt)/norm(T.r)))
    end
    local lower=required-dot(n,rotatingAccel)
    if dot(a,n)<lower then a=add(a,mul(n,lower-dot(a,n))) end
    return a
end
local function force(acceleration)
    if not T.q then stop(); return end
    local a=localVector(T.q,surfaceBarrier(acceleration))
    F.saturated=false
    for _,axis in ipairs({"x","y","z"}) do
        local pos,neg=axis.."p",axis.."n"
        local value=a[axis]
        local requestedKey=axis..(value>=0 and "p" or "n")
        if math.abs(value)>F.accel[requestedKey] then F.saturated=true end
        -- Always clear opposite group first; all axes obey requested power.
        if value>=0 then channel(neg,0); channel(pos,value/F.accel[pos])
        else channel(pos,0); channel(neg,-value/F.accel[neg]) end
    end
end
local function learn(previous)
    if not C.LEARN_ACCEL or not previous or not previous.valid or not T.valid or
       previous.body~=T.body or not previous.effective then return end
    local dt=T.time-previous.time
    if dt<.045 or dt>1 then return end
    local qdot=T.q.w*previous.q.w+T.q.x*previous.q.x+T.q.y*previous.q.y+T.q.z*previous.q.z
    if math.abs(qdot)<.9995 then return end
    local grav=mul(unit(previous.r),-previous.mu/norm(previous.r)^2)
    local measured=localVector(previous.q,sub(mul(sub(T.effective,previous.effective),1/dt),grav))
    for _,axis in ipairs({"x","y","z"}) do
        local p,n=F.lastCommand[axis.."p"] or 0,F.lastCommand[axis.."n"] or 0
        local key=p>n and axis.."p" or axis.."n"
        local u=p-n
        -- Two consecutive intervals of the same demand avoid command latency.
        if math.abs(u)>=.25 and F.learnCommand and math.abs(u-(F.learnCommand[axis] or 0))<.07 then
            local estimate=measured[axis]/u
            if finite(estimate) and estimate>.1 and estimate<2000 then
                F.accel[key]=.95*F.accel[key]+.05*estimate
            end
        end
    end
    F.learnCommand={x=(F.lastCommand.xp or 0)-(F.lastCommand.xn or 0),
                    y=(F.lastCommand.yp or 0)-(F.lastCommand.yn or 0),
                    z=(F.lastCommand.zp or 0)-(F.lastCommand.zn or 0)}
end
local function poll()
    local previous=T
    local fresh={valid=false,deep=previous.deep,knownDimension=false}
    local function call(method)
        if not HW.sputnik then return nil end
        local ok,data=pcall(peripheral.call,HW.sputnik,method)
        return ok and type(data)=="table" and data or nil
    end
    local ph=call("getPhysics"); local ds=call("getDeepSpaceData")
    if ds and type(ds.inDeepSpace)=="boolean" then
        fresh.deep=ds.inDeepSpace; fresh.knownDimension=true; fresh.body=tostring(ds.parentBody or "")
    end
    if ph then fresh.q=quaternion(ph.quaternion); fresh.localV=vector(ph.velocity) and ph.velocity or nil end
    if not fresh.deep then
        fresh.pos=call("getGlobalPos")
        fresh.gravity=ph and finite(ph.gravityY) and math.abs(ph.gravityY) or 11
        fresh.valid=fresh.knownDimension and fresh.q~=nil and fresh.localV~=nil and vector(fresh.pos)
    elseif ds and ph and fresh.q and fresh.localV and type(ph.space)=="table" and
           ph.space.available==true and ph.space.frame==fresh.body and
           vector(ph.space.position) and vector(ph.space.velocity) and
           finite(ds.parentRadius) and ds.parentRadius>0 and finite(ds.gravity) and ds.gravity>0 and
           finite(ds.universeTime) then
        fresh.r=ph.space.position; fresh.v=ph.space.velocity; fresh.R=ds.parentRadius
        fresh.mu=ds.gravity*norm(fresh.r)^2; fresh.time=ds.universeTime*.05
        fresh.effective=add(fresh.v,fresh.localV) -- pending delta-v, single rigid ship
        fresh.orbit=elements(fresh.r,fresh.v,fresh.mu)
        fresh.pendingOrbit=elements(fresh.r,fresh.effective,fresh.mu)
        fresh.valid=fresh.orbit~=nil and fresh.pendingOrbit~=nil
        fresh.safe=fresh.valid and fresh.orbit.bound and fresh.pendingOrbit.bound and
            math.min(fresh.orbit.pe,fresh.pendingOrbit.pe)>safeRadius(fresh.R)
    end
    T=fresh
    if T.deep then learn(previous) end
    if T.valid then F.lastGood=now end
end

-- Cartesian tracking with acceleration feedforward in a moving orbital frame.
-- For a circular target dv_target/dt=-rhat*vc*vt/r. Subtract orbital
-- gravity to get the thrust required; never feed ph.velocity into orbital Pe.
local function track(target,feedforward,tolerance)
    local err=sub(target,T.effective)
    local grav=mul(unit(T.r),-T.mu/norm(T.r)^2)
    local a=add(mul(err,1/C.CONTROL_TIME),sub(feedforward or V(),grav))
    force(a)
    return norm(err)<(tolerance or C.ORBIT_DV_TOL),norm(err)
end
local function orbitGuidance(lunar)
    local r=norm(T.r); local rh=unit(T.r)
    local vr=dot(T.effective,rh); local tangent=unit(sub(T.effective,mul(rh,vr)))
    if norm(tangent)<.1 then tangent=unit(cross(V(0,1,0),rh)) end
    if norm(tangent)<.1 then tangent=unit(cross(V(1,0,0),rh)) end
    local goal=goalRadius(T.R,lunar)
    local gap=goal-r
    local radial=clamp(gap/60,-C.MAX_RADIAL_SPEED,C.MAX_RADIAL_SPEED)
    -- Climb continuously; do NOT kill the launch velocity at the boundary.
    -- Plane changes only AFTER clearing the entire rotating cube.
    if not lunar and r>safeRadius(T.R)+50000 then
        tangent=unit(cross(V(0,1,0),rh))
    end
    local vc=math.sqrt(T.mu/r)
    local target=add(mul(tangent,vc),mul(rh,radial))
    if not lunar and r>safeRadius(T.R)+50000 then
        local normal= sub(V(0,1,0),mul(rh,rh.y))
        target=add(target,mul(normal,clamp(-T.r.y/120,-1000,1000)))
    end
    local vt=norm(sub(T.effective,mul(rh,vr)))
    local ff=add(mul(rh,-vc*vt/r),mul(tangent,radial*vt/r-.5*vc*vr/r))
    local done,dv=track(target,ff)
    local aligned=lunar or (T.orbit.h.y>.999 and math.abs(T.r.y)<5000)
    local settled=done and math.abs(gap)<1500 and math.abs(vr)<5 and T.safe and
                  T.orbit.e<.008 and norm(T.localV)<3 and aligned
    F.next=string.format("RAISE/CIRC r %.0f/%.0f km Pe %.0f km dV %.1f",r/1000,goal/1000,T.orbit.pe/1000,dv)
    return settled
end
local function targetMoonAt(t,mu)
    local p,v=moonAt(t,mu)
    return add(p,mul(unit(v),C.MOON_AIM_RADIUS))
end
local function transferCandidate()
    local r=norm(T.r); local _,_,rm=moonAt(T.time,T.mu)
    local tof=math.pi*math.sqrt(((r+rm)/2)^3/T.mu)
    -- Offset from exact 180 degrees avoids Lambert's singular collinear case.
    local arrival=T.time+tof*.94
    local target=targetMoonAt(arrival,T.mu)
    local co=clamp(dot(unit(T.r),unit(target)),-1,1)
    local angle=math.acos(co)
    if dot(cross(T.r,target),V(0,1,0))<0 then angle=2*math.pi-angle end
    if angle<math.rad(145) or angle>math.rad(175) then return nil end
    local v=lambert(T.r,target,arrival-T.time,T.mu,V(0,1,0))
    if not v then return nil end
    local o=elements(T.r,v,T.mu)
    if not o or o.pe<safeRadius(T.R)+10000 then return nil end
    return {arrival=arrival,mu=T.mu,velocity=v,lastPlan=T.time,started=T.time}
end
local function transferGuidance()
    local plan=F.transfer
    if not plan then state("PARKING","REPLAN TRANSFER"); return end
    local remaining=plan.arrival-T.time
    if remaining<30 then
        F.transfer=nil; F.attempts=F.attempts+1
        state("INSERTION","MISSED ENCOUNTER: RETURN TO SAFE PARKING / RETRY"); return
    end
    if T.time-plan.lastPlan>=C.TRANSFER_REPLAN or not plan.velocity then
        local aim=targetMoonAt(plan.arrival,plan.mu)
        local desired=lambert(T.r,aim,remaining,plan.mu,V(0,1,0))
        local o=desired and elements(T.r,desired,plan.mu)
        -- Outbound trajectory may still have a low *past* periapsis; allow
        -- it only if already climbing and outside the safe envelope.
        if desired and o and (o.pe>safeRadius(T.R) or
            (dot(desired,unit(T.r))>0 and norm(T.r)>safeRadius(T.R)+100000)) then
            plan.velocity=desired; plan.lastPlan=T.time
        else
            F.transfer=nil; state("INSERTION","NO SAFE LAMBERT SOLUTION: REBUILD / RETRY"); return
        end
    end
    -- Integrate target velocity between Lambert updates with same gravity;
    -- this avoids braking the naturally acquired radial speed during TLI.
    local err=sub(plan.velocity,T.effective)
    local dv=norm(err)
    if dv<C.MIDCOURSE_TOL then stop() else force(mul(err,1/C.CONTROL_TIME)) end
    F.next=string.format("LUNAR TRANSFER ETA %.0fs dV %.1f",remaining,dv)
end
local function update()
    if F.state=="ABORT" or not F.auto then stop(); return end
    if F.state=="READY" then
        stop()
        if F.armed and now>=(F.launchAt or 0) then state("ASCENT","AUTO LAUNCH") else return end
    end
    if not T.valid then
        F.next="RETRY: WAITING FOR FRESH SPUTNIK DATA"
        -- During short warp gaps preserve the last command; never invent a
        -- dimension change because a peripheral call failed.
        if now-(F.lastGood or -1e9)>C.DATA_GRACE then stop() end
        if now-(F.lastScan or -1e9)>1 then scan(); F.lastScan=now end
        return
    end
    if now-HW.lastAck>C.LINK_TIMEOUT then
        stop(); F.next="RETRY: WAITING FOR THRUSTER LINK"
        if now-(F.lastScan or -1e9)>1 then scan(); F.lastScan=now end
        return
    end
    if not T.deep then
        if F.state~="ASCENT" then
            F.attempts=F.attempts+1; F.transfer=nil; F.learnCommand=nil
            state("ASCENT","DIMENSION FALLBACK: AUTOMATIC RELAUNCH")
        end
        local vy=T.localV.y
        -- World UP converted through the measured quaternion, even after warp.
        if T.pos.y>7500 then
            local up=localVector(T.q,V(0,1,0)); local scale=0
            for _,ax in ipairs({"x","y","z"}) do
                local key=ax..(up[ax]>=0 and "p" or "n")
                scale=math.max(scale,math.abs(up[ax])/F.accel[key])
            end
            force(V(0,scale>0 and 1/scale or 20,0))
        else force(V(0,T.gravity+(35-vy)/2,0)) end
        F.next=string.format("ASCENT Y %.0f Vy %.1f",T.pos.y,vy)
        return
    end
    if F.state=="ASCENT" then
        F.transfer=nil; F.learnCommand=nil; state("INSERTION","WARP: CONTINUOUS RADIAL CLIMB")
    end
    local lunar=moonBody(T.body)
    if not lunar and not overworld(T.body) then
        stop(); F.next="RETRY: UNSUPPORTED PARENT FRAME "..T.body; return
    end
    if lunar and F.state~="LUNAR_CAPTURE" and F.state~="LUNAR_ORBIT" then
        F.transfer=nil; state("LUNAR_CAPTURE","MOON SOI ACQUIRED")
    elseif not lunar and (F.state=="LUNAR_CAPTURE" or F.state=="LUNAR_ORBIT") then
        F.transfer=nil; F.attempts=F.attempts+1; state("INSERTION","LEFT MOON SOI: REPLAN")
    end
    if F.state=="INSERTION" or F.state=="LUNAR_CAPTURE" then
        if orbitGuidance(lunar) then
            F.stable=F.stable+(F.dt or C.TICK)
            if F.stable>=C.STABLE_SECONDS then
                stop(); state(lunar and "LUNAR_ORBIT" or "PARKING","ORBIT VERIFIED")
            end
        else F.stable=0 end
    elseif F.state=="PARKING" or F.state=="LUNAR_ORBIT" then
        stop()
        -- Monitor after acquisition too; v7 simply coasted even if Pe fell.
        if not T.safe or math.abs(dot(T.v,unit(T.r)))>30 or norm(T.localV)>10 then
            state(lunar and "LUNAR_CAPTURE" or "INSERTION","ORBIT DRIFT: RECIRCULARIZE"); return
        end
        if not lunar then
            -- Analytic Moon ephemeris is authorized only for standard universe.
            if math.abs(T.mu/standardMu()-1)>.02 or math.abs(T.R-C.OW_RADIUS)>1 then
                F.next="PARKING: NONSTANDARD UNIVERSE; NEED REAL MOON EPHEMERIS"; return
            end
            local plan=transferCandidate()
            if plan then F.transfer=plan; state("TRANSFER","LUNAR WINDOW: LAMBERT BURN")
            else F.next="SAFE PARKING: WAITING LUNAR WINDOW" end
        else F.next="LUNAR ORBIT: HOLD / MONITOR" end
    elseif F.state=="TRANSFER" then
        transferGuidance()
    else state(lunar and "LUNAR_CAPTURE" or "INSERTION","RESUME FROM CURRENT FRAME") end
end

local function propagatePlan(dt)
    if T.valid and T.deep and F.transfer and F.transfer.velocity and dt>0 and dt<2 then
        F.transfer.velocity=add(F.transfer.velocity,mul(unit(T.r),-T.mu/norm(T.r)^2*dt))
    end
end
local function draw()
    term.setBackgroundColor(colors.black); term.setTextColor(colors.white); term.clear(); term.setCursorPos(1,1)
    print("COSMONAUTICS v8 | "..F.state.." | "..(F.auto and "AUTO" or "MANUAL"))
    print("Shape envelope: "..C.SHAPE.." | retries: "..F.attempts)
    print("Frame: "..(T.body or "unknown").." | data: "..tostring(T.valid))
    print("Link: "..(now-HW.lastAck<=C.LINK_TIMEOUT and "OK" or "WAIT"))
    if T.valid and T.deep then
        print(string.format("r %.1f km | safe r %.1f km",norm(T.r)/1000,safeRadius(T.R)/1000))
        print(string.format("Pe %.1f km | e %.5f | SAFE %s",T.orbit.pe/1000,T.orbit.e,tostring(T.safe)))
        print(string.format("v %.1f | pending local %.2f m/s",norm(T.v),norm(T.localV)))
        print(string.format("radial %.1f | mu %.4g",dot(T.v,unit(T.r)),T.mu))
    end
    print(F.next)
    if F.saturated then print("THRUST SATURATED: see force/mass and axis mapping") end
    print("L launch/resume | A stop | M auto/manual")
    print("U autolaunch | Q quit | flight_v8.log")
end
local function cycle()
    poll()
    local dt=T.valid and T.deep and F.lastTime and T.time-F.lastTime or C.TICK
    if not finite(dt) or dt<0 or dt>2 then dt=C.TICK end
    F.dt=dt
    propagatePlan(dt)
    F.lastTime=T.valid and T.deep and T.time or nil
    update()
    if now-(F.lastLog or -1e9)>=C.LOG_INTERVAL then
        local data={state=F.state,body=T.body,valid=T.valid,deep=T.deep,
            r=T.r,v=T.v,localV=T.localV,q=T.q,mu=T.mu,orbit=T.orbit,
            time=T.time,surfaceDistance=T.surfaceDistance,saturated=F.saturated,
            accel=F.accel,command=F.lastCommand,next=F.next}
        log(textutils.serialize(data,{compact=true})); F.lastLog=now
    end
    draw()
end

-- Export pure/controller functions ONLY for offline test harness.
if ...=="__test" then
    return {C=C,F=F,HW=HW,V=V,add=add,sub=sub,mul=mul,dot=dot,cross=cross,norm=norm,
        unit=unit,rotate=rotate,elements=elements,envelope=envelope,safeRadius=safeRadius,
        goalRadius=goalRadius,moonAt=moonAt,standardMu=standardMu,lambert=lambert,
        poll=poll,update=update,orbitGuidance=orbitGuidance,transferCandidate=transferCandidate,
        transferGuidance=transferGuidance,propagatePlan=propagatePlan,force=force,
        setT=function(t) T=t end,getT=function() return T end,
        setNow=function(t) now=t end,learn=learn,track=track}
end
local function main()
    now=os.epoch("utc")/1000; F.launchAt=now+C.LAUNCH_DELAY
    scan(); stop(); local timer=os.startTimer(C.TICK)
    while true do
        local ev,a,b,proto=os.pullEventRaw()
        now=os.epoch("utc")/1000
        if ev=="terminate" then stop(); return end -- explicit user's Ctrl+T
        if ev=="rednet_message" and proto==C.PROTOCOL and type(b)=="table" and b.type=="ACK" then
            if not HW.target or HW.target==a then HW.target=a; HW.lastAck=now end
        elseif ev=="peripheral" or ev=="peripheral_detach" then pcall(scan)
        elseif ev=="char" then
            local k=a:upper()
            if k=="Q" then stop(); return
            elseif k=="A" then stop(); F.armed=false; state("ABORT","MANUAL STOP")
            elseif k=="M" then F.auto=not F.auto; if not F.auto then stop() end
            elseif k=="L" then F.auto=true; F.armed=true; F.launchAt=now; state("READY","RESUME")
            elseif k=="U" then F.armed=not F.armed; F.launchAt=now+C.LAUNCH_DELAY end
        elseif ev=="timer" and a==timer then
            if now-HW.lastBeat>=C.HEARTBEAT then pcall(send,"HEARTBEAT"); HW.lastBeat=now end
            local ok,err=xpcall(cycle,debug.traceback)
            if not ok then
                pcall(stop); F.attempts=F.attempts+1
                F.next="RETRY AFTER LUA ERROR: "..tostring(err); log(F.next)
                pcall(scan) -- preserve mission state; retry, never terminate automatically
            end
            timer=os.startTimer(C.TICK)
        end
    end
end
main()
