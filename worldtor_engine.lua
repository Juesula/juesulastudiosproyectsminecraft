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
WT.version = '2.1.0'
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
