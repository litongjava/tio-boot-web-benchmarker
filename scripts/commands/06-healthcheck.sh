#!/usr/bin/env bash
# 健康检查 + JIT 预热 + 观测每请求日志的开销（日志过重会把压测变成磁盘测试）。
#
# 判据刻意放宽成「至少一个由 WebHelloConfig 显式注册的接口可用」：
# 目标是「服务起来了吗」，而不是「每个接口都在」。
# 某个接口 404 会在这里被如实打印出来，但不会让整个部署失败 ——
# 那属于代码/文档问题，应该被人看见，而不是把部署卡住。
set -e

PORT="${APP_PORT:-10061}"
APP_DIR=/srv/apps/tio-boot-web-benchmarker
BASE="http://127.0.0.1:$PORT"

echo '=== 等待端口起来 ==='
UP=0
for _ in $(seq 1 45); do
  if curl -s -o /dev/null "$BASE/plaintext"; then UP=1; break; fi
  sleep 2
done
if [ "$UP" != "1" ]; then
  echo '服务没有起来'
  echo '--- startup.log ---'; tail -60 "$APP_DIR/logs/startup.log" 2>/dev/null || true
  echo '--- startup-error.log ---'; tail -40 "$APP_DIR/logs/startup-error.log" 2>/dev/null || true
  exit 1
fi

echo '=== 各接口连通性与响应样例 ==='
HEALTHY=0
for p in /plaintext /json /hello /ok /; do
  code=$(curl -s -o /tmp/tbwb-body -w '%{http_code}' "$BASE$p" || true)
  body=$(head -c 120 /tmp/tbwb-body 2>/dev/null | tr -d '\r\n')
  printf '  %-11s HTTP %-4s %s\n' "$p" "$code" "$body"
  case "$p:$code" in
    /plaintext:200|/json:200|/hello:200) HEALTHY=1 ;;
  esac
done

echo '=== 响应头（看 content-type / content-length）==='
curl -s -D - -o /dev/null "$BASE/plaintext" | head -8
curl -s -D - -o /dev/null "$BASE/json" | head -8

echo '=== 启动日志（前 40 行，含路由与端口）==='
head -40 "$APP_DIR/logs/startup.log" 2>/dev/null || true

echo '=== JIT 预热 20000 次请求 ==='
if command -v ab >/dev/null 2>&1; then
  ab -q -k -n 20000 -c 50 "$BASE/plaintext" >/dev/null 2>&1 || true
else
  for _ in $(seq 1 200); do curl -s -o /dev/null "$BASE/plaintext"; done
fi

echo '=== 日志规模（判断每请求日志是否成为瓶颈）==='
du -sh "$APP_DIR/logs"
ls -lh "$APP_DIR/logs" | head -10

if [ "$HEALTHY" != "1" ]; then
  echo '显式注册的接口（/plaintext、/json、/hello）全都不可用，部署判定为失败'
  exit 1
fi
echo '健康检查通过'
