-- WorldTor 2 Engine v2.0 | CC:Tweaked + DirectGPU opcional
-- API: loadfile('worldtor_engine.lua')() -> tabla WorldTor (compatible con WorldTor 1)
-- Componentes: doble buffer, sprites, texto, figuras, camara, efectos, animacion intro y sonido.
local WT = { version = '2.0.0' }
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

local function newTerminal(target)
    local self = { target=target or term.current(), cameraX=0, cameraY=0,
                   particles={}, frame=0, shakeTime=0, shakeSize=1 }
    function self:resize()
        self.w,self.h=self.target.getSize()
        self._front = nil -- resize invalida la comparacion diferencial
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
    function self:invalidate()
        self._front=nil
    end
    function self:stats()
        return {frame=self.frame, drawCalls=self.lastDrawCalls or 0,
                skippedRows=self.lastSkippedRows or 0, backend=self.backend or 'terminal'}
    end
    function self:flip()
        self.frame=self.frame+1
        local sx,sy=0,0
        if self.shakeTime>0 then
            self.shakeTime=self.shakeTime-1
            sx=math.random(-self.shakeSize,self.shakeSize)
            sy=math.random(-self.shakeSize,self.shakeSize)
        end
        self.target.setCursorBlink(false)
        local nextFront={}
        local draws,skips=0,0
        for y=1,self.h do
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
            local a,b,c=table.concat(chars),table.concat(fore),table.concat(back)
            local prev=self._front and self._front[y]
            if not prev or a~=prev[1] or b~=prev[2] or c~=prev[3] then
                self.target.setCursorPos(1,y)
                self.target.blit(a,b,c)
                draws=draws+1
            else skips=skips+1 end
            nextFront[y]={a,b,c}
        end
        self._front=nextFront
        self.lastDrawCalls=draws;self.lastSkippedRows=skips
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
-- WorldTor 2: utilidades nuevas (sin modificar la API v1)
-- ================================================================
local BASE_RGB = {
    [colors.white]=0xf0f0f0, [colors.orange]=0xf2b233,
    [colors.magenta]=0xe57fd8, [colors.lightBlue]=0x99b2f2,
    [colors.yellow]=0xdede6c, [colors.lime]=0x7fcc19,
    [colors.pink]=0xf2b2cc, [colors.gray]=0x4c4c4c,
    [colors.lightGray]=0x999999, [colors.cyan]=0x4c99b2,
    [colors.purple]=0xb266e5, [colors.blue]=0x3366cc,
    [colors.brown]=0x7f664c, [colors.green]=0x57a64e,
    [colors.red]=0xcc4c4c, [colors.black]=0x111111
}
local INDEX_COLOR = {}
for color,code in pairs(fallbackColors) do
    INDEX_COLOR[tonumber(code,16)]=color
end
local function rounded(x) return math.floor(x+0.5) end
local function channel(v) return math.max(0,math.min(255,rounded(tonumber(v) or 0))) end
function WT.rgb(r,g,b) return channel(r)*65536+channel(g)*256+channel(b) end
function WT.rgbChannels(rgb)
    rgb=tonumber(rgb) or 0
    return math.floor(rgb/65536)%256, math.floor(rgb/256)%256, rgb%256
end
function WT.colorRGB(ccColor)
    return BASE_RGB[ccColor] or 0xffffff
end
function WT.lerpColor(a,b,t)
    t=clamp(t or 0,0,1)
    local ar,ag,ab=WT.rgbChannels(a)
    local br,bg,bb=WT.rgbChannels(b)
    return WT.rgb(ar+(br-ar)*t,ag+(bg-ag)*t,ab+(bb-ab)*t)
end
function WT.easeInOut(t)
    t=clamp(t or 0,0,1)
    return t*t*(3-2*t)
end
function WT.rectHit(a,b)
    return a.x<b.x+b.w and a.x+a.w>b.x and a.y<b.y+b.h and a.y+a.h>b.y
end
function WT.newAnimation(frames,seconds,loop)
    assert(type(frames)=='table' and #frames>0,'frames necesita al menos 1 fotograma')
    local anim={frames=frames, seconds=math.max(0.001,seconds or 0.15),loop=loop~=false,
                index=1,elapsed=0,done=false}
    function anim:reset() self.index=1;self.elapsed=0;self.done=false end
    function anim:frame() return self.frames[self.index] end
    function anim:update(dt)
        if self.done then return end
        self.elapsed=self.elapsed+math.max(0,tonumber(dt) or 0)
        local steps=math.floor(self.elapsed/self.seconds)
        if steps<1 then return end
        if self.loop then
            self.elapsed=self.elapsed-steps*self.seconds
            self.index=((self.index-1+steps)%#self.frames)+1
        elseif steps>=#self.frames-self.index+1 then
            self.index=#self.frames;self.elapsed=0;self.done=true
        else
            self.elapsed=self.elapsed-steps*self.seconds
            self.index=self.index+steps
        end
    end
    return anim
end
function WT.newClock()
    local now = function()
        if os and os.epoch then return os.epoch('utc')/1000 end
        return os.clock()
    end
    local t=now()
    return function(maxDt)
        local n=now();local dt=math.max(0,n-t);t=n
        return math.min(dt,maxDt or 0.25)
    end
end

local oldNewTerminal=newTerminal
function WT.new(target,opts)
    if type(target)=='table' and target.backend and opts==nil then
        opts=target;target=opts.target
    end
    opts=opts or {}
    if opts.backend=='directgpu' or opts.backend=='auto' then
        local gfx,err=WT.newGPU(opts)
        if gfx then return gfx end
        if opts.backend=='directgpu' then return nil,err end
    end
    local gfx=oldNewTerminal(target)
    gfx.backend='terminal'
    return gfx
end

-- Para juegos nuevos: auto = DirectGPU si hay periferico y monitor; si no, terminal.
-- WorldTor 1 Engine.new(term.current()) sigue siendo terminal, sin alteraciones de coordenadas.
local function findGPU(options)
    if options.gpu then return options.gpu end
    if not peripheral or not peripheral.find then return nil end
    local ok,g=pcall(peripheral.find,'directgpu')
    if ok then return g end
    return nil
end

-- Colores GPU: 0xRRGGBB, WT.rgb(r,g,b) o tabla {r,g,b}.
local function gpuColor(c)
    if type(c)=='table' then return WT.rgb(c[1],c[2],c[3]) end
    if type(c)=='number' then return math.floor(c)%0x1000000 end
    return 0xffffff
end
local function callGPU(g,method,...)
    if type(g[method])~='function' then return false,'DirectGPU carece de '..method end
    return pcall(g[method],...)
end

function WT.newGPU(options)
    options=options or {}
    local gpu=findGPU(options)
    if not gpu then return nil,'No se encontro periferico directgpu' end
    local display=options.display
    if display==nil then
        local ok,id=callGPU(gpu,'autoDetectAndCreateDisplay')
        if not ok or id==nil or id==false then
            return nil,'DirectGPU no pudo crear pantalla; conecta un monitor: '..tostring(id)
        end
        display=id
    end
    local ok,info=callGPU(gpu,'getDisplayInfo',display)
    if not ok or type(info)~='table' then
        if options.display==nil then callGPU(gpu,'removeDisplay',display) end
        return nil,'DirectGPU no pudo consultar la resolucion del monitor'
    end
    local pw,ph=tonumber(info.pixelWidth),tonumber(info.pixelHeight)
    if not pw or not ph or pw<1 or ph<1 then
        if options.display==nil then callGPU(gpu,'removeDisplay',display) end
        return nil,'DirectGPU devolvio una resolucion no valida'
    end
    pw,ph=math.floor(pw),math.floor(ph)
    local cellW=math.max(2,rounded(options.cellWidth or 8))
    local cellH=math.max(4,rounded(options.cellHeight or 14))
    local tw,th=math.floor(pw/cellW),math.floor(ph/cellH)
    tw=math.max(1,math.min(tw,tonumber(options.gridWidth) or tw))
    th=math.max(1,math.min(th,tonumber(options.gridHeight) or th))
    local dummy={
        getSize=function() return tw,th end,
        setCursorBlink=function() end,
        setCursorPos=function() end,
        blit=function() end
    }
    local gfx=oldNewTerminal(dummy)
    gfx.backend='directgpu';gfx.gpu=gpu;gfx.display=display
    function gfx:isGPU() return true end
    gfx.pixelWidth=pw;gfx.pixelHeight=ph
    gfx.cellWidth=cellW;gfx.cellHeight=cellH
    gfx.nativeCommands={};gfx.gpuBackground=0x000000
    gfx.font=options.font or 'Monospaced'
    gfx.fontSize=tonumber(options.fontSize) or math.max(6,math.floor(cellH*0.75))
    gfx.ownsDisplay=options.display==nil
    gfx.nativeOnly=options.nativeOnly==true
    local oldClear=gfx.clear
    function gfx:clear(ch,fg,bg)
        oldClear(self,ch,fg,bg)
        self.nativeCommands={}
        self.gpuBackground=WT.colorRGB(bg or colors.black)
    end
    -- Las coordenadas nativas de WorldTor empiezan en 1; DirectGPU empieza en 0.
    local function pos(self,x,y,screen)
        if not screen then x=x-self.cameraX;y=y-self.cameraY end
        return rounded(x)-1,rounded(y)-1
    end
    local function queue(self,method,args)
        if #self.nativeCommands>=10000 then
            return false,'Demasiados comandos DirectGPU en un solo fotograma'
        end
        self.nativeCommands[#self.nativeCommands+1]={method=method,args=args}
        return true
    end
    function gfx:gpuClear(color)
        self.gpuBackground=gpuColor(color or 0)
        self.nativeCommands={}
    end
    function gfx:gpuPixel(x,y,color,screen)
        x,y=pos(self,x,y,screen)
        if x<0 or y<0 or x>=pw or y>=ph then return false end
        local r,g,b=WT.rgbChannels(gpuColor(color))
        return queue(self,'setPixel',{display,x,y,r,g,b})
    end
    function gfx:gpuRect(x,y,w,h,color,filled,screen)
        x,y=pos(self,x,y,screen)
        w,h=rounded(w),rounded(h)
        if w<=0 or h<=0 then return false end
        local r,g,b=WT.rgbChannels(gpuColor(color))
        if filled==false then
            return queue(self,'drawLine',{display,x,y,x+w-1,y,r,g,b})
                and queue(self,'drawLine',{display,x,y+h-1,x+w-1,y+h-1,r,g,b})
                and queue(self,'drawLine',{display,x,y,x,y+h-1,r,g,b})
                and queue(self,'drawLine',{display,x+w-1,y,x+w-1,y+h-1,r,g,b})
        end
        return queue(self,'fillRect',{display,x,y,w,h,r,g,b})
    end
    function gfx:gpuLine(x1,y1,x2,y2,color,screen)
        x1,y1=pos(self,x1,y1,screen);x2,y2=pos(self,x2,y2,screen)
        local r,g,b=WT.rgbChannels(gpuColor(color))
        return queue(self,'drawLine',{display,x1,y1,x2,y2,r,g,b})
    end
    function gfx:gpuCircle(x,y,radius,color,filled,screen)
        x,y=pos(self,x,y,screen)
        local r,g,b=WT.rgbChannels(gpuColor(color))
        return queue(self,'drawCircle',{display,x,y,rounded(radius),r,g,b,filled~=false})
    end
    function gfx:gpuEllipse(x,y,rx,ry,color,filled,screen)
        x,y=pos(self,x,y,screen)
        local r,g,b=WT.rgbChannels(gpuColor(color))
        return queue(self,'drawEllipse',{display,x,y,rounded(rx),rounded(ry),r,g,b,filled~=false})
    end
    function gfx:gpuText(x,y,str,color,size,font,style,screen)
        x,y=pos(self,x,y,screen)
        local r,g,b=WT.rgbChannels(gpuColor(color))
        return queue(self,'drawText',{display,tostring(str or ''),x,y,r,g,b,font or self.font,
                                        size or self.fontSize,style or 'plain'})
    end
    -- Sprite RGB: filas como strings + paleta, o listas de colores RGB.
    -- Los espacios o false son transparentes. Agrupa tramos de un mismo color.
    function gfx:gpuSprite(x,y,sprite,scale,screen,palette)
        scale=math.max(1,rounded(scale or 1))
        palette=palette or {}
        for iy,row in ipairs(sprite or {}) do
            local n=type(row)=='string' and #row or (type(row)=='table' and #row or 0)
            local function at(i)
                if type(row)=='string' then
                    local key=row:sub(i,i)
                    if key==' ' then return false end
                    return palette[key] or false
                end
                return row[i]
            end
            local i=1
            while i<=n do
                local c=at(i)
                if c~=nil and c~=false then
                    local j=i+1
                    while j<=n and at(j)==c do j=j+1 end
                    local ok=self:gpuRect(x+(i-1)*scale,y+(iy-1)*scale,
                                           (j-i)*scale,scale,c,true,screen)
                    if not ok then return false end
                    i=j
                else i=i+1 end
            end
        end
        return true
    end
    function gfx:gpuImageJPEG(data,x,y,w,h,screen)
        x,y=pos(self,x,y,screen)
        return queue(self,'loadJPEGRegionBytes',{display,data,x,y,rounded(w),rounded(h)})
    end
    function gfx:release()
        if self.ownsDisplay then
            local ok,err=callGPU(self.gpu,'removeDisplay',self.display)
            if ok then self.ownsDisplay=false end
            return ok,err
        end
        return true
    end
    local oldFlip=gfx.flip
    local function emit(method,...)
        local ok,msg=callGPU(gpu,method,...)
        if not ok then error('DirectGPU '..method..': '..tostring(msg),2) end
    end
    local function rgbOfHex(c)
        local cc=INDEX_COLOR[tonumber(c,16) or 0]
        return WT.rgbChannels(WT.colorRGB(cc))
    end
    function gfx:flip()
        -- GPU utiliza comandos nativos. Se dibuja primero el layer de texto v1
        -- y luego la capa de pixeles v2; updateDisplay exactamente una vez.
        local r,g,b=WT.rgbChannels(self.gpuBackground)
        emit('clear',display,r,g,b)
        local sx,sy=0,0
        if self.shakeTime>0 then
            self.shakeTime=self.shakeTime-1
            sx=math.random(-self.shakeSize,self.shakeSize)
            sy=math.random(-self.shakeSize,self.shakeSize)
        end
        local calls=1
        -- Agrupa fondos por tramos de color para evitar una llamada por caracter.
        -- nativeOnly omite el layer de caracteres (ideal para juegos RGB puros).
        if not self.nativeOnly then for y=1,self.h do
            local ox,oy=sx,sy
            if y<=2 or y==self.h then ox,oy=0,0 end
            local srcY=y+oy
            if srcY>=1 and srcY<=self.h then
                local x=1
                while x<=self.w do
                    local srcX=x+ox
                    local bg=srcX>=1 and srcX<=self.w and self.back[srcY][srcX] or 'f'
                    local n=x+1
                    while n<=self.w do
                        local tx=n+ox
                        local other=tx>=1 and tx<=self.w and self.back[srcY][tx] or 'f'
                        if other~=bg then break end
                        n=n+1
                    end
                    local R,G,B=rgbOfHex(bg)
                    emit('fillRect',display,(x-1)*cellW,(y-1)*cellH,(n-x)*cellW,cellH,R,G,B)
                    calls=calls+1;x=n
                end
                x=1
                while x<=self.w do
                    local tx=x+ox
                    local chr=tx>=1 and tx<=self.w and self.chars[srcY][tx] or ' '
                    if chr==' ' then x=x+1
                    else
                        local fg=self.fore[srcY][tx]
                        local n=x+1
                        local text={chr}
                        while n<=self.w do
                            local nx=n+ox
                            local nchr=nx>=1 and nx<=self.w and self.chars[srcY][nx] or ' '
                            local nfg=nx>=1 and nx<=self.w and self.fore[srcY][nx] or '0'
                            if nchr==' ' or fg~=nfg then break end
                            text[#text+1]=nchr;n=n+1
                        end
                        local R,G,B=rgbOfHex(fg)
                        emit('drawText',display,table.concat(text),(x-1)*cellW,
                             (y-1)*cellH,R,G,B,self.font,self.fontSize,'plain')
                        calls=calls+1;x=n
                    end
                end
            end
        end
        end -- capa de caracteres v1
        for _,cmd in ipairs(self.nativeCommands) do
            emit(cmd.method,(table.unpack or unpack)(cmd.args))
            calls=calls+1
        end
        emit('updateDisplay',display)
        self.frame=self.frame+1
        self.lastDrawCalls=calls+1;self.lastSkippedRows=0
        self.nativeCommands={}
    end
    return gfx
end

-- Nuevas primitivas terminales utiles tambien sin DirectGPU.
local baseNew=WT.new
WT.new=function(target,opts)
    local gfx,err=baseNew(target,opts)
    if not gfx then return nil,err end
    function gfx:isGPU() return self.backend=='directgpu' end
    function gfx:drawAnimation(x,y,animation,fg,bg,transparent)
        return self:sprite(x,y,animation:frame(),fg,bg,transparent)
    end
    function gfx:tilemap(x,y,map,tiles,fg,bg)
        for row,values in ipairs(map or {}) do
            for col,key in ipairs(values) do
                if tiles[key] then self:sprite(x+col-1,y+row-1,tiles[key],fg,bg) end
            end
        end
    end
    return gfx
end

return WT
