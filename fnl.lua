--[[ ============================================================
    远程防甩开启模块（上传到 GitHub）
    ------------------------------------------------------------
    用途：由主脚本 loadstring(game:HttpGet(...))() 远程执行
    特点：此文件不经 Prometheus VM 混淆，Stepped 热循环在原生
          Lua 下运行，不会卡顿。
    桥接：通过 _G 全局变量暴露状态，供本地关闭函数访问。
    ============================================================ ]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local speaker = Players.LocalPlayer

-- 防重复开启
if _G.__antifling_active then
    return
end

-- ★ 全局状态桥（本地关闭函数通过这些访问/断开）
_G.__antifling_parts = {}
_G.__antifling_connections = {}
_G.__antifling_active = true

local parts = _G.__antifling_parts
local connections = _G.__antifling_connections

-- 将零件纳入监控
local function trackPart(part)
    if part:IsA("BasePart") then
        parts[part] = true
    end
end

-- 将零件移出监控
local function untrackPart(part)
    parts[part] = nil
end

-- 监控一个角色：现有零件 + 未来新增/移除 + 角色删除时清理
local function watchCharacter(character)
    -- 现有零件
    for _, part in ipairs(character:GetDescendants()) do
        trackPart(part)
    end

    -- 未来新增零件
    local descAddedConn = character.DescendantAdded:Connect(function(desc)
        trackPart(desc)
    end)
    table.insert(connections, descAddedConn)

    -- 未来移除零件
    local descRemovingConn = character.DescendantRemoving:Connect(function(desc)
        untrackPart(desc)
    end)
    table.insert(connections, descRemovingConn)

    -- 当角色从游戏世界移除（死亡、重置、移除）时，彻底清理
    local ancestryConn
    ancestryConn = character.AncestryChanged:Connect(function(_, parent)
        if parent == nil then
            for _, part in ipairs(character:GetDescendants()) do
                untrackPart(part)
            end
        end
    end)
    table.insert(connections, ancestryConn)
end

-- 为一名玩家绑定完整的监控（当前角色 + 未来重生）
local function setupPlayer(player)
    if player == speaker then return end

    -- 绑定角色重生事件
    local charConn = player.CharacterAdded:Connect(function(character)
        watchCharacter(character)
    end)
    table.insert(connections, charConn)

    -- 如果当前已有角色，立即监控
    if player.Character then
        watchCharacter(player.Character)
    end
end

-- 为所有在线玩家绑定监控（包括当前和重生）
for _, player in ipairs(Players:GetPlayers()) do
    setupPlayer(player)
end

-- 监听未来加入的玩家
local playerAddedConn = Players.PlayerAdded:Connect(setupPlayer)
table.insert(connections, playerAddedConn)

-- ★ 热循环（原生 Lua 执行，不经 VM，不卡）
local steppedConn = RunService.Stepped:Connect(function()
    for part in pairs(parts) do
        pcall(function()
            part.CanCollide = false
        end)
    end
end)
table.insert(connections, steppedConn)