local Players = game:GetService("Players")
local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "EggWeightDisplay"
gui.ResetOnSpawn = false

local label = Instance.new("TextLabel")
label.Size = UDim2.new(0, 260, 0, 50)
label.Position = UDim2.new(0.5, -130, 0.1, 0)
label.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
label.TextColor3 = Color3.fromRGB(255, 255, 255)
label.TextScaled = true
label.Text = "Egg Weight: Checking..."
label.Parent = gui

gui.Parent = player:WaitForChild("PlayerGui")

-- Search for egg objects and their weight values
local function findEggWeight()
    for _, obj in ipairs(game:GetDescendants()) do
        if obj:IsA("ValueBase") then
            local name = obj.Name:lower()
            if name:find("weight") or name == "kg" then
                return tostring(obj.Value) .. " kg"
            end
        end
    end
    return "Weight data not found"
end

label.Text = "Egg Weight: " .. findEggWeight()
