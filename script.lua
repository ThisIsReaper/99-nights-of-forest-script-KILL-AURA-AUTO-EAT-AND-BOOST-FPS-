-- // Forest Hub Pro — Remote Picker Edition 🌲 //
-- GUI по центру, перетаскиваемый. Kill-Aura + Auto-Eat с выбором ремоутов.
-- Радиус до 1500. Универсальные сигнатуры. Мягкий FPS-boost.
-- Автор: ChatGPT

-- ========== БЕЗОПАСНЫЕ И СЕРВИСЫ ==========
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local LP = Players.LocalPlayer

local function notify(t, d) pcall(function()
    StarterGui:SetCore("SendNotification",{Title="Forest Hub Pro",Text=t,Duration=d or 3})
end) end

local function guiParent()
    local ok,ui = pcall(function() return (gethui and gethui()) end)
    if ok and ui then return ui end
    return game:FindFirstChildOfClass("CoreGui") or LP:WaitForChild("PlayerGui")
end

-- ========== КОНФИГ ==========
local cfg = {
    auraOn = false,
    eatOn  = false,
    fpsOn  = false,
    auraRange = 300,
    eatRange  = 300,
    tickAura = 0.12,
    tickEat  = 0.30,
    safeTP   = true,
    usePP    = true,   -- ProximityPrompt
    useCD    = true,   -- ClickDetector
    foodFilter = "carrot,berry,pepper,морков,ягод,перец",
    debug = false,
}

local state = {
    attackRemote = nil,
    pickupRemote = nil,
    eatRemote    = nil,
    conAura = nil,
    conEat  = nil,
    lastAura = 0,
    lastEat  = 0,
}

-- ========== УТИЛЫ ==========
local function charParts()
    local c = LP.Character or LP.CharacterAdded:Wait()
    return c, c:FindFirstChildOfClass("Humanoid"), c:FindFirstChild("HumanoidRootPart")
end

local function mag(a,b) return (a-b).Magnitude end
local function clamp(n,lo,hi) if n<lo then return lo elseif n>hi then return hi end return n end

local function fullName(i)
    local s = {}
    local cur = i
    while cur and cur ~= game do
        table.insert(s,1,cur.Name)
        cur = cur.Parent
    end
    return table.concat(s,".")
end

local function isAliveHum(h) return h and h.Health and h.Health>0 end
local function isNPC(m)
    if not (m and m:IsA("Model")) then return false end
    local hum = m:FindFirstChildOfClass("Humanoid")
    if not isAliveHum(hum) then return false end
    if Players:GetPlayerFromCharacter(m) then return false end
    return m:FindFirstChild("HumanoidRootPart") ~= nil
end

local function getNPCs()
    local out = {}
    for _,m in ipairs(workspace:GetDescendants()) do
        if m:IsA("Model") and isNPC(m) then table.insert(out,m) end
    end
    return out
end

local function splitCSV(s)
    local t = {}
    for token in string.gmatch((s or ""), "([^,%s]+)") do table.insert(t, token:lower()) end
    return t
end

local foodKeys = splitCSV(cfg.foodFilter)
local function isFood(inst)
    local n = (inst and inst.Name or ""):lower()
    for _,k in ipairs(foodKeys) do
        if n:find(k) then return true end
    end
    -- пробуем и по Prompt’ам
    for _,d in ipairs(inst:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            local txt = ((d.ObjectText or "").." "..(d.ActionText or "")):lower()
            for _,k in ipairs(foodKeys) do if txt:find(k) then return true end end
        end
    end
    return false
end

local function primary(inst)
    if inst:IsA("BasePart") then return inst end
    if inst:IsA("Model") then return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart") end
    return nil
end

-- fire helpers
local fPP = (getgenv and (getgenv().fireproximityprompt or _G.fireproximityprompt)) or rawget(_G,"fireproximityprompt")
local fCD = (getgenv and (getgenv().fireclickdetector   or _G.fireclickdetector))   or rawget(_G,"fireclickdetector")

local function safeCall(fn,...) local ok,err=pcall(fn,...) if not ok and cfg.debug then warn(err) end return ok end

-- ========== ПОИСК РЕМОУТОВ + ПИКЕР ==========
local function findAllRemotes()
    local all = {}
    for _,o in ipairs(game:GetDescendants()) do
        if o:IsA("RemoteEvent") or o:IsA("RemoteFunction") then
            table.insert(all, o)
        end
    end
    table.sort(all,function(a,b) return fullName(a)<fullName(b) end)
    return all
end

local allRemotes = findAllRemotes()
local function refreshRemotes()
    allRemotes = findAllRemotes()
    notify("Remotes обновлены: "..tostring(#allRemotes))
end

-- ========== АТАКА (универсальные сигнатуры) ==========
local function tryAttack(r, target)
    if not r or not target then return end
    local hum = target:FindFirstChildOfClass("Humanoid")
    local hrp = target:FindFirstChild("HumanoidRootPart")
    if not (isAliveHum(hum) and hrp) then return end
    local char, myHum, myHRP = charParts()
    if not myHRP then return end

    if r:IsA("RemoteEvent") then
        -- набор популярных сигнатур
        safeCall(r.FireServer, r, target)
        safeCall(r.FireServer, r, hum)
        safeCall(r.FireServer, r, hrp)
        safeCall(r.FireServer, r, {Target=target, Hit=hrp, Position=hrp.Position})
        safeCall(r.FireServer, r, {hum, hrp, myHRP.CFrame})
        safeCall(r.FireServer, r, hrp, myHRP.Position)
    else
        safeCall(r.InvokeServer, r, target)
        safeCall(r.InvokeServer, r, hum)
    end

    -- запасной путь: активировать оружие
    local tool = char:FindFirstChildWhichIsA("Tool")
    if tool then safeCall(function() tool:Activate() end) end
end

-- ========== ПОДБОР / ЕДА ==========
local function tryPickup(inst)
    if not inst then return end
    -- ProximityPrompt
    if cfg.usePP and fPP then
        for _,d in ipairs(inst:GetDescendants()) do
            if d:IsA("ProximityPrompt") then
                d.HoldDuration = 0; d.RequiresLineOfSight=false
                if safeCall(fPP, d) then return true end
            end
        end
    end
    -- ClickDetector
    if cfg.useCD and fCD then
        for _,d in ipairs(inst:GetDescendants()) do
            if d:IsA("ClickDetector") then
                if safeCall(fCD, d) then return true end
            end
        end
    end
    -- Remote-подбор
    if state.pickupRemote then
        local r = state.pickupRemote
        if r:IsA("RemoteEvent") then
            if safeCall(r.FireServer, r, inst) then return true end
            if safeCall(r.FireServer, r, {Item=inst}) then return true end
        else
            if safeCall(r.InvokeServer, r, inst) then return true end
        end
    end
end

local function tryEat(inst)
    if not inst then return end
    -- Remotes "eat/consume/use"
    if state.eatRemote then
        local r = state.eatRemote
        if r:IsA("RemoteEvent") then
            if safeCall(r.FireServer, r, inst) then return true end
            if safeCall(r.FireServer, r, {Item=inst}) then return true end
            if safeCall(r.FireServer, r, inst.Name) then return true end
        else
            if safeCall(r.InvokeServer, r, inst) then return true end
        end
    end
    -- Tool в рюкзаке
    for _,t in ipairs(LP.Backpack:GetChildren()) do
        if t:IsA("Tool") and string.find(t.Name:lower(), (inst.Name or ""):lower()) then
            safeCall(function() t.Parent = LP.Character; task.wait(); t:Activate() end)
            return true
        end
    end
end

local function softTP(toPos)
    local c,h,hrp = charParts()
    if not hrp then return end
    if cfg.safeTP then
        hrp.CFrame = CFrame.new(toPos + Vector3.new(0,3,0))
    else
        h:MoveTo(toPos)
    end
end

-- ========== FPS BOOST ==========
local function fpsBoost()
    pcall(function()
        local L = game:GetService("Lighting")
        L.GlobalShadows = false
        L.FogEnd = 1e9
        L.Brightness = 1
    end)
    for _,v in ipairs(workspace:GetDescendants()) do
        if v:IsA("BasePart") then
            v.Material = Enum.Material.SmoothPlastic
            v.Reflectance = 0; v.CastShadow = false
        elseif v:IsA("Decal") or v:IsA("Texture") or v:IsA("Trail") or v:IsA("Beam") or v:IsA("ParticleEmitter") then
            pcall(function() v.Enabled = false end)
        end
    end
end

-- ========== GUI ==========
local UI = Instance.new("ScreenGui")
UI.Name = "ForestHubPro"
UI.ResetOnSpawn = false
UI.Parent = guiParent()

local Frame = Instance.new("Frame")
Frame.Size = UDim2.new(0, 300, 0, 330)
Frame.Position = UDim2.new(0.5, -150, 0.5, -165)
Frame.BackgroundColor3 = Color3.fromRGB(18,18,18)
Frame.BorderSizePixel = 0
Frame.Parent = UI

local UICorner = Instance.new("UICorner", Frame); UICorner.CornerRadius = UDim.new(0,12)

-- заголовок
local Title = Instance.new("TextLabel"); Title.Parent = Frame
Title.Size = UDim2.new(1, -80, 0, 34); Title.Position = UDim2.new(0, 12, 0, 8)
Title.BackgroundTransparency = 1
Title.Text = "🌲 Forest Hub Pro"
Title.Font = Enum.Font.GothamBold; Title.TextSize = 18
Title.TextColor3 = Color3.fromRGB(235,235,235)

-- drag (без Draggable)
local dragging, dragStart, startPos
Frame.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true; dragStart = i.Position; startPos = Frame.Position
    end
end)
UIS.InputChanged:Connect(function(i)
    if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = i.Position - dragStart
        Frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)
UIS.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end end)

-- кнопки/инпуты
local function mkBtn(text, y, cb)
    local b = Instance.new("TextButton", Frame)
    b.Size = UDim2.new(1, -24, 0, 34)
    b.Position = UDim2.new(0, 12, 0, y)
    b.BackgroundColor3 = Color3.fromRGB(40,40,40); b.BorderSizePixel = 0
    b.Text = text; b.Font = Enum.Font.GothamBold; b.TextSize=14; b.TextColor3=Color3.fromRGB(220,220,220)
    local c = Instance.new("UICorner", b); c.CornerRadius = UDim.new(0,8)
    b.MouseButton1Click:Connect(function() cb(b) end)
    return b
end

local function mkLabel(text, y)
    local l = Instance.new("TextLabel", Frame)
    l.Size = UDim2.new(1, -24, 0, 20); l.Position = UDim2.new(0, 12, 0, y)
    l.BackgroundTransparency=1; l.Text = text; l.Font=Enum.Font.Gotham; l.TextSize=13
    l.TextXAlignment = Enum.TextXAlignment.Left; l.TextColor3=Color3.fromRGB(200,200,200)
    return l
end

local function mkBox(y, def)
    local t = Instance.new("TextBox", Frame)
    t.Size = UDim2.new(1, -24, 0, 28); t.Position = UDim2.new(0, 12, 0, y)
    t.BackgroundColor3 = Color3.fromRGB(30,30,30); t.BorderSizePixel=0
    t.Text = tostring(def or ""); t.Font=Enum.Font.Gotham; t.TextSize=13; t.TextColor3=Color3.new(1,1,1)
    local c = Instance.new("UICorner", t); c.CornerRadius = UDim.new(0,8)
    return t
end

local function toggleColor(btn, on)
    btn.BackgroundColor3 = on and Color3.fromRGB(30,120,60) or Color3.fromRGB(40,40,40)
    btn.TextColor3 = on and Color3.fromRGB(220,255,220) or Color3.fromRGB(220,220,220)
end

-- FPS
local fpsBtn = mkBtn("⚡ FPS Boost (вкл/выкл)", 44, function(b)
    cfg.fpsOn = not cfg.fpsOn
    toggleColor(b, cfg.fpsOn)
    if cfg.fpsOn then fpsBoost() else notify("FPS: частично откатить можно только перезапуском карты") end
end)

-- Range Aura
mkLabel("Aura Range (0-1500):", 88)
local auraBox = mkBox(108, cfg.auraRange)
auraBox.FocusLost:Connect(function()
    local n = tonumber(auraBox.Text) or cfg.auraRange
    cfg.auraRange = clamp(math.floor(n), 0, 1500)
    auraBox.Text = tostring(cfg.auraRange)
end)

-- Range Eat
mkLabel("Eat Range (0-1500):", 142)
local eatBox = mkBox(162, cfg.eatRange)
eatBox.FocusLost:Connect(function()
    local n = tonumber(eatBox.Text) or cfg.eatRange
    cfg.eatRange = clamp(math.floor(n), 0, 1500)
    eatBox.Text = tostring(cfg.eatRange)
end)

-- Food filter
mkLabel("Food filter (CSV):", 196)
local foodBox = mkBox(216, cfg.foodFilter)
foodBox.FocusLost:Connect(function()
    cfg.foodFilter = foodBox.Text or cfg.foodFilter
    foodKeys = splitCSV(cfg.foodFilter)
end)

-- Кнопки-тогглы
local auraBtn = mkBtn("⚔️ Kill-Aura (OFF)", 252, function(b)
    cfg.auraOn = not cfg.auraOn
    toggleColor(b, cfg.auraOn)
    b.Text = "⚔️ Kill-Aura ("..(cfg.auraOn and "ON" or "OFF")..")"
end)

local eatBtn = mkBtn("🥕 Auto-Eat (OFF)", 292, function(b)
    cfg.eatOn = not cfg.eatOn
    toggleColor(b, cfg.eatOn)
    b.Text = "🥕 Auto-Eat ("..(cfg.eatOn and "ON" or "OFF")..")"
end)

-- ПИКЕР РЕМОУТОВ (простые выпадающие списки в отдельном оверлее)
local Picker = Instance.new("Frame", UI)
Picker.Visible=false; Picker.BackgroundColor3=Color3.fromRGB(18,18,18); Picker.BorderSizePixel=0
Picker.Size=UDim2.new(0,360,0,300); Picker.Position=UDim2.new(0.5,-180,0.5,-150)
Instance.new("UICorner", Picker).CornerRadius=UDim.new(0,12)

local pickTitle = Instance.new("TextLabel", Picker)
pickTitle.Size=UDim2.new(1,-20,0,30); pickTitle.Position=UDim2.new(0,10,0,8); pickTitle.BackgroundTransparency=1
pickTitle.Text="Выбери Remote и назначь на роль"; pickTitle.Font=Enum.Font.GothamBold; pickTitle.TextSize=16
pickTitle.TextColor3=Color3.fromRGB(235,235,235); pickTitle.TextXAlignment=Enum.TextXAlignment.Left

local roles = {"Attack","Pickup","Eat"}
local roleIdx = 1
local roleBtn = mkBtn("Роль: Attack", 46, function(b)
    roleIdx = roleIdx % #roles + 1
    b.Text = "Роль: "..roles[roleIdx]
end)
roleBtn.Parent = Picker

local list = Instance.new("ScrollingFrame", Picker)
list.Size=UDim2.new(1,-20,1,-110); list.Position=UDim2.new(0,10,0,90)
list.BackgroundColor3=Color3.fromRGB(24,24,24); list.BorderSizePixel=0; list.ScrollBarThickness=6; list.CanvasSize=UDim2.new(0,0,0,0)
Instance.new("UICorner", list).CornerRadius=UDim.new(0,8)

local function rebuildList()
    list:ClearAllChildren()
    local y=6
    for _,r in ipairs(allRemotes) do
        local b = Instance.new("TextButton", list)
        b.Size=UDim2.new(1,-12,0,28); b.Position=UDim2.new(0,6,0,y)
        b.BackgroundColor3=Color3.fromRGB(36,36,36); b.BorderSizePixel=0
        b.Text = (r.ClassName=="RemoteEvent" and "[Event] " or "[Func] ")..fullName(r)
        b.Font=Enum.Font.Gotham; b.TextSize=12; b.TextXAlignment=Enum.TextXAlignment.Left
        b.TextColor3=Color3.fromRGB(220,220,220)
        Instance.new("UICorner", b).CornerRadius=UDim.new(0,6)
        b.MouseButton1Click:Connect(function()
            if roles[roleIdx]=="Attack" then state.attackRemote = r; notify("Назначен Attack: "..fullName(r))
            elseif roles[roleIdx]=="Pickup" then state.pickupRemote = r; notify("Назначен Pickup: "..fullName(r))
            else state.eatRemote = r; notify("Назначен Eat: "..fullName(r)) end
        end)
        y = y + 32
    end
    list.CanvasSize = UDim2.new(0,0,0,y+6)
end
rebuildList()

local pickClose = mkBtn("Закрыть", 260, function() Picker.Visible=false end); pickClose.Parent=Picker
local openPicker = mkBtn("🎯 Remotes Picker", 8, function() Picker.Visible=true end)
local refreshBtn = mkBtn("🔄 Обновить Remotes", 8, function() refreshRemotes(); rebuildList() end)
openPicker.Parent = Frame; refreshBtn.Parent = Frame; refreshBtn.Position = UDim2.new(0, 156, 0, 8)

-- ========== ПОТОКИ ==========
local function auraStep()
    if not cfg.auraOn or not state.attackRemote then return end
    if os.clock() - state.lastAura < cfg.tickAura then return end
    state.lastAura = os.clock()
    local c,h,hrp = charParts(); if not (hrp and isAliveHum(h)) then return end
    local r = clamp(cfg.auraRange,0,1500)
    for _,m in ipairs(getNPCs()) do
        if m ~= c then
            local th=m:FindFirstChildOfClass("Humanoid")
            local tr=m:FindFirstChild("HumanoidRootPart")
            if tr and isAliveHum(th) and mag(hrp.Position,tr.Position) <= r then
                tryAttack(state.attackRemote, m)
            end
        end
    end
end

local function eatStep()
    if not cfg.eatOn then return end
    if os.clock() - state.lastEat < cfg.tickEat then return end
    state.lastEat = os.clock()
    local c,h,hrp = charParts(); if not (hrp and isAliveHum(h)) then return end
    local r = clamp(cfg.eatRange,0,1500)

    local nearest, nd = nil, nil
    for _,inst in ipairs(workspace:GetDescendants()) do
        if inst:IsA("BasePart") or inst:IsA("Model") then
            if isFood(inst) then
                local p = primary(inst)
                if p then
                    local d = mag(hrp.Position, p.Position)
                    if d<=r and (not nd or d<nd) then nearest, nd = inst, d end
                end
            end
        end
    end
    if nearest then
        local p = primary(nearest)
        if p and nd>16 then softTP(p.Position) end
        tryPickup(nearest); task.wait(0.1); tryEat(nearest)
    end
end

RS.Heartbeat:Connect(function()
    auraStep()
    eatStep()
end)

notify("GUI загружен. Настрой Remotes через 🎯 Remotes Picker, затем включай модули.")
