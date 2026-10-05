#!/usr/bin/env bash
# 诊断（第六轮）：列出 nexus.io:java-model:1.2.7 注解包里的全部类名，
# 用来把 com.litongjava.annotation.* 的 import 一一对应地换成 nexus.io.annotation.*。
set -e
M2=/root/.m2/repository
JM="$M2/nexus/io/java-model/1.2.7/java-model-1.2.7.jar"

echo "=== nexus.io.annotation 全部类 ==="
unzip -l "$JM" | grep 'nexus/io/annotation/' | grep '\.class$' | awk '{print $NF}' \
  | sed 's#nexus/io/annotation/##; s#\.class$##' | grep -v '\$' | sort | tr '\n' ' '
echo
echo
echo "=== 我们要用的四个是否都在 ==="
for c in AComponentScan AConfiguration Initialization RequestPath; do
  if unzip -l "$JM" | grep -q "nexus/io/annotation/$c.class"; then echo "  有 $c"; else echo "  没有 $c"; fi
done
