#!/usr/bin/env bash
# 同步代码：把工作区对齐到远端的 main。
#
# 为什么不用平台的「Git 准备阶段」：那段是一次性的，拉不动就直接中止整次运行。
# 这台服务器到 github.com 的连接是间歇性的（实测 SSL connection timeout，约一半概率），
# 所以这里自己拉，带重试；重试都用完就明确失败 —— 绝不能默默用旧代码去构建，
# 否则压测报告上的提交号会是错的。
set -e

WORKDIR="${WORKDIR:-/srv/deploy/workspaces/tio-boot-web-benchmarker}"
cd "$WORKDIR"

echo "工作区   : $WORKDIR"
echo "当前提交 : $(git rev-parse --short HEAD) $(git log -1 --pretty=%s)"

if [ ! -d .git ]; then
  echo '工作区里没有 .git，改为完整克隆'
  cd "$(dirname "$WORKDIR")"
  rm -rf "$WORKDIR"
  git clone --depth 1 https://github.com/litongjava/tio-boot-web-benchmarker.git "$WORKDIR"
  cd "$WORKDIR"
fi

OK=0
for i in 1 2 3 4 5; do
  echo ">>> 第 $i 次 git fetch"
  if git fetch --depth 1 origin main; then OK=1; break; fi
  echo "    失败，5 秒后重试"
  sleep 5
done
if [ "$OK" != "1" ]; then
  echo '多次拉取都失败：拒绝用工作区里的旧代码继续构建'
  exit 1
fi

git reset --hard FETCH_HEAD
echo "同步到   : $(git rev-parse --short HEAD) $(git log -1 --pretty=%s)"
