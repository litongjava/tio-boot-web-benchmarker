#!/usr/bin/env bash
# 部署平台自检：搞清平台自身是怎么装在这台机器上的，为「用任务功能升级平台」做准备。
set -e

echo '=== 部署平台 systemd 单元 ==='
systemctl cat deploy-server 2>/dev/null || echo '（没有 deploy-server.service）'

echo
echo '=== 部署平台数据与安装目录 ==='
for d in /srv/deploy /srv/deploy/data /srv/deploy/bin /opt/deploy-server /srv/deploy-server; do
  [ -e "$d" ] && { echo "--- $d ---"; ls -la "$d" | head -20; }
done

echo
echo '=== 可能的源码工作区 ==='
for d in /srv/worksapce/deploy /srv/workspace/deploy /srv/deploy/workspaces/deploy /root/deploy; do
  [ -d "$d" ] && { echo "--- $d ---"; ls -la "$d" | head -20; }
done

echo
echo '=== 构建工具链 ==='
echo "go   : $(command -v go || echo 未安装) $(go version 2>/dev/null | awk '{print $3}')"
echo "node : $(command -v node || echo 未安装) $(node -v 2>/dev/null)"
echo "pnpm : $(command -v pnpm || echo 未安装) $(pnpm -v 2>/dev/null)"
echo "make : $(command -v make || echo 未安装)"
echo "gcc  : $(command -v gcc || echo 未安装)"

echo
echo '=== 外网可达性（升级平台要能从 git 拉代码） ==='
timeout 10 git ls-remote https://gitee.com/ppnt/deploy.git HEAD >/dev/null 2>&1 && echo 'gitee.com/ppnt/deploy 可达' || echo 'gitee.com/ppnt/deploy 不可达'
timeout 10 git ls-remote https://github.com/litongjava/tio-boot-web-benchmarker.git HEAD >/dev/null 2>&1 && echo 'github litongjava/tio-boot-web-benchmarker 可达' || echo 'github 不可达'
timeout 10 curl -sI https://registry.npmmirror.com >/dev/null 2>&1 && echo 'npmmirror 可达' || echo 'npmmirror 不可达'

echo
echo '=== 磁盘与内存余量（构建平台要占地方） ==='
df -h / | tail -1
free -m | head -2
