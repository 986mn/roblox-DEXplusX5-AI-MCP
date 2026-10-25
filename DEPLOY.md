# 部署指南

从零到跑通的完整步骤。三种环境都覆盖：Codespaces、本机、局域网。

---

## 架构

```
AI 客户端 (Claude Desktop / Cursor / Claude Code)
        |  MCP 协议 (stdio)
        v
+-------------------------------------+
|  Node.js 服务端   :16384            |   <- Codespaces / 你的电脑
|  /dex/poll    <- Lua 拉任务          |
|  /dex/result  -> Lua 回结果          |
|  /dex/event   <- Lua 推选中           |
+-------------------------------------+
        |  HTTP 轮询 (150ms, JSON)
        v
+-------------------------------------+
|  Roblox 执行器 (Luau)                |
|  script.lua = DEX++ + DexMCP        |
|  lua/dex_mcp_poller.lua             |
|      -> getgenv().DEX               |
+-------------------------------------+
```

**两条通道分工明确：**

| 通道 | 语言 | 跑在哪 | 干什么 |
|---|---|---|---|
| MCP (stdio) | TypeScript | 服务端进程 | 接 AI 客户端 |
| HTTP (轮询) | TypeScript <-> Luau | 服务端 <-> Roblox | 传任务和结果 |

Luau 只能在 Roblox 里跑，没有 HTTP 服务器，所以服务端必须是 Node。

---

## 方式一：GitHub Codespaces（免安装）

### 1. 创建 Codespace

打开仓库 -> Code -> Codespaces -> Create codespace on main。

容器会自动完成：

| 阶段 | 动作 |
|---|---|
| postCreate | npm install -> tsc -> 校验 4 个产物 |
| postStart | 杀残留 -> 起服务 -> 等就绪 -> 设端口公开 -> 起保活 |

耗时 1-3 分钟。完成后终端打印：

```
 Dashboard : https://xxxxx-16384.app.github.dev/
 Status    : https://xxxxx-16384.app.github.dev/api/status

 Paste into your executor BEFORE loading DEX++:

   getgenv().BridgeURL = "https://xxxxx-16384.app.github.dev"
```

### 2. 连接 Roblox

```lua
-- 必须在加载 DEX 之前设
getgenv().BridgeURL = "https://xxxxx-16384.app.github.dev"

loadstring(game:HttpGet(
  "https://raw.githubusercontent.com/986mn/roblox-DEXplusX5-AI-MCP/main/script.lua"
))()

-- 然后加载轮询器
loadstring(game:HttpGet(
  "https://raw.githubusercontent.com/986mn/roblox-DEXplusX5-AI-MCP/main/lua/dex_mcp_poller.lua"
))()
```

### 3. 确认连通

浏览器打开 `https://xxxxx-16384.app.github.dev/api/status`：

```json
{ "ok": true, "clientOnline": true, "msSinceLastPoll": 87 }
```

`clientOnline: true` 就通了。

### 两个必须做对的地方

**1. 端口必须是 public**

Roblox 执行器没有 GitHub 登录态，私密端口只会拿到登录页。`devcontainer.json` 已声明 visibility public，`start.sh` 还会用 `gh` 再设一次。若失败，手动在 PORTS 面板右键 16384 -> Port Visibility -> Public。

**2. https 前缀不能少**

Codespaces 只提供 HTTPS。如果执行器不支持 TLS，轮询器会自动降级试 http，但那样一定失败——此时只能走方式三（局域网）。

### 空闲唤醒后服务没了？

Codespaces 闲置会停容器，而 postStart 在唤醒时不一定重跑（GitHub 已知行为）。手动救：

```bash
bash .devcontainer/ensure-running.sh
```

只看状态：

```bash
bash .devcontainer/ensure-running.sh --status
```

### 12 小时硬上限

免费 Codespaces 最长 12 小时，无法绕过。keepalive.sh 只能防空闲暂停。

---

## 方式二：本机跑服务端

```bash
git clone https://github.com/986mn/roblox-DEXplusX5-AI-MCP.git
cd roblox-DEXplusX5-AI-MCP/server
npm install
npx tsc
node dist/index.js < /dev/zero
```

Windows：

```powershell
cd server
npm install
npx tsc
node dist/index.js
```

大于符号 /dev/zero 很重要。MCP 是 stdio 协议，stdin 一关进程就退出。PowerShell 下若服务立刻退出，改用能保持窗口的终端。

执行器侧（同一台机器）：

```lua
getgenv().BridgeURL = "localhost:16384"
```

---

## 方式三：局域网（手机玩 Roblox 推荐）

服务端跑在电脑，手机 Roblox 连过来。

### 1. 电脑起服务

同方式二。

### 2. 查电脑局域网 IP

```bash
ip addr | grep 'inet 192'
```

Windows：

```powershell
ipconfig | findstr IPv4
```

假设 192.168.1.100。

### 3. 放行防火墙

```powershell
# Windows 管理员 PowerShell
New-NetFirewallRule -DisplayName "DEX MCP" -Direction Inbound -LocalPort 16384 -Protocol TCP -Action Allow
```

```bash
# Linux
sudo ufw allow 16384/tcp
```

### 4. 手机执行器

```lua
getgenv().BridgeURL = "192.168.1.100:16384"

loadstring(game:HttpGet(
  "https://raw.githubusercontent.com/986mn/roblox-DEXplusX5-AI-MCP/main/script.lua"
))()

loadstring(game:HttpGet(
  "https://raw.githubusercontent.com/986mn/roblox-DEXplusX5-AI-MCP/main/lua/dex_mcp_poller.lua"
))()
```

手机和电脑必须在同一个 Wi-Fi。

---

## 接入 AI 客户端

### Claude Desktop / Cursor / Windsurf

```json
{
  "mcpServers": {
    "dexplusx5": {
      "command": "node",
      "args": ["/绝对路径/roblox-DEXplusX5-AI-MCP/server/dist/index.js"]
    }
  }
}
```

| 客户端 | 路径 |
|---|---|
| Claude Desktop (macOS) | ~/Library/Application Support/Claude/claude_desktop_config.json |
| Claude Desktop (Windows) | %APPDATA%\Claude\claude_desktop_config.json |
| Cursor | ~/.cursor/mcp.json |
| Windsurf | ~/.codeium/windsurf/mcp_config.json |
| VS Code | ~/.vscode/mcp.json |

改完重启客户端。

### Claude Code

```bash
claude mcp add dexplusx5 -- node /绝对路径/server/dist/index.js
```

---

## 验证清单

1. `curl localhost:16384/api/status` 返回 JSON -> 服务端活着
2. 执行器打印 `[DPP-MCP] injected` -> DEX 模块加载了
3. 执行器打印 `[DPP-POLL] connected via ...` -> 轮询器连上了
4. `/api/status` 里 `clientOnline: true` -> 双向通道通
5. AI 客户端能看到 11 个 dex-* 工具 -> MCP 侧通

哪一步断了看对应日志：

```lua
-- 执行器里
print(getgenv().DEX_POLLER.Status())
print(table.concat(getgenv().DEX_POLLER.Log(), "\n"))
```

```bash
# 服务端
tail -f server/.server.log
curl localhost:16384/api/log
```

---

## 故障排查

| 现象 | 原因 | 处理 |
|---|---|---|
| clientOnline false | 轮询器没跑 | 执行器里加载 dex_mcp_poller.lua |
| no HTTP request function | 执行器无 request | 换执行器，或告知名字我加兼容 |
| probe failed https | 执行器不支持 TLS | 改用局域网 192.168.x.x:16384 |
| 工具调用超时 30s | Lua 侧没拉到任务 | 查 DEX_POLLER.Status().polls 是否在涨 |
| DEX method not available | 模块版本旧 | 重新加载 script.lua |
| Codespaces 唤醒后 502 | postStart 没重跑 | bash .devcontainer/ensure-running.sh |
| 服务刚起就退出 | stdin 被关 | 启动加小于号 /dev/zero |

---

## 安全

- 16384 端口无鉴权，任何人都能对你的 Roblox 会话执行任意 Luau
- 绝不要暴露到公网
- Codespaces 端口设 public 意味着任何拿到 URL 的人都能用，用完就停容器
- 跨机请走 SSH 隧道：`ssh -L 16384:localhost:16384 user@目标机器`
