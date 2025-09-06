local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local killAuraEnabled = false
local autoEatEnabled = false
local range = 1500

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Parent = game.CoreGui
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 260, 0, 200)
MainFrame.Position = UDim2.new(0.5, -130, 0.5, -100)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
MainFrame.BackgroundTransparency = 0.1
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner", MainFrame)
UICorner.CornerRadius = UDim.new(0, 12)

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 40)
Title.Text = "🌲 Forest Hub Deluxe"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 22
Title.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
Title.BorderSizePixel = 0
Title.Parent = MainFrame
local cornerT = Instance.new("UICorner", Title)
cornerT.CornerRadius = UDim.new(0, 12)

local function createButton(name, pos, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -30, 0, 40)
    btn.Position = UDim2.new(0, 15, 0, pos)
    btn.Text = name
    btn.TextColor3 = Color3.fromRGB(200, 200, 200)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 18
    btn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = false
    btn.Parent = MainFrame
    local corner = Instance.new("UICorner", btn)
    corner.CornerRadius = UDim.new(0, 8)

    btn.MouseEnter:Connect(function()
        btn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    end)
    btn.MouseLeave:Connect(function()
        if btn.TextColor3 ~= Color3.fromRGB(0, 255, 100) then
            btn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
        end
    end)

    btn.MouseButton1Click:Connect(function()
        local active = callback()
        if active then
            btn.TextColor3 = Color3.fromRGB(0, 255, 100)
            btn.BackgroundColor3 = Color3.fromRGB(30, 80, 30)
        else
            btn.TextColor3 = Color3.fromRGB(200, 200, 200)
            btn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
        end
    end)

    return btn
end

createButton("⚡ FPS Boost", 50, function()
    for _,v in pairs(workspace:GetDescendants()) do
        if v:IsA("Part") or v:IsA("MeshPart") or v:IsA("UnionOperation") then
            v.Material = Enum.Material.SmoothPlastic
            v.Reflectance = 0
        elseif v:IsA("Decal") or v:IsA("Texture") then
            v:Destroy()
        end
    end
    game.Lighting.GlobalShadows = false
    game.Lighting.FogEnd = 1e10
    sethiddenproperty(game.Lighting, "Technology", 2)
    return true
end)

createButton("⚔️ Kill Aura", 100, function()
    killAuraEnabled = not killAuraEnabled
    return killAuraEnabled
end)

createButton("🥕 Auto Eat", 150, function()
    autoEatEnabled = not autoEatEnabled
    return autoEatEnabled
end)

local damageEvent, pickupEvent, eatEvent
for _,v in pairs(game:GetDescendants()) do
    if v:IsA("RemoteEvent") then
        local n = v.Name:lower()
        if string.find(n, "damage") then
            damageEvent = v
        elseif string.find(n, "pickup") then
            pickupEvent = v
        elseif string.find(n, "eat") or string.find(n, "consume") then
            eatEvent = v
        end
    end
end

RunService.Heartbeat:Connect(function()
    if killAuraEnabled and damageEvent then
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            for _,mob in pairs(workspace:GetDescendants()) do
                if mob:FindFirstChild("Humanoid") and mob:FindFirstChild("HumanoidRootPart") then
                    if mob ~= char and mob.Humanoid.Health > 0 then
                        if (hrp.Position - mob.HumanoidRootPart.Position).Magnitude < range then
                            damageEvent:FireServer(mob)
                        end
                    end
                end
            end
        end
    end
end)

local foodNames = {"Carrot", "Berry", "Pepper"}
task.spawn(function()
    while task.wait(1) do
        if autoEatEnabled and pickupEvent and eatEvent then
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                for _,item in pairs(workspace:GetDescendants()) do
                    if item:IsA("Part") and table.find(foodNames, item.Name) then
                        if (hrp.Position - item.Position).Magnitude < range then
                            pickupEvent:FireServer(item)
                            task.wait(0.2)
                            eatEvent:FireServer(item)
                        end
                    end
                end
            end
        end
    end
end)
