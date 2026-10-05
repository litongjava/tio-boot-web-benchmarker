#!/usr/bin/env bash
# 升级「部署平台」自身：下载新二进制 → 校验 → 备份 → 安装 → 交给一个脱离本进程的看门脚本重启。
#
# 为什么要脱离本进程：这条命令本身就是平台在执行。直接 systemctl restart 会把
# 执行它的进程一起杀掉，本次运行会被标成「中断」，也看不到结果。
# 所以真正做重启 + 健康检查 + 回滚的是一段 setsid 出去的脚本 —— 即使新版本起不来，
# 平台也能自己恢复，不会把唯一的远程执行通道弄丢。
set -e

URL="${PLATFORM_BIN_URL:?缺少 PLATFORM_BIN_URL}"
SHA="${PLATFORM_BIN_SHA256:-}"
BIN=/usr/local/bin/deploy-server
STAMP=$(date +%Y%m%d%H%M%S)

echo "=== 1/5 源可达性 ==="
if ! curl -fsS -m 15 -o /dev/null "${URL%/*}/"; then
  echo "拿不到 $URL 所在目录：确认提供文件的一端在跑，且防火墙放行了该端口"
  exit 1
fi
echo "ok: $URL"

echo "=== 2/5 下载与校验 ==="
curl -fsS -m 300 -o /tmp/deploy-server-new "$URL"
# curl -o 落下来的是 0644，直接执行会得到 exit 126（Permission denied）。
chmod 0755 /tmp/deploy-server-new
ls -lh /tmp/deploy-server-new
if [ -n "$SHA" ]; then
  GOT=$(sha256sum /tmp/deploy-server-new | awk '{print $1}')
  if [ "$GOT" != "$SHA" ]; then
    echo "sha256 不匹配：期望 $SHA，实际 $GOT"
    exit 1
  fi
  echo "sha256 校验通过：$GOT"
fi
/tmp/deploy-server-new --version

echo "=== 3/5 备份当前版本与数据 ==="
cp -f "$BIN" "$BIN.bak-$STAMP"
chmod 0755 "$BIN.bak-$STAMP"
echo "旧二进制：$BIN.bak-$STAMP"
mkdir -p /srv/deploy/backup
tar -czf "/srv/deploy/backup/data-$STAMP.tar.gz" -C /srv/deploy data
ls -lh "/srv/deploy/backup/data-$STAMP.tar.gz"

echo "=== 4/5 安装新二进制 ==="
install -m 0755 /tmp/deploy-server-new "$BIN"
"$BIN" --version

echo "=== 5/5 生成看门脚本并脱离本进程执行 ==="
cat > /tmp/deploy-upgrade.sh <<EOF
#!/usr/bin/env bash
# 由升级命令 setsid 出来的看门脚本：重启 + 健康检查 + 启动失败自动回滚。
# 写在这里而不是升级命令里，是因为它必须在平台进程消失之后仍然活着。
exec >>/tmp/deploy-upgrade.log 2>&1
echo "[\$(date '+%F %T')] 升级 $STAMP：准备重启 deploy-server"
sleep 3
systemctl restart deploy-server
for i in \$(seq 1 30); do
  sleep 2
  if curl -fsS -m 5 http://127.0.0.1:10055/api/v1/healthz >/tmp/deploy-healthz.json 2>/dev/null; then
    echo "[\$(date '+%F %T')] 健康检查通过：\$(cat /tmp/deploy-healthz.json)"
    exit 0
  fi
done
echo "[\$(date '+%F %T')] 新版本 60 秒内没有起来，回滚到 $BIN.bak-$STAMP"
cp -f "$BIN.bak-$STAMP" "$BIN"
systemctl restart deploy-server
sleep 5
if curl -fsS -m 5 http://127.0.0.1:10055/api/v1/healthz; then
  echo ""
  echo "[\$(date '+%F %T')] 已回滚并恢复服务"
else
  echo "[\$(date '+%F %T')] 回滚后仍不健康，需要人工介入"
fi
EOF
chmod 0755 /tmp/deploy-upgrade.sh
: > /tmp/deploy-upgrade.log
setsid nohup /tmp/deploy-upgrade.sh < /dev/null > /dev/null 2>&1 &
echo "看门脚本已启动（日志 /tmp/deploy-upgrade.log）；本次运行到此结束，约 10 秒后新版本接管"
