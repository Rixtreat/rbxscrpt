-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

local LP = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- Rayfield
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local Window = Rayfield:CreateWindow({
    Name = "Daley Hub",
    LoadingTitle = "Loading Daley Hub...",
    LoadingSubtitle = "by Daley",
    Theme = "Default",
    DisableRayfieldPrompts = false,
    DisableBuildWarnings = false,
    ConfigurationSaving = { Enabled = false },
    KeySystem = false,
})

-- ==========================================
-- [[ STATE ]] --
-- ==========================================
local States = {
    SpeedEnabled    = false,
    SpeedValue      = 50,
    FlyEnabled      = false,
    FlySpeed        = 50,
    NoclipEnabled   = false,
    MarkedPosition  = nil,
    ESPEnabled      = false,
    ShowHighlights  = true,
    ShowUsernames   = true,
    ShowStuds       = true,
    DefaultESPColor = Color3.fromRGB(180, 30, 30),
    TeleportTarget  = nil,
    
    -- Combat / Attack States
    AutoFarmEnabled   = false,
    AutoM1Enabled     = false,
    M1AttackSpeed     = 0.1,
    AutoFinisher      = false,
    FarmMode          = "In Front", 
    FarmDistance      = 4,         
    EnemyESPEnabled   = false,
    SelectedMobTarget = "All Mobs",
    
    -- Player Combat Exploits
    AutoKillPlayer    = false,
    KillDistance      = 3,
    FullbringEnabled  = false,
    
    -- Hitbox Sizes
    HitboxExtender    = false,
    HitboxSize        = 15,
    
    -- Universal Scanner States
    ScanKeyword      = "",
    ScannerESP       = false,

    -- Stats Automation States
    AutoStrengthEnabled   = false,
    AutoEnduranceEnabled  = false,
    AutoStaminaEnabled    = false,
    AutoFocusEnabled      = false,
    AutoBrainrotEnabled   = false,
    AutoLuckEnabled       = false,
    StatDelayTime         = 0.2
}

local ESP_Cache = {}
local Scanner_ESP_Cache = {}
local Enemy_ESP_Cache = {}
local Extended_Hitbox_Cache = {}

local currentSequence = 0x2F

-- ==========================================
-- [[ UTILITY ]] --
-- ==========================================
local function GetRoot()
    local char = LP.Character
    return char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
end

local function GetHumanoid()
    local char = LP.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function GetOtherPlayers()
    local names = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then
            table.insert(names, p.Name)
        end
    end
    if #names == 0 then table.insert(names, "None") end
    return names
end

local function IsPlayerCharacter(model)
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character == model then
            return true
        end
    end
    return false
end

local function CleanMobName(fullName)
    local splitIndex = string.find(fullName, ":")
    if splitIndex then
        return string.sub(fullName, 1, splitIndex - 1)
    end
    return fullName
end

local function GetObjectPosition(obj)
    if obj:IsA("BasePart") then
        return obj.Position
    elseif obj:IsA("Model") then
        if obj.PrimaryPart then
            return obj.PrimaryPart.Position
        else
            return obj:GetPivot().Position
        end
    end
    return nil
end

local function QuickTeleport(name, x, y, z)
    local root = GetRoot()
    if root then
        root.CFrame = CFrame.new(x, y, z)
        Rayfield:Notify({
            Title = "Teleported",
            Content = "Arrived at: " .. name,
            Duration = 2
        })
    end
end

local function GetLiveMobNames()
    local mobNames = {"All Mobs", "Snow Bear", "Yuki Oni Boss"}
    local seen = {["All Mobs"] = true, ["Snow Bear"] = true, ["Yuki Oni Boss"] = true}
    
    for _, descendant in ipairs(Workspace:GetDescendants()) do
        if descendant:IsA("Humanoid") then
            local model = descendant.Parent
            if model and model:IsA("Model") and not IsPlayerCharacter(model) and descendant.Health > 0 then
                local cleanedName = CleanMobName(model.Name)
                if not seen[cleanedName] and cleanedName ~= "" then
                    seen[cleanedName] = true
                    table.insert(mobNames, cleanedName)
                end
            end
        end
    end
    return mobNames
end

-- Server Hopping Logistics
local function HopServer(findLow)
    local placeId = game.PlaceId
    local currentJobId = game.JobId
    local url = "https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Asc&limit=100"
    
    Rayfield:Notify({Title = "Server Hop", Content = "Fetching server list...", Duration = 3})
    
    local success, result = pcall(function()
        return HttpService:JSONDecode(game:HttpGet(url))
    end)
    
    if success and result and result.data then
        local validServers = {}
        
        for _, server in ipairs(result.data) do
            if type(server) == "table" and server.id ~= currentJobId and server.playing and server.maxPlayers then
                if server.playing < server.maxPlayers then
                    table.insert(validServers, server)
                end
            end
        end
        
        if #validServers > 0 then
            if findLow then
                table.sort(validServers, function(a, b)
                    return a.playing < b.playing
                end)
                Rayfield:Notify({Title = "Server Hop", Content = "Routing to lowest available server...", Duration = 3})
                TeleportService:TeleportToPlaceInstance(placeId, validServers[1].id, LP)
            else
                local randomServer = validServers[math.random(1, #validServers)]
                Rayfield:Notify({Title = "Server Hop", Content = "Routing to random lobby...", Duration = 3})
                TeleportService:TeleportToPlaceInstance(placeId, randomServer.id, LP)
            end
        else
            Rayfield:Notify({Title = "Hop Error", Content = "No alternative servers found.", Duration = 3})
        end
    else
        Rayfield:Notify({Title = "Hop Error", Content = "Failed to query external server lists.", Duration = 3})
    end
end

-- ==========================================
-- [[ PLAYER ESP BOUNDS ]] --
-- ==========================================
local function CreateESP(player)
    if player == LP or ESP_Cache[player] then return end
    local objects = {}

    local function applyToCharacter(char)
        if not char then return end

        local highlight = Instance.new("Highlight")
        highlight.FillTransparency = 0.5
        highlight.OutlineTransparency = 0
        highlight.Adornee = char
        highlight.Enabled = false
        highlight.Parent = char
        objects.Highlight = highlight

        local billboard = Instance.new("BillboardGui")
        billboard.Size = UDim2.new(0, 200, 0, 50)
        billboard.AlwaysOnTop = true
        billboard.ExtentsOffset = Vector3.new(0, 3, 0)
        billboard.Enabled = false
        billboard.Name = "Univ_Overlay"
        billboard.Parent = char
        objects.Billboard = billboard

        local label = Instance.new("TextLabel", billboard)
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.TextStrokeTransparency = 0
        label.TextSize = 13
        label.Font = Enum.Font.SourceSansBold
        label.Text = player.Name
        label.TextColor3 = States.DefaultESPColor
        objects.Label = label

        local root = char:WaitForChild("HumanoidRootPart", 5)
        if root then billboard.Adornee = root end
    end

    if player.Character then applyToCharacter(player.Character) end
    player.CharacterAdded:Connect(applyToCharacter)
    ESP_Cache[player] = objects
end

local function RemoveESP(player)
    if ESP_Cache[player] then
        pcall(function()
            if ESP_Cache[player].Highlight then ESP_Cache[player].Highlight:Destroy() end
            if ESP_Cache[player].Billboard then ESP_Cache[player].Billboard:Destroy() end
        end)
        ESP_Cache[player] = nil
    end
end

for _, p in ipairs(Players:GetPlayers()) do CreateESP(p) end
Players.PlayerAdded:Connect(CreateESP)
Players.PlayerRemoving:Connect(RemoveESP)

-- ==========================================
-- [[ TABS INTERFACE ]] --
-- ==========================================
local CombatTab    = Window:CreateTab("Combat", nil)
local MovementTab  = Window:CreateTab("Movement", nil)
local LocationsTab = Window:CreateTab("Locations", nil)
local ScannerTab   = Window:CreateTab("Universal Scanner", nil)
local StatsTab     = Window:CreateTab("Stats", nil)
local UtilityTab   = Window:CreateTab("Utility", nil)
local VisualsTab   = Window:CreateTab("Visuals", nil)
local PlayersTab   = Window:CreateTab("Players", nil)

-- ==========================================
-- [[ COMBAT TAB ]] --
-- ==========================================
CombatTab:CreateSection("Auto Combat Utilities")

CombatTab:CreateToggle({
    Name     = "Auto Screen Clicker (M1)",
    Default  = false,
    Callback = function(v) States.AutoM1Enabled = v end,
})

CombatTab:CreateSlider({
    Name         = "Click Delay Speed",
    Range        = {5, 50},
    Increment    = 1,
    Suffix       = " ms",
    CurrentValue = 10,
    Callback     = function(v) States.M1AttackSpeed = v / 100 end,
})

CombatTab:CreateToggle({
    Name     = "Auto Finisher (Spam B)",
    Default  = false,
    Callback = function(v) States.AutoFinisher = v end,
})

CombatTab:CreateToggle({
    Name     = "Fullbring State Mod",
    Default  = false,
    Callback = function(v) States.FullbringEnabled = v end,
})

CombatTab:CreateSection("Hitbox Extender Mod")

CombatTab:CreateToggle({
    Name     = "Enable Hitbox Extender",
    Default  = false,
    Callback = function(v)
        States.HitboxExtender = v
        if not v then
            for part, data in pairs(Extended_Hitbox_Cache) do
                pcall(function()
                    if part and part.Parent then
                        part.Size = data.OriginalSize
                        part.Transparency = data.OriginalTransparency
                        part.CanCollide = data.OriginalCollide
                    end
                    if data.Adornment then data.Adornment:Destroy() end
                    for _, child in ipairs(part:GetChildren()) do
                        if child:IsA("BoxHandleAdornment") or child:IsA("SelectionBox") then
                            child:Destroy()
                        end
                    end
                end)
            end
            table.clear(Extended_Hitbox_Cache)
        end
    end,
})

CombatTab:CreateSlider({
    Name         = "Hitbox Size Scale",
    Range        = {2, 30},
    Increment    = 1,
    Suffix       = " studs",
    CurrentValue = 15,
    Callback     = function(v) States.HitboxSize = v end,
})

CombatTab:CreateSection("Mob Auto Farm Engine")

CombatTab:CreateToggle({
    Name     = "Auto Farm Targets",
    Default  = false,
    Callback = function(v) States.AutoFarmEnabled = v end,
})

local mobDropdown = CombatTab:CreateDropdown({
    Name = "Select Target Mob",
    Options = {"All Mobs", "Snow Bear", "Yuki Oni Boss"},
    CurrentOption = {"All Mobs"},
    MultipleOptions = false,
    Callback = function(option) States.SelectedMobTarget = option[1] or "All Mobs" end,
})

CombatTab:CreateButton({
    Name     = "Scan & Refresh Nearby Mobs",
    Callback = function()
        local freshList = GetLiveMobNames()
        mobDropdown:Refresh(freshList, true)
        Rayfield:Notify({
            Title = "Scanner updated",
            Content = string.format("Found %d distinct target types.", #freshList - 1),
            Duration = 2
        })
    end,
})

CombatTab:CreateDropdown({
    Name = "Farm Position Mode",
    Options = {"In Front", "Behind", "Above"},
    CurrentOption = {"In Front"},
    MultipleOptions = false,
    Callback = function(option) States.FarmMode = option[1] end,
})

CombatTab:CreateSlider({
    Name         = "Farm Attack Distance",
    Range        = {2, 12},
    Increment    = 1,
    Suffix       = " studs",
    CurrentValue = 4,
    Callback     = function(v) States.FarmDistance = v end,
})

CombatTab:CreateSection("Visual Assistance")

CombatTab:CreateToggle({
    Name     = "Valid Enemy ESP",
    Default  = false,
    Callback = function(v)
        States.EnemyESPEnabled = v
        if not v then
            for _, obj in pairs(Enemy_ESP_Cache) do
                pcall(function() 
                    if obj.Highlight then obj.Highlight:Destroy() end
                    if obj.Billboard then obj.Billboard:Destroy() end
                end)
            end
            table.clear(Enemy_ESP_Cache)
        end
    end,
})

task.spawn(function()
    task.wait(1)
    if mobDropdown then mobDropdown:Refresh(GetLiveMobNames(), true) end
end)

-- ==========================================
-- [[ MOVEMENT TAB ]] --
-- ==========================================
MovementTab:CreateSection("Physique Alterations")

MovementTab:CreateToggle({
    Name     = "Speed Mode",
    Default  = false,
    Callback = function(v) States.SpeedEnabled = v end,
})

MovementTab:CreateSlider({
    Name         = "Adjustable Walk Speed",
    Range        = {16, 250},
    Increment    = 1,
    Suffix       = " studs/s",
    CurrentValue = 50,
    Callback     = function(v) States.SpeedValue = v end,
})

MovementTab:CreateToggle({
    Name     = "Fly Mode",
    Default  = false,
    Callback = function(v)
        local hum = GetHumanoid()
        States.FlyEnabled = v
        if not v and hum then hum.PlatformStand = false end
    end,
})

MovementTab:CreateSlider({
    Name         = "Adjustable Fly Speed",
    Range        = {10, 250},
    Increment    = 1,
    Suffix       = " studs/s",
    CurrentValue = 50,
    Callback     = function(v) States.FlySpeed = v end,
})

MovementTab:CreateToggle({
    Name     = "Noclip",
    Default  = false,
    Callback = function(v) States.NoclipEnabled = v end,
})

MovementTab:CreateSection("Spatial Mapping & Coordinate Teleports")

local MoveMarkedLabel = MovementTab:CreateLabel("Marked Position: None")

MovementTab:CreateButton({
    Name     = "Mark Coordinates",
    Callback = function()
        local root = GetRoot()
        if root then
            States.MarkedPosition = root.Position
            local p = root.Position
            MoveMarkedLabel:Set(string.format("Marked: %.2f, %.2f, %.2f", p.X, p.Y, p.Z))
            Rayfield:Notify({
                Title = "Coordinates Logged",
                Content = string.format("X: %.2f  Y: %.2f  Z: %.2f", p.X, p.Y, p.Z),
                Duration = 3,
            })
        end
    end,
})

MovementTab:CreateButton({
    Name     = "Copy Coordinates to Clipboard",
    Callback = function()
        if States.MarkedPosition then
            local p = States.MarkedPosition
            local str = string.format("%.2f, %.2f, %.2f", p.X, p.Y, p.Z)
            if setclipboard then setclipboard(str) end
            Rayfield:Notify({Title = "Copied", Content = str, Duration = 2})
        else
            Rayfield:Notify({Title = "Nothing Marked", Content = "Log coordinates first.", Duration = 2})
        end
    end,
})

MovementTab:CreateButton({
    Name     = "Teleport to Marked Position",
    Callback = function()
        local root = GetRoot()
        if root and States.MarkedPosition then
            root.CFrame = CFrame.new(States.MarkedPosition)
            Rayfield:Notify({Title = "Teleported", Content = "Moved to logged coordinates.", Duration = 2})
        else
            Rayfield:Notify({Title = "Error", Content = "No coordinates marked yet.", Duration = 3})
        end
    end,
})

local manualX, manualY, manualZ = 0, 0, 0

MovementTab:CreateInput({
    Name = "Target X Coordinate",
    PlaceholderText = "Enter X",
    RemoveTextAfterFocusLost = false,
    Callback = function(text) manualX = tonumber(text) or 0 end,
})

MovementTab:CreateInput({
    Name = "Target Y Coordinate",
    PlaceholderText = "Enter Y",
    RemoveTextAfterFocusLost = false,
    Callback = function(text) manualY = tonumber(text) or 0 end,
})

MovementTab:CreateInput({
    Name = "Target Z Coordinate",
    PlaceholderText = "Enter Z",
    RemoveTextAfterFocusLost = false,
    Callback = function(text) manualZ = tonumber(text) or 0 end
})

MovementTab:CreateButton({
    Name     = "Teleport to Custom Coordinates",
    Callback = function()
        local root = GetRoot()
        if root then
            root.CFrame = CFrame.new(manualX, manualY, manualZ)
            Rayfield:Notify({
                Title = "Teleported",
                Content = string.format("Moved to %.2f, %.2f, %.2f", manualX, manualY, manualZ),
                Duration = 2,
            })
        end
    end,
})

-- ==========================================
-- [[ LOCATIONS TAB ]] --
-- ==========================================
LocationsTab:CreateSection("Key Landmarks")

LocationsTab:CreateButton({
    Name     = "Midori Village",
    Callback = function() QuickTeleport("Midori Village", -7837.39, 189.85, 3943.08) end,
})

LocationsTab:CreateButton({
    Name     = "Kyogai",
    Callback = function() QuickTeleport("Kyogai", -9357.22, 188.45, 3300.28) end,
})

LocationsTab:CreateButton({
    Name     = "Snow Cavern",
    Callback = function() QuickTeleport("Snow Cavern", -6691.21, 188.45, 1806.52) end,
})

LocationsTab:CreateButton({
    Name     = "Snow Town",
    Callback = function() QuickTeleport("Snow Town", -6569.76, 190.00, 2636.13) end,
})

LocationsTab:CreateSection("Training Hubs")

LocationsTab:CreateButton({
    Name     = "Thunder Training",
    Callback = function() QuickTeleport("Thunder Training", -9063.26, 275.45, 4757.11) end,
})

LocationsTab:CreateButton({
    Name     = "Water Training",
    Callback = function() QuickTeleport("Water Training", -6098.72, 283.45, 3960.27) end,
})

LocationsTab:CreateButton({
    Name     = "Inspect Training",
    Callback = function() QuickTeleport("Inspect Training", -8289.98, 191.45, 3051.92) end,
})

LocationsTab:CreateButton({
    Name     = "General Training",
    Callback = function() QuickTeleport("General Training", -8956.49, 296.03, 2354.39) end,
})

-- ==========================================
-- [[ UNIVERSAL SCANNER TAB ]] --
-- ==========================================
ScannerTab:CreateSection("Target Settings")

ScannerTab:CreateInput({
    Name = "Scan Target Keyword",
    PlaceholderText = "e.g., Chest, Ore, Wood, Boss",
    RemoveTextAfterFocusLost = false,
    Callback = function(text) States.ScanKeyword = string.lower(text) end,
})

ScannerTab:CreateSection("Actions")

ScannerTab:CreateToggle({
    Name     = "Enable Keyword ESP",
    Default  = false,
    Callback = function(v)
        States.ScannerESP = v
        if not v then
            for _, obj in pairs(Scanner_ESP_Cache) do
                pcall(function() 
                    if obj.Billboard then obj.Billboard:Destroy() end
                    if obj.Highlight then obj.Highlight:Destroy() end
                end)
            end
            table.clear(Scanner_ESP_Cache)
        end
    end,
})

ScannerTab:CreateButton({
    Name     = "Teleport to Nearest Match",
    Callback = function()
        if States.ScanKeyword == "" then return end
        local root = GetRoot()
        if not root then return end
        
        local closestObj, closestPos = nil, nil
        local closestDist = math.huge
        
        for _, desc in ipairs(Workspace:GetDescendants()) do
            if string.find(string.lower(desc.Name), States.ScanKeyword) then
                local pos = GetObjectPosition(desc)
                if pos then
                    local dist = (pos - root.Position).Magnitude
                    if dist < closestDist then
                        closestDist = dist
                        closestObj = desc
                        closestPos = pos
                    end
                end
            end
        end
        
        if closestObj and closestPos then
            root.CFrame = CFrame.new(closestPos + Vector3.new(0, 3, 0))
            Rayfield:Notify({Title = "Teleported", Content = "Moved to: " .. closestObj.Name, Duration = 2})
        else
            Rayfield:Notify({Title = "No Match Found", Content = "Could not find object matching keyword.", Duration = 2})
        end
    end,
})

-- ==========================================
-- [[ STATS TAB ]] --
-- ==========================================
StatsTab:CreateSection("Automated Character Attributes")

StatsTab:CreateToggle({
    Name     = "Auto Upgrade Strength",
    Default  = false,
    Callback = function(v) States.AutoStrengthEnabled = v end,
})

StatsTab:CreateToggle({
    Name     = "Auto Upgrade Endurance",
    Default  = false,
    Callback = function(v) States.AutoEnduranceEnabled = v end,
})

StatsTab:CreateToggle({
    Name     = "Auto Upgrade Stamina",
    Default  = false,
    Callback = function(v) States.AutoStaminaEnabled = v end,
})

StatsTab:CreateToggle({
    Name     = "Auto Upgrade Focus",
    Default  = false,
    Callback = function(v) States.AutoFocusEnabled = v end
})

StatsTab:CreateToggle({
    Name     = "Auto Upgrade Luck",
    Default  = false,
    Callback = function(v) States.AutoLuckEnabled = v end,
})

StatsTab:CreateToggle({
    Name     = "Auto Upgrade Brainrot Slots (1-40)",
    Default  = false,
    Callback = function(v) States.AutoBrainrotEnabled = v end,
})

StatsTab:CreateSlider({
    Name         = "Loop Delay Interval",
    Range        = {1, 10},
    Increment    = 1,
    Suffix       = " / 10s",
    CurrentValue = 2,
    Callback     = function(v) States.StatDelayTime = v / 10 end,
})

-- ==========================================
-- [[ UTILITY TAB ]] --
-- ==========================================
UtilityTab:CreateSection("General Scripts")

UtilityTab:CreateButton({
    Name     = "Re-align Camera Viewport",
    Callback = function()
        Camera.CameraSubject = GetHumanoid()
        Camera.CameraType = Enum.CameraType.Custom
    end,
})

UtilityTab:CreateSection("Server Management")

UtilityTab:CreateButton({
    Name     = "Hop to Low Server",
    Callback = function()
        HopServer(true)
    end,
})

UtilityTab:CreateButton({
    Name     = "Hop to Random Server",
    Callback = function()
        HopServer(false)
    end,
})

-- ==========================================
-- [[ VISUALS TAB ]] --
-- ==========================================
VisualsTab:CreateSection("Master Control")

VisualsTab:CreateToggle({
    Name     = "Player ESP",
    Default  = false,
    Callback = function(v)
        States.ESPEnabled = v
        if not v then
            for _, objects in pairs(ESP_Cache) do
                if objects.Highlight then objects.Highlight.Enabled = false end
                if objects.Billboard then objects.Billboard.Enabled = false end
            end
        end
    end,
})

VisualsTab:CreateToggle({
    Name     = "Highlights",
    Default  = true,
    Callback = function(v) States.ShowHighlights = v end,
})

VisualsTab:CreateSection("Overlay Info")

VisualsTab:CreateToggle({
    Name     = "Show Usernames",
    Default  = true,
    Callback = function(v) States.ShowUsernames = v end
})

VisualsTab:CreateToggle({
    Name     = "Show Studs (Distance)",
    Default  = true,
    Callback = function(v) States.ShowStuds = v end
})

-- ==========================================
-- [[ PLAYERS TAB ]] --
-- ==========================================
PlayersTab:CreateSection("Player Tracking & Engagement Mod")

local playerDropdown = PlayersTab:CreateDropdown({
    Name = "Select Player",
    Options = GetOtherPlayers(),
    CurrentOption = {GetOtherPlayers()[1]},
    MultipleOptions = false,
    Callback = function(option) States.TeleportTarget = option[1] end,
})

PlayersTab:CreateButton({
    Name     = "Refresh Player List",
    Callback = function() playerDropdown:Refresh(GetOtherPlayers(), true) end,
})

PlayersTab:CreateButton({
    Name     = "Teleport to Selected Player",
    Callback = function()
        local targetName = States.TeleportTarget
        if not targetName or targetName == "None" then
            Rayfield:Notify({Title = "No Player Selected", Content = "Pick a player from the dropdown.", Duration = 2})
            return
        end

        local targetPlayer = Players:FindFirstChild(targetName)
        local root = GetRoot()
        if targetPlayer and targetPlayer.Character and root then
            local targetRoot = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
            if targetRoot then
                root.CFrame = CFrame.new(targetRoot.Position + Vector3.new(0, 2, 0))
                Rayfield:Notify({Title = "Teleported", Content = "Moved to " .. targetName, Duration = 2})
            end
        else
            Rayfield:Notify({Title = "Failed", Content = "Player not found or has no character.", Duration = 2})
        end
    end,
})

PlayersTab:CreateToggle({
    Name     = "Auto Kill Player (Stay Behind Target)",
    Default  = false,
    Callback = function(v) States.AutoKillPlayer = v end,
})

PlayersTab:CreateSlider({
    Name         = "Kill Position Offset Distance",
    Range        = {1, 10},
    Increment    = 1,
    Suffix       = " studs",
    CurrentValue = 3,
    Callback     = function(v) States.KillDistance = v end,
})

-- ==========================================
-- [[ BACKGROUND WORKERS ]] --
-- ==========================================

local targetRemotePath = ReplicatedStorage:FindFirstChild("Files")
    and ReplicatedStorage.Files:FindFirstChild("Modules")
    and ReplicatedStorage.Files.Modules:FindFirstChild("Global")
    and ReplicatedStorage.Files.Modules.Global:FindFirstChild("Game")
    and ReplicatedStorage.Files.Modules.Global.Game:FindFirstChild("Packet")
    and ReplicatedStorage.Files.Modules.Global.Game.Packet:FindFirstChild("RemoteEvent")

if targetRemotePath and hookmetamethod then
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        local args = {...}
        
        if self == targetRemotePath and method == "FireServer" then
            local firstArg = args[1]
            if typeof(firstArg) == "buffer" and buffer.len(firstArg) >= 3 then
                currentSequence = buffer.readu8(firstArg, 2)
            end
        end
        return oldNamecall(self, ...)
    end)
end

-- Function helper to fetch the closest selected farming mob target
local function GetClosestMob()
    local root = GetRoot()
    if not root then return nil end

    local closest, targetDist = nil, math.huge
    for _, desc in ipairs(Workspace:GetDescendants()) do
        if desc:IsA("Humanoid") and desc.Health > 0 then
            local model = desc.Parent
            if model and model:IsA("Model") and not IsPlayerCharacter(model) then
                local cleaned = CleanMobName(model.Name)
                if States.SelectedMobTarget == "All Mobs" or cleaned == States.SelectedMobTarget then
                    local mobRoot = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
                    if mobRoot then
                        local dist = (mobRoot.Position - root.Position).Magnitude
                        if dist < targetDist then
                            targetDist = dist
                            closest = mobRoot
                        end
                    end
                end
            end
        end
    end
    return closest
end

-- Heartbeat Loop: Unified physical positioning system
RunService.Heartbeat:Connect(function()
    local root = GetRoot()
    local hum = GetHumanoid()
    if not root or not hum then return end

    -- 1. PRIORITY: MOB AUTO-FARM CORE
    if States.AutoFarmEnabled then
        local targetMobRoot = GetClosestMob()
        if targetMobRoot then
            root.Velocity = Vector3.new(0, 0, 0)
            
            local targetCFrame = targetMobRoot.CFrame
            if States.FarmMode == "Behind" then
                targetCFrame = targetCFrame * CFrame.new(0, 0, States.FarmDistance)
            elseif States.FarmMode == "Above" then
                targetCFrame = targetCFrame * CFrame.new(0, States.FarmDistance, 0) * CFrame.Angles(math.rad(-90), 0, 0)
            else -- "In Front"
                targetCFrame = targetCFrame * CFrame.new(0, 0, -States.FarmDistance)
            end
            
            root.CFrame = targetCFrame
            return 
        end
    end

    -- 2. AUTO KILL PLAYER LAYER
    if States.AutoKillPlayer and States.TeleportTarget and States.TeleportTarget ~= "None" then
        local targetPlayer = Players:FindFirstChild(States.TeleportTarget)
        if targetPlayer and targetPlayer.Character then
            local targetRoot = targetPlayer.Character:FindFirstChild("HumanoidRootPart") or targetPlayer.Character:FindFirstChild("Torso")
            local targetHum = targetPlayer.Character:FindFirstChildOfClass("Humanoid")
            
            if targetRoot and targetHum and targetHum.Health > 0 then
                root.Velocity = Vector3.new(0, 0, 0)
                root.CFrame = CFrame.new(targetRoot.Position + (targetRoot.CFrame.LookVector * -States.KillDistance), targetRoot.Position)
                return
            end
        end
    end

    -- 3. STANDARD FLY / SPEED COMPONENT
    if States.FlyEnabled then
        hum.PlatformStand = true
        local flyVel = Vector3.new(0, 0, 0)
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then flyVel = flyVel + Camera.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then flyVel = flyVel - Camera.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then flyVel = flyVel - Camera.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then flyVel = flyVel + Camera.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then flyVel = flyVel + Vector3.new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then flyVel = flyVel - Vector3.new(0, 1, 0) end
        
        if flyVel.Magnitude > 0 then
            root.Velocity = flyVel.Unit * States.FlySpeed
        else
            root.Velocity = Vector3.new(0, 0, 0)
        end
    elseif States.SpeedEnabled then
        local moveDir = hum.MoveDirection
        if moveDir.Magnitude > 0 then
            root.Velocity = Vector3.new(moveDir.X * States.SpeedValue, root.Velocity.Y, moveDir.Z * States.SpeedValue)
        end
    end

    -- 4. NOCLIP TICKER
    if States.NoclipEnabled and LP.Character then
        for _, part in ipairs(LP.Character:GetChildren()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end
end)

-- ========================================================
-- [[ FIXED AUTOMATED M1 CLICKER ENGINE ]]
-- ========================================================
task.spawn(function()
    while task.wait() do
        -- Triggers if manual clicker toggle is on OR if auto-farming/killing is actively hunting
        if States.AutoM1Enabled or (States.AutoFarmEnabled and GetClosestMob()) or (States.AutoKillPlayer and States.TeleportTarget ~= "None") then
            pcall(function()
                -- Layer 1: Tool Direct Engine Activation
                local currentCharacter = LP.Character
                if currentCharacter then
                    local equippedTool = currentCharacter:FindFirstChildOfClass("Tool")
                    if equippedTool then
                        equippedTool:Activate()
                    end
                end
                
                -- Layer 2: Viewport Engine Virtual Click (Bypasses OS Hardware Constraints)
                if VirtualUser then
                    VirtualUser:ClickButton1(Vector2.new(9999, 9999))
                end
            end)
            task.wait(States.M1AttackSpeed)
        end
    end
end)

task.spawn(function()
    while task.wait(0.1) do
        if States.AutoFinisher then
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.B, false, game)
            task.wait(0.01)
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.B, false, game)
        end
    end
end)

-- Stats Automated Loop Worker
task.spawn(function()
    while task.wait() do
        if States.AutoStrengthEnabled or States.AutoEnduranceEnabled or States.AutoStaminaEnabled or States.AutoFocusEnabled or States.AutoLuckEnabled or States.AutoBrainrotEnabled then
            task.wait(States.StatDelayTime)
        end
    end
end)

-- Combined Player and Valid Enemy ESP Rendering Loop
RunService.RenderStepped:Connect(function()
    local myRoot = GetRoot()
    
    if States.ESPEnabled then
        for player, objects in pairs(ESP_Cache) do
            if player and player.Character and objects.Label then
                if objects.Highlight then
                    objects.Highlight.Enabled = States.ShowHighlights
                end
                
                local targetRoot = player.Character:FindFirstChild("HumanoidRootPart")
                if targetRoot and myRoot then
                    objects.Billboard.Enabled = true
                    local dist = math.floor((targetRoot.Position - myRoot.Position).Magnitude)
                    
                    local displayText = ""
                    if States.ShowUsernames then displayText = player.Name end
                    if States.ShowStuds then 
                        displayText = displayText ~= "" and displayText .. "\n[" .. dist .. " studs]" or "[" .. dist .. " studs]"
                    end
                    objects.Label.Text = displayText
                else
                    objects.Billboard.Enabled = false
                end
            end
        end
    end

    if States.EnemyESPEnabled and myRoot then
        for _, desc in ipairs(Workspace:GetDescendants()) do
            if desc:IsA("Humanoid") and desc.Health > 0 then
                local model = desc.Parent
                if model and model:IsA("Model") and not IsPlayerCharacter(model) then
                    local mobRoot = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
                    if mobRoot then
                        local cached = Enemy_ESP_Cache[model]
                        if not cached then
                            cached = {}
                            local hl = Instance.new("Highlight")
                            hl.FillColor = Color3.fromRGB(255, 50, 50)
                            hl.FillTransparency = 0.6
                            hl.OutlineColor = Color3.fromRGB(255, 0, 0)
                            hl.Adornee = model
                            hl.Parent = model
                            cached.Highlight = hl
                            
                            local bb = Instance.new("BillboardGui")
                            bb.Size = UDim2.new(0, 150, 0, 40)
                            bb.AlwaysOnTop = true
                            bb.ExtentsOffset = Vector3.new(0, 3, 0)
                            bb.Adornee = mobRoot
                            bb.Parent = model
                            
                            local lbl = Instance.new("TextLabel", bb)
                            lbl.Size = UDim2.new(1, 0, 1, 0)
                            lbl.BackgroundTransparency = 1
                            lbl.TextSize = 12
                            lbl.Font = Enum.Font.SourceSansBold
                            lbl.TextColor3 = Color3.fromRGB(255, 50, 50)
                            lbl.TextStrokeTransparency = 0
                            cached.Label = lbl
                            cached.Billboard = bb
                            
                            Enemy_ESP_Cache[model] = cached
                        end
                        
                        local dist = math.floor((mobRoot.Position - myRoot.Position).Magnitude)
                        cached.Label.Text = string.format("%s\n[%d studs]", CleanMobName(model.Name), dist)
                    end
                end
            end
        end
    end
end)
