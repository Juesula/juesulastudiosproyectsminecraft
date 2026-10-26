-- Ejemplo opcional para probar WorldShop 3.2 / WorldTor.
-- El motor se entrega virtualmente en el modo prueba del servidor.
local WorldTor=assert(loadfile('worldtor_engine.lua'))()
local gfx=WorldTor.new(term.current())
local x=math.floor(gfx.w/2)
local y=math.floor(gfx.h/2)
while true do
  gfx:clear(' ',colors.white,colors.black)
  gfx:center(1,'WORLD SHOP - DEMO DE PRUEBA',colors.cyan)
  gfx:center(2,'Flechas: mover | Q: salir',colors.lightGray)
  gfx:pixel(x,y,'@',colors.lime)
  gfx:footer()
  gfx:flip()
  local event,key=os.pullEvent('key')
  if key==keys.q then break
  elseif key==keys.left then x=math.max(1,x-1)
  elseif key==keys.right then x=math.min(gfx.w,x+1)
  elseif key==keys.up then y=math.max(3,y-1)
  elseif key==keys.down then y=math.min(gfx.h-1,y+1) end
end
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1,1)
print('Has cerrado el juego de prueba.')
