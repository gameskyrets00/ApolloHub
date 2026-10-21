--[[
  Egg ESP - shows "RARITY | Egg Name | 123.4 Kg | 9 studs" above every egg
  Works on eggs already in the world and on newly spawned ones.
  Set DEBUG = true to print what data each egg contains (helps if Kg shows "?").
]]

local CONFIG = {
    DEBUG        = false,
    MAX_DISTANCE = math.huge,          -- hide eggs farther than this (studs)
    TEXT_SIZE    = 16,
    OUTLINE      = true,               -- highlight outline on the egg
    NAME_MATCH   = "egg",              -- model name must contain this (lowercase)
    -- Names of Attributes / Value objects that may hold the weight or rarity.
    WEIGHT_KEYS  = { "Weight", "Kg", "KG", "Mass", "Size", "EggWeight" },
    RARITY_KEYS  = { "Rarity", "Tier", "Type" },
}

local RARITY_COLORS = {
    common    = Color3.fromRGB(190, 190, 190),
    uncommon  = Color3.fromRGB(100, 220, 100),
    rare      = Color3.fromRGB(80, 150, 255),
    epic      = Color3.fromRGB(180, 90, 255),
    legendary = Color3.fromRGB(255, 190, 40),
    mythic    = Color3.fromRGB(255, 80, 120),
    secret    = Color3.fromRGB(255, 255, 255),
}

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local CoreGui    = game:GetService("CoreGui")
local lp         = Players.LocalPlayer

-- Clean up a previous run
if getgenv then
    if getgenv().__EggESP then getgenv().__EggESP() end
end

local container = Instance.new("Folder")
container.Name = "EggESP"
container.Parent = (gethui and gethui()) or CoreGui

local tracked, conns = {}, {}

local function readKey(obj, keys)
    for _, k in ipairs(keys) do
        local a = obj:GetAttribute(k)
        if a ~= nil then return a end
        local child = obj:FindFirstChild(k)
        if child and child:IsA("ValueBase") then return child.Value end
    end
end

local function parseKg(text)
    return tonumber(string.match(text or "", "([%d%.]+)%s*[Kk][Gg]"))
end

-- Try to find weight: attributes -> value objects -> any text label in the model
local function getWeight(model)
    local v = readKey(model, CONFIG.WEIGHT_KEYS)
    if type(v) == "number" then return v end
    if type(v) == "string" then return parseKg(v) or tonumber(v) end
    for _, d in ipairs(model:GetDescendants()) do
        local val = readKey(d, CONFIG.WEIGHT_KEYS)
        if type(val) == "number" then return val end
        if d:IsA("TextLabel") or d:IsA("TextBox") then
            local kg = parseKg(d.Text)
            if kg then return kg end
        end
    end
end

local function getRarity(model)
    local v = readKey(model, CONFIG.RARITY_KEYS)
    if v == nil then
        for _, d in ipairs(model:GetDescendants()) do
            v = readKey(d, CONFIG.RARITY_KEYS)
            if v ~= nil then break end
        end
    end
    return v and tostring(v) or "?"
end

local function getPart(model)
    return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
end

local function debugDump(model)
    print("[EggESP] ---", model:GetFullName())
    for k, v in pairs(model:GetAttributes()) do print("  attr", k, v) end
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("ValueBase") then print("  value", d.Name, d.Value) end
        if d:IsA("TextLabel") then print("  text", d.Name, d.Text) end
        for k, v in pairs(d:GetAttributes()) do print("  attr@" .. d.Name, k, v) end
    end
end

local function track(model)
    if tracked[model] then return end
    if not (model:IsA("Model") or model:IsA("BasePart")) then return end
    if not string.find(string.lower(model.Name), CONFIG.NAME_MATCH, 1, true) then return end
    local part = model:IsA("BasePart") and model or getPart(model)
    if not part then return end

    if CONFIG.DEBUG then debugDump(model) end

    local gui = Instance.new("BillboardGui")
    gui.Name = "ESP"
    gui.Adornee = part
    gui.AlwaysOnTop = true
    gui.Size = UDim2.fromOffset(300, 30)
    gui.StudsOffset = Vector3.new(0, 3, 0)
    gui.Parent = container

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamBold
    label.TextSize = CONFIG.TEXT_SIZE
    label.TextStrokeTransparency = 0.3
    label.TextColor3 = Color3.new(1, 1, 1)
    label.Parent = gui

    local hl
    if CONFIG.OUTLINE then
        hl = Instance.new("Highlight")
        hl.FillTransparency = 1
        hl.OutlineColor = Color3.new(1, 1, 1)
        hl.Adornee = model
        hl.Parent = container
    end

    tracked[model] = { gui = gui, label = label, part = part, hl = hl, model = model }
end

local function untrack(model)
    local t = tracked[model]
    if not t then return end
    t.gui:Destroy()
    if t.hl then t.hl:Destroy() end
    tracked[model] = nil
end

-- Existing + newly spawned eggs
for _, d in ipairs(workspace:GetDescendants()) do track(d) end
table.insert(conns, workspace.DescendantAdded:Connect(function(d)
    task.wait(0.2) -- let attributes/children replicate
    track(d)
end))
table.insert(conns, workspace.DescendantRemoving:Connect(untrack))

-- Update loop
table.insert(conns, RunService.RenderStepped:Connect(function()
    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    for model, t in pairs(tracked) do
        if not t.part.Parent then
            untrack(model)
        else
            local dist = root and (root.Position - t.part.Position).Magnitude or 0
            t.gui.Enabled = dist <= CONFIG.MAX_DISTANCE
            local kg = getWeight(model)
            local rarity = getRarity(model)
            t.label.Text = string.format("%s | %s | %s Kg | %d studs",
                string.upper(rarity), model.Name,
                kg and string.format("%.1f", kg) or "?", math.floor(dist))
            local c = RARITY_COLORS[string.lower(rarity)] or Color3.new(1, 1, 1)
            t.label.TextColor3 = c
            if t.hl then t.hl.OutlineColor = c end
        end
    end
end))

if getgenv then
    getgenv().__EggESP = function()
        for _, c in ipairs(conns) do c:Disconnect() end
        container:Destroy()
    end
end
