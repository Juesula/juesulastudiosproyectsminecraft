      line(9,'  1 barril a la derecha: INGRESO',colors.yellow)
      line(10,'  1 barril abajo: ALMACEN',colors.yellow)
      line(12,'  [C] Cambiar / desvincular cajero',colors.lime)
      line(13,'  [K] Mostrar clave de enlace',colors.orange)
      line(15,'  Advertencia: Rednet sin cifrar',colors.red)
    else
      line(5,'  ESTADISTICAS',colors.lightBlue)
      line(7,'  Usuarios registrados: '..n,colors.white)
      line(9,'  Juegos publicados: '..prod,colors.white)
      line(11,'  Revisiones pendientes: '..pend,colors.orange)
      local deposits=0;for _ in pairs(db.receipts) do deposits=deposits+1 end
      line(13,'  Ingresos procesados: '..deposits,colors.white)
      line(15,'  DB: '..DBFILE,colors.gray)
    end
    line(h-1,'  '..notice:sub(1,w-2),colors.yellow)
    line(h,' [Q] Apagar  |  Pulsa teclas o haz clic',colors.lightGray,colors.gray)
  end
  local function choose(id)
    if id and db.deployments[id] and db.deployments[id].status=='pending' then selection=id;return true end
    return false
  end
  while true do
    draw()
    local e={os.pullEventRaw()}
    if e[1]=='monitor_touch' then e={'mouse_click',1,e[3],e[4]} end
    local action=nil
    if e[1]=='char' then action=tostring(e[2]):lower()
    elseif e[1]=='key' then
      if e[2]==keys.one then action='1' elseif e[2]==keys.two then action='2'
      elseif e[2]==keys.three then action='3' elseif e[2]==keys.four then action='4' elseif e[2]==keys.five then action='5' end
    elseif e[1]=='mouse_click' then
      local x,y=e[3],e[4];local w,h=term.getSize()
      if y==3 then if x<=11 then action='1' elseif x<=24 then action='2' elseif x<=35 then action='3' elseif x<=46 then action='4' else action='5' end
      elseif view=='pendientes' and y>=6 and y<=h-6 then
        local arr=pending();local maxRows=math.max(1,h-11)
        local g=arr[page*maxRows+y-5]
        if g then choose(g.id);notice='Seleccionado #'..g.id end
      elseif view=='historial' and y>=6 and y<=h-6 then
        local arr={};for _,d in pairs(db.deployments) do arr[#arr+1]=d end
        table.sort(arr,function(a,b)return a.id>b.id end)
        local rows=math.max(1,h-11);local d=arr[page*rows+y-5]
        if d then historySelection=d.id end
      elseif view=='historial' and y==h-4 then
        if x<13 then action='t' else action='v' end
      elseif view=='pendientes' and y==h-4 then
        if x<14 then action='t' elseif x<28 then action='a' else action='r' end
      elseif view=='cajero' and y==12 then action='c'
      elseif view=='cajero' and y==13 then action='k' end
    elseif e[1]=='terminate' then return end
    if action=='1' then view='inicio'
    elseif action=='2' then view='pendientes';page=0;local a=pending();selection=a[1] and a[1].id or nil
    elseif action=='3' then view='cajero'
    elseif action=='4' then view='datos'
    elseif action=='5' then view='historial';page=0;historySelection=nil
    elseif action=='q' then return
    elseif view=='pendientes' then
      local arr=pending();local maxRows=math.max(1,select(2,term.getSize())-11)
      if action=='n' then page=math.min(page+1,math.max(0,math.ceil(#arr/maxRows)-1));selection=arr[page*maxRows+1] and arr[page*maxRows+1].id or nil
      elseif action=='b' then page=math.max(0,page-1);selection=arr[page*maxRows+1] and arr[page*maxRows+1].id or nil
      elseif action=='t' and selection then
        local d=db.deployments[selection]
        if d and d.status=='pending' then
          local result=reviewGame(selection);notice='Prueba terminada: '..tostring(result)
          local a=pending();selection=a[1] and a[1].id or nil
        end
      elseif (action=='a' or action=='r') and selection then
        local d=db.deployments[selection]
        if d and d.status=='pending' then
          local ok,msg=action=='a' and publish(selection,false) or reject(selection)
          notice='D'..selection..': '..tostring(msg)
          local a=pending();selection=a[1] and a[1].id or nil
        end
      end
    elseif view=='historial' then
      local arr={};for _,d in pairs(db.deployments) do arr[#arr+1]=d end
      table.sort(arr,function(a,b)return a.id>b.id end)
      local rows=math.max(1,select(2,term.getSize())-11)
      if action=='n' then page=math.min(page+1,math.max(0,math.ceil(#arr/rows)-1));historySelection=nil
      elseif action=='b' then page=math.max(0,page-1);historySelection=nil
      elseif historySelection then
        local d=db.deployments[historySelection]
        if action=='t' and d then
          local res=reviewGame(d.id);notice='Preview D'..d.id..': '..tostring(res)
        elseif action=='l' and d then
          term.clear();term.setCursorPos(1,1)
          print('DEPLOYMENT D'..d.id..' | '..d.version..' | '..d.status)
          print('Notas: '..(d.notes or ''))
          for _,entry in ipairs(d.logs or {}) do print('> '..entry) end
          print('ENTER para volver');read()
        elseif action=='v' and d then
          term.clear();term.setCursorPos(1,1)
          print('RESTAURAR PRODUCCION D'..d.id..' / '..d.version)
          print('Juego: '..db.games[d.gameId].title)
          print('Escribe RESTAURAR para confirmar:')
          local confirmation=read()
          if confirmation=='RESTAURAR' then
            local ok,msg=publish(d.id,true);notice=msg
          else notice='Cancelado' end
        end
      end
    elseif view=='cajero' then
      if action=='c' then
        term.setBackgroundColor(colors.black);term.clear();print('ID servidor: '..os.getComputerID());print('Cajero actual: '..cashierCfg.cashierId)
        write('ID ordenador cajero (0 para desactivar): ')
        local v=tonumber(read());if v and v>=0 and v==math.floor(v) then cashierCfg.cashierId=v;saveObj(fs.combine(ROOT,'cashier'),cashierCfg);notice='Cajero autorizado: '..v end
      elseif action=='k' then
        term.setBackgroundColor(colors.black);term.clear();print('CLAVE SECRETA DEL CAJERO (NO COMPARTIR):')
        print(cashierCfg.key);print('Pulsa ENTER');read();notice='Clave consultada'
      end
    end
  end
end
parallel.waitForAny(network,admin)

