

local CONFIG = {
    DEBUG          = false,
    MAX_DISTANCE   = math.huge,   -- hide eggs farther than this
    TEXT_SIZE      = 16,
    OUTLINE        = false,       -- Highlight is laggy with many eggs
    NAME_MATCH     = "egg",
    UPDATE_RATE    = 0.15,        -- seconds between label updates
    DATA_RATE      = 1,           -- seconds between re-reading Kg/rarity
    IGNORE_NAMES   = { eggs = true, eggfolder = true, eggs_folder = true },
    WEIGHT_KEYS    = { "Weight", "Kg", "KG", "Mass", "Size", "EggWeight" },
    RARITY_KEYS    = { "Rarity", "Tier", "Type" },
}

local RARITY_COLORS = {
    common = Color3.fromRGB(190,190,190), uncommon = Color3.fromRGB(100,220,100),
    rare = Color3.fromRGB(80,150,255),    epic = Color3.fromRGB(180,90,255),
    legendary = Color3.fromRGB(255,190,40), mythic = Color3.fromRGB(255,80,120),
    celestial = Color3.fromRGB(255,200,60),
    secret = Color3.fromRGB(255,255,255),
}

local Players, RunService, CoreGui = game:GetService("Players"), game:GetService("RunService"), game:GetService("CoreGui")
local lp = Players.LocalPlayer

if getgenv and getgenv().__EggESP then getgenv().__EggESP() end

local container = Instance.new("Folder")
container.Name = "EggESP"
container.Parent = (gethui and gethui()) or CoreGui

local tracked, conns = {}, {}   -- tracked[rootEgg] = data

local function matches(inst)
    local n = string.lower(inst.Name)
    return string.find(n, CONFIG.NAME_MATCH, 1, true) ~= nil and not CONFIG.IGNORE_NAMES[n]
end

-- A "container" holds several eggs (e.g. a model with many egg children)
local function isContainer(m)
    local c = 0
    for _, ch in ipairs(m:GetChildren()) do
        if ch:IsA("Model") and matches(ch) then
            c += 1
            if c >= 2 then return true end
        end
    end
    return false
end

-- Walk up to the OUTERMOST single-egg model so parts/meshes never get their own ESP
local function resolveRoot(inst)
    local top
    local cur = inst
    while cur and cur ~= workspace do
        if (cur:IsA("Model") or cur:IsA("BasePart")) and matches(cur) then
            if cur:IsA("Model") and isContainer(cur) then break end
            top = cur
        end
        cur = cur.Parent
    end
    return top
end

local function readKey(obj, keys)
    for _, k in ipairs(keys) do
        local a = obj:GetAttribute(k)
        if a ~= nil then return a end
        local ch = obj:FindFirstChild(k)
        if ch and ch:IsA("ValueBase") then return ch.Value end
    end
end

local function parseKg(t) return tonumber(string.match(t or "", "([%d%.]+)%s*[Kk][Gg]")) end

local WEIGHT_HINTS = { "weight", "kg", "mass", "size" }

local function looksLikeWeight(name)
    name = string.lower(name)
    for _, h in ipairs(WEIGHT_HINTS) do
        if string.find(name, h, 1, true) then return true end
    end
    return false
end

local function readData(model)
    local kg, rarity

    -- 1) exact keys on the egg itself
    local v = readKey(model, CONFIG.WEIGHT_KEYS)
    if type(v) == "number" then kg = v elseif type(v) == "string" then kg = parseKg(v) or tonumber(v) end
    rarity = readKey(model, CONFIG.RARITY_KEYS)

    -- 2) fuzzy search: any attribute / value / text that looks like weight
    if not kg or rarity == nil then
        local objs = model:GetDescendants()
        table.insert(objs, 1, model)
        for _, d in ipairs(objs) do
            if not kg then
                for k, val in pairs(d:GetAttributes()) do
                    if looksLikeWeight(k) then
                        if type(val) == "number" then kg = val; break end
                        if type(val) == "string" then kg = parseKg(val) or tonumber(val); if kg then break end end
                    end
                end
                if not kg and d:IsA("ValueBase") and looksLikeWeight(d.Name) and type(d.Value) == "number" then
                    kg = d.Value
                end
                if not kg and (d:IsA("TextLabel") or d:IsA("TextBox")) then
                    kg = parseKg(d.Text)
                end
            end
            if rarity == nil then rarity = readKey(d, CONFIG.RARITY_KEYS) end
            if kg and rarity ~= nil then break end
        end
    end

    -- 3) fallback: Roblox physical mass of the egg
    if not kg then
        local ok, mass = pcall(function()
            if model:IsA("BasePart") then return model.AssemblyMass end
            local total = 0
            for _, p in ipairs(model:GetDescendants()) do
                if p:IsA("BasePart") then total += p:GetMass() end
            end
            return total
        end)
        if ok and mass and mass > 0 then kg = mass end
    end

    return kg, rarity and tostring(rarity) or "?"
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

local function untrack(model)
    local t = tracked[model]
    if not t then return end
    t.gui:Destroy()
    if t.hl then t.hl:Destroy() end
    tracked[model] = nil
end

local function track(inst)
    local root = resolveRoot(inst)
    if not root or tracked[root] then return end
    local part = root:IsA("BasePart") and root or root.PrimaryPart or root:FindFirstChildWhichIsA("BasePart", true)
    if not part then return end

    -- remove any ESP previously made for a child/part of this egg
    for m in pairs(tracked) do
        if m ~= root and m:IsDescendantOf(root) then untrack(m) end
    end

    if CONFIG.DEBUG then debugDump(root) end

    local gui = Instance.new("BillboardGui")
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
    label.Parent = gui

    local hl
    if CONFIG.OUTLINE then
        hl = Instance.new("Highlight")
        hl.FillTransparency = 1
        hl.Adornee = root
        hl.Parent = container
    end

    tracked[root] = { gui = gui, label = label, part = part, hl = hl, lastData = 0, lastText = "" }
end

-- Initial scan
for _, d in ipairs(workspace:GetDescendants()) do
    if matches(d) then track(d) end
end

-- New spawns: only react to instances whose name matches (no thread spam)
table.insert(conns, workspace.DescendantAdded:Connect(function(d)
    if matches(d) then
        task.delay(0.3, function() if d.Parent then track(d) end end)
    end
end))
table.insert(conns, workspace.DescendantRemoving:Connect(function(d)
    if tracked[d] then untrack(d) end
end))

-- Throttled update loop
local acc = 0
table.insert(conns, RunService.Heartbeat:Connect(function(dt)
    acc += dt
    if acc < CONFIG.UPDATE_RATE then return end
    acc = 0
    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local now = os.clock()
    for model, t in pairs(tracked) do
        if not model.Parent or not t.part.Parent then
            untrack(model)
        else
            local dist = root and (root.Position - t.part.Position).Magnitude or 0
            local show = dist <= CONFIG.MAX_DISTANCE
            t.gui.Enabled = show
            if show then
                if now - t.lastData >= CONFIG.DATA_RATE then
                    t.kg, t.rarity = readData(model)
                    t.lastData = now
                end
                local text = string.format("%s | %s | %s Kg | %d studs",
                    string.upper(t.rarity or "?"), model.Name,
                    t.kg and string.format("%.1f", t.kg) or "?", math.floor(dist))
                if text ~= t.lastText then
                    t.label.Text = text
                    t.lastText = text
                    local c = RARITY_COLORS[string.lower(t.rarity or "")] or Color3.new(1,1,1)
                    t.label.TextColor3 = c
                    if t.hl then t.hl.OutlineColor = c end
                end
            end
        end
    end
end))

if getgenv then
    getgenv().__EggESP = function()
        for _, c in ipairs(conns) do c:Disconnect() end
        container:Destroy()
    end
end
