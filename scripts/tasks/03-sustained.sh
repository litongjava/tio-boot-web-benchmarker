#!/usr/bin/env bash
# 压测 C：持续压测 + 资源时间线。
#
# 目的不是再刷一个 QPS 数字，而是看「压力持续两分钟后会不会退」：
# 延迟是否随时间抬升、CPU 是否被吃满、内存有没有持续上涨（GC 跟不跟得上）。
set -e

BASE="${BASE_URL:-http://127.0.0.1:10061}"
OUT="${APP_DIR:-/srv/apps/tio-boot-web-benchmarker}/bench"
DUR="${SUSTAIN_SECONDS:-120}"
mkdir -p "$OUT"

echo "######### 持续压测 wrk -t8 -c200 -d${DUR}s ${BASE}/plaintext #########"

# 每 10 秒采一次负载与内存，压测结束后一并打印。
(
  for _ in $(seq 1 $((DUR / 10 + 2))); do
    printf '%s | %s | %s\n' \
      "$(date '+%H:%M:%S')" \
      "$(uptime | sed 's/.*load average/load/')" \
      "$(free -m | awk 'NR==2{print "mem used "$3"MB avail "$7"MB"}')"
    sleep 10
  done
) > "$OUT/resource-timeline.txt" 2>&1 &
MON=$!

APP_PID=$(pgrep -f 'tio-boot-web-benchmarker/app.jar' | head -1 || true)
echo "应用进程 : ${APP_PID:-未找到}"

wrk -t8 -c200 -d"${DUR}"s --latency "$BASE/plaintext" 2>&1 | tee "$OUT/wrk-sustained-c200.txt"

sleep 1
kill "$MON" 2>/dev/null || true

echo
echo '=== 压测期间资源时间线（每 10 秒）==='
cat "$OUT/resource-timeline.txt"

echo
echo '=== 应用进程状态 ==='
if [ -n "$APP_PID" ]; then
  ps -o pid,pcpu,pmem,rss,etime,args -p "$APP_PID" | cut -c1-160
  echo "线程数   : $(ls /proc/"$APP_PID"/task 2>/dev/null | wc -l)"
fi

echo
echo '=== CPU 占用前 5 的进程 ==='
ps -eo pcpu,pmem,pid,comm --sort=-pcpu | head -6

echo
echo '=== 应用日志规模（判断是否被日志 IO 拖住）==='
du -sh "${APP_DIR:-/srv/apps/tio-boot-web-benchmarker}"/logs 2>/dev/null || true
