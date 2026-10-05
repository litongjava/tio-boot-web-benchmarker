#!/usr/bin/env bash
# 环境勘察：确认主机规格、端口占用与工具链，只读，不做任何改动。
set -e

echo '=== 主机 ==='
hostname
uname -srm
echo "cores: $(nproc)"
free -m | head -2
uptime

echo '=== 已监听端口 ==='
ss -ltn | tail -n +2 | awk '{print $4}' | sed 's/.*://' | sort -n -u | tr '\n' ' '
echo

echo '=== 工具链 ==='
for t in java mvn git curl ab wrk; do
  printf '  %-8s %s\n' "$t" "$(command -v "$t" 2>/dev/null || echo 未安装)"
done
echo "  JAVA_HOME=$JAVA_HOME"
java -version 2>&1 | head -2 || true

echo '=== 目标端口 ==='
PORT="${APP_PORT:-10061}"
if ss -ltn | grep -qE ":${PORT}\b"; then
  echo "  警告：$PORT 已被占用"
  ss -ltnp 2>/dev/null | grep -E ":${PORT}\b" || true
else
  echo "  $PORT 空闲，可用于本次部署"
fi
