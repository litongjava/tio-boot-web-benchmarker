#!/usr/bin/env bash
# 把 jar 发布到 /srv/apps/tio-boot-web-benchmarker，并写外部端口配置。
#
# app.properties 与 my.txt 都写一份：不同版本的 tio-boot 读取的外部配置文件名不一致，
# 两个都放可以避免「配置没生效、进程偷偷监听默认端口」这种最难查的情况。
set -e

WORKDIR="${WORKDIR:-/srv/deploy/workspaces/tio-boot-web-benchmarker}"
APP_DIR=/srv/apps/tio-boot-web-benchmarker
PORT="${APP_PORT:-10061}"

JAR=$(ls -t "$WORKDIR"/target/tio-boot-web-benchmarker-*.jar 2>/dev/null | grep -vE -- '-(sources|javadoc)\.jar$' | head -1)
if [ -z "$JAR" ]; then
  echo '未找到构建产物，请先执行「Maven 构建生产包」'
  exit 1
fi

mkdir -p "$APP_DIR/logs" "$APP_DIR/bench"
cp -f "$JAR" "$APP_DIR/app.jar"
printf 'server.port=%s\n' "$PORT" > "$APP_DIR/app.properties"
printf 'server.port=%s\n' "$PORT" > "$APP_DIR/my.txt"

echo "来源 jar : $JAR"
echo "发布 jar : $APP_DIR/app.jar ($(du -h "$APP_DIR/app.jar" | cut -f1))"
echo "监听端口 : $PORT"
ls -la "$APP_DIR"
