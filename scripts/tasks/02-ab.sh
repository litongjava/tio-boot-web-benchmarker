#!/usr/bin/env bash
# 压测 B：ab（ApacheBench）并发矩阵。
#
# 与文档里老数据可比的一档是 plaintext @ c1000；keep-alive 打开/关闭各测一次，
# 因为这两个数差得很多，混在一起看会得出错误结论。
set -e

BASE="${BASE_URL:-http://127.0.0.1:10061}"
OUT="${APP_DIR:-/srv/apps/tio-boot-web-benchmarker}/bench"
mkdir -p "$OUT"

echo "ab 版本 : $(ab -V 2>&1 | head -1)"

run() {
  ep="$1"; c="$2"; n="$3"; ka="$4"
  echo
  echo "######### ab ${ka} -n${n} -c${c} ${BASE}/${ep} #########"
  # shellcheck disable=SC2086
  ab ${ka} -n"${n}" -c"${c}" "${BASE}/${ep}" 2>&1 | tee "$OUT/ab-${ep}-c${c}${ka:+-k}.txt"
}

run plaintext 100 200000 -k
run json      100 200000 -k
run ok        100 200000 -k
run hello     100 200000 -k
run plaintext 1000 200000 -k
# 不开 keep-alive：每个请求一条新连接，量的是「连接建立 + 处理」的总成本。
run plaintext 1000  50000 ""

echo
echo '=== 结果文件 ==='
ls -lh "$OUT"/ab-*.txt
