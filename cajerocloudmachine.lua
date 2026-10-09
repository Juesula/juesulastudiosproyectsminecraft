local PROTOCOLO = "CLOUD_MACHINE_V6"
local SERVER_ID = nil

local function abrirModem()
    local modems = {peripheral.find("modem")}
    if #modems == 0 then return false end
    rednet.open(peripheral.getName(modems[1]))
    return true
end

if not abrirModem() then print("Falta modem.") return end

local function configCajero()
    if fs.exists("cajero_cfg.txt") then
        local f = fs.open("cajero_cfg.txt", "r")
        SERVER_ID = tonumber(f.readAll())
        f.close()
    end
    if not SERVER_ID then
        term.clear(); term.setCursorPos(1,1)
        term.setTextColor(colors.yellow)
        write("Vincular a ID de Servidor (Venta): ")
        term.setTextColor(colors.white)
        SERVER_ID = tonumber(read())
        local f = fs.open("cajero_cfg.txt", "w")
        f.write(tostring(SERVER_ID))
        f.close()
    end
end
configCajero()

local function loopCofres()
    while true do
        local c_in = peripheral.wrap("top")
        local c_out = peripheral.wrap("bottom")

        if c_in and c_out then
            for slot = 1, c_in.size() do
                local item = c_in.getItemDetail(slot)
                if item and item.displayName == "HIERTORRES" then
                    local moved = c_in.pushItems(peripheral.getName(c_out), slot)
                    if moved > 0 then
                        local creditos = moved * 10
                        rednet.send(SERVER_ID, {tipo="ADD_BALANCE", amount=creditos}, PROTOCOLO)
                    end
                end
            end
        end
        os.sleep(1)
    end
end

local function loopPantalla()
    while true do
        rednet.send(SERVER_ID, {tipo="GET_VENTA"}, PROTOCOLO)
        local t = os.startTimer(2)
        local msg_recibido = nil
        
        while true do
            local ev = {os.pullEvent()}
            if ev[1] == "rednet_message" and ev[2] == SERVER_ID and ev[3].tipo == "INFO_VENTA" then
                msg_recibido = ev[3]
                break
            elseif ev[1] == "timer" and ev[2] == t then break end
        end
        
        term.setBackgroundColor(colors.black)
        term.clear(); term.setCursorPos(1,1)
        term.setTextColor(colors.green)
        print("=== CAJERO AUTOMATICO ===")
        term.setTextColor(colors.white)
        print("Servidor Vinculado: " .. SERVER_ID)
        
        if msg_recibido then
            print("Estado: " .. msg_recibido.status)
            print("Dueño:  " .. (msg_recibido.owner or "Nadie"))
            print("Saldo:  " .. msg_recibido.balance .. " creditos")
        else
            term.setTextColor(colors.red)
            print("\n[!] SERVIDOR DESCONECTADO")
            term.setTextColor(colors.white)
        end
        
        term.setCursorPos(1, 8)
        term.setTextColor(colors.gray)
        print("-------------------------")
        print("1 HIERTORRE = 10 creditos (5 min)")
        print("Inserta HIERTORRES en cofre ARRIBA.")
        
        os.sleep(3)
    end
end

parallel.waitForAny(loopPantalla, loopCofres)
