# roblox-DEXplusX5-AI-MCP

<p align="center">
  <img src="banner.svg" alt="roblox-DEXplusX5-AI-MCP" width="100%"/>
</p>

<p align="center">
  <strong>DEX PlusPlusPlusPlus ↔ AI/MCP 双向桥接</strong><br/>
  <sub>让 Claude / Cursor 等 AI 客户端直接读写你的 DEX 调试会话</sub>
</p>

<p align="center">
  <img src="demo.gif" alt="演示" width="480"/>
</p>

> **本 fork 在上游 [DEX++ (snmwdd/DexPlusPlusPlusPlus)](https://github.com/snmwdd/DexPlusPlusPlusPlus) 基础上新增了 AI/MCP 桥接能力。**

[English](./README_EN.md) · **中文**

---

## 目录

- [这是什么](#这是什么)
- [快速开始](#快速开始)
- [五种形态](#五种形态)
- [部署](#部署)
- [DEX API](#dex-api)
- [故障排查](#故障排查)
- [安全](#安全)
- [上游原文](#上游原文)

---

## 这是什么

通过一个 Node.js MCP 服务端 + 执行器侧 Lua 轮询器，让 Claude / Cursor 等 AI 客户端直接读写你的 DEX 会话：查看选中对象、读属性、反编译脚本、改属性、执行 Luau。

```
AI 客户端 (Claude / Cursor)
    |  MCP 协议 (stdio)
    v
Node.js 服务端  :16384        <- 本机 / Codespaces
    |  HTTP 轮询 (150ms JSON)
    v
Roblox 执行器 (Luau)
    script.lua = DEX++ + DexMCP
    dex_mcp_poller.lua -> getgenv().DEX
```

---

## 快速开始

### 1. 起服务端

```bash
git clone https://github.com/986mn/roblox-DEXplusX5-AI-MCP.git
cd roblox-DEXplusX5-AI-MCP
bash oneshot.sh
```

一条命令：装依赖 → 编译 → 起服务 → 打印执行器加载代码。

### 2. 执行器加载

```lua
getgenv().BridgeURL = "localhost:16384"  -- 或局域网 IP / Codespaces https 地址

loadstring(game:HttpGet(
  "https://raw.githubusercontent.com/986mn/roblox-DEXplusX5-AI-MCP/main/script.lua"
))()

loadstring(game:HttpGet(
  "https://raw.githubusercontent.com/986mn/roblox-DEXplusX5-AI-MCP/main/dex_mcp_poller.lua"
))()
```

看到 `[DPP-MCP] injected` 和 `[DPP-POLL] connected` 就通了。

---

## 五种形态

| 版本 | 内容 | 适用 |
|---|---|---|
| **A** | 完整读写 API | 只要 API |
| **C** | 悬浮按钮 + 队列 | 只要 UI |
| **AC** | A + C 合并 | 完整功能，推荐 |
| **B** | 运行时包装器（含 A） | 用官方 DEX |
| **BC** | B + C | 官方 DEX + 按钮 |

```lua
-- AC 合并单文件（API + 按钮）
loadstring(game:HttpGet(".../dex_mcp_AC.lua"))()

-- BC（官方 DEX + 按钮）
getgenv().DEX_URL = "https://raw.githubusercontent.com/snmwdd/DexPlusPlusPlusPlus/refs/heads/main/script.lua"
loadstring(game:HttpGet(".../dex_mcp_BC.lua"))()
```

---

## 部署

### 方式一：GitHub Codespaces（免安装）

打开仓库 → Code → Codespaces → Create codespace on main。容器自动完成 npm install → tsc → 起服务 → 设端口公开 → 起保活。

完成后终端打印地址，复制到执行器：

```lua
getgenv().BridgeURL = "https://xxxxx-16384.app.github.dev"
```

**两个必须做对的地方：**

1. **端口必须 public**：Roblox 执行器没有 GitHub 登录态，私密端口只会拿到登录页。`devcontainer.json` 已声明 public，若失败手动在 PORTS 面板设 Public。
2. **https 前缀不能少**：Codespaces 只提供 HTTPS。若执行器不支持 TLS，只能改用局域网。

**空闲唤醒后服务没了？** Codespaces 闲置会停容器，`postStart` 唤醒时不重跑。手动救：

```bash
bash .devcontainer/ensure-running.sh
```

**12 小时硬上限**：免费 Codespaces 最长 12 小时，无法绕过。

### 方式二：本机

```bash
cd server
npm install
npx tsc
node dist/index.js < /dev/zero
```

执行器：`getgenv().BridgeURL = "localhost:16384"`

### 方式三：局域网（手机玩 Roblox 推荐）

服务端跑电脑，手机连过来。查电脑 IP（`ip addr` / `ipconfig`），放行防火墙 16384 端口，手机执行器：

```lua
getgenv().BridgeURL = "192.168.1.100:16384"
```

### 接入 AI 客户端

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

| 客户端 | 配置文件 |
|---|---|
| Claude Desktop | `claude_desktop_config.json` |
| Cursor | `~/.cursor/mcp.json` |
| Windsurf | `~/.codeium/windsurf/mcp_config.json` |
| VS Code | `~/.vscode/mcp.json` |

---

## DEX API

给 [DEX++](https://github.com/snmwdd/DexPlusPlusPlusPlus) 接上 AI 通道。
AI 能看到你在 DEX 里选中的对象，也能反过来驱动 DEX 跳转、改属性、反编译、执行代码。

> 本 fork 在上游基础上**只新增一个模块** `src/modules/DexMCP.lua`，
> 并在 `Main.ModuleList` 末尾注册。上游代码未做任何修改。

---

## 快速使用

```lua
-- 在 Roblox 执行器里直接跑，DEX 与桥接一同加载
loadstring(game:HttpGet(
  "https://raw.githubusercontent.com/986mn/roblox-DEXplusX5-AI-MCP/main/script.lua"
))()
```

加载后控制台会打印：

```
[DPP-MCP] injected | mcp-dpp-1.0 | DEX v12.0
[DPP-MCP] read : getgenv().DEX.Snapshot()
[DPP-MCP] write: getgenv().DEX.Select({'game.Workspace.X'})
[DPP-MCP] queue: getgenv().DEX_QUEUE.Take()
[DPP-MCP] no getgenv().BridgeURL -> pull-only mode
```

---

## 配置（可选）

在 **加载 DEX 之前** 设置：

```lua
getgenv().BridgeURL     = "192.168.1.100:16384"  -- MCP 服务端地址
getgenv().DEX_MCP_DEBUG = true                   -- 调试日志
```

设了 `BridgeURL` 后，你在 DEX 里每次改选中都会自动 POST 到 `<BridgeURL>/dex/event`。
不设就是纯本地模式，AI 需要主动调工具来读。

> `BridgeURL` 会被强制降级成 `http://`，因为执行器的 `request()` 一般不支持 TLS。

---

## API

```lua
local D = getgenv().DEX

-- 读
D.Snapshot()                          -- 当前选中 + DEX 状态
D.Tree("game.Workspace", 3, 200)      -- 实例树（深度/上限）
D.Props("game.Workspace.NPC")         -- 属性 + Attributes + Tags
D.Source("game.ReplicatedStorage.X")  -- 反编译（默认当前模式）
D.Source(path, "AdvancedDecompiler")   -- 指定反编译后端
D.Resolve("game.Workspace.NPC")       -- 路径 -> Instance
D.BuildPath(obj)                      -- Instance -> 路径

-- 写
D.Select({"game.Workspace.NPC"})          -- 设选中（UI 跳过去）
D.Select({p1, p2}, true)                  -- 追加选中
D.SetProp(path, "Health", "0")            -- 自动类型转换
D.SetProp(path, "CFrame", "lua:CFrame.new(0,50,0)")
D.SetProps(path, {Health="0", Anchored="true"})
D.Run("return 1+1", true)                 -- 执行并带回返回值
D.App("Explorer", true)                   -- 开关面板
D.OpenScript(path, "Executor")            -- 在 Notepad 里打开
D.Refresh()                               -- 重建树和属性面板

-- 队列
getgenv().DEX_QUEUE.Take() / .Peek() / .Count() / .Selected() / .Send(reason)
```

### 六个反编译后端

`D.Source(path, mode)` 的 `mode` 可取：

| mode | 依赖 |
|---|---|
| `lua.expert/demo` | 内置，需 `getscriptbytecode` + `request` |
| `Luaunveil` | 内置，同上 |
| `Konstant` | 需 `getscriptbytecode` + `request` |
| `AdvancedDecompiler` | 需 `getscriptbytecode` |
| `Shiny` | 需本地 Shiny 服务 + `crypt` |
| `Executor` | 需执行器自带 `decompile` |

### 路径格式

```lua
game.Workspace.Map.NPC                      -- 普通
Workspace.Map.NPC                           -- 省略 game
game:GetService("ReplicatedStorage").Mods   -- 服务
game.Workspace:GetChildren()[3]             -- 重名索引
game.Workspace["奇怪 名字"]                  -- 特殊字符
```

`nil` 父对象的实例会输出 `getNil(...)` 片段，这类路径**不可回解析**，构造时已主动跳过。

---

## 实现说明

### 为什么是一个模块

DEX++ 的模块加载顺序：

```
Main.Init()
  → LoadModule("Localization") → LoadModule("Lib")
  → FetchAPI → FetchRMD
  → LoadModules()        -- Main.ModuleList 里的模块依次执行
  → Explorer.Init() ... Spy.Init()
  → CreateMainGui()
```

`initAfterMain` 阶段已经拿得到 `Explorer` / `Properties` / `ScriptViewer`，
所以桥接代码作为普通模块接入最干净：不碰上游代码，也不需要 `loadstring` 拼接。

### 面板同步怎么做的

`Explorer.Selection.Changed` 本来就挂着 `Properties.ShowExplorerProps`，
所以只要 `selection:SetTable(found)`，属性面板会自动重读。
额外再调 `Explorer.ViewNode(node)` 让树滚到目标位置。

### 写属性的降级链

```
读当前值 → 按类型 coerce（number/boolean/Enum/Vector3/Color3）
  → 赋值成功 → 刷新面板
  → 赋值失败（只读）→ 退化成 SetAttribute
  → 属性根本不存在 → 直接 SetAttribute
```

`lua:` 前缀可以塞任意 Luau 表达式：

```lua
D.SetProp(path, "CFrame", "lua:CFrame.new(0,50,0)")
D.SetProp(path, "Color", "lua:Color3.fromRGB(255,0,0)")
```

---

## 已知限制

| 限制 | 说明 |
|---|---|
| 仅限 Roblox 执行器 | DEX 用了 Luau 专有语法（`continue`、`..=`、反引号字符串） |
| nil 实例无法往返 | DEX 输出 `getNil(...)` 代码片段，不是可解析路径 |
| 反编译看执行器 | 缺 `decompile` / `getscriptbytecode` 时只能拿 `.Source`（通常空） |
| 推送强制 http | 执行器 `request()` 通常无 TLS |
| 3 次失败熔断 | 推送连续失败会关闭，`Snapshot().pushEnabled` 可查状态 |

---

## 验证记录

| 项 | 结果 |
|---|---|
| `DexMCP.lua` 语法（`luac -p`） | ✅ RC=0 |
| 模块契约 `{InitDeps, InitAfterMain, Main}` | ✅ |
| `Main.ModuleList` 注册 | ✅ |
| `build.py` 构建 | ✅ RC=0 |
| `out.lua` 含 DexMCP | ✅ 1,651,055 字节 |
| `script.lua` 含 DexMCP | ✅ 同上 |
| 上游代码改动 | ✅ 仅 `ModuleList` 一行 |

---

## 安全

- MCP 服务端端口默认无鉴权，**切勿暴露公网**
- 跨机用 VPN 或 SSH 隧道
- 仅用于自建测试环境；公开游戏使用可能违反 Roblox 服务条款

---

## 来源

- DEX++：[snmwdd/DexPlusPlusPlusPlus](https://github.com/snmwdd/DexPlusPlusPlusPlus)（作者 snmwdd / Gpt6.1）
- 桥接模块：本 fork 新增

---

## 故障排查

| 现象 | 原因 | 处理 |
|---|---|---|
| clientOnline false | 轮询器没跑 | 执行器里加载 dex_mcp_poller.lua |
| no HTTP request function | 执行器无 request | 换执行器，或告知名字加兼容 |
| probe failed https | 执行器不支持 TLS | 改用局域网 192.168.x.x:16384 |
| 工具调用超时 30s | Lua 侧没拉到任务 | 查 DEX_POLLER.Status().polls 是否在涨 |
| DEX method not available | 模块版本旧 | 重新加载 script.lua |
| Codespaces 唤醒后 502 | postStart 没重跑 | bash .devcontainer/ensure-running.sh |
| 服务刚起就退出 | stdin 被关 | 启动加 < /dev/zero |

## 安全

- **16384 端口无鉴权**，任何人都能对你的 Roblox 会话执行任意 Luau
- 绝不要暴露到公网
- Codespaces 端口设 public 意味着任何拿到 URL 的人都能用，用完就停容器
- 跨机请走 SSH 隧道：`ssh -L 16384:localhost:16384 user@目标机器`

---

## 上游原文

# Dex# v12.0 (DexPlusPlusPlusPlus)

![DevTool Dex#](https://img.shields.io/badge/DevTool-Dex++++-green)
![Roblox Luau](https://img.shields.io/badge/Roblox-Luau-blue)
![Lua Script](https://img.shields.io/badge/Lua-Script-black)

### Dex# 是 Dex 和 Dex++ 的扩展与定制版本

[![简体中文 Simplified Chinese](https://img.shields.io/badge/简体中文-Chinese-red?style=flat-square&labelColor=black)](https://github.com/snmwdd/DexPlusPlusPlusPlus/blob/main/README_CN.md)
[![English 英文](https://img.shields.io/badge/English-英文-blue?style=flat-square&labelColor=black)](https://github.com/snmwdd/DexPlusPlusPlusPlus/blob/main/README.md)

![预览](./image/截屏2026-10-04%2016.52.58.png)

[查看更多图片](./image.md)

## 最新版本脚本

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/snmwdd/DexPlusPlusPlusPlus/refs/heads/main/script.lua"))()
```

## Dex# 和 Dex++ 有什么区别？

Dex# 是基于 Dex++ 进行定制和扩展的版本。

在保留原有 Dex / Dex++ 功能的基础上，Dex# 增加了新的对象选择与编辑工具、语言切换、反编译器选项，并修复和优化了部分界面与兼容性问题。

### Dex# 新增 / 修复的功能

- 支持直接点击 GUI 对象进行选择
- 点击 GUI 选择支持 PlayerGui 和 CoreGui，仅排除 Dex 自身界面与执行器隐藏容器中的内容
- 选择 GUI 后自动在 Explorer 中定位对应对象
- 为当前选中的 GUI 显示蓝色选择轮廓
- 为选中的 GUI 对象和 Part 增加移动、缩放和旋转工具
- GUI 支持可视化缩放控制点
- GUI 支持旋转控制
- 增加位置与尺寸辅助显示
- Part 支持原生三轴移动、缩放和旋转控制柄
- GUI 选择与编辑同时支持鼠标和触摸操作
- Settings 中加入 English / 中文语言切换
- 默认语言为英文
- 语言选项下新增默认开启的“翻译属性”，中文模式下翻译属性名称和分类，支持中英文属性搜索，切换立即生效并保存设置
- “保存实例”窗口支持完整中英文界面，“反编脚本”默认关闭，可按需开启
- Dex# 菜单新增灰色半透明“文件管理器”，浏览执行器 Workspace 文件目录，支持搜索、新建、文本编辑保存和确认删除；文本预览上限为 256 KB
- 文件管理器操作按钮只显示灰色图标，悬停显示中英文提示；文件夹、Lua/Luau 与普通文件分别显示对应图标，窄窗口支持工具栏横向滚动
- 同一窗口可切换到“游戏资源”，搜索并预览游戏内图片、贴图和模型，修改图片资源引用、复制资源 ID/实例路径、定位到资源列表、将模型导出到上次浏览的 Workspace 文件夹；清除引用和删除模型均需确认。模型预览使用移除脚本的副本，修改作用于当前客户端会话；资源列表只绘制可见行
- Dex# 菜单新增 **spy**，原作者 **deivid、upio** 已加入“关于”。使用 Dex 原有启动进度预加载，完成后隐藏；打开菜单直接显示，关闭或缩小后保留已加载状态并继续捕获。窗口与控件采用 Dex 灰色半透明风格，设置及调用过滤器使用 Dex 原生勾选开关，常用图标复用 Dex 图标。界面随 Dex 设置切换中英文，远程对象名称、输入内容、参数和代码保持原样。二级窗口使用父级层级避免遮挡；重载／卸载 Dex 时清理 Spy，启动失败不会阻止 Dex 加载。
- 优化反编译器选择菜单，使界面更加紧凑
- 增加 ASCII 风格的 `Re-Deobf` 按钮
- 新增 `lua.expert/demo`
- 新增 [Luaunveil / luau-decompiler](https://github.com/Luaunveil/luau-decompiler)
- 同时保留以下反编译模式：
  - Konstant
  - AdvancedDecompiler
  - Shiny
  - Executor
- 改善 DataModel 根节点兼容性，解决部分情况下 Explorer 树为空的问题
- 优化 Script Viewer 工具栏在不同窗口尺寸下的布局
- 修复重复创建 Settings 窗口的问题
- 修复无效透明度数值导致的问题

> 除 `Executor` 模式外，其他反编译模式需要执行器支持 `getscriptbytecode`。

## 构建

1. 下载或克隆此仓库。
2. 确保电脑上已安装 Python 3。
3. 运行 `build.py`。
4. 构建完成后将生成 `out.lua`。

## Credits

- [Chillz](https://github.com/AZYsGithub) – Dex++ 维护者
- [Cazan](https://github.com/Cazzanos) – 协助开发 Model Viewer
- [Moon](https://github.com/LorekeeperZinnia/Dex) – 原始 Dex Explorer
- [Toon](https://github.com/Toon-arch) – 项目贡献者，以及 IY Dex 部分组件的来源
- [ChatGPT](https://chatgpt.com) – 协助代码开发、调试与文档整理
- 修复设置勾选开关需先点击输入框、重复点击才生效的问题；禁用开关不触发修改，快速切换不会被过期动画覆盖。
