--[[
================================================================
  DexMCP Poller — executor-side bridge for DEX PlusPlusPlusPlus
================================================================
  Requires: the DexMCP module already loaded (getgenv().DEX exists),
  i.e. run this AFTER DEX++ itself is running.

  What it does
    Every POLL_INTERVAL ms it asks the MCP server for a job:
        GET  <base>/dex/poll
    Executes it against getgenv().DEX, then reports back:
        POST <base>/dex/result
    Selection changes are pushed as:
        POST <base>/dex/event

  Config (set BEFORE loading)
    getgenv().BridgeURL     = "https://xxxx-16384.app.github.dev"
    getgenv().DEX_MCP_DEBUG = true

  Public handles
    getgenv().DEX_POLLER    = { Stop(), Start(), Status(), Ping() }
    getgenv().DEX_POLLER_LOG = { ... }   -- last 100 log lines
]]

--[[ DEX_MCP_POLLER_BEGIN ]]
do

local g = getgenv and getgenv() or _G

if g.DEX_POLLER and g.DEX_POLLER.__version then
	print("[DPP-POLL] already running (" .. tostring(g.DEX_POLLER.__version) .. ")")
	return
end

local D = g.DEX
if not D or not D.Version then
	error("[DPP-POLL] getgenv().DEX not found. Load DEX++ with the DexMCP module first.")
end

local VERSION      = "poller-1.0"
local POLL_INTERVAL = tonumber(g.DEX_MCP_POLL_MS) or 150
local EVENT_FLUSH   = 800
local DEBUG        = g.DEX_MCP_DEBUG == true
local MAX_LOG      = 100

local HttpService = game:GetService("HttpService")

-- ------------------------------------------------------------
--  Log ring buffer (visible from the server dashboard)
-- ------------------------------------------------------------
local Log = {}
local function log(fmt, ...)
	local msg = select("#", ...) > 0 and string.format(fmt, ...) or tostring(fmt)
	local line = os.date("%H:%M:%S") .. " " .. msg
	Log[#Log + 1] = line
	while #Log > MAX_LOG do table.remove(Log, 1) end
	if DEBUG then print("[DPP-POLL] " .. msg) end
end

-- ------------------------------------------------------------
--  HTTP: find a request function across executors
-- ------------------------------------------------------------
local function resolveRequest()
	-- prefer the copy DEX++ already normalised, then fall back to raw globals
	if g.DEX and g.DEX.env and type(g.DEX.env.request) == "function" then
		return g.DEX.env.request, "env.request"
	end
	local ok, r = pcall(function() return syn and syn.request end)
	if ok and type(r) == "function" then return r, "syn.request" end
	if type(rawget(g, "http_request")) == "function" then return rawget(g, "http_request"), "http_request" end
	if type(rawget(g, "request")) == "function" then return rawget(g, "request"), "request" end
	local ok2, r2 = pcall(function() return http and http.request end)
	if ok2 and type(r2) == "function" then return r2, "http.request" end
	local ok3, r3 = pcall(function() return fluxus and fluxus.request end)
	if ok3 and type(r3) == "function" then return r3, "fluxus.request" end
	return nil, nil
end

local request, requestSource = resolveRequest()
if not request then
	error("[DPP-POLL] no HTTP request function available on this executor")
end

-- ------------------------------------------------------------
--  Base URL with https -> http downgrade
-- ------------------------------------------------------------
local base = nil
local baseScheme = nil

local function normaliseBase(raw)
	if type(raw) ~= "string" or raw == "" then return nil end
	raw = raw:gsub("^%s+", ""):gsub("%s+$", ""):gsub("/+$", "")
	if raw:sub(1, 2) == "//" then raw = "http:" .. raw end
	if not raw:find("^%a[%w+.-]*://") then raw = "http://" .. raw end
	return raw
end

local function setBase(url)
	base = url:gsub("/+$", "")
	baseScheme = base:match("^(%a[%w+.-]*)://") or "http"
end

setBase(normaliseBase(g.BridgeURL) or "http://localhost:16384")

-- ------------------------------------------------------------
--  Low level HTTP helpers
-- ------------------------------------------------------------
local function httpJson(method, path, payload, timeout)
	local url = base .. path
	local body = nil
	if payload ~= nil then
		local ok, enc = pcall(function() return HttpService:JSONEncode(payload) end)
		if not ok then return false, "json encode failed" end
		body = enc
	end

	local ok, res = pcall(request, {
		Url     = url,
		Method  = method,
		Headers = { ["Content-Type"] = "application/json" },
		Body    = body,
	})

	if not ok then return false, tostring(res) end
	if type(res) ~= "table" then return false, "bad response type" end

	local code = res.StatusCode or res.Status or res.status_code or 0
	local text = res.Body or res.body or ""
	return true, code, text
end

local function decode(text)
	if type(text) ~= "string" or text == "" then return nil end
	local ok, v = pcall(function() return HttpService:JSONDecode(text) end)
	if ok then return v end
	return nil
end

-- ------------------------------------------------------------
--  Protocol probe: find an endpoint that actually answers
-- ------------------------------------------------------------
local function probeOnce(url)
	local ok, res = pcall(request, {
		Url     = url .. "/api/status",
		Method  = "GET",
		Headers = { ["Content-Type"] = "application/json" },
	})
	if not ok or type(res) ~= "table" then return false, tostring(res) end
	local code = res.StatusCode or res.Status or 0
	if code == 200 then
		return true, decode(res.Body or res.body)
	end
	return false, "HTTP " .. tostring(code)
end

local function probeAndSelect()
	local candidates = {}

	local configured = normaliseBase(g.BridgeURL)
	if configured then
		table.insert(candidates, configured)
		-- if the user typed https:// but the executor lacks TLS, try http:// as well
		if configured:match("^https://") then
			table.insert(candidates, configured:gsub("^https://", "http://", 1))
		end
	end

	for _, url in ipairs(candidates) do
		local ok, info = probeOnce(url)
		if ok then
			setBase(url)
			log("connected via %s (%s)", base, baseScheme)
			if info and info.ok then
				log("server: %s", tostring(info.name or "?"))
			end
			return true
		else
			log("probe failed %s -> %s", url, tostring(info))
		end
	end

	return false
end

-- ------------------------------------------------------------
--  Op dispatch: maps a job op to a DEX method
-- ------------------------------------------------------------
local ARG_ORDER = {
	snapshot   = {},
	describe   = { "path" },
	resolve    = { "path" },
	buildpath  = { "path" },
	select     = { "paths", "additive" },
	tree       = { "path", "depth", "limit" },
	props      = { "path" },
	source     = { "path", "mode" },
	setprop    = { "path", "prop", "value" },
	setprops   = { "path", "props" },
	run        = { "code", "wantReturn" },
	app        = { "name", "open" },
	openscript = { "path", "mode" },
	refresh    = {},
	pending    = {},
	takepending= {},
}

local METHOD = {
	snapshot   = "Snapshot",
	describe   = "Describe",
	resolve    = "Resolve",
	buildpath  = "BuildPath",
	select     = "Select",
	tree       = "Tree",
	props      = "Props",
	source     = "Source",
	setprop    = "SetProp",
	setprops   = "SetProps",
	run        = "Run",
	app        = "App",
	openscript = "OpenScript",
	refresh    = "Refresh",
	pending    = "PeekPending",
	takepending= "TakePending",
}

local function runJob(job)
	local op = job.op
	if type(op) ~= "string" then return { ok = false, error = "missing op" } end

	local fnName = METHOD[op]
	if not fnName then return { ok = false, error = "unknown op: " .. tostring(op) } end

	local fn = D[fnName]
	if type(fn) ~= "function" then
		return { ok = false, error = "DEX method not available: " .. fnName }
	end

	local args = job.args or {}
	local order = ARG_ORDER[op] or {}
	local call = {}
	for i = 1, #order do
		call[i] = args[order[i]]
	end

	local pack = table.pack or function(...) return { n = select("#", ...), ... } end
	local res = pack(pcall(fn, table.unpack(call, 1, #order)))

	if not res[1] then
		return { ok = false, error = tostring(res[2]) }
	end

	-- DEX methods return (ok, value) or (value) or (nil, err)
	if res.n >= 2 and res[2] == false then
		return { ok = false, error = tostring(res[3]) }
	end

	local payload
	if res.n >= 3 then
		-- (true, a, b)
		payload = { res[2], res[3] }
	elseif res.n == 2 then
		payload = res[2]
	else
		payload = nil
	end

	return { ok = true, data = payload }
end

-- ------------------------------------------------------------
--  Main loop
-- ------------------------------------------------------------
local running = false
local loopThread = nil
local stats = {
	polls = 0, jobs = 0, errors = 0,
	lastPoll = nil, lastJob = nil, connectedAt = nil,
}
local consecutiveFailures = 0

local function pollOnce()
	local ok, code, text = httpJson("GET", "/dex/poll", nil)
	stats.polls = stats.polls + 1
	stats.lastPoll = os.time()

	if not ok then
		consecutiveFailures = consecutiveFailures + 1
		if consecutiveFailures <= 3 or consecutiveFailures % 20 == 0 then
			log("poll transport error (%d): %s", consecutiveFailures, tostring(code))
		end
		return
	end

	if code == 204 or code == 404 then
		consecutiveFailures = 0
		return
	end

	if code ~= 200 then
		consecutiveFailures = consecutiveFailures + 1
		if consecutiveFailures <= 3 then
			log("poll unexpected HTTP %s: %s", tostring(code), tostring(text):sub(1, 120))
		end
		return
	end

	consecutiveFailures = 0
	local job = decode(text)
	if not job or not job.id then return end

	stats.jobs = stats.jobs + 1
	stats.lastJob = os.date("%H:%M:%S") .. " " .. tostring(job.op)

	local result
	local okRun, err = pcall(function() result = runJob(job) end)
	if not okRun then
		result = { ok = false, error = tostring(err) }
		stats.errors = stats.errors + 1
	end

	if not result.ok then
		stats.errors = stats.errors + 1
		log("job %s (%s) failed: %s", tostring(job.id), tostring(job.op), tostring(result.error))
	else
		log("job %s (%s) ok", tostring(job.id), tostring(job.op))
	end

	result.id = job.id
	local okPost, codeP, textP = httpJson("POST", "/dex/result", result)
	if not okPost or (codeP ~= 200 and codeP ~= 204) then
		log("result post failed: %s %s", tostring(codeP), tostring(textP):sub(1, 120))
	end
end

local function loop()
	while running do
		local ok, err = pcall(pollOnce)
		if not ok then
			log("loop error: %s", tostring(err))
		end
		task.wait(POLL_INTERVAL / 1000)
	end
end

-- ------------------------------------------------------------
--  Selection push (debounced)
-- ------------------------------------------------------------
local lastPush = 0
local selCon

local function pushSelection()
	local now = tick()
	if now - lastPush < (EVENT_FLUSH / 1000) then return end
	lastPush = now

	local ok, snap = pcall(D.Snapshot)
	if not ok or type(snap) ~= "table" then return end

	httpJson("POST", "/dex/event", {
		type     = "selection",
		reason   = "dex-selection",
		time     = os.date("%H:%M:%S"),
		paths    = snap.selectionPaths or {},
		data     = snap,
		clientId = tostring(game.JobId),
	})
end

local function hookSelection()
	local E = D.Explorer
	local sel = E and E.Selection
	if not sel or not sel.Changed then return false end
	if selCon then selCon:Disconnect() selCon = nil end
	selCon = sel.Changed:Connect(function()
		task.spawn(pushSelection)
	end)
	return true
end

-- ------------------------------------------------------------
--  Public API
-- ------------------------------------------------------------
local API = {}
API.__version = VERSION
API.Version   = VERSION

function API.Status()
	return {
		version     = VERSION,
		running     = running,
		base        = base,
		scheme      = baseScheme,
		request     = requestSource,
		interval    = POLL_INTERVAL,
		polls       = stats.polls,
		jobs        = stats.jobs,
		errors      = stats.errors,
		lastPoll    = stats.lastPoll,
		lastJob     = stats.lastJob,
		connectedAt = stats.connectedAt,
		failures    = consecutiveFailures,
	}
end

function API.Log()
	local out = {}
	for i = 1, #Log do out[i] = Log[i] end
	return out
end

function API.Ping()
	return probeAndSelect()
end

function API.Stop()
	running = false
	if selCon then selCon:Disconnect() selCon = nil end
	log("stopped")
end

function API.Start()
	if running then return end
	running = true
	log("starting | base=%s request=%s interval=%dms", base, tostring(requestSource), POLL_INTERVAL)

	if not probeAndSelect() then
		log("probe failed, entering retry loop anyway (swap BridgeURL + call DEX_POLLER.Ping())")
	else
		stats.connectedAt = os.date("%H:%M:%S")
	end

	hookSelection()

	local task_ = task or { spawn = function(f) coroutine.wrap(f)() end, wait = wait }
	task_.spawn(loop)
end

API.Base = function(url)
	if url then
		setBase(normaliseBase(url) or base)
		log("base changed to %s", base)
	end
	return base
end

-- ------------------------------------------------------------
--  Mount + auto start
-- ------------------------------------------------------------
g.DEX_POLLER     = API
g.DEX_POLLER_LOG = Log

print("[DPP-POLL] " .. VERSION .. " | request=" .. tostring(requestSource) .. " | base=" .. base)

API.Start()

print("[DPP-POLL] running — status: getgenv().DEX_POLLER.Status()")

end
--[[ DEX_MCP_POLLER_END ]]
