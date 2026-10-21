local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")

TeleportService:TeleportToPlaceInstance(
    game.PlaceId,
    game.JobId,
    Players.LocalPlayer
)
