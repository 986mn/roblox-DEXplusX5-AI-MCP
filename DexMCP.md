# DexMCP — DEX PlusPlusPlusPlus 的 MCP 桥接

给 [DEX++](https://github.com/snmwdd/DexPlusPlusPlusPlus) 接上 AI 通道。
AI 能看到你在 DEX 里选中的对象，也能反过来驱动 DEX 跳转、改属性、反编译、执行代码。

> 本 fork 在上游基础上**只新增一个模块** `src/modules/DexMCP.lua`，
> 并在 `Main.ModuleList` 末尾注册。上游代码未做任何修改。

---

## 快速使用

```lua
-- 在 Roblox 执行器里直接跑，DEX 与桥接一同加载
loadstring(game:HttpGet(
  "https://raw.githubusercontent.com/986mn/DexPlusPlusPlusPlus/main/script.lua"
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
