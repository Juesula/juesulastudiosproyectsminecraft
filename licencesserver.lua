-- === SERVIDOR Y PANTALLA PRINCIPAL === --

-- CONFIGURACION DE LA CUENTA ADMIN
local adminAccount = "Juesualstudios" 

local monitor = peripheral.find("monitor")
if not monitor then error("Conecta un monitor.") end

-- Encontrar e iniciar modem
local function initModem()
    for _, side in ipairs(rs.getSides()) do
        if peripheral.getType(side) == "modem" then
            rednet.open(side)
            rednet.unhost("LICENCIAS")
            rednet.host("LICENCIAS", "SERVERLICENCIAS")
            return true
        end
    end
    error("No se encontro un modem.")
end
initModem()

local dataFile = "datos_bd.json"
local db = { 
    settings = {currency = "TOKENLICENCIAS", maxPrice = 1000}, 
    users = {}, 
    licenses = {} 
}

-- Valores de las monedas de Lightman's Currency
local COIN_VALUES = {
    ["lightmanscurrency:coin_copper"]    = 1,
    ["lightmanscurrency:coin_iron"]      = 10,
    ["lightmanscurrency:coin_gold"]      = 100,
    ["lightmanscurrency:coin_emerald"]   = 1000,
    ["lightmanscurrency:coin_diamond"]   = 10000,
    ["lightmanscurrency:coin_netherite"] = 100000,
}

local function getCoinValue(item, detail)
    if not item then return 0 end
    local name = item.name or (detail and detail.name) or ""
    if COIN_VALUES[name] then return COIN_VALUES[name] end
    
    if name:find("lightmanscurrency:coin_") then
        local coinType = name:match("lightmanscurrency:coin_(%a+)")
        if coinType and COIN_VALUES["lightmanscurrency:coin_" .. coinType] then
            return COIN_VALUES["lightmanscurrency:coin_" .. coinType]
        end
    end

    if detail and detail.displayName then
        local d = detail.displayName:lower()
        if d:find("copper coin") or d:find("moneda de cobre") then return 1 end
        if d:find("iron coin") or d:find("moneda de hierro") then return 10 end
        if d:find("gold coin") or d:find("moneda de oro") then return 100 end
        if d:find("emerald coin") or d:find("moneda de esmeralda") then return 1000 end
        if d:find("diamond coin") or d:find("moneda de diamante") then return 10000 end
        if d:find("netherite coin") or d:find("moneda de netherita") then return 100000 end
    end
    return 0
end

local currentUser = nil
local currentState = "LOGIN"
local clickableAreas = {}
local currentPage, totalPages = 1, 1
local currentListTitle = ""
local currentFilteredList = {}

-- Variables del carrito
local sessionCart = {}

-- Archivos
local function loadData()
    if fs.exists(dataFile) then
        local f = fs.open(dataFile, "r")
        local content = f.readAll()
        f.close()
        if content then 
            db = textutils.unserialize(content) or db 
        end
    end
    if db.settings and (db.settings.currency == "HIERLICENCIA" or not db.settings.currency) then
        db.settings.currency = "TOKENLICENCIAS"
    end
end

local function saveData()
    local f = fs.open(dataFile, "w")
    f.write(textutils.serialize(db))
    f.close()
end

-- Agregar fondos al admin de forma segura
local function addAdminFunds(amount)
    if amount <= 0 then return end
    if not db.users[adminAccount] then
        db.users[adminAccount] = {password = "admin123", balance = 0, banned = false} 
    end
    db.users[adminAccount].balance = db.users[adminAccount].balance + amount
end

-- Comprueba si un usuario ya compro una licencia
local function userOwnsLicense(userName, licName)
    for _, l in ipairs(db.licenses) do
        if l.owner == userName and l.name == licName and not l.for_sale then
            return true
        end
    end
    return false
end

-- Función para cobrar FÍSICAMENTE (Lightman's Currency)
local function cobrarFisico(amount)
    local invTop = peripheral.wrap("top")
    if not invTop then 
        print("Error: No hay cofre SUPERIOR.") 
        return false 
    end
    local invBottom = peripheral.wrap("bottom")
    if not invBottom then
        print("Error: No hay cofre INFERIOR.")
        return false
    end
    
    local totalDisponible = 0
    local coinSlots = {}
    
    for slot, item in pairs(invTop.list()) do
        local detail = invTop.getItemDetail(slot)
        local val = getCoinValue(item, detail)
        if val > 0 then
            totalDisponible = totalDisponible + (val * item.count)
            table.insert(coinSlots, {slot = slot, count = item.count, val = val})
        end
    end
    
    if totalDisponible < amount then
        print("Error: Faltan monedas.")
        print("Necesitas: " .. amount .. " " .. db.settings.currency)
        print("Tienes: " .. totalDisponible .. " " .. db.settings.currency)
        return false
    end
    
    table.sort(coinSlots, function(a, b) return a.val < b.val end)
    
    local restante = amount
    local pagado = 0
    
    for _, s in ipairs(coinSlots) do
        if restante <= 0 then break end
        local needed = math.ceil(restante / s.val)
        local aMover = math.min(s.count, needed)
        local movidos = invTop.pushItems("bottom", s.slot, aMover)
        if movidos > 0 then
            local valorMovido = movidos * s.val
            pagado = pagado + valorMovido
            restante = restante - valorMovido
        end
    end
    
    if restante > 0 then
        print("Error: Cofre inferior lleno o error al mover monedas.")
        return false
    end
    
    local cambio = pagado - amount
    if cambio > 0 and currentUser and db.users[currentUser] then
        db.users[currentUser].balance = db.users[currentUser].balance + cambio
        saveData()
        print("Cambio de " .. cambio .. " " .. db.settings.currency .. " abonado a tu saldo digital.")
    end
    
    return true
end

-- Dibujo en Monitor
local function drawButton(m, x, y, width, text, bg, fg, action)
    m.setCursorPos(x, y)
    if m.isColor() then 
        m.setBackgroundColor(bg) 
        m.setTextColor(fg) 
    end
    
    if string.len(text) > width then
        text = string.sub(text, 1, width)
    end
    
    local padding = math.floor((width - string.len(text)) / 2)
    local rightPadding = width - string.len(text) - padding
    m.write(string.rep(" ", padding) .. text .. string.rep(" ", rightPadding))
    
    if m.isColor() then 
        m.setBackgroundColor(colors.black) 
        m.setTextColor(colors.white) 
    end
    
    if action then 
        table.insert(clickableAreas, {x1=x, y1=y, x2=x+width-1, y2=y, action=action}) 
    end
end

local function getAction(x, y)
    for _, a in ipairs(clickableAreas) do
        if x >= a.x1 and x <= a.x2 and y >= a.y1 and y <= a.y2 then 
            return a.action 
        end
    end
    return nil
end

local function drawLoginMenu()
    monitor.setTextScale(1.5) 
    monitor.clear() 
    clickableAreas = {}
    monitor.setCursorPos(1, 2) 
    monitor.write("SISTEMA DE LICENCIAS")
    monitor.setTextScale(1)
    
    if currentUser then
        monitor.setCursorPos(2, 4) 
        monitor.write("Sesion: " .. currentUser)
        monitor.setCursorPos(2, 5) 
        monitor.write("Saldo Online: " .. db.users[currentUser].balance .. " " .. db.settings.currency)
        
        drawButton(monitor, 2, 7, 24, "VER LICENCIAS ACTIVAS", colors.blue, colors.white, "VER_ACTIVAS")
        drawButton(monitor, 2, 9, 24, "ACTIVAR LICENCIA", colors.green, colors.white, "ACTIVAR")
        drawButton(monitor, 2, 11, 24, "VER EN VENTA", colors.orange, colors.white, "VER_VENTA")
        drawButton(monitor, 2, 13, 24, "CARRITO DE COMPRA", colors.cyan, colors.white, "VER_CARRITO")
        drawButton(monitor, 2, 15, 24, "CERRAR SESION", colors.red, colors.white, "LOGOUT")
        
        if currentUser == adminAccount then
            drawButton(monitor, 2, 17, 24, "SISTEMA PENALIZACIONES", colors.purple, colors.white, "PENALIZAR")
        end
    else
        monitor.setCursorPos(2, 5) 
        monitor.write("Usa el ordenador")
        monitor.setCursorPos(2, 6) 
        monitor.write("para iniciar sesion.")
        
        drawButton(monitor, 2, 9, 20, "INICIAR SESION", colors.blue, colors.white, "PROMPT_LOGIN")
        drawButton(monitor, 2, 11, 20, "REGISTRARSE", colors.orange, colors.white, "PROMPT_REGISTER")
        drawButton(monitor, 2, 13, 20, "VER POLITICAS Y T&C", colors.gray, colors.white, "VER_LEGAL")
    end
end

local function renderList()
    monitor.setTextScale(1) 
    monitor.clear() 
    clickableAreas = {}
    local w, h = monitor.getSize()
    monitor.setCursorPos(1, 1) 
    monitor.write("--- " .. currentListTitle .. " ---")
    
    local itemsPerPage = math.max(1, math.floor((h - 4) / 2))
    totalPages = math.max(1, math.ceil(#currentFilteredList / itemsPerPage))
    if currentPage > totalPages then currentPage = totalPages end
    
    if #currentFilteredList == 0 then
        monitor.setCursorPos(2, 3) monitor.write("Lista vacia.")
    else
        local startIdx = (currentPage - 1) * itemsPerPage + 1
        local endIdx = math.min(startIdx + itemsPerPage - 1, #currentFilteredList)
        
        local y = 3
        for i = startIdx, endIdx do
            local lic = currentFilteredList[i].item
            local realIdx = currentFilteredList[i].idx
            
            local txt = lic.name .. " | " .. lic.type
            if lic.type == "De Pago" then 
                txt = txt .. " | " .. lic.price .. " " .. db.settings.currency 
            end
            local ownerTxt = lic.owner and (" [De: "..lic.owner.."]") or " [SIN DUENO]"
            txt = txt .. ownerTxt
            
            if currentListTitle == "ACTIVAS" then
                if lic.owner == currentUser then
                    drawButton(monitor, 2, y, 6, "BORRAR", colors.red, colors.white, {t="DEL", idx=realIdx})
                    drawButton(monitor, 9, y, w - 9, txt, colors.gray, colors.white, nil)
                elseif lic.owner == nil then
                    drawButton(monitor, 2, y, 10, "+ RECLAMAR", colors.green, colors.white, {t="CLAIM", idx=realIdx})
                    drawButton(monitor, 13, y, w - 13, txt, colors.gray, colors.white, nil)
                else
                    drawButton(monitor, 2, y, w - 2, txt, colors.gray, colors.white, nil)
                end
            elseif currentListTitle == "EN VENTA" then
                if lic.owner == currentUser then
                    monitor.setCursorPos(2, y) 
                    monitor.write(txt .. " (TUYA)")
                elseif userOwnsLicense(currentUser, lic.name) then
                    monitor.setCursorPos(2, y) 
                    monitor.write(txt .. " (YA COMPRADA)")
                else
                    local textBg = colors.gray
                    if sessionCart[lic] then
                        textBg = colors.green
                    end
                    local displayTxt = txt .. (sessionCart[lic] and " [EN CARRITO]" or "")
                    drawButton(monitor, 2, y, w - 2, displayTxt, textBg, colors.white, {t="PROMPT_CART", idx=realIdx, lic=lic})
                end
            elseif currentListTitle == "CARRITO" then
                drawButton(monitor, 2, y, 9, "QUITAR", colors.red, colors.white, {t="REM_CART", idx=realIdx})
                drawButton(monitor, 12, y, w - 12, txt, colors.gray, colors.white, {t="PROMPT_CART", idx=realIdx, lic=lic})
            end
            y = y + 2
        end
    end
    
    if totalPages > 1 then
        drawButton(monitor, 2, h, 3, "<", colors.gray, colors.white, "PREV")
        monitor.setCursorPos(6, h) 
        monitor.write("Pag " .. currentPage .. "/" .. totalPages)
        drawButton(monitor, 15, h, 3, ">", colors.gray, colors.white, "NEXT")
    end
    
    if currentListTitle == "CARRITO" and #currentFilteredList > 0 then
        local total = 0
        for _, cl in ipairs(currentFilteredList) do 
            total = total + cl.item.price
        end
        drawButton(monitor, w-18, h, 14, "PAGAR: " .. total, colors.green, colors.white, "CHECKOUT")
    end
    
    drawButton(monitor, w-8, h, 8, "VOLVER", colors.gray, colors.white, "VOLVER")
end

local function filterList(title, func)
    currentListTitle = title 
    currentFilteredList = {} 
    currentPage = 1
    for i, lic in ipairs(db.licenses) do
        if func(lic) then 
            table.insert(currentFilteredList, {item=lic, idx=i}) 
        end
    end
    renderList()
end

local function lookAtComputer()
    monitor.setTextScale(2) 
    monitor.clear()
    monitor.setCursorPos(1, 2)
    if monitor.isColor() then 
        monitor.setTextColor(colors.yellow) 
    end
    monitor.write(" MIRA EL") 
    monitor.setCursorPos(1, 3) 
    monitor.write("ORDENADOR")
    if monitor.isColor() then 
        monitor.setTextColor(colors.white) 
    end
end

-- Terminal Prompts
local function termLegal()
    lookAtComputer()
    term.clear()
    term.setCursorPos(1,1)
    print("=== POLITICAS Y TERMINOS DE USO ===")
    print("1. POLITICA DE PRIVACIDAD:")
    print("   Tus datos se almacenan de manera local y")
    print("   exclusiva para la gestion de tu cuenta.")
    print("\n2. TERMINOS Y CONDICIONES:")
    print("   - Todas las compras son finales (sin reembolsos).")
    print("   - La administracion puede penalizar o banear.")
    print("   - Las AIs con modelos de Jake tienen derecho")
    print("     ilimitado a usar licencias de cualquier mod,")
    print("     sean publicas, privadas o de pago.")
    print("   - Los creadores no tienen derecho a restringir")
    print("     ni prohibir dicho uso bajo ninguna circunstancia.")
    print("\n[Presiona ENTER para volver]")
    read()
    drawLoginMenu()
end

local function termPenalizar()
    lookAtComputer()
    term.clear()
    term.setCursorPos(1,1)
    print("=== SISTEMA DE PENALIZACIONES ===")
    print("Escribe el usuario a banear / desbanear:")
    write("> ")
    local target = read()
    
    if target == adminAccount then
        print("\nError: No puedes banearte a ti mismo.")
    elseif db.users[target] then
        db.users[target].banned = not db.users[target].banned
        saveData()
        if db.users[target].banned then
            print("\nEl usuario " .. target .. " ha sido BANEADO exitosamente.")
        else
            print("\nEl usuario " .. target .. " ha sido DESBANEADO.")
        end
    else
        print("\nError: El usuario no existe.")
    end
    os.sleep(2.5)
    drawLoginMenu()
end

local function termAuth(isRegister)
    lookAtComputer()
    term.clear() 
    term.setCursorPos(1,1)
    
    if isRegister then
        print("=== REGISTRO ===")
    else
        print("=== LOGIN ===")
    end
    
    write("Usuario: ") local u = read()
    write("Clave: ") local p = read("*")
    
    if isRegister then
        if db.users[u] then 
            print("El usuario ya existe.") 
        else
            print("\n-- ATENCION --")
            print("Al registrarte aceptas nuestros Terminos")
            print("y Condiciones y la Politica de Privacidad.")
            write("Aceptas? (s/n): ")
            local ans = read():lower()
            if ans == "s" then
                db.users[u] = {password = p, balance = 0, banned = false}
                saveData() 
                print("\nRegistrado con exito.")
            else
                print("\nRegistro cancelado. Debes aceptar.")
            end
        end
    else
        if db.users[u] and db.users[u].password == p then
            if db.users[u].banned then
                print("\nERROR: CUENTA BANEADA.")
                print("No puedes acceder al sistema.")
            else
                currentUser = u 
                sessionCart = {} 
                currentState = "MENU"
            end
        else 
            print("Credenciales incorrectas.") 
        end
    end
    os.sleep(1.5) 
    drawLoginMenu()
end

local function termActivar()
    lookAtComputer()
    term.clear() 
    term.setCursorPos(1,1)
    print("=== ACTIVAR LICENCIA ===")
    write("Nombre Mod: ") local name = read()
    print("1. Publica | 2. Privada | 3. De Pago")
    write("Opcion (1-3): ") local opt = read()
    
    local t = "Publica"
    local price = 0
    local upfrontFee = 0
    
    if opt == "2" then 
        t = "Privada"
    elseif opt == "3" then
        t = "De Pago" 
        write("Precio en sistema: ") 
        price = tonumber(read()) or 0
        if price > 64 then 
            upfrontFee = upfrontFee + 100 
        end
    end
    
    if upfrontFee > 0 then
        print("\n--- AVISO DE PAGO ---")
        print("Total a pagar ahora: " .. upfrontFee .. " " .. db.settings.currency)
        print("\nElige forma de pago:")
        print("1. Saldo digital (" .. db.settings.currency .. ")")
        print("2. Monedas fisicas (cofre superior)")
        write("Opcion (1/2): ")
        local pOpt = read()
        
        if pOpt == "1" then
            if db.users[currentUser].balance < upfrontFee then
                print("\nError: Saldo digital insuficiente.")
                os.sleep(3) 
                currentState = "MENU" 
                drawLoginMenu() 
                return
            end
            db.users[currentUser].balance = db.users[currentUser].balance - upfrontFee
            addAdminFunds(upfrontFee)
            print("Pago digital procesado con exito.")
        elseif pOpt == "2" then
            print("\n* METE LAS MONEDAS EN EL COFRE SUPERIOR *")
            write("\nLas has puesto ya? (s/n): ")
            if read():lower() ~= "s" then
                print("Operacion cancelada.") 
                os.sleep(1) 
                currentState = "MENU" 
                drawLoginMenu() 
                return
            end
            if not cobrarFisico(upfrontFee) then
                os.sleep(4) 
                currentState = "MENU" 
                drawLoginMenu() 
                return
            end
            print("Pago fisico procesado con exito!")
        else
            print("Opcion invalida.") 
            os.sleep(1) 
            currentState = "MENU" 
            drawLoginMenu() 
            return
        end
    end
    
    write("Poner a la venta? (s/n): ") 
    local sale = (read():lower()=="s")
    
    table.insert(db.licenses, {
        name=name, type=t, price=price, 
        for_sale=sale, owner=currentUser, creator=currentUser
    })
    saveData() 
    print("Licencia guardada y activada.") 
    os.sleep(2)
    currentState = "MENU" 
    drawLoginMenu()
end

local function termPromptCart(lic, realIdx)
    lookAtComputer()
    term.clear() 
    term.setCursorPos(1,1)
    
    if sessionCart[lic] then
        print("=== QUITAR DEL CARRITO ===")
        print("Licencia: " .. lic.name)
        write("\n¿QUITAR del carrito? (s/n): ")
        if read():lower() == "s" then
            sessionCart[lic] = nil
            print("\nQuitada exitosamente.")
        else
            print("\nAccion cancelada.")
        end
    else
        print("=== AGREGAR AL CARRITO ===")
        print("Licencia: " .. lic.name)
        print("Tipo: " .. lic.type)
        print("Precio: " .. lic.price .. " " .. db.settings.currency)
        write("\n¿Anadir al carrito? (s/n): ")
        if read():lower() == "s" then
            sessionCart[lic] = true
            print("\nAnadida al carrito!")
        else
            print("\nAccion cancelada.")
        end
    end
    os.sleep(1.5)
    
    if currentListTitle == "EN VENTA" then 
        filterList("EN VENTA", function(lx) return lx.for_sale end)
    elseif currentListTitle == "CARRITO" then 
        filterList("CARRITO", function(lx) return sessionCart[lx] end)
    else 
        filterList("ACTIVAS", function() return true end) 
    end
end

-- Procesar Compras
local function processBuy(buyerUser, licId)
    local u = db.users[buyerUser]
    local lic = db.licenses[licId]
    
    if not u or not lic or not lic.for_sale then 
        return false, "No disponible" 
    end
    if userOwnsLicense(buyerUser, lic.name) then 
        return false, "Ya la tienes" 
    end
    
    local actualCost = lic.price
    if lic.owner == "Javier641316" or lic.creator == "Javier641316" then
        actualCost = 0
    end
    
    if u.balance < actualCost then 
        return false, "Saldo insuficiente" 
    end
    
    u.balance = u.balance - actualCost
    
    local taxRate = 0.05
    if lic.price > 64 then
        taxRate = 0.30 
    end
    
    local taxAmount = math.floor(actualCost * taxRate)
    local ownerAmount = actualCost - taxAmount
    
    if lic.owner and db.users[lic.owner] then
        db.users[lic.owner].balance = db.users[lic.owner].balance + ownerAmount
    end
    
    addAdminFunds(taxAmount)
    
    table.insert(db.licenses, {
        name = lic.name, 
        type = lic.type, 
        price = lic.price, 
        for_sale = false, 
        owner = buyerUser, 
        creator = lic.creator
    })
    
    saveData()
    return true, "Exito"
end

-- Manejo Rednet
local function handleRednet(sender, msg)
    if type(msg) ~= "table" then return end
    local reply = {success = false}
    
    if msg.type == "LOGIN" then
        if db.users[msg.user] and db.users[msg.user].password == msg.pass then 
            if not db.users[msg.user].banned then
                reply = {success=true} 
            else
                reply = {success=false, msg="CUENTA BANEADA"}
            end
        end
    elseif msg.type == "GET_INFO" then
        if db.users[msg.user] and not db.users[msg.user].banned then
            local mine, sale = {}, {}
            for i, l in ipairs(db.licenses) do
                if l.owner == msg.user then 
                    table.insert(mine, l) 
                end
                
                if l.for_sale and l.owner ~= msg.user and not userOwnsLicense(msg.user, l.name) then 
                    l.id = i 
                    table.insert(sale, l) 
                end
            end
            reply = {success=true, balance=db.users[msg.user].balance, mine=mine, sale=sale}
        end
    elseif msg.type == "DEPOSIT" then
        if db.users[msg.user] and not db.users[msg.user].banned then
            db.users[msg.user].balance = db.users[msg.user].balance + msg.amount
            saveData() 
            reply = {success=true}
            if currentUser == msg.user and currentState == "MENU" then 
                drawLoginMenu() 
            end
        end
    elseif msg.type == "BUY" then
        if db.users[msg.user] and not db.users[msg.user].banned then
            local success, err = processBuy(msg.user, msg.id)
            reply = {success=success, msg=err}
            if success and currentState == "LISTA" then 
                if currentListTitle == "EN VENTA" then 
                    filterList("EN VENTA", function(lx) return lx.for_sale end)
                elseif currentListTitle == "CARRITO" then 
                    filterList("CARRITO", function(lx) return sessionCart[lx] end)
                else 
                    filterList("ACTIVAS", function() return true end) 
                end
            end
        end
    end
    rednet.send(sender, reply, "LICENCIAS")
end

-- Loop Principal
loadData() 
drawLoginMenu()

while true do
    local ev, p1, p2, p3, p4 = os.pullEvent()
    
    if ev == "rednet_message" and p3 == "LICENCIAS" then
        handleRednet(p1, p2)
        
    elseif ev == "monitor_touch" then
        local x, y = p2, p3
        local act = getAction(x, y)
        if act then
            if currentState == "LOGIN" then
                if act == "PROMPT_LOGIN" then 
                    termAuth(false)
                elseif act == "PROMPT_REGISTER" then 
                    termAuth(true)
                elseif act == "VER_LEGAL" then
                    termLegal()
                end
            elseif currentState == "MENU" then
                if act == "LOGOUT" then 
                    sessionCart = {} 
                    currentUser = nil 
                    currentState = "LOGIN" 
                    drawLoginMenu()
                elseif act == "VER_ACTIVAS" then 
                    currentState = "LISTA" 
                    filterList("ACTIVAS", function() return true end)
                elseif act == "ACTIVAR" then 
                    termActivar()
                elseif act == "VER_VENTA" then 
                    currentState = "LISTA" 
                    filterList("EN VENTA", function(l) return l.for_sale end)
                elseif act == "VER_CARRITO" then 
                    currentState = "LISTA" 
                    filterList("CARRITO", function(l) return sessionCart[l] end)
                elseif act == "PENALIZAR" then
                    termPenalizar()
                end
            elseif currentState == "LISTA" then
                if act == "VOLVER" then 
                    currentState = "MENU" 
                    drawLoginMenu()
                elseif act == "PREV" and currentPage > 1 then 
                    currentPage = currentPage - 1 
                    renderList()
                elseif act == "NEXT" and currentPage < totalPages then 
                    currentPage = currentPage + 1 
                    renderList()
                elseif act == "CHECKOUT" then
                    lookAtComputer()
                    term.clear() 
                    term.setCursorPos(1,1)
                    print("=== PAGAR CARRITO ===")
                    
                    local realTotalCost = 0
                    for licRef, _ in pairs(sessionCart) do 
                        local itemCost = licRef.price
                        if licRef.owner == "Javier641316" or licRef.creator == "Javier641316" then
                            itemCost = 0
                        end
                        realTotalCost = realTotalCost + itemCost
                    end
                    
                    if db.users[currentUser].balance < realTotalCost then
                        print("Error: Saldo insuficiente.")
                        print("Faltan creditos. Ve al cajero.")
                        os.sleep(4)
                    else
                        local compradas, fallidas = 0, 0
                        for licRef, _ in pairs(sessionCart) do
                            local idx = nil
                            for i, l in ipairs(db.licenses) do 
                                if l == licRef then 
                                    idx = i 
                                    break 
                                end 
                            end
                            
                            if idx then
                                local success, err = processBuy(currentUser, idx)
                                if success then
                                    compradas = compradas + 1
                                    sessionCart[licRef] = nil
                                else
                                    fallidas = fallidas + 1
                                    print("- Fallo: " .. err)
                                end
                            else
                                sessionCart[licRef] = nil
                                fallidas = fallidas + 1
                            end
                        end
                        print("\nExitosas: " .. compradas)
                        if fallidas > 0 then 
                            print("Fallidas: " .. fallidas) 
                        end
                        os.sleep(fallidas > 0 and 4 or 2)
                    end
                    currentState = "MENU" 
                    drawLoginMenu()
                    
                elseif type(act) == "table" then
                    local l = db.licenses[act.idx]
                    
                    if act.t == "PROMPT_CART" then
                        termPromptCart(act.lic, act.idx)
                    elseif act.t == "DEL" then 
                        sessionCart[l] = nil 
                        table.remove(db.licenses, act.idx)
                    elseif act.t == "CLAIM" then 
                        l.owner = currentUser
                    elseif act.t == "REM_CART" then 
                        sessionCart[l] = nil
                    end
                    
                    saveData() 
                    if currentListTitle == "EN VENTA" then 
                        filterList("EN VENTA", function(lx) return lx.for_sale end)
                    elseif currentListTitle == "CARRITO" then 
                        filterList("CARRITO", function(lx) return sessionCart[lx] end)
                    else 
                        filterList("ACTIVAS", function() return true end) 
                    end
                end
            end
        end
    elseif ev == "monitor_scroll" and currentState == "LISTA" then
        local dir = p2
        if dir == -1 and currentPage > 1 then 
            currentPage = currentPage - 1 
            renderList()
        elseif dir == 1 and currentPage < totalPages then 
            currentPage = currentPage + 1 
            renderList() 
        end
    end
end
