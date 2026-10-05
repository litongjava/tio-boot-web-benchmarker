#!/usr/bin/env bash
# 压测 A：wrk 并发矩阵。
#
# 全程用 127.0.0.1 打本机，把网络变量摘出去：这一轮要量的是 tio-boot 的处理能力，
# 不是链路质量。每档先跑 30 秒，用 --latency 拿到延迟分布。
set -e

BASE="${BASE_URL:-http://127.0.0.1:10061}"
OUT="${APP_DIR:-/srv/apps/tio-boot-web-benchmarker}/bench"
WORKDIR="${WORKDIR:-/srv/deploy/workspaces/tio-boot-web-benchmarker}"
mkdir -p "$OUT"

echo '=== 压测环境 ==='
echo "时间     : $(date '+%F %T')"
echo "目标     : $BASE"
echo "内核     : $(uname -srm)"
echo "CPU      : $(nproc) 逻辑核 / $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)"
echo "内存     : $(free -m | awk 'NR==2{print $2" MB 合计, "$7" MB 可用"}')"
echo "应用提交 : $(cd "$WORKDIR" && git rev-parse --short HEAD) $(cd "$WORKDIR" && git log -1 --pretty=%s)"
echo "wrk      : $(wrk --version 2>&1 | head -1)"
echo "JDK      : $(java -version 2>&1 | head -1)"

echo
echo '=== 压测前资源 ==='
uptime
free -m | head -2

# 端点:并发 的组合。plaintext 是纯字节写回（框架下限），json 带一次序列化，
# ok/hello 走 RespBodyVo 包装（更接近真实业务返回）。
for s in plaintext:100 plaintext:400 plaintext:1000 json:100 ok:100 hello:100; do
  EP="${s%%:*}"
  C="${s##*:}"
  echo
  echo "######### wrk -t8 -c${C} -d30s ${BASE}/${EP} #########"
  wrk -t8 -c"$C" -d30s --latency "$BASE/$EP" 2>&1 | tee "$OUT/wrk-${EP}-c${C}.txt"
done

echo
echo '=== 压测后资源 ==='
uptime
free -m | head -2
echo
echo '=== 结果文件 ==='
ls -lh "$OUT"/wrk-*.txt
