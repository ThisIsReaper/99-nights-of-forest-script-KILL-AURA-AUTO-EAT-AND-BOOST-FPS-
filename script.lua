--[[
  99 Nights in the Forest — Helper
  FPS Boost + Kill Aura + Auto Eat (GUI, настраиваемый радиус до 1500)
  Сделано для эксплуата-исполнителей (Delta/Synapse и т.п.)
]]

if getgenv and getgenv().ForestHelper then
    -- повторный запуск перезагружает GUI
    pcall(function() getgenv().ForestHelper._destroy() end)
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local LP = Players.LocalPlayer
local PG = LP:WaitForChild("PlayerGui")

local function notify(t, tt)
    pcall(function()
        StarterGui:SetCore("SendNotification", {Title="Forest Helper", Text=t, Duration=tt or 4})
    end)
end

local cfg = {
    fpsEnabled = false,
    fpsAggressive = false,
    auraEnabled = false,
    auraRange = 200, -- можно менять в GUI до 1500
    auraTick = 0.12,
    eatEnabled = false,
    eatRange = 200,
    eatTick = 0.4,
    safeTP = true,    -- «мягкие» тп (короткие прыжки)
    debug = false,
}

local state = {
    conAura = nil,
    conEat = nil,
    attackRemotes = {},
    eatRemotes = {},
    pickupRemotes = {},
    ui = nil,
}

-- ────────────────────────────── Утилиты ──────────────────────────────

local function charParts()
    local char = LP.Character or LP.CharacterAdded:Wait()
    return char, char:FindFirstChild("Humanoid"), char:FindFirstChild("HumanoidRootPart")
end

local function dist(a, b)
    return (a - b).Magnitude
end

local function clamp(n, lo, hi)
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

local function isAliveHumanoid(h)
    return h and h.Health and h.Health > 0
end

local function isNPCModel(m)
    if not m or not m:IsA("Model") then return false end
    local hum = m:FindFirstChildOfClass("Humanoid")
    if not isAliveHumanoid(hum) then return false end
    if Players:GetPlayerFromCharacter(m) then return false end
    local hrp = m:FindFirstChild("HumanoidRootPart")
    return hrp ~= nil
end

local function getAllNPCs()
    local out = {}
    for _, m in ipairs(workspace:GetDescendants()) do
        if m:IsA("Model") and isNPCModel(m) then
            table.insert(out, m)
        end
    end
    return out
end

local function isFoodInstance(inst)
    if not inst or not inst.Name then return false end
    local n = string.lower(inst.Name)
    -- подхватываем EN/RU ключи
    if n:find("carrot") or n:find("berry") or n:find("pepper") then return true end
    if n:find("морков") or n:find("ягод") or n:find("перец") then return true end
    return false
end

local function getItemPrimary(inst)
    if inst:IsA("BasePart") then return inst end
    if inst:IsA("Model") then
        return inst.PrimaryPart or inst:FindFirstChild("HumanoidRootPart") or inst:FindFirstChildWhichIsA("BasePart")
    end
    return nil
end

-- Поиск ремоутов по “сигнатурам” имен
local nameHintsAttack = {"attack","hit","damage","strike","slash","punch","swing"}
local nameHintsEat    = {"eat","consume","use"}
local nameHintsPick   = {"pickup","pick","collect","grab","take","loot"}

local function huntRemotes()
    local foundA, foundE, foundP = {}, {}, {}
    local function pushIfMatch(obj, arr, hints)
        local name = string.lower(obj.Name or "")
        for _,h in ipairs(hints) do
            if name:find(h) then
                table.insert(arr, obj)
                break
            end
        end
    end
    for _,obj in ipairs(game:GetDescendants()) do
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
            pushIfMatch(obj, foundA, nameHintsAttack)
            pushIfMatch(obj, foundE, nameHintsEat)
            pushIfMatch(obj, foundP, nameHintsPick)
        end
    end
    state.attackRemotes = foundA
    state.eatRemotes = foundE
    state.pickupRemotes = foundP
    if cfg.debug then
        print("[Remotes] attack:", #foundA, "eat:", #foundE, "pickup:", #foundP)
    end
end

huntRemotes()
task.delay(8, huntRemotes) -- повторный поиск чуть позже (на случай поздней инициализации)

-- безопасное pcall
local function try(fn, ...)
    local ok, res = pcall(fn, ...)
    if ok then return true, res end
    return false, res
end

-- попытки атаковать цель различными сигнатурами
local function tryAttackTarget(targetModel)
    local hum = targetModel:FindFirstChildOfClass("Humanoid")
    local hrp = targetModel:FindFirstChild("HumanoidRootPart")
    if not isAliveHumanoid(hum) or not hrp then return end

    -- 1) пробуем ремоуты
    for _,r in ipairs(state.attackRemotes) do
        if r:IsA("RemoteEvent") then
            try(r.FireServer, r, targetModel)
            try(r.FireServer, r, hum)
            try(r.FireServer, r, targetModel, hrp.Position)
            try(r.FireServer, r, {Target = targetModel, Hit = hrp, Pos = hrp.Position})
        elseif r:IsA("RemoteFunction") then
            try(r.InvokeServer, r, targetModel)
        end
    end

    -- 2) пробуем активировать любое оружие/тул
    local char = LP.Character
    if char then
        local tool = char:FindFirstChildWhichIsA("Tool")
        if tool then
            try(function() tool:Activate() end)
        end
    end

    -- 3) щелчок мышкой через VirtualUser (на некоторых проектах триггерит клик-детекторы/оружие)
    local vu = game:GetService("VirtualUser")
    try(function()
        vu:CaptureController()
        vu:Button1Down(Vector2.new(0,0), workspace.CurrentCamera and workspace.CurrentCamera.CFrame)
        task.wait(0.02)
        vu:Button1Up(Vector2.new(0,0), workspace.CurrentCamera and workspace.CurrentCamera.CFrame)
    end)
end

-- перемещение к точке (короткий “прыжок”)
local function softTP(pos)
    local char, hum, hrp = charParts()
    if not hrp then return end
    if cfg.safeTP then
        hrp.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
    else
        hum:MoveTo(pos)
    end
end

-- попытки подобрать и съесть еду
local hasFPP = (typeof(getgenv)=="function" and (getgenv().fireproximityprompt or _G.fireproximityprompt or fireproximityprompt))
local hasFCD = (typeof(getgenv)=="function" and (getgenv().fireclickdetector or _G.fireclickdetector or fireclickdetector))
local function firePP(pp)
    local f = getgenv and (getgenv().fireproximityprompt or _G.fireproximityprompt) or fireproximityprompt
    if typeof(f) == "function" then
        f(pp)
        return true
    end
    return false
end
local function fireCD(cd)
    local f = getgenv and (getgenv().fireclickdetector or _G.fireclickdetector) or fireclickdetector
    if typeof(f) == "function" then
        f(cd)
        return true
    end
    return false
end

local function tryPickup(inst)
    -- 1) ProximityPrompt
    for _,d in ipairs(inst:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            d.HoldDuration = 0
            d.RequiresLineOfSight = false
            if hasFPP then return firePP(d) end
        end
    end
    -- 2) ClickDetector
    for _,d in ipairs(inst:GetDescendants()) do
        if d:IsA("ClickDetector") then
            if hasFCD then return fireCD(d) end
        end
    end
    -- 3) Remote pickup
    for _,r in ipairs(state.pickupRemotes) do
        if r:IsA("RemoteEvent") then
            if try(r.FireServer, r, inst) then return true end
            if try(r.FireServer, r, {Item = inst}) then return true end
        elseif r:IsA("RemoteFunction") then
            if try(r.InvokeServer, r, inst) then return true end
        end
    end
    return false
end

local function tryEat(instOrName)
    -- 1) Прямые remotes "eat/consume/use"
    for _,r in ipairs(state.eatRemotes) do
        if r:IsA("RemoteEvent") then
            if try(r.FireServer, r, instOrName) then return true end
            if try(r.FireServer, r, {Item = instOrName}) then return true end
            if typeof(instOrName)=="Instance" and try(r.FireServer, r, instOrName.Name) then return true end
        elseif r:IsA("RemoteFunction") then
            if try(r.InvokeServer, r, instOrName) then return true end
        end
    end
    -- 2) Tool в Backpack с именем предмета — активируем
    local name = typeof(instOrName)=="Instance" and instOrName.Name or tostring(instOrName)
    for _,tool in ipairs(LP.Backpack:GetChildren()) do
        if tool:IsA("Tool") and string.find(string.lower(tool.Name), string.lower(name)) then
            try(function()
                tool.Parent = LP.Character
                task.wait()
                tool:Activate()
            end)
            return true
        end
    end
    return false
end

-- ────────────────────────────── FPS BOOST ──────────────────────────────
local function applyFPS(mild, aggressive)
    -- Освещение/эффекты
    pcall(function()
        local L = game:GetService("Lighting")
        L.GlobalShadows = false
        L.FogEnd = 1e9
        L.Brightness = 1
        L.OutdoorAmbient = Color3.new(1,1,1)
    end)
    -- Мягкий режим: упрощаем материалы
    if mild then
        for _,v in ipairs(workspace:GetDescendants()) do
            if v:IsA("BasePart") then
                v.Material = Enum.Material.SmoothPlastic
                v.Reflectance = 0
                v.CastShadow = false
            end
        end
    end
    -- Агрессивный: удаляем декали/текстуры (НЕОБРАТИМО в рамках сессии)
    if aggressive then
        for _,v in ipairs(workspace:GetDescendants()) do
            if v:IsA("Decal") or v:IsA("Texture") then
                pcall(function() v:Destroy() end)
            end
        end
    end
end

local function revertFPS()
    -- Полного отката нет (если уже удалили декали). Возвращаем лишь базовые флаги.
    pcall(function()
        local L = game:GetService("Lighting")
        L.GlobalShadows = true
    end)
end

-- ────────────────────────────── ПОТОКИ ──────────────────────────────
local function startAura()
    if state.conAura then state.conAura:Disconnect() end
    state.conAura = RunService.Heartbeat:Connect(function(dt)
        if not cfg.auraEnabled then return end
        local char, hum, hrp = charParts()
        if not hrp or not isAliveHumanoid(hum) then return end

        local npcs = getAllNPCs()
        if #npcs == 0 then return end
        local r = clamp(cfg.auraRange, 0, 1500)
        local now = os.clock()
        -- атакуем ближайших в радиусе
        for _,m in ipairs(npcs) do
            local th = m:FindFirstChildOfClass("Humanoid")
            local tr = m:FindFirstChild("HumanoidRootPart")
            if tr and isAliveHumanoid(th) and dist(hrp.Position, tr.Position) <= r then
                tryAttackTarget(m)
            end
        end
        task.wait(cfg.auraTick)
    end)
end

local function startEat()
    if state.conEat then state.conEat:Disconnect() end
    state.conEat = RunService.Heartbeat:Connect(function()
        if not cfg.eatEnabled then return end
        local char, hum, hrp = charParts()
        if not hrp or not isAliveHumanoid(hum) then return end

        local nearestFood, nearestDist
        local r = clamp(cfg.eatRange, 0, 1500)
        for _,inst in ipairs(workspace:GetDescendants()) do
            if isFoodInstance(inst) then
                local p = getItemPrimary(inst)
                if p then
                    local d = dist(hrp.Position, p.Position)
                    if d <= r and (not nearestDist or d < nearestDist) then
                        nearestFood, nearestDist = inst, d
                    end
                end
            end
        end

        if nearestFood then
            local p = getItemPrimary(nearestFood)
            if p then
                if nearestDist > 18 then
                    softTP(p.Position)
                end
                -- пробуем подобрать
                tryPickup(nearestFood)
                task.wait(0.15)
                -- пробуем съесть
                tryEat(nearestFood)
            end
        end
        task.wait(cfg.eatTick)
    end)
end

-- ────────────────────────────── GUI ──────────────────────────────
local function makeButton(parent, text)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -10, 0, 36)
    b.Position = UDim2.new(0, 5, 0, 0)
    b.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    b.TextColor3 = Color3.fromRGB(235, 235, 235)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 14
    b.Text = text
    b.AutoButtonColor = true
    b.Parent = parent
    return b
end

local function makeLabel(parent, text, y)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -10, 0, 20)
    l.Position = UDim2.new(0, 5, 0, y)
    l.BackgroundTransparency = 1
    l.TextColor3 = Color3.fromRGB(230,230,230)
    l.Font = Enum.Font.Gotham
    l.TextSize = 14
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Text = text
    l.Parent = parent
    return l
end

local function makeInput(parent, y, default)
    local tb = Instance.new("TextBox")
    tb.Size = UDim2.new(1, -10, 0, 28)
    tb.Position = UDim2.new(0, 5, 0, y)
    tb.BackgroundColor3 = Color3.fromRGB(30,30,30)
    tb.TextColor3 = Color3.new(1,1,1)
    tb.Font = Enum.Font.Gotham
    tb.TextSize = 14
    tb.Text = tostring(default or "")
    tb.PlaceholderText = "0 - 1500"
    tb.ClearTextOnFocus = false
    tb.Parent = parent
    return tb
end

local function colorOn(on)
    return on and Color3.fromRGB(30,160,75) or Color3.fromRGB(40,40,40)
end

local function buildUI()
    if state.ui then pcall(function() state.ui:Destroy() end) end
    local gui = Instance.new("ScreenGui")
    gui.Name = "ForestHelperUI"
    gui.ResetOnSpawn = false
    gui.Parent = PG

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 300, 0, 360)
    frame.Position = UDim2.new(0, 30, 0, 120)
    frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    frame.BorderSizePixel = 0
    frame.Parent = gui

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -10, 0, 32)
    title.Position = UDim2.new(0, 5, 0, 5)
    title.BackgroundTransparency = 1
    title.Text = "99 Nights Helper"
    title.Font = Enum.Font.GothamBold
    title.TextSize = 18
    title.TextColor3 = Color3.fromRGB(255,255,255)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = frame

    -- перетаскивание
    local dragging, dragStart, startPos
    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    frame.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)

    -- FPS
    local fpsBtn = makeButton(frame, "FPS Boost: OFF")
    fpsBtn.Position = UDim2.new(0, 5, 0, 45)
    fpsBtn.BackgroundColor3 = colorOn(cfg.fpsEnabled)
    fpsBtn.MouseButton1Click:Connect(function()
        cfg.fpsEnabled = not cfg.fpsEnabled
        fpsBtn.BackgroundColor3 = colorOn(cfg.fpsEnabled)
        fpsBtn.Text = "FPS Boost: " .. (cfg.fpsEnabled and "ON" or "OFF")
        if cfg.fpsEnabled then
            applyFPS(true, cfg.fpsAggressive)
            notify("FPS Boost включен")
        else
            revertFPS()
            notify("FPS Boost выключен (частично)")
        end
    end)

    local fpsAgg = makeButton(frame, "Aggressive FPS: OFF")
    fpsAgg.Position = UDim2.new(0, 5, 0, 85)
    fpsAgg.BackgroundColor3 = colorOn(cfg.fpsAggressive)
    fpsAgg.MouseButton1Click:Connect(function()
        cfg.fpsAggressive = not cfg.fpsAggressive
        fpsAgg.BackgroundColor3 = colorOn(cfg.fpsAggressive)
        fpsAgg.Text = "Aggressive FPS: " .. (cfg.fpsAggressive and "ON" or "OFF")
        if cfg.fpsEnabled then
            applyFPS(true, cfg.fpsAggressive)
        end
        if cfg.fpsAggressive then
            notify("Агрессивный FPS: удалены декали/текстуры (необратимо)")
        end
    end)

    -- KILL AURA
    local auraBtn = makeButton(frame, "Kill Aura: OFF")
    auraBtn.Position = UDim2.new(0, 5, 0, 135)
    auraBtn.BackgroundColor3 = colorOn(cfg.auraEnabled)
    auraBtn.MouseButton1Click:Connect(function()
        cfg.auraEnabled = not cfg.auraEnabled
        auraBtn.BackgroundColor3 = colorOn(cfg.auraEnabled)
        auraBtn.Text = "Kill Aura: " .. (cfg.auraEnabled and "ON" or "OFF")
        if cfg.auraEnabled then startAura() end
    end)

    makeLabel(frame, "Aura Range (0-1500):", 175)
    local auraInput = makeInput(frame, 195, cfg.auraRange)
    auraInput.FocusLost:Connect(function(enter)
        local n = tonumber(auraInput.Text) or cfg.auraRange
        cfg.auraRange = clamp(math.floor(n), 0, 1500)
        auraInput.Text = tostring(cfg.auraRange)
        notify("Радиус Kill Aura = "..cfg.auraRange)
    end)

    -- AUTO EAT
    local eatBtn = makeButton(frame, "Auto-Eat: OFF")
    eatBtn.Position = UDim2.new(0, 5, 0, 235)
    eatBtn.BackgroundColor3 = colorOn(cfg.eatEnabled)
    eatBtn.MouseButton1Click:Connect(function()
        cfg.eatEnabled = not cfg.eatEnabled
        eatBtn.BackgroundColor3 = colorOn(cfg.eatEnabled)
        eatBtn.Text = "Auto-Eat: " .. (cfg.eatEnabled and "ON" or "OFF")
        if cfg.eatEnabled then startEat() end
    end)

    makeLabel(frame, "Eat Range (0-1500):", 275)
    local eatInput = makeInput(frame, 295, cfg.eatRange)
    eatInput.FocusLost:Connect(function()
        local n = tonumber(eatInput.Text) or cfg.eatRange
        cfg.eatRange = clamp(math.floor(n), 0, 1500)
        eatInput.Text = tostring(cfg.eatRange)
        notify("Радиус Auto-Eat = "..cfg.eatRange)
    end)

    state.ui = gui
    getgenv().ForestHelper = {
        _destroy = function()
            pcall(function() if state.conAura then state.conAura:Disconnect() end end)
            pcall(function() if state.conEat then state.conEat:Disconnect() end end)
            pcall(function() if gui then gui:Destroy() end end)
        end,
        cfg = cfg
    }
end

-- ────────────────────────────── Запуск ──────────────────────────────
buildUI()
notify("GUI загружен. Включай модули по кнопкам!")

-- Автозапуск мягкого FPS (можно выключить кнопкой)
cfg.fpsEnabled = true
applyFPS(true, false)
