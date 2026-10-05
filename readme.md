# tio-boot-web-benchmarker

基于 [tio-boot](https://github.com/litongjava/tio-boot) 的最小 Web 服务压测工程：**用最小的接口把框架的吞吐量量出来**，并通过[轻量部署平台](https://gitee.com/ppnt/deploy)完成「构建部署」与「压测执行」两条链路。

> **本文档同时是压测报告。** 第 7 章是 2026-10-05 在 `MiWiFi-R4A-srv`（i3-12100F / 8 逻辑核 / 16 GB / Debian 12 / JDK 8）上的实测数据，原始日志见 [`docs/benchmark-raw-2026-10-05.log`](docs/benchmark-raw-2026-10-05.log)。

---

## 1. 接口一览

服务默认监听 `8080`，本工程在生产部署时通过外部配置改成 `10061`（见 §5.3）。四个接口分两类，用来把「框架开销」和「业务开销」分开看：

| 接口 | 实现方式 | 响应体 | 说明 |
| --- | --- | --- | --- |
| `/plaintext` | `WebHelloConfig` 注册的 Handler | `Hello, World!`（13 B） | 直接把预编码的字节写回，**框架吞吐量的上限** |
| `/json` | 同上 | `{"message":"Hello, World!"}`（27 B） | 多一次 fastjson2 序列化 |
| `/hello` | 同上 | `{"data":{},"msg":null,"error":null,"ok":true,"code":1}`（54 B） | `RespBodyVo` 包装，接近真实业务返回 |
| `/ok` | `@RequestPath` 注解控制器 | `{"data":null,...,"ok":true,"code":1}`（56 B） | 走注解路由 + 返回值自动序列化 |

---

## 2. 代码结构

```
src/main/java/com/litongjava/tio/web/hello/
├── HelloApp.java                     启动类（@AComponentScan）
├── config/WebHelloConfig.java        用 @AConfiguration + @Initialization 手工注册三个 Handler
├── controller/OkController.java      @RequestPath 注解式控制器
├── handler/
│   ├── IndexHandler.java             /plaintext 与 /json（预编码字节，走 TioRequestContext）
│   └── HelloHandler.java             /hello（RespBodyVo）
└── model/Message.java                JSON 返回体
```

### 2.1 启动类

```java
package com.litongjava.tio.web.hello;

import nexus.io.annotation.AComponentScan;
import nexus.io.tio.boot.TioApplication;

@AComponentScan
public class HelloApp {
  public static void main(String[] args) {
    long start = System.currentTimeMillis();
    TioApplication.run(HelloApp.class, args);
    long end = System.currentTimeMillis();
    System.out.println((end - start) + "ms");
  }
}
```

### 2.2 路由注册

```java
@AConfiguration
public class WebHelloConfig {
  @Initialization
  public void config() {
    TioBootServer server = TioBootServer.me();
    HttpRequestRouter requestRouter = server.getRequestRouter();
    requestRouter.add("/hello", new HelloHandler()::hello);
    requestRouter.add("/plaintext", new IndexHandler()::plaintext);
    requestRouter.add("/json", new IndexHandler()::json);
  }
}
```

### 2.3 注解式控制器

```java
@RequestPath
public class OkController {
  @RequestPath("/ok")
  public RespBodyVo ok() {
    return RespBodyVo.ok();
  }
}
```

---

## 3. 关键依赖

```xml
<properties>
  <java.version>1.8</java.version>
  <tio.boot.version>2.1.7</tio.boot.version>
  <jfinal-aop.version>1.4.0</jfinal-aop.version>
  <hotswap-classloader.version>1.2.9</hotswap-classloader.version>
</properties>

<dependencies>
  <dependency>
    <groupId>nexus.io</groupId>
    <artifactId>tio-boot</artifactId>
    <version>${tio.boot.version}</version>
  </dependency>
  <dependency>
    <groupId>nexus.io</groupId>
    <artifactId>jfinal-aop</artifactId>
    <version>${jfinal-aop.version}</version>
  </dependency>
  <dependency>
    <groupId>com.alibaba.fastjson2</groupId>
    <artifactId>fastjson2</artifactId>
    <version>2.0.52</version>
  </dependency>
  <dependency>
    <groupId>com.litongjava</groupId>
    <artifactId>hotswap-classloader</artifactId>
    <version>${hotswap-classloader.version}</version>
  </dependency>
  <dependency>
    <groupId>ch.qos.logback</groupId>
    <artifactId>logback-classic</artifactId>
    <version>1.2.3</version>
  </dependency>
</dependencies>
```

### 3.1 从 `com.litongjava:tio-boot` 迁到 `nexus.io:tio-boot` 踩的两个坑

tio-boot 2.x 换了 groupId（`com.litongjava` → `nexus.io`），**包名也跟着换了一遍**。两处没跟上，症状都是「服务起得来、端口在听，但所有接口 404」——查起来很费时间，记在这里：

**坑 1：注解包名不同。**

| 旧 | 新 |
| --- | --- |
| `com.litongjava.annotation.AComponentScan` | `nexus.io.annotation.AComponentScan` |
| `com.litongjava.annotation.AConfiguration` | `nexus.io.annotation.AConfiguration` |
| `com.litongjava.annotation.Initialization` | `nexus.io.annotation.Initialization` |
| `com.litongjava.annotation.RequestPath` | `nexus.io.annotation.RequestPath` |
| `com.litongjava.model.body.RespBodyVo` | `nexus.io.model.body.RespBodyVo` |

两套注解类名完全相同、只是包名不同，而旧的 `com.litongjava:java-model` 可能仍以传递依赖的形式留在 classpath 上 —— 所以**编译期一点错都不会报**，运行期组件扫描直接扫到 0 个类。

**坑 2：`jfinal-aop` 必须用 `nexus.io` 这一支。**

tio-boot 启动时要找 `nexus.io.jfinal.aop.Aop`；如果依赖里放的是 `com.litongjava:jfinal-aop`，日志会打印：

```
AOP class not found: nexus.io.jfinal.aop.Aop
```

注解扫描随之失效（扫描器就在这支 AOP 库里）。**实测：只换注解包、不换 jfinal-aop，接口依然全部 404** —— 两个坑要一起修。修好后启动日志会变成：

```
n.i.j.a.s.DefaultComponentScanner.findClasses:69 - resource:jar:file:.../app.jar!/BOOT-INF/classes!/com/litongjava/tio/web/hello
n.i.t.b.c.TioApplicationContext.run:139 - Scanned classes count: 6
n.i.t.b.c.TioApplicationContext.run:388 - HTTP handler: { "GET /plaintext": ... }
n.i.t.b.c.TioApplicationContext.run:418 - Initialization times (ms): Total: 96, Scan Classes: 9, ... Route: 9
```

顺带把 `tio-core` / `tio-http-*` / `tio-websocket-*` 用 `dependencyManagement` 压到同一个 `${tio.boot.version}`，避免传递依赖混进旧版。

---

## 4. 本地构建与运行

```bash
export JAVA_HOME=/path/to/jdk1.8
mvn clean package -DskipTests -Pproduction
java -jar target/tio-boot-web-benchmarker-1.0.0.jar
curl http://localhost:8080/plaintext
```

---

## 5. 通过轻量部署平台部署

平台地址：`http://192.168.31.97:10055`。平台把可执行的东西分成两类，本工程两边都用上了：

| | 用途 | 本工程里对应什么 |
| --- | --- | --- |
| **项目（Project）** | 构建与部署，可以有 Git 准备阶段与依赖构建 | `tio-boot-web-benchmarker`：拉代码 → Maven 构建 → 发布 → systemd 守护 → 健康检查 |
| **任务（Task）** | 执行某一个作业，没有 Git、没有依赖 | `tio-boot-bench`：wrk / ab 并发矩阵 + 持续压测 |

两者都可以用 **Hook** 免登录触发，适合挂到 CI 或告警系统上。

### 5.1 仓库里的脚本

```
scripts/
├── project.json          项目定义（构建 + 部署），命令脚本在 commands/
├── task.json             任务定义（压测），步骤脚本在 tasks/
├── deploy.ps1            驱动项目：登录 → 创建/更新项目 → 执行 → 跟日志
├── task.ps1              驱动任务：登录 → 创建/更新任务 → 执行 → 跟日志
├── commands/             项目的每一步（同步代码/构建/发布/systemd/健康检查）
└── tasks/                任务的每一步（wrk 矩阵 / ab 矩阵 / 持续压测）
```

```powershell
# 构建并部署靶机
$env:DEPLOY_PASSWORD='***'
powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1

# 跑一次压测（任务）
powershell -ExecutionPolicy Bypass -File scripts\task.ps1
```

### 5.2 为什么把压测做成「任务」而不是「项目」

项目语义是「把代码变成线上服务」，一次执行包含 Git、构建、发布、重启、健康检查；压测只是「跑一次作业」，不产生任何部署产物。混在项目里会导致：每跑一次压测都要重新构建部署一遍，而且压测结果会混进部署历史。分开以后：

- 靶机代码没变时可以只重跑压测，不需要重新构建；
- 压测的历史与靶机的部署历史各自独立，看板上不会互相污染；
- 压测任务同样能被 Hook 触发，方便「每天固定跑一次」这种诉求。

### 5.3 运行配置

发布时会往 `/srv/apps/tio-boot-web-benchmarker/` 写两个文件：

```
app.properties    server.port=10061
my.txt            server.port=10061
```

两个都写是因为不同版本的 tio-boot 读取的外部配置文件名不一致，只放一个很容易出现「配置没生效、进程偷偷监听 8080」。启动日志里 `Server port: 10061` 说明外部配置生效了。

systemd 单元：

```ini
[Service]
WorkingDirectory=/srv/apps/tio-boot-web-benchmarker
ExecStart=/usr/java/jdk1.8.0_411/bin/java -server -Xms2g -Xmx2g -jar /srv/apps/tio-boot-web-benchmarker/app.jar
Restart=always
LimitNOFILE=1048576
```

### 5.4 一个环境上的取舍：Git 准备阶段改成了命令

平台内置的 Git 准备阶段**没有重试**，拉不动就直接中止整次运行。这台服务器到 `github.com` 的连接是间歇性的（实测约一半概率 `SSL connection timeout`），所以项目定义里 `useGit: false`，改由第一步命令 `00-sync-code.sh` 自己 `git fetch`：带 5 次重试，重试都用完就**明确失败** —— 绝不默默拿工作区里的旧代码去构建，否则压测报告上的提交号会是错的。

---

## 6. 压测环境

| 项 | 值 |
| --- | --- |
| 主机 | `MiWiFi-R4A-srv` |
| 操作系统 | Debian GNU/Linux 12 (bookworm)，Linux 6.1.0-53-amd64 |
| CPU | 12th Gen Intel(R) Core(TM) i3-12100F，4 物理核 / **8 逻辑核** |
| 内存 | 15.8 GB |
| JDK | Oracle JDK **1.8.0_411**（`-Xms2g -Xmx2g`） |
| 被测提交 | `05f7238` |
| 压测工具 | wrk 4.1.0-3+b2、ApacheBench 2.3 |
| 部署方式 | 轻量部署平台「项目」构建部署；「任务」执行压测 |
| 客户端 | 与靶机同机（`127.0.0.1`），排除网络变量 |

同机上还跑着 nginx、PostgreSQL、Redis、Elasticsearch、部署平台本身；压测期间它们基本空闲（应用进程独占约 4.4 个核，见 §7.3）。

---

## 7. 压测结果

> 全部数据来自一次任务执行（Task Run #9，提交 `05f7238`），原始输出见 [`docs/benchmark-raw-2026-10-05.log`](docs/benchmark-raw-2026-10-05.log)。

### 7.1 wrk 并发矩阵（8 线程 / 每档 30 秒）

| 接口 | 并发 | QPS | 平均延迟 | P50 | P90 | P99 | 吞吐 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `/plaintext` | 100 | **515,988** | 332.95 µs | 141 µs | 606 µs | 3.68 ms | 72.83 MB/s |
| `/plaintext` | 400 | **549,657** | 1.01 ms | 581 µs | 2.63 ms | 5.33 ms | 77.58 MB/s |
| `/plaintext` | 1000 | **510,694** | 2.43 ms | 1.70 ms | 5.88 ms | 11.70 ms | 72.08 MB/s |
| `/json` | 100 | **511,801** | 494.22 µs | 117 µs | 1.52 ms | 4.23 ms | 82.00 MB/s |
| `/ok` | 100 | **488,411** | 360.19 µs | 133 µs | 0.92 ms | 3.22 ms | 98.28 MB/s |
| `/hello` | 100 | **491,428** | 320.69 µs | 135 µs | 789 µs | 2.74 ms | 97.95 MB/s |

单档请求总数在 1,470 万 ~ 1,651 万之间，30 秒内完成，无 socket 错误。

### 7.2 ab 并发矩阵

| 接口 | 并发 | keep-alive | QPS | 平均耗时 | 失败请求 | 总请求 |
| --- | ---: | :---: | ---: | ---: | ---: | ---: |
| `/plaintext` | 100 | ✔ | 239,914 | 0.417 ms | 0 | 200,000 |
| `/json` | 100 | ✔ | 252,158 | 0.397 ms | 0 | 200,000 |
| `/ok` | 100 | ✔ | 251,024 | 0.398 ms | 0 | 200,000 |
| `/hello` | 100 | ✔ | 253,565 | 0.394 ms | 0 | 200,000 |
| `/plaintext` | 1000 | ✔ | 188,207 | 5.313 ms | 0 | 200,000 |
| `/plaintext` | 1000 | ✘ | 37,278 | 26.825 ms | 0 | 50,000 |

最后一行是不开 keep-alive 的结果：**每个请求都要新建连接，QPS 掉到约 1/5**。这也是为什么本文所有 ab 数据都标了 keep-alive 状态 —— 两种口径混在一起看必然得出错误结论。

### 7.3 持续压测与资源观测（wrk -t8 -c200，120 秒）

```
Running 2m test @ http://127.0.0.1:10061/plaintext
  8 threads and 200 connections
  Latency   716.84us    1.06ms  38.15ms   87.35%
  50%  249.00us   75%  0.95ms   90%  2.09ms   99%  4.64ms
  64984902 requests in 2.00m, 8.96GB read
Requests/sec: 541156.89
Transfer/sec:     76.38MB
```

120 秒内完成 **6,498 万**个请求，平均 **541,157 QPS**，**P99 4.64 ms**。

资源时间线（每 10 秒采样，节选）：

| 时刻 | load average | 内存 |
| --- | --- | --- |
| 14:09:43 | 19.10 / 9.90 / 3.99 | used 3542 MB, avail 12285 MB |
| 14:10:43 | 22.10 / 12.43 / 5.23 | used 3552 MB, avail 12275 MB |
| 14:11:43 | 22.94 / 14.44 / 6.38 | used 3521 MB, avail 12305 MB |

- **延迟没有随时间退化**：整段 120 秒的 P99 仍是 4.64 ms，与 30 秒短测同档（5.33 ms）基本一致。
- **内存完全平稳**：used 在 3520 ~ 3552 MB 之间波动（< 1%），没有持续上涨，GC 跟得上、没有泄漏迹象。
- **应用进程**：RSS 873 MB，44 个线程，CPU 441%（约 4.4 / 8 核）。
- **日志不是瓶颈**：整轮压测下来 `/srv/apps/tio-boot-web-benchmarker/logs` 只有 **12 KB** —— tio-boot 不按请求打 info 日志，压测量的是框架本身而不是磁盘。

---

## 8. 分析

1. **四个接口的差距在预期之内，而且都很小。**`/plaintext`（515,988）到 `/ok`（488,412）只差 **5.6%**，中间夹着一次 fastjson2 序列化（`/json` 511,801）和一次 `RespBodyVo` 包装（`/hello` 491,428）。在这个量级上，**返回体的序列化成本远小于框架的 I/O 与调度成本**，优化重点不在「怎么拼 JSON」。

2. **并发 400 是这台机器的甜点。**`/plaintext` 在 c100 / c400 / c1000 下分别是 515,988 / 549,657 / 510,694 QPS：从 100 涨到 400 还有 6.5% 收益，再往上开始因为排队回落（P99 从 5.33 ms 涨到 11.70 ms）。i3-12100F 只有 4 个物理核，压测端与应用端还要抢同一批核，这个拐点是合理的。

3. **ab 与 wrk 的差距来自工具本身，不是服务端。**同样打 `/plaintext` @ c100，wrk 报 515,988 QPS、ab 报 239,914 QPS。ab 是「一个请求一个线程」的模型，客户端先成为瓶颈；跨工具比较 QPS 没有意义，**同一工具内的横向对比才是有效结论**。

4. **连接复用是数量级差异。**c1000 下开/不开 keep-alive 是 188,207 与 37,278 QPS，差约 **5 倍**。生产环境务必确认前置 nginx 开了 `keepalive`，否则再快的后端也只能发挥一小部分。

5. **稳定性没有代价。**120 秒持续 54 万 QPS，延迟分布与短测一致、内存零增长。对一台 4 物理核小主机、堆只给 2 GB 的 JDK 8 服务来说，这条曲线是平的。

### 与旧版文档数据的对比

旧文档记录的是 `ab -c1000 /ok` ≈ 11,230 QPS、`wrk -t8 -c100 /ok` ≈ 42,154 QPS。本次同口径下：

| 口径 | 旧记录 | 本次 | 备注 |
| --- | ---: | ---: | --- |
| wrk -t8 -c100（/hello 与旧 /ok 口径最接近） | 42,154 | 491,428 | ≈ 11.7× |
| ab -c1000（旧记录未标 keep-alive） | 11,230 | 188,207（keep-alive）/ 37,278（不 keep-alive） | 口径不同 |

**这两组数字不可直接比较**：旧数据没有记录 CPU、内存、JDK 与 keep-alive 状态，机器也不同。本报告的价值在于给出**有完整环境记录、可复现**的新基线，而不是宣称「变快了 11 倍」。

---

## 9. 结论

- tio-boot 2.1.7 在 JDK 8、4 物理核小主机上，`/plaintext` 稳定在 **50 ~ 55 万 QPS**、**P99 < 12 ms**；120 秒持续压测 **54 万 QPS**，延迟与内存都不退化。
- 四个接口的吞吐差异 < 6%，说明瓶颈在 I/O 与调度，不在返回体的组装方式。
- 部署链路上，**「项目」负责构建与部署、「任务」负责执行一次性作业**的分工是有效的：靶机不变时可以只重跑压测，两边历史互不污染，且都能用 Hook 免登录触发。
- 迁移到 `nexus.io` 版 tio-boot 时务必同时改注解包与 `jfinal-aop` 的 groupId（§3.1），否则会出现「服务在跑、接口全 404」这种最难查的故障。

---

> **备注**：以上数据仅代表该次执行、该台机器与该套参数下的结果。换机器、换 JDK、改 JVM 参数或开启 per-request 日志，结论都会变。建议在生产环境做持续、多维度的压测，并结合 `top` / `jstat` / `nmon` 等工具定位瓶颈。
