local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("RunService")
local LP = Players.LocalPlayer

local function guiParent()
    if gethui then return gethui() end
    return game:FindFirstChildOfClass("CoreGui") or LP:WaitForChild("PlayerGui")
end

local cfg = {
    auraOn = false,
    eatOn  = false,
    fpsOn  = false,
    auraRange = 300,
    eatRange  = 300,
    tickAura = 0.12,
    tickEat  = 0.3,
}

local state = {
    attackRemote=nil,
    pickupRemote=nil,
    eatRemote=nil,
    lastAura=0,
    lastEat=0,
}

local function charParts()
    local c=LP.Character or LP.CharacterAdded:Wait()
    return c, c:FindFirstChildOfClass("Humanoid"), c:FindFirstChild("HumanoidRootPart")
end

local function mag(a,b) return (a-b).Magnitude end
local function clamp(n,lo,hi) if n<lo then return lo elseif n>hi then return hi end return n end
local function isAliveHum(h) return h and h.Health and h.Health>0 end

local function isNPC(m)
    if not m or not m:IsA("Model") then return false end
    local hum=m:FindFirstChildOfClass("Humanoid")
    if not isAliveHum(hum) then return false end
    if Players:GetPlayerFromCharacter(m) then return false end
    return m:FindFirstChild("HumanoidRootPart")~=nil
end

local function getNPCs()
    local out={}
    for _,m in ipairs(workspace:GetDescendants()) do
        if isNPC(m) then table.insert(out,m) end
    end
    return out
end

local function tryAttack(r, target)
    if not r or not target then return end
    local hum=target:FindFirstChildOfClass("Humanoid")
    local hrp=target:FindFirstChild("HumanoidRootPart")
    if not (isAliveHum(hum) and hrp) then return end
    if r:IsA("RemoteEvent") then
        pcall(function() r:FireServer(target) end)
        pcall(function() r:FireServer(hum) end)
        pcall(function() r:FireServer(hrp) end)
    else
        pcall(function() r:InvokeServer(target) end)
    end
end

local function isFood(inst)
    local n=(inst and inst.Name or ""):lower()
    return n:find("carrot") or n:find("berry") or n:find("pepper") or n:find("морков") or n:find("ягод") or n:find("перец")
end

local function primary(inst)
    if inst:IsA("BasePart") then return inst end
    if inst:IsA("Model") then return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart") end
    return nil
end

local function tryPickup(inst)
    if state.pickupRemote then
        local r=state.pickupRemote
        if r:IsA("RemoteEvent") then
            pcall(function() r:FireServer(inst) end)
        else
            pcall(function() r:InvokeServer(inst) end)
        end
    end
end

local function tryEat(inst)
    if state.eatRemote then
        local r=state.eatRemote
        if r:IsA("RemoteEvent") then
            pcall(function() r:FireServer(inst) end)
        else
            pcall(function() r:InvokeServer(inst) end)
        end
    end
end

local UI = Instance.new("ScreenGui")
UI.Name="ForestHubCompact"
UI.ResetOnSpawn=false
UI.Parent=guiParent()

local main = Instance.new("Frame")
main.Size=UDim2.new(0,220,0,240)
main.Position=UDim2.new(0.5,-110,0.5,-120)
main.BackgroundColor3=Color3.fromRGB(20,20,20)
main.BorderSizePixel=0
main.Active=true
main.Draggable=true
main.Visible=false
main.Parent=UI
Instance.new("UICorner",main).CornerRadius=UDim.new(0,10)

local title=Instance.new("TextLabel",main)
title.Size=UDim2.new(1,0,0,28)
title.BackgroundTransparency=1
title.Text="🌲 Forest Hub"
title.Font=Enum.Font.GothamBold
title.TextSize=16
title.TextColor3=Color3.new(1,1,1)

local function mkBtn(text,y,cb)
    local b=Instance.new("TextButton",main)
    b.Size=UDim2.new(1,-20,0,30)
    b.Position=UDim2.new(0,10,0,y)
    b.BackgroundColor3=Color3.fromRGB(40,40,40)
    b.BorderSizePixel=0
    b.Text=text
    b.Font=Enum.Font.GothamBold
    b.TextSize=13
    b.TextColor3=Color3.new(1,1,1)
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,8)
    b.MouseButton1Click:Connect(function() cb(b) end)
    return b
end

local function toggleColor(btn,on)
    btn.BackgroundColor3=on and Color3.fromRGB(40,120,60) or Color3.fromRGB(40,40,40)
end

local auraBtn=mkBtn("⚔️ Kill-Aura (OFF)",40,function(b)
    cfg.auraOn=not cfg.auraOn
    b.Text="⚔️ Kill-Aura ("..(cfg.auraOn and "ON" or "OFF")..")"
    toggleColor(b,cfg.auraOn)
end)

local eatBtn=mkBtn("🥕 Auto-Eat (OFF)",80,function(b)
    cfg.eatOn=not cfg.eatOn
    b.Text="🥕 Auto-Eat ("..(cfg.eatOn and "ON" or "OFF")..")"
    toggleColor(b,cfg.eatOn)
end)

local auraBox=Instance.new("TextBox",main)
auraBox.Size=UDim2.new(1,-20,0,26)
auraBox.Position=UDim2.new(0,10,0,130)
auraBox.BackgroundColor3=Color3.fromRGB(30,30,30)
auraBox.Text=tostring(cfg.auraRange)
auraBox.Font=Enum.Font.Gotham
auraBox.TextSize=13
auraBox.TextColor3=Color3.new(1,1,1)
Instance.new("UICorner",auraBox).CornerRadius=UDim.new(0,6)
auraBox.FocusLost:Connect(function()
    local n=tonumber(auraBox.Text) or cfg.auraRange
    cfg.auraRange=clamp(math.floor(n),0,1500)
    auraBox.Text=tostring(cfg.auraRange)
end)

local eatBox=Instance.new("TextBox",main)
eatBox.Size=UDim2.new(1,-20,0,26)
eatBox.Position=UDim2.new(0,10,0,170)
eatBox.BackgroundColor3=Color3.fromRGB(30,30,30)
eatBox.Text=tostring(cfg.eatRange)
eatBox.Font=Enum.Font.Gotham
eatBox.TextSize=13
eatBox.TextColor3=Color3.new(1,1,1)
Instance.new("UICorner",eatBox).CornerRadius=UDim.new(0,6)
eatBox.FocusLost:Connect(function()
    local n=tonumber(eatBox.Text) or cfg.eatRange
    cfg.eatRange=clamp(math.floor(n),0,1500)
    eatBox.Text=tostring(cfg.eatRange)
end)

local toggleBtn=Instance.new("ImageButton",UI)
toggleBtn.Size=UDim2.new(0,50,0,50)
toggleBtn.Position=UDim2.new(0,10,0.5,-25)
toggleBtn.BackgroundTransparency=1
toggleBtn.Image="rbxassetid://7699174"

toggleBtn.MouseButton1Click:Connect(function()
    main.Visible=not main.Visible
end)

RS.Heartbeat:Connect(function()
    if cfg.auraOn and state.attackRemote then
        if os.clock()-state.lastAura>=cfg.tickAura then
            state.lastAura=os.clock()
            local c,h,hrp=charParts()
            if hrp and isAliveHum(h) then
                for _,m in ipairs(getNPCs()) do
                    local tr=m:FindFirstChild("HumanoidRootPart")
                    if tr and mag(hrp.Position,tr.Position)<=cfg.auraRange then
                        tryAttack(state.attackRemote,m)
                    end
                end
            end
        end
    end
    if cfg.eatOn then
        if os.clock()-state.lastEat>=cfg.tickEat then
            state.lastEat=os.clock()
            local c,h,hrp=charParts()
            if hrp and isAliveHum(h) then
                for _,inst in ipairs(workspace:GetDescendants()) do
                    if isFood(inst) then
                        local p=primary(inst)
                        if p and mag(hrp.Position,p.Position)<=cfg.eatRange then
                            tryPickup(inst)
                            tryEat(inst)
                        end
                    end
                end
            end
        end
    end
end)
