# roblox-DEXplusX5-AI-MCP

<p align="center">
  <img src="abc/banner.svg" alt="roblox-DEXplusX5-AI-MCP" width="100%"/>
</p>

<p align="center">
  <strong>DEX PlusPlusPlusPlus ↔ AI/MCP 双向桥接</strong><br/>
  <sub>让 Claude / Cursor 等 AI 客户端直接读写你的 DEX 调试会话</sub>
</p>

<p align="center">
  <img src="abc/demo.gif" alt="演示" width="480"/>
</p>

> **本 fork 在上游 [DEX++ (snmwdd/DexPlusPlusPlusPlus)](https://github.com/snmwdd/DexPlusPlusPlusPlus) 基础上新增了 AI/MCP 桥接能力。**
>
> 通过一个 Node.js MCP 服务端 + 执行器侧 Lua 轮询器，让 Claude / Cursor 等 AI 客户端直接读写你的 DEX 会话：查看选中对象、读属性、反编译脚本、改属性、执行 Luau。

---

## 快速开始（MCP 桥接）

**1. 起服务端**（本机或 Codespaces，见 [DEPLOY.md](./DEPLOY.md)）

```bash
git clone https://github.com/986mn/roblox-DEXplusX5-AI-MCP.git
cd roblox-DEXplusX5-AI-MCP
bash abc/oneshot.sh
```

**2. 执行器里加载**

```lua
getgenv().BridgeURL = "localhost:16384"  -- 或局域网 IP / Codespaces https 地址

-- DEX++ 本体 + DexMCP 模块
loadstring(game:HttpGet(
  "https://raw.githubusercontent.com/986mn/roblox-DEXplusX5-AI-MCP/main/script.lua"
))()

-- 轮询器（连接 MCP 服务端）
loadstring(game:HttpGet(
  "https://raw.githubusercontent.com/986mn/roblox-DEXplusX5-AI-MCP/main/lua/dex_mcp_poller.lua"
))()
```

看到 `[DPP-MCP] injected` 和 `[DPP-POLL] connected` 就通了。

**详细部署（Codespaces / 本机 / 局域网）与故障排查：见 [DEPLOY.md](./DEPLOY.md)**

**DEX 桥接 API 说明：见 [DexMCP.md](./DexMCP.md)**

---

## 五种形态（abc/ 目录）

| 版本 | 内容 | 适用 |
|---|---|---|
| **A** | 完整读写 API | 只要 API |
| **C** | 悬浮按钮 + 队列 | 只要 UI |
| **AC** | A + C 合并 | 完整功能，推荐 |
| **B** | 运行时包装器（含 A） | 用官方 DEX |
| **BC** | B + C | 官方 DEX + 按钮 |

```lua
-- AC 合并单文件（API + 按钮）
loadstring(game:HttpGet(".../abc/dex_mcp_AC.lua"))()

-- BC（官方 DEX + 按钮）
getgenv().DEX_URL = "https://raw.githubusercontent.com/snmwdd/DexPlusPlusPlusPlus/refs/heads/main/script.lua"
loadstring(game:HttpGet(".../abc/dex_mcp_BC.lua"))()
```

---

## 目录结构

```
server/                 MCP 服务端（TypeScript，11 个 dex-* 工具）
lua/dex_mcp_poller.lua 执行器侧轮询器
abc/                    五种形态脚本 + oneshot.sh + 配图（banner/demo）
src/modules/DexMCP.lua DEX 桥接模块（注入 getgenv().DEX）
src/                    上游 DEX++ 源码（未改动）
script.lua              DEX++ 构建产物（已含 DexMCP）
.devcontainer/          Codespaces 自动部署 + 保活
```

> **注意**：仓库已从 `DexPlusPlusPlusPlus` 改名为 `roblox-DEXplusX5-AI-MCP`，旧的 raw 链接已失效。

---

---

# 以下是上游 DEX++ 原始中文 README（未改动）

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
