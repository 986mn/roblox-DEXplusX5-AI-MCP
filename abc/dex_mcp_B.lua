--[[
================================================================
  DexMCP B — 运行时包装器（不改 DEX 源，下载官方原版再注入）
================================================================
  原理：
    1. 下载官方 DEX++ 源码（DEX_URL，默认 snmwdd 原版）
    2. 把 DexMCP 模块注入 EmbeddedModules 表
    3. 把 "DexMCP" 加入 Main.ModuleList
    4. 整体 loadstring 执行

  好处：
    - 不依赖本 fork，直接用官方原版 DEX
    - 官方更新时只需换 DEX_URL

  用法：
    getgenv().DEX_URL = "https://raw.githubusercontent.com/snmwdd/DexPlusPlusPlusPlus/refs/heads/main/script.lua"
    loadstring(game:HttpGet("https://raw.githubusercontent.com/986mn/roblox-DEXplusX5-AI-MCP/main/abc/dex_mcp_B.lua"))()
================================================================
]]

do

local g = getgenv and getgenv() or _G

if g.DEX and g.DEX.Version then
	print("[DPP-MCP-B] 已加载过 (" .. tostring(g.DEX.Version) .. ")，跳过")
	return
end

local DEX_URL = g.DEX_URL
	or "https://raw.githubusercontent.com/snmwdd/DexPlusPlusPlusPlus/refs/heads/main/script.lua"

print("[DPP-MCP-B] 下载官方 DEX++: " .. DEX_URL)

local okHttp, src = pcall(function() return game:HttpGet(DEX_URL) end)
if not okHttp or type(src) ~= "string" or #src < 1000 then
	error("[DPP-MCP-B] DEX 下载失败: " .. tostring(src))
end

print("[DPP-MCP-B] 下载完成: " .. #src .. " 字符")

-- 如果源码里已经含 DexMCP（比如拿的是本 fork 的 script.lua），直接跑
if src:find('["DexMCP"]', 1, true) then
	print("[DPP-MCP-B] 源码已含 DexMCP，直接执行")
	local fn, e = loadstring(src)
	if not fn then error("[DPP-MCP-B] loadstring 失败: " .. tostring(e)) end
	fn()
	return
end

-- ------------------------------------------------------------
-- 注入点 1：把 DexMCP 模块塞进 EmbeddedModules 表
-- ------------------------------------------------------------
local MODULE_SRC = [==[
--[[
	DexMCP Module

	Bridges DEX PlusPlusPlusPlus to an MCP server (AI agent).
	Exposes a read/write API on getgenv().DEX so an external MCP server
	can query the DEX selection, read properties, decompile scripts,
	execute Luau, and drive the DEX UI.

	This module follows the standard DEX++ module contract:
		return {InitDeps = ..., InitAfterMain = ..., Main = ...}
	and is registered in Main.ModuleList as "DexMCP".

	API cheat sheet (from any executor console):
		local D = getgenv().DEX
		D.Snapshot()                          -- current selection + meta
		D.Select({"game.Workspace.NPC"})      -- select (UI jumps to it)
		D.Tree("game.Workspace", 3, 200)      -- instance tree
		D.Props("game.Workspace.NPC")         -- properties/attributes/tags
		D.Source("game.ReplicatedStorage.X")  -- decompile (6 modes)
		D.SetProp(path, "Health", "0")        -- write
		D.Run("return 1+1")                   -- execute
		D.App("Explorer", true)               -- toggle a panel
		D.OpenScript(path, "Executor")        -- open in Notepad tab
		getgenv().DEX_QUEUE.Take()            -- queue handoff
]]

-- Common Locals
local Main,Lib,Apps,Settings -- Main Containers
local Explorer, Properties, ScriptViewer, Notebook -- Major Apps
local API,RMD,env,service,plr,create,createSimple -- Main Locals

local function initDeps(data)
	Main = data.Main
	Lib = data.Lib
	Apps = data.Apps
	Settings = data.Settings

	API = data.API
	RMD = data.RMD
	env = data.env
	service = data.service
	plr = data.plr
	create = data.create
	createSimple = data.createSimple
end

local function initAfterMain()
	Explorer = Apps.Explorer
	Properties = Apps.Properties
	ScriptViewer = Apps.ScriptViewer
	Notebook = Apps.Notebook
end

local function main()
	local g = getgenv and getgenv() or _G

	local VERSION   = "mcp-dpp-1.0"
	local DEBUG     = g.DEX_MCP_DEBUG == true
	local MAX_PEND  = 120
	local MAX_TREE  = 4000
	local MAX_SEL   = 64
	local startedAt = tick()

	local function log(...)
		if DEBUG then print("[DPP-MCP]", ...) end
	end

	local Bridge = {}
	local Pending = { items = {}, seq = 0 }

	local function buildPath(obj)
		if not obj or typeof(obj) ~= "Instance" then return nil end
		if obj.Parent == nil and obj ~= game then return nil end

		if Explorer and Explorer.GetInstancePath then
			local ok, p = pcall(Explorer.GetInstancePath, obj)
			if ok and type(p) == "string" and #p > 0 and not p:find("getNil", 1, true) then
				return p
			end
		end

		local parts = {}
		local cur = obj
		while cur and cur ~= game do
			local name = cur.Name
			local part
			if name:match("^[%a_][%w_]*$") then
				part = "." .. name
			else
				part = '["' .. name:gsub('"', '\\"') .. '"]'
			end
			local par = cur.Parent
			if par and par:FindFirstChild(name) ~= cur then
				local children = par:GetChildren()
				for i = 1, #children do
					if children[i] == cur then
						part = ":GetChildren()[" .. i .. "]"
						break
					end
				end
			end
			table.insert(parts, 1, part)
			cur = cur.Parent
		end
		return "game" .. table.concat(parts)
	end

	local function resolvePath(path)
		if type(path) ~= "string" then return nil end
		path = path:gsub("^%s+", ""):gsub("%s+$", "")
		if path == "" then return nil end
		if path:find("getNil", 1, true) then return nil end
		if path == "game" then return game end
		if path:sub(1, 5) ~= "game." and path:sub(1, 5) ~= "game[" and path:sub(1, 6) ~= "game:" then
			path = "game." .. path
		end

		local cur = game
		local i, len = 5, #path

		while i <= len do
			local ch = path:sub(i, i)

			if ch == "." then
				local name, nxt = path:match("^%.([%w_]+)()", i)
				if not name then return nil end
				local child = cur:FindFirstChild(name)
				if not child and cur == game then
					local ok, svc = pcall(function() return game:GetService(name) end)
					if ok then child = svc end
				end
				if not child then return nil end
				cur, i = child, nxt

			elseif ch == "[" then
				local _, name, nxt = path:match('^%[%s*(["\'])(.-)%1%s*%]()', i)
				if name then
					local child = cur:FindFirstChild(name)
					if not child then return nil end
					cur, i = child, nxt
				else
					local idx, nxt2 = path:match("^%[(%d+)%]()", i)
					if not idx then return nil end
					local target = cur:GetChildren()[tonumber(idx)]
					if not target then return nil end
					cur, i = target, nxt2
				end

			elseif ch == ":" then
				local svcName, nxt = path:match('^:GetService%(%s*["\'](.-)["\']%s*%)()', i)
				if svcName then
					local ok, svc = pcall(function() return game:GetService(svcName) end)
					if not ok or not svc then return nil end
					cur, i = svc, nxt
				else
					local n, nxt2 = path:match("^:GetChildren%(%)%[(%d+)%]()", i)
					if not n then return nil end
					local target = cur:GetChildren()[tonumber(n)]
					if not target then return nil end
					cur, i = target, nxt2
				end

			else
				return nil
			end
		end

		return cur
	end

	local function nodeFor(obj)
		if not obj then return nil end
		local map = Explorer and Explorer.Nodes
		if map and map[obj] then return map[obj] end
		return { Obj = obj, Parent = obj.Parent and map and map[obj.Parent] or nil }
	end

	local function selectedNodes()
		local out = {}
		local sel = Explorer and Explorer.Selection
		if sel and sel.List then
			for i = 1, #sel.List do
				if i > MAX_SEL then break end
				out[#out + 1] = sel.List[i]
			end
		end
		return out
	end

	local function selectedObjs()
		local out = {}
		local nds = selectedNodes()
		for i = 1, #nds do
			if nds[i] and nds[i].Obj then out[#out + 1] = nds[i].Obj end
		end
		return out
	end

	local function describe(obj)
		if not obj or typeof(obj) ~= "Instance" then return nil end

		local info = { name = obj.Name, class = obj.ClassName, path = buildPath(obj) }

		local okFull, full = pcall(function() return obj:GetFullName() end)
		if okFull and type(full) == "string" then info.fullName = full end

		local par = obj.Parent
		if par then
			info.parent = { name = par.Name, class = par.ClassName }
		else
			info.nilParent = true
		end

		local okPos, pos = pcall(function() return obj.Position end)
		if okPos and typeof(pos) == "Vector3" then
			info.position = {
				math.floor(pos.X * 100) / 100,
				math.floor(pos.Y * 100) / 100,
				math.floor(pos.Z * 100) / 100,
			}
		end

		local okHp, hp = pcall(function() return obj.Health end)
		if okHp and type(hp) == "number" then info.health = hp end

		local okHum, hum = pcall(function() return obj:FindFirstChildOfClass("Humanoid") end)
		if okHum and hum then info.hasHumanoid = true end

		if obj:IsA("LuaSourceContainer") and env and env.isViableDecompileScript then
			local okV, viable = pcall(env.isViableDecompileScript, obj)
			if okV then info.decompilable = viable and true or false end
		end

		return info
	end

	local function currentDecompileMode()
		if not (env and env.getDecompileMode) then return nil end
		local ok, mode = pcall(env.getDecompileMode)
		if ok then return mode end
		return nil
	end

	local function snapshot()
		local items, paths = {}, {}
		local objs = selectedObjs()
		for i = 1, #objs do
			local d = describe(objs[i])
			if d then
				items[#items + 1] = d
				if d.path then paths[#paths + 1] = d.path end
			end
		end

		local appNames = {}
		if Main.MenuApps then
			for name in pairs(Main.MenuApps) do appNames[#appNames + 1] = tostring(name) end
			table.sort(appNames)
		end

		return {
			version        = VERSION,
			dexVersion     = Main.Version,
			placeId        = game.PlaceId,
			jobId          = game.JobId,
			selection      = items,
			selectionPaths = paths,
			selectionCount = #items,
			apps           = appNames,
			pendingCount   = #Pending.items,
			uptime         = math.floor(tick() - startedAt),
			pushEnabled    = Bridge.PushEnabled and true or false,
			decompileModes = (env and env.decompileModes) or {},
			decompileMode  = currentDecompileMode(),
			executor       = Main.Executor,
			elevated       = Main.Elevated and true or false,
		}
	end

	local function selectPaths(paths, additive)
		if type(paths) == "string" then paths = { paths } end
		if type(paths) ~= "table" then return false, "paths must be table or string" end

		local sel = Explorer and Explorer.Selection
		if not sel then return false, "DEX selection not ready" end

		local found, missing = {}, {}
		for i = 1, #paths do
			local p = paths[i]
			local obj = resolvePath(p)
			if obj then
				local nd = nodeFor(obj)
				if nd then found[#found + 1] = nd end
			else
				missing[#missing + 1] = tostring(p)
			end
		end

		if #found == 0 then
			local msg = "no object matched"
			if #missing > 0 then msg = msg .. " (missing: " .. table.concat(missing, ", ") .. ")" end
			return false, msg
		end

		if additive then
			sel:AddTable(found)
		else
			sel:SetTable(found)
		end

		if found[1] and Explorer.ViewNode then
			pcall(function() Explorer.ViewNode(found[1]) end)
		end

		return true, #found, missing
	end

	local function listTree(path, depth, limit)
		local root = resolvePath(path or "game")
		if not root then return nil, "root not found: " .. tostring(path) end

		depth = math.clamp(tonumber(depth) or 2, 1, 8)
		limit = math.clamp(tonumber(limit) or 300, 1, MAX_TREE)

		local count = 0
		local function walk(obj, d)
			if count >= limit then return nil end
			count = count + 1
			local entry = { name = obj.Name, class = obj.ClassName }
			local children = obj:GetChildren()
			if d < depth then
				local kids = {}
				for i = 1, #children do
					if count >= limit then break end
					local child = walk(children[i], d + 1)
					if child then kids[#kids + 1] = child end
				end
				if #kids > 0 then entry.children = kids end
			elseif #children > 0 then
				entry.childCount = #children
			end
			return entry
		end

		return walk(root, 1)
	end

	local function readProps(path)
		local obj = resolvePath(path)
		if not obj then return nil, "object not found: " .. tostring(path) end

		local out = { name = obj.Name, class = obj.ClassName, path = buildPath(obj) }

		local props = {}
		if API and API.GetMember then
			local ok, list = pcall(API.GetMember, obj.ClassName, "Properties")
			if ok and type(list) == "table" then
				local n = 0
				for _, m in ipairs(list) do
					if n >= 400 then break end
					local okv, v = pcall(function() return obj[m.Name] end)
					if okv then
						local okS, s = pcall(tostring, v)
						props[m.Name] = okS and s or "?"
						n = n + 1
					end
				end
			end
		end
		out.properties = props

		local attrs = {}
		local okA, names = pcall(function() return obj:GetAttributes() end)
		if okA and type(names) == "table" then
			for _, n in ipairs(names) do
				local okV, v = pcall(function() return obj:GetAttribute(n) end)
				if okV then attrs[n] = tostring(v) end
			end
		end
		out.attributes = attrs

		local tags = {}
		local okT, t = pcall(function()
			return service.CollectionService:GetTags(obj)
		end)
		if okT and type(t) == "table" then
			for _, tag in ipairs(t) do tags[#tags + 1] = tag end
		end
		out.tags = tags

		local okC, kids = pcall(function() return #obj:GetChildren() end)
		if okC then out.childCount = kids end

		return out
	end

	local function readSource(path, mode)
		local obj = resolvePath(path)
		if not obj then return nil, "object not found: " .. tostring(path) end
		if not obj:IsA("LuaSourceContainer") then
			return nil, "not a script (class=" .. obj.ClassName .. ")"
		end

		if env and env.isViableDecompileScript then
			local okV, viable = pcall(env.isViableDecompileScript, obj)
			if okV and not viable then
				return nil, "not decompilable (server-side RunContext or unsupported class)"
			end
		end

		local wantMode = mode or currentDecompileMode()

		if env and env.decompileWith then
			local ok, src = pcall(env.decompileWith, wantMode, obj)
			if ok and type(src) == "string" and #src > 0 then
				return {
					path   = buildPath(obj),
					class  = obj.ClassName,
					mode   = wantMode or "default",
					source = src,
					length = #src,
				}
			end
			return nil, "decompile failed: " .. tostring(src)
		end

		if env and type(env.decompile) == "function" then
			local ok, src = pcall(env.decompile, obj)
			if ok and type(src) == "string" and #src > 0 then
				return { path = buildPath(obj), class = obj.ClassName, mode = "executor", source = src, length = #src }
			end
		end

		local ok2, src2 = pcall(function() return obj.Source end)
		if ok2 and type(src2) == "string" and #src2 > 0 then
			return { path = buildPath(obj), class = obj.ClassName, mode = "source", source = src2, length = #src2 }
		end

		return nil, "decompile unavailable on this executor"
	end

	local function coerce(value, current)
		if type(value) ~= "string" then return value, nil end

		local expr = value:match("^lua:(.+)$")
		if expr then
			local fn, lerr = loadstring("return " .. expr)
			if not fn then return nil, "loadstring failed: " .. tostring(lerr) end
			local ok, v = pcall(fn)
			if ok then return v, nil end
			return nil, "eval failed: " .. tostring(v)
		end

		local t = type(current)

		if t == "number" then
			local n = tonumber(value)
			if n then return n, nil end
			return nil, "expected number, got '" .. value .. "'"

		elseif t == "boolean" then
			local lv = value:lower()
			if lv == "true" then return true, nil end
			if lv == "false" then return false, nil end
			return nil, "expected boolean, got '" .. value .. "'"

		elseif t == "EnumItem" then
			local enumName, itemName = tostring(value):match("^(%w+)%.(.+)$")
			if enumName and Enum[enumName] and Enum[enumName][itemName] then
				return Enum[enumName][itemName], nil
			end
			return value, nil

		elseif t == "Vector3" then
			local x, y, z = tostring(value):match("([%d%.%-]+)%s*,%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)")
			if x then return Vector3.new(tonumber(x), tonumber(y), tonumber(z)), nil end
			return value, nil

		elseif t == "Color3" then
			local r, g, b = tostring(value):match("([%d%.]+)%s*,%s*([%d%.]+)%s*,%s*([%d%.]+)")
			if r then return Color3.new(tonumber(r), tonumber(g), tonumber(b)), nil end
			return value, nil
		end

		return value, nil
	end

	local function refreshDex()
		if Properties then
			if Properties.ShowExplorerProps then pcall(Properties.ShowExplorerProps) end
			if Properties.Refresh then pcall(Properties.Refresh) end
		end
		if Explorer and Explorer.Refresh then pcall(Explorer.Refresh) end
	end

	local function setProp(path, propName, value)
		local obj = resolvePath(path)
		if not obj then return false, "object not found: " .. tostring(path) end
		if type(propName) ~= "string" then return false, "propName required" end

		local okCur, current = pcall(function() return obj[propName] end)

		if not okCur then
			local okA, okS, err = pcall(function() return obj:SetAttribute(propName, value) end)
			if okA and okS then
				refreshDex()
				return true, "attribute set"
			end
			local msg = "property not readable: " .. propName
			if err then msg = msg .. " / " .. tostring(err) end
			return false, msg
		end

		local newVal, cerr = coerce(value, current)
		if cerr then return false, cerr end

		local ok, err = pcall(function() obj[propName] = newVal end)
		if not ok then
			local okA, okS = pcall(function() return obj:SetAttribute(propName, value) end)
			if okA and okS then
				refreshDex()
				return true, "attribute set (property was read-only)"
			end
			return false, "set failed: " .. tostring(err)
		end

		refreshDex()
		return true, tostring(newVal)
	end

	local function setProps(path, tbl)
		if type(tbl) ~= "table" then return false, "props must be a table" end
		local results, okCount = {}, 0
		for k, v in pairs(tbl) do
			local ok, msg = setProp(path, k, v)
			results[k] = ok and ("ok: " .. tostring(msg)) or ("fail: " .. tostring(msg))
			if ok then okCount = okCount + 1 end
		end
		return true, okCount, results
	end

	local function safeEncode(v)
		local tv = type(v)
		if tv == "string" or tv == "number" or tv == "boolean" then return v end
		if v == nil then return "nil" end
		local ok, s = pcall(function() return service.HttpService:JSONEncode(v) end)
		if ok then return s end
		local ok2, s2 = pcall(tostring, v)
		return ok2 and s2 or "<unserialisable>"
	end

	local function runCode(code, wantReturn)
		local fn, lerr = loadstring(tostring(code))
		if not fn then return { ok = false, error = tostring(lerr) } end

		local pack = table.pack or function(...) return { n = select("#", ...), ... } end
		local res = pack(pcall(fn))

		if not res[1] then return { ok = false, error = tostring(res[2]) } end
		if not wantReturn or res.n <= 1 then return { ok = true, results = {} } end

		local out = {}
		for i = 2, res.n do out[#out + 1] = safeEncode(res[i]) end
		return { ok = true, results = out }
	end

	local function appControl(name, open)
		if not Main.MenuApps then return false, "menu not ready" end

		local ctrl = Main.MenuApps[name]
		if not ctrl and type(name) == "string" then
			local lower = name:lower()
			for k, v in pairs(Main.MenuApps) do
				if tostring(k):lower() == lower then ctrl = v break end
			end
			if not ctrl then
				for k, v in pairs(Main.MenuApps) do
					if tostring(k):lower():find(lower, 1, true) then ctrl = v break end
				end
			end
		end

		if not ctrl then
			local avail = {}
			for n in pairs(Main.MenuApps) do avail[#avail + 1] = tostring(n) end
			table.sort(avail)
			return false, "no app named '" .. tostring(name) .. "'; available: " .. table.concat(avail, ", ")
		end

		if open == false then
			pcall(function() ctrl.Disable() end)
		else
			pcall(function() ctrl.Enable() end)
		end
		return true
	end

	local function refreshAll()
		if Explorer then
			if Explorer.Update then pcall(function() Explorer.Update() end) end
			if Explorer.Refresh then pcall(function() Explorer.Refresh() end) end
		end
		if Properties then
			if Properties.ShowExplorerProps then pcall(Properties.ShowExplorerProps) end
			if Properties.Refresh then pcall(Properties.Refresh) end
		end
		return true
	end

	local function openScript(path, mode)
		local obj = resolvePath(path)
		if not obj then return false, "object not found: " .. tostring(path) end
		if not obj:IsA("LuaSourceContainer") then return false, "not a script" end
		if not (ScriptViewer and ScriptViewer.ViewScript) then return false, "ScriptViewer not ready" end

		local wantMode = mode or currentDecompileMode()

		local ok, err = pcall(function()
			task.spawn(function()
				ScriptViewer.ViewScript(obj, wantMode)
			end)
		end)

		local nd = nodeFor(obj)
		if nd and Explorer.ViewNode then
			pcall(function() Explorer.ViewNode(nd) end)
		end

		if not ok then return false, tostring(err) end
		return true, wantMode or "default"
	end

	local function pushPending(reason)
		local objs = selectedObjs()
		if #objs == 0 then return false, "nothing selected in DEX" end

		local paths, details = {}, {}
		for i = 1, #objs do
			local p = buildPath(objs[i])
			if p then paths[#paths + 1] = p end
			local d = describe(objs[i])
			if d then details[#details + 1] = d end
		end
		if #paths == 0 then return false, "selected objects have no resolvable path" end

		Pending.seq = Pending.seq + 1
		Pending.items[#Pending.items + 1] = {
			seq    = Pending.seq,
			time   = os.date("%H:%M:%S"),
			reason = reason or "manual",
			paths  = paths,
			detail = details,
		}
		while #Pending.items > MAX_PEND do table.remove(Pending.items, 1) end

		if env.setclipboard then
			pcall(env.setclipboard, table.concat(paths, "\n"))
		end
		print("[DPP->MCP] " .. #paths .. " object(s) queued (" .. tostring(reason or "manual") .. ")\n" .. table.concat(paths, "\n"))
		return true, #paths
	end

	local function takePending()
		local out, last = Pending.items, Pending.seq
		Pending.items = {}
		return { lastSeq = last, count = #out, events = out }
	end

	local function peekPending()
		return { lastSeq = Pending.seq, count = #Pending.items, events = Pending.items }
	end

	local pushFails = 0
	local pushDisabled = false

	local function bridgeBase()
		local raw = g.BridgeURL
		if type(raw) ~= "string" or raw == "" then return nil end
		raw = raw:gsub("^%s+", ""):gsub("%s+$", ""):gsub("/+$", "")
		raw = raw:gsub("^https://", "http://"):gsub("^wss?://", "http://")
		return raw
	end

	local function postEvent(payload)
		local base = bridgeBase()
		if not base then return false, "BridgeURL not set" end
		if pushDisabled then return false, "push disabled after 3 failures" end
		if not env.request then return false, "executor has no request()" end

		payload.clientId = payload.clientId or tostring(game.JobId)

		local ok, res = pcall(function()
			return env.request({
				Url     = base .. "/dex/event",
				Method  = "POST",
				Headers = { ["Content-Type"] = "application/json" },
				Body    = service.HttpService:JSONEncode(payload),
			})
		end)

		if ok and res and (res.StatusCode == 200 or res.StatusCode == 204) then
			pushFails = 0
			Bridge.PushEnabled = true
			return true
		end

		pushFails = pushFails + 1
		if pushFails >= 3 then
			pushDisabled = true
			Bridge.PushEnabled = false
			warn("[DPP-MCP] push disabled after 3 consecutive failures (last: " .. tostring(res and res.StatusCode or res) .. ")")
		end
		return false, tostring(res and res.StatusCode or res)
	end

	Bridge.Version     = VERSION
	Bridge.PushEnabled = false

	Bridge.Snapshot    = snapshot
	Bridge.Describe    = describe
	Bridge.Resolve     = resolvePath
	Bridge.BuildPath   = buildPath
	Bridge.Node        = nodeFor
	Bridge.Selection   = selectedObjs
	Bridge.Select      = selectPaths
	Bridge.Tree        = listTree
	Bridge.Props       = readProps
	Bridge.Source      = readSource
	Bridge.SetProp     = setProp
	Bridge.SetProps    = setProps
	Bridge.Run         = runCode
	Bridge.App         = appControl
	Bridge.OpenScript  = openScript
	Bridge.Refresh     = refreshAll
	Bridge.PushPending = pushPending
	Bridge.TakePending = takePending
	Bridge.PeekPending = peekPending
	Bridge.Push        = postEvent
	Bridge.Pending     = Pending

	Bridge.Main         = Main
	Bridge.Apps         = Apps
	Bridge.Lib          = Lib
	Bridge.API          = API
	Bridge.RMD          = RMD
	Bridge.env          = env
	Bridge.Explorer     = Explorer
	Bridge.Properties   = Properties
	Bridge.ScriptViewer = ScriptViewer
	Bridge.Notebook     = Notebook
	Bridge.settings     = Settings
	Bridge.service      = service
	Bridge.plr          = plr

	local sel = Explorer and Explorer.Selection
	if sel and sel.Changed then
		sel.Changed:Connect(function()
			if not bridgeBase() then return end
			local snap = snapshot()
			postEvent({
				type   = "selection",
				reason = "dex-selection",
				time   = os.date("%H:%M:%S"),
				paths  = snap.selectionPaths,
				data   = snap,
			})
		end)
	end

	g.DPP     = Bridge
	g.DEX     = Bridge
	g.DEX_MCP = Bridge

	g.DEX_QUEUE = {
		Take     = function() return takePending() end,
		Peek     = function() return peekPending() end,
		Send     = function(reason) return pushPending(reason) end,
		Selected = function()
			local snap = snapshot()
			return snap.selectionPaths
		end,
		Count    = function() return #Pending.items end,
	}

	print("[DPP-MCP] injected | " .. VERSION .. " | DEX " .. tostring(Main.Version))
	print("[DPP-MCP] read : getgenv().DEX.Snapshot()")
	print("[DPP-MCP] write: getgenv().DEX.Select({'game.Workspace.X'})")
	print("[DPP-MCP] queue: getgenv().DEX_QUEUE.Take()")
	if bridgeBase() then
		print("[DPP-MCP] push -> " .. bridgeBase() .. "/dex/event")
	else
		print("[DPP-MCP] no getgenv().BridgeURL -> pull-only mode")
	end

	return Bridge
end

-- TODO: Remove when open source
if gethsfuncs then
	_G.moduleData = {InitDeps = initDeps, InitAfterMain = initAfterMain, Main = main}
else
	return {InitDeps = initDeps, InitAfterMain = initAfterMain, Main = main}
end

]==]

local inject = "\n\nEmbeddedModules[\"DexMCP\"] = function()\n" .. MODULE_SRC .. "\nend\n"

-- 找到 EmbeddedModules 定义结束的位置（在 Main = (function() 之前）
local mainPos = src:find("Main = (function()", 1, true)
if not mainPos then
	error("[DPP-MCP-B] 找不到 Main 定义，DEX 结构已变")
end

-- 在 main.lua 之前注入模块（EmbeddedModules 表定义之后）
local srcWithModule = src:sub(1, mainPos - 1) .. inject .. src:sub(mainPos)

-- ------------------------------------------------------------
-- 注入点 2：把 "DexMCP" 加入 Main.ModuleList
-- ------------------------------------------------------------
local old = 'Main.ModuleList = {"Explorer","Properties","ScriptViewer","Console","SaveInstance","ModelViewer","SettingsWindow","FileManager","GameAssets","CobaltRuntime","SpyLocalization","Spy"}'
local new = 'Main.ModuleList = {"Explorer","Properties","ScriptViewer","Console","SaveInstance","ModelViewer","SettingsWindow","FileManager","GameAssets","CobaltRuntime","SpyLocalization","Spy","DexMCP"}'

local patched = srcWithModule
if srcWithModule:find(old, 1, true) then
	patched = srcWithModule:gsub(old, new, 1)
	print("[DPP-MCP-B] ModuleList 已注入 DexMCP")
else
	-- 官方源可能模块顺序/写法不同，尝试更宽松的匹配
	local m = patched:find('"Spy"}', 1, true)
	if m then
		patched = patched:sub(1, m + 4) .. ',"DexMCP"}' .. patched:sub(m + 6)
		print("[DPP-MCP-B] ModuleList 已注入（宽松匹配）")
	else
		error("[DPP-MCP-B] 无法定位 ModuleList，官方 DEX 结构已变，请反馈")
	end
end

print("[DPP-MCP-B] 拼接完成: " .. #patched .. " 字符（+" .. (#patched - #src) .. "）")

-- 调试：可选落盘
if g.DEX_MCP_DEBUG and g.writefile then
	pcall(g.writefile, "dexpp_mcp_patched.lua", patched)
end

-- ------------------------------------------------------------
-- 执行
-- ------------------------------------------------------------
local fn, lerr = loadstring(patched)
if not fn then
	error("[DPP-MCP-B] loadstring 失败: " .. tostring(lerr))
end

local okRun, rerr = pcall(fn)
if not okRun then
	error("[DPP-MCP-B] 执行失败: " .. tostring(rerr))
end

-- ------------------------------------------------------------
-- 校验
-- ------------------------------------------------------------
if g.DEX and g.DEX.Version then
	print("[DPP-MCP-B] 就绪: " .. tostring(g.DEX.Version))
	print("[DPP-MCP-B] 试试: getgenv().DEX.Snapshot()")
else
	warn("[DPP-MCP-B] 执行完毕但 getgenv().DEX 未挂载，DEX 可能中途出错")
end

end
