#!/usr/bin/env bash
# 注册 systemd 单元并重启，确认端口真的监听起来。
set -e

APP_DIR=/srv/apps/tio-boot-web-benchmarker
PORT="${APP_PORT:-10061}"

# 端口被别人（不是本服务）占用时直接失败，避免「测了半天打的是别的进程」。
if ss -ltn | grep -qE ":${PORT}\b" && ! systemctl is-active --quiet tio-boot-web-benchmarker; then
  echo "端口 $PORT 已被其它进程占用："
  ss -ltnp 2>/dev/null | grep -E ":${PORT}\b" || true
  exit 1
fi

cat > /etc/systemd/system/tio-boot-web-benchmarker.service <<'UNIT'
[Unit]
Description=tio-boot web benchmarker (tio-boot-web-benchmarker)
After=network-online.target

[Service]
Type=simple
WorkingDirectory=/srv/apps/tio-boot-web-benchmarker
ExecStart=/usr/java/jdk1.8.0_411/bin/java -server -Xms2g -Xmx2g -jar /srv/apps/tio-boot-web-benchmarker/app.jar
Restart=always
RestartSec=5
LimitNOFILE=1048576
Environment=TZ=Asia/Shanghai
Environment=LANG=C.UTF-8
StandardOutput=append:/srv/apps/tio-boot-web-benchmarker/logs/startup.log
StandardError=append:/srv/apps/tio-boot-web-benchmarker/logs/startup-error.log

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable tio-boot-web-benchmarker >/dev/null 2>&1 || true

# 清空上一次的日志，方便本次定位；systemd 的 append: 用的是 O_APPEND，截断是安全的。
: > "$APP_DIR/logs/startup.log"
: > "$APP_DIR/logs/startup-error.log"
rm -f "$APP_DIR"/logs/log.*.log

systemctl restart tio-boot-web-benchmarker
sleep 4
echo "服务状态 : $(systemctl is-active tio-boot-web-benchmarker)"

if ! ss -ltn | grep -qE ":${PORT}\b"; then
  echo "端口 $PORT 没有监听起来，实际监听的 java 端口："
  ss -ltnp 2>/dev/null | grep java || true
  echo '--- startup.log 尾部 ---'
  tail -40 "$APP_DIR/logs/startup.log" 2>/dev/null || true
  echo '--- startup-error.log 尾部 ---'
  tail -40 "$APP_DIR/logs/startup-error.log" 2>/dev/null || true
  exit 1
fi

echo '端口已监听：'
ss -ltnp 2>/dev/null | grep -E ":${PORT}\b" || true
