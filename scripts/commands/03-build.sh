#!/usr/bin/env bash
# Maven 构建生产包。服务器上的 JDK 是 1.8.0_411，Maven 3.8.8。
set -e

export JAVA_HOME=/usr/java/jdk1.8.0_411
export PATH="$JAVA_HOME/bin:$PATH"

WORKDIR="${WORKDIR:-/srv/deploy/workspaces/tio-boot-web-benchmarker}"
cd "$WORKDIR"

echo "工作目录 : $WORKDIR"
echo "JDK      : $(java -version 2>&1 | head -1)"
echo "Maven    : $(mvn -v 2>&1 | head -1)"
echo "分支提交 : $(git rev-parse --short HEAD) $(git log -1 --pretty=%s)"

mvn -B clean package -DskipTests -Pproduction -Dgpg.skip=true -Dmaven.javadoc.skip=true

echo '=== 构建产物 ==='
ls -lh target/tio-boot-web-benchmarker-*.jar
