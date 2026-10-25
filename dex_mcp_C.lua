--[[
================================================================
  DexMCP C — 悬浮按钮 + 队列（独立注入脚本）
================================================================
  前提：DEX++ 已加载，且 DexMCP 模块（A）已注入，getgenv().DEX 存在。

  功能：
    - 右下角可拖动 [→ MCP] 按钮
    - 左键：把当前 DEX 选中对象发到队列
    - 右键：打印队列 + 复制全部路径到剪贴板
    - Ctrl+Shift+M：发送当前选中

  读取：
    getgenv().DEX_QUEUE.Take() / .Peek() / .Count() / .Selected()
================================================================
]]

do

local g = getgenv and getgenv() or _G

if g.DEX_QUEUE and g.DEX_QUEUE.__version then
	print("[DPP-MCP-C] 按钮已加载，跳过")
	return
end

local D = g.DEX
if not D or not D.Version then
	error("[DPP-MCP-C] getgenv().DEX 不存在，请先加载 DexMCP 模块（A）")
end

local VERSION = "mcp-dpp-C-1.0"
local DEBUG = g.DEX_MCP_DEBUG == true
local BUTTON_KEY = "Ctrl+Shift+M"
local MAX_PEND = 120

local HttpService = game:GetService("HttpService")

-- task 兼容
local TASK = task or (function()
	local t = {}
	t.wait = function(s) if wait then return wait(s) end end
	t.spawn = function(f, ...) return coroutine.wrap(f)(...) end
	t.defer = function(f, ...)
		local a = table.pack and table.pack(...) or { n = select("#", ...), ... }
		coroutine.wrap(function() f(table.unpack(a, 1, a.n or #a)) end)()
	end
	t.delay = function(s, f) t.spawn(function() t.wait(s) f() end) end
	return t
end)()

-- ------------------------------------------------------------
-- 队列
-- ------------------------------------------------------------
local Queue = { items = {}, seq = 0 }

local function selectedPaths()
	local out = {}
	if D.Snapshot then
		local ok, snap = pcall(D.Snapshot)
		if ok and type(snap) == "table" and snap.selectionPaths then
			for i = 1, #snap.selectionPaths do
				out[#out + 1] = snap.selectionPaths[i]
			end
		end
	end
	return out
end

local function send(reason)
	local paths = selectedPaths()
	if #paths == 0 then return false, "DEX 里没有选中对象" end

	Queue.seq = Queue.seq + 1
	Queue.items[#Queue.items + 1] = {
		seq = Queue.seq,
		time = os.date("%H:%M:%S"),
		reason = reason or "button",
		paths = paths,
	}
	while #Queue.items > MAX_PEND do table.remove(Queue.items, 1) end

	if D.env and D.env.setclipboard then
		pcall(D.env.setclipboard, table.concat(paths, "\n"))
	end

	-- 可选推送
	local base = g.BridgeURL
	if type(base) == "string" and base ~= "" then
		pcall(function()
			local b = base:gsub("^%s+", ""):gsub("%s+$", ""):gsub("/+$", "")
			b = b:gsub("^https://", "http://"):gsub("^wss?://", "http://")
			if D.env and D.env.request then
				D.env.request({
					Url = b .. "/dex/event",
					Method = "POST",
					Headers = { ["Content-Type"] = "application/json" },
					Body = HttpService:JSONEncode({
						type = "selection", reason = reason or "button",
						time = os.date("%H:%M:%S"), paths = paths,
						clientId = tostring(game.JobId),
					}),
				})
			end
		end)
	end

	print("[DPP->MCP] " .. #paths .. " object(s) queued (" .. tostring(reason or "button") .. "):\n" .. table.concat(paths, "\n"))
	return true, #paths
end

-- ------------------------------------------------------------
-- 按钮
-- ------------------------------------------------------------
local BUTTON_NAME = "DexPlusPlusMCPButton"
local button, pulseUntil

local function secureParent()
	if D.Main and D.Main.GetSecureContainer then
		local ok, root = pcall(D.Main.GetSecureContainer)
		if ok and root then return root end
	end
	if gethui then
		local ok, root = pcall(gethui)
		if ok and root then return root end
	end
	return game:GetService("CoreGui")
end

local function buildButton()
	if button and button.Parent then return true end
	local existing = secureParent():FindFirstChild(BUTTON_NAME)
	if existing then existing:Destroy() end

	local gui = Instance.new("ScreenGui")
	gui.Name = BUTTON_NAME
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 999999
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local frame = Instance.new("TextButton")
	frame.Name = "Btn"
	frame.Size = UDim2.new(0, 96, 0, 30)
	frame.Position = UDim2.new(1, -110, 0, 96)
	frame.BackgroundColor3 = Color3.fromRGB(32, 34, 38)
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0
	frame.Text = "-> MCP"
	frame.TextColor3 = Color3.fromRGB(120, 210, 255)
	frame.TextSize = 14
	frame.Font = Enum.Font.SourceSansSemibold
	frame.AutoButtonColor = false
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(60, 140, 190)
	stroke.Thickness = 1
	stroke.Transparency = 0.3
	stroke.Parent = frame

	button = frame
	gui.Parent = secureParent()

	-- 拖动
	local dragging, dragStart, startPos = false, nil, nil
	frame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.MouseButton2
		or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = frame.Position
		end
	end)
	frame.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.MouseButton2
		or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	local uis = game:GetService("UserInputService")
	uis.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
		and input.UserInputType ~= Enum.UserInputType.Touch then return end
		local delta = input.Position - dragStart
		frame.Position = UDim2.new(
			startPos.X.Scale, startPos.X.Offset + delta.X,
			startPos.Y.Scale, startPos.Y.Offset + delta.Y)
	end)

	-- 左键发送
	frame.MouseButton1Click:Connect(function()
		local ok, n = send("button")
		if ok then
			frame.Text = "v " .. tostring(n)
			pulseUntil = tick() + 1.2
			TASK.delay(1.2, function()
				if tick() >= pulseUntil and frame and frame.Parent then frame.Text = "-> MCP" end
			end)
		else
			frame.Text = "none"
			TASK.delay(1.2, function()
				if frame and frame.Parent then frame.Text = "-> MCP" end
			end)
		end
	end)

	-- 右键打印 + 复制
	frame.MouseButton2Click:Connect(function()
		local lines = {}
		for i = 1, #Queue.items do
			local ev = Queue.items[i]
			lines[#lines + 1] = ("#%d %s (%s)"):format(ev.seq, ev.time, ev.reason)
			for j = 1, #ev.paths do lines[#lines + 1] = "  " .. ev.paths[j] end
		end
		print("[DPP-MCP] queue (" .. #Queue.items .. " entries):\n" .. table.concat(lines, "\n"))
		local all = {}
		for i = 1, #Queue.items do
			for j = 1, #Queue.items[i].paths do all[#all + 1] = Queue.items[i].paths[j] end
		end
		if D.env and D.env.setclipboard then pcall(D.env.setclipboard, table.concat(all, "\n")) end
	end)

	return true
end

-- ------------------------------------------------------------
-- 快捷键
-- ------------------------------------------------------------
local function hookShortcut()
	local uis = game:GetService("UserInputService")
	uis.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode ~= Enum.KeyCode.M then return end
		local okC, ctrl = pcall(function() return uis:IsKeyDown(Enum.KeyCode.LeftControl) or uis:IsKeyDown(Enum.KeyCode.RightControl) end)
		if not okC or not ctrl then return end
		local okS, shift = pcall(function() return uis:IsKeyDown(Enum.KeyCode.LeftShift) or uis:IsKeyDown(Enum.KeyCode.RightShift) end)
		if not okS or not shift then return end
		local ok, n = send("hotkey")
		if ok and button and button.Parent then
			button.Text = "v " .. tostring(n)
			pulseUntil = tick() + 1.2
			TASK.delay(1.2, function()
				if tick() >= pulseUntil and button and button.Parent then button.Text = "-> MCP" end
			end)
		end
	end)
end

-- ------------------------------------------------------------
-- 对外 API
-- ------------------------------------------------------------
local API = {}
API.__version = VERSION
API.Version = VERSION
API.Take = function()
	local out, last = Queue.items, Queue.seq
	Queue.items = {}
	return { lastSeq = last, count = #out, events = out }
end
API.Peek = function()
	return { lastSeq = Queue.seq, count = #Queue.items, events = Queue.items }
end
API.Send = function(reason) return send(reason) end
API.Selected = function() return selectedPaths() end
API.Count = function() return #Queue.items end
API.Clear = function()
	local n = #Queue.items
	Queue.items = {}
	return n
end
API.Button = function() return button end
API.Shortcut = BUTTON_KEY

-- ------------------------------------------------------------
-- 挂载
-- ------------------------------------------------------------
g.DEX_QUEUE = API
g.DEX_MCP_C = API

local okBtn, btnErr = pcall(buildButton)
if not okBtn then
	warn("[DPP-MCP-C] 按钮创建失败: " .. tostring(btnErr))
end

pcall(hookShortcut)

print("[DPP-MCP-C] 注入 | version=" .. VERSION)
print("[DPP-MCP-C] 点 [-> MCP] 或按 " .. BUTTON_KEY .. " 发送选中")
print("[DPP-MCP-C] 读取: getgenv().DEX_QUEUE.Take()")

end
