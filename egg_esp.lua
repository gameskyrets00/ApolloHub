local CONFIG = {
    DEBUG          = false,
    MAX_DISTANCE   = math.huge,
    TEXT_SIZE      = 16,
    OUTLINE        = false,
    NAME_MATCH     = "egg",
    UPDATE_RATE    = 0.15,
    DATA_RATE      = 1,
    IGNORE_NAMES   = { eggs = true, eggfolder = true, eggs_folder = true },
    WEIGHT_KEYS    = { "Weight", "Kg", "KG", "Mass", "EggWeight", "BaseWeight", "PetWeight" },
    RARITY_KEYS    = { "Rarity", "Tier", "Type" },
}

local RARITY_COLORS = {
    common = Color3.fromRGB(190,190,190), uncommon = Color3.fromRGB(100,220,100),
    rare = Color3.fromRGB(80,150,255),    epic = Color3.fromRGB(180,90,255),
    legendary = Color3.fromRGB(255,190,40), mythic = Color3.fromRGB(255,80,120),
    celestial = Color3.fromRGB(255,200,60), secret = Color3.fromRGB(255,255,255),
}

local Players, RunService, CoreGui = game:GetService("Players"), game:GetService("RunService"), game:GetService("CoreGui")
local lp = Players.LocalPlayer

if getgenv and getgenv().__EggESP then getgenv().__EggESP() end

local container = Instance.new("Folder")
container.Name = "EggESP"
container.Parent = (gethui and gethui()) or CoreGui

local tracked, conns = {}, {}

local function matches(inst)
    local n = string.lower(inst.Name)
    return string.find(n, CONFIG.NAME_MATCH, 1, true) ~= nil and not CONFIG.IGNORE_NAMES[n]
end

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

-- parse numbers from values/text: 123, "123.4", "1,234.5 KG"
local function toNumber(v)
    if type(v) == "number" then return v end
    if type(v) == "string" then
        local s = v:gsub(",", "")
        local withUnit = string.match(s, "(%d+%.?%d*)%s*[Kk][Gg]")
        return tonumber(withUnit) or tonumber(s)
    end
end

local function readKey(obj, keys)
    for _, k in ipairs(keys) do
        local a = obj:GetAttribute(k)
        if a ~= nil then return a end
        local ch = obj:FindFirstChild(k)
        if ch and ch:IsA("ValueBase") then return ch.Value end
    end
end

local function looksLikeWeight(name)
    name = string.lower(name)
    return string.find(name, "weight", 1, true) or string.find(name, "kg", 1, true)
end

local function readData(model)
    local kg, rarity, source

    -- 1) exact keys on the egg itself (most reliable, per-egg data)
    local v = readKey(model, CONFIG.WEIGHT_KEYS)
    kg = toNumber(v)
    if kg then source = "egg key" end
    rarity = readKey(model, CONFIG.RARITY_KEYS)

    -- 2) search inside THIS egg only (attributes, values, text labels)
    if not kg or rarity == nil then
        local objs = model:GetDescendants()
        table.insert(objs, 1, model)
        for _, d in ipairs(objs) do
            if not kg then
                -- exact keys on children
                local ev = readKey(d, CONFIG.WEIGHT_KEYS)
                if ev ~= nil and toNumber(ev) then kg = toNumber(ev); source = "child key " .. d.Name end
                -- fuzzy attribute names
                if not kg then
                    for k, val in pairs(d:GetAttributes()) do
                        if looksLikeWeight(k) and toNumber(val) then
                            kg = toNumber(val); source = "attr " .. k; break
                        end
                    end
                end
                -- ValueObjects named like weight
                if not kg and d:IsA("ValueBase") and looksLikeWeight(d.Name) and toNumber(d.Value) then
                    kg = toNumber(d.Value); source = "value " .. d.Name
                end
                -- text that explicitly contains "kg"
                if not kg and (d:IsA("TextLabel") or d:IsA("TextBox")) then
                    local s = string.gsub(d.Text or "", ",", "")
                    local n = tonumber(string.match(s, "(%d+%.?%d*)%s*[Kk][Gg]"))
                    if n then kg = n; source = "text " .. d.Name end
                end
            end
            if rarity == nil then rarity = readKey(d, CONFIG.RARITY_KEYS) end
            if kg and rarity ~= nil then break end
        end
    end

    -- NO physical-mass fallback: that's what made every egg show the same Kg.
    return kg, rarity and tostring(rarity) or "?", source
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

for _, d in ipairs(workspace:GetDescendants()) do
    if matches(d) then track(d) end
end

table.insert(conns, workspace.DescendantAdded:Connect(function(d)
    if matches(d) then
        task.delay(0.3, function() if d.Parent then track(d) end end)
    end
end))
table.insert(conns, workspace.DescendantRemoving:Connect(function(d)
    if tracked[d] then untrack(d) end
end))

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
                    local src
                    t.kg, t.rarity, src = readData(model)
                    t.lastData = now
                    if CONFIG.DEBUG and src and src ~= t.src then
                        t.src = src
                        print("[EggESP]", model.Name, "Kg from", src, "=", t.kg)
                    end
                end
                local text = string.format("%s | %s | %s Kg | %d studs",
                    string.upper(t.rarity or "?"), model.Name,
                    t.kg and string.format("%.1f", t.kg) or "?", math.floor(dist))
                if text ~= t.lastText then
                    t.label.Text = text
                    t.lastText = text
                    local c = RARITY_COLORS[string.lower(t.rarity or "")] or Color3.new(1, 1, 1)
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
