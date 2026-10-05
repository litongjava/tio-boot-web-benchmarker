#!/usr/bin/env bash
# 安装压测工具：ab（apache2-utils）与 wrk（apt 里没有则源码编译）。
# 幂等：已安装就跳过。
set -e

export DEBIAN_FRONTEND=noninteractive

if ! command -v ab >/dev/null 2>&1; then
  echo '>>> 安装 apache2-utils（提供 ab）'
  apt-get update -qq
  apt-get install -y -qq apache2-utils
else
  echo '>>> ab 已安装，跳过'
fi

if ! command -v wrk >/dev/null 2>&1; then
  echo '>>> 安装 wrk'
  if ! apt-get install -y -qq wrk 2>/dev/null; then
    echo '>>> apt 源里没有 wrk，改为源码编译（需要 libssl-dev）'
    apt-get install -y -qq build-essential libssl-dev
    rm -rf /tmp/wrk-src
    git clone --depth 1 https://github.com/wg/wrk.git /tmp/wrk-src
    make -C /tmp/wrk-src -j"$(nproc)"
    install -m 0755 /tmp/wrk-src/wrk /usr/local/bin/wrk
  fi
else
  echo '>>> wrk 已安装，跳过'
fi

echo '=== 版本 ==='
echo "  ab  : $(command -v ab)"
ab -V 2>&1 | head -1 | sed 's/^/        /'
echo "  wrk : $(command -v wrk)"
wrk --version 2>&1 | head -2 | sed 's/^/        /'
