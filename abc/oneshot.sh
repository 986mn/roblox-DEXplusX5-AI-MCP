#!/usr/bin/env bash
#================================================================
#  DEX++ MCP 一键启动脚本
#================================================================
#  一条命令完成：
#    1. 安装依赖 + 编译服务端
#    2. 启动 HTTP 服务 (16384)
#    3. 打印执行器里要粘贴的加载代码
#
#  用法：
#    bash oneshot.sh                # 本机启动，打印 localhost 地址
#    PORT=16384 bash oneshot.sh     # 指定端口
#================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER="$ROOT/server"
PORT="${PORT:-16384}"

step() { printf '
[1;36m[%s][0m %s
' "$1" "$2"; }

cd "$SERVER"

# ---------- 1. 依赖 ----------
if [ ! -d node_modules ]; then
  step 1/4 "安装依赖（首次较慢）"
  npm install --no-audit --no-fund
else
  step 1/4 "依赖已存在，跳过"
fi

# ---------- 2. 编译 ----------
if [ ! -f dist/index.js ] || [ -n "$(find src -name '*.ts' -newer dist/index.js -print -quit 2>/dev/null)" ]; then
  step 2/4 "编译 TypeScript"
  npx tsc
else
  step 2/4 "已编译，跳过"
fi

# ---------- 3. 杀旧进程 ----------
pkill -f 'node dist/index.js' 2>/dev/null || true
sleep 0.3

# ---------- 4. 启动 ----------
step 3/4 "启动服务 (端口 $PORT)"
PORT="$PORT" nohup node dist/index.js < /dev/zero > "$SERVER/.server.log" 2>&1 &
echo "$!" > "$SERVER/.server.pid"

# 等就绪
for _ in $(seq 1 40); do
  if curl -fsS "http://127.0.0.1:$PORT/api/status" >/dev/null 2>&1; then break; fi
  sleep 0.5
done

if ! curl -fsS "http://127.0.0.1:$PORT/api/status" >/dev/null 2>&1; then
  echo "服务启动失败，日志：" >&2
  tail -n 30 "$SERVER/.server.log" >&2
  exit 1
fi

# ---------- 打印结果 ----------
LOCAL_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || echo '127.0.0.1')"

step 4/4 "启动完成"
cat <<INFO

  ============================================================
   DEX++ MCP 已启动

   本机地址 : http://localhost:$PORT
   局域网   : http://$LOCAL_IP:$PORT
   状态     : http://localhost:$PORT/api/status

   —— 执行器里粘贴（先设 BridgeURL 再加载）——

   getgenv().BridgeURL = "$LOCAL_IP:$PORT"

   loadstring(game:HttpGet(
     "https://raw.githubusercontent.com/986mn/roblox-DEXplusX5-AI-MCP/main/script.lua"
   ))()

   loadstring(game:HttpGet(
     "https://raw.githubusercontent.com/986mn/roblox-DEXplusX5-AI-MCP/main/lua/dex_mcp_poller.lua"
   ))()

   —— 可选：悬浮按钮 ——

   loadstring(game:HttpGet(
     "https://raw.githubusercontent.com/986mn/roblox-DEXplusX5-AI-MCP/main/abc/dex_mcp_C.lua"
   ))()

  ============================================================

   停止服务：kill \$(cat server/.server.pid)
   看日志  ：tail -f server/.server.log

INFO
