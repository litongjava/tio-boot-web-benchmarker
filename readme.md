# tio-boot-web-benchmarker

基于 [tio-boot](https://github.com/litongjava/tio-boot) 的最小 Web 服务压测工程：**用最小的接口把框架的吞吐量量出来**。四个接口从「纯字节写回」到「注解路由 + 返回值序列化」，用来把框架开销与业务开销分开看。

本文只讲三件事：**怎么构建、怎么测、测出来什么数据**。

---

## 1. 接口一览

服务默认监听 `8080`。

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

`tio-core` / `tio-http-*` / `tio-websocket-*` 由 `dependencyManagement` 统一压到 `${tio.boot.version}`，避免传递依赖混进旧版本。

---

## 4. 构建

```bash
export JAVA_HOME=/path/to/jdk1.8

# 生产包：spring-boot-maven-plugin repackage 成可执行 fat jar
mvn clean package -DskipTests -Pproduction

# 产物
ls -lh target/tio-boot-web-benchmarker-1.0.0.jar
```

启动（压测时用同一套参数，保证可复现）：

```bash
java -server -Xms2g -Xmx2g -jar target/tio-boot-web-benchmarker-1.0.0.jar

# 确认路由注册成功：启动日志里应有这两个块
#   Scanned classes count: 6
#   HTTP handler: { "GET /plaintext": ..., "GET /json": ..., "GET /hello": ... }
#   controller method mapping { "/ok": ... }
```

改端口用外置配置（与 jar 同目录）：

```
# my.txt
server.port=10061
```

冒烟验证：

```bash
for p in /plaintext /json /hello /ok; do
  printf '%-11s %s\n' "$p" "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:10061$p")"
done
```

---

## 5. 怎么测

### 5.1 测试环境

| 项 | 值 |
| --- | --- |
| 主机 | 自建小主机，Debian GNU/Linux 12 (bookworm)，Linux 6.1.0-53-amd64 |
| CPU | 12th Gen Intel(R) Core(TM) i3-12100F，4 物理核 / **8 逻辑核** |
| 内存 | 15.8 GB |
| 磁盘 | NVMe |
| JDK | Oracle JDK **1.8.0_411**，`-server -Xms2g -Xmx2g` |
| 被测服务 | 单实例，tio-boot 2.1.7，worker 线程 16 |
| 压测工具 | wrk 4.1.0-3+b2、ApacheBench 2.3 |
| 客户端位置 | **与靶机同机**（`127.0.0.1`），排除网络变量 |
| 同机其他负载 | nginx、PostgreSQL、Redis、Elasticsearch（压测期间基本空闲） |

> **环境等级：单机基准（Single-Host Benchmark）。** 压测端与被测端在同一台 4 物理核机器上抢 CPU，且每档只跑一次、没有绑核与隔离。适合做**代码级回归对比**（同一环境内改代码前后谁快），不适合当作对外可比、可认证的性能结论。详见 §7。

### 5.2 测试方法

1. **预热**：每档开测前先打 2 万次请求，让 JIT 编译先热起来。
   *注意*：在 50 万 QPS 的量级上，2 万次只相当于 **约 0.04 秒**的负载量，远不足以证明 JIT 已完全稳定——它只能避免「把冷启动最慢的那一段算进结果」。
2. **短测矩阵（wrk）**：8 线程，并发 100 / 400 / 1000，每档 30 秒，开 `--latency` 拿延迟分布。
   `-c` 是**保持的连接数**，不是用户数，也不是 QPS。
3. **短测矩阵（ab）**：`-k -c100`（四个接口各 20 万请求）、`-k -c1000`（20 万）、以及**不开 keep-alive** 的 `-c1000`（5 万）作为对照。
   *注意*：这几次 ab 的实际耗时只有 **0.79 ~ 1.34 秒**（见 §6.2），本质上更接近**突发测试**，不适合用来判断稳态容量。
4. **持续压测**：`wrk -t8 -c200 -d120s`，同时每 10 秒采样 load average 与内存，观察延迟是否随时间退化。
5. 全程走 `127.0.0.1`，不经过 nginx、不出网卡。

### 5.3 测试命令

```bash
BASE=http://127.0.0.1:10061

# wrk 并发矩阵
for s in plaintext:100 plaintext:400 plaintext:1000 json:100 ok:100 hello:100; do
  ep="${s%%:*}"; c="${s##*:}"
  wrk -t8 -c"$c" -d30s --latency "$BASE/$ep"
done

# ab 并发矩阵（keep-alive）
for ep in plaintext json ok hello; do
  ab -k -n200000 -c100 "$BASE/$ep"
done
ab -k -n200000 -c1000 "$BASE/plaintext"

# 对照：不开 keep-alive（每请求一条新连接）
ab -n50000 -c1000 "$BASE/plaintext"

# 持续压测
wrk -t8 -c200 -d120s --latency "$BASE/plaintext"
```

---

## 6. 测试数据

> 数据来自一次完整执行，原始输出见 [`docs/benchmark-raw-2026-10-05.log`](docs/benchmark-raw-2026-10-05.log)。

### 6.1 wrk 并发矩阵（8 线程 / 每档 30 秒）

| 接口 | 并发 | QPS | 平均延迟 | P50 | P90 | P99 | 吞吐 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `/plaintext` | 100 | **515,988** | 332.95 µs | 141 µs | 606 µs | 3.68 ms | 72.83 MB/s |
| `/plaintext` | 400 | **549,657** | 1.01 ms | 581 µs | 2.63 ms | 5.33 ms | 77.58 MB/s |
| `/plaintext` | 1000 | **510,694** | 2.43 ms | 1.70 ms | 5.88 ms | 11.70 ms | 72.08 MB/s |
| `/json` | 100 | **511,801** | 494.22 µs | 117 µs | 1.52 ms | 4.23 ms | 82.00 MB/s |
| `/ok` | 100 | **488,411** | 360.19 µs | 133 µs | 0.92 ms | 3.22 ms | 98.28 MB/s |
| `/hello` | 100 | **491,428** | 320.69 µs | 135 µs | 789 µs | 2.74 ms | 97.95 MB/s |

单档请求总数在 1,470 万 ~ 1,651 万之间，30 秒内完成，无 socket 错误。

### 6.2 ab 并发矩阵

| 接口 | 并发 | keep-alive | QPS | 平均耗时 | 失败请求 | 总请求 | 实测耗时 |
| --- | ---: | :---: | ---: | ---: | ---: | ---: | ---: |
| `/plaintext` | 100 | ✔ | 239,914 | 0.417 ms | 0 | 200,000 | 0.83 s |
| `/json` | 100 | ✔ | 252,158 | 0.397 ms | 0 | 200,000 | 0.79 s |
| `/ok` | 100 | ✔ | 251,024 | 0.398 ms | 0 | 200,000 | 0.80 s |
| `/hello` | 100 | ✔ | 253,565 | 0.394 ms | 0 | 200,000 | 0.79 s |
| `/plaintext` | 1000 | ✔ | 188,207 | 5.313 ms | 0 | 200,000 | 1.06 s |
| `/plaintext` | 1000 | ✘ | 37,278 | 26.825 ms | 0 | 50,000 | 1.34 s |

**注意最后一列**：ab 这几档全都只跑了 1 秒左右。它们验证的是「短突发下服务端顶得住」，**不能当作稳态容量**；判断稳态要看 §6.3 的 120 秒持续压测。

全部 6 档的 `Failed requests` 都是 **0**，wrk 也没有报告任何 socket 错误（原始日志里没有 `Socket errors` / `Non-2xx` 段落）。不过这只说明「请求成功返回」，**没有校验过响应内容**。

### 6.3 持续压测与资源观测（wrk -t8 -c200，120 秒）

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

资源时间线（每 10 秒采样）：

| 时刻 | load average | 内存 |
| --- | --- | --- |
| +10s | 19.10 / 9.90 / 3.99 | used 3542 MB, avail 12285 MB |
| +70s | 22.10 / 12.43 / 5.23 | used 3552 MB, avail 12275 MB |
| +120s | 22.94 / 14.44 / 6.38 | used 3521 MB, avail 12305 MB |

- **延迟没有随时间退化**：整段 120 秒的 P99 仍是 4.64 ms，与 30 秒短测同档（5.33 ms）基本一致。
- **内存完全平稳**：used 在 3520 ~ 3552 MB 之间波动（< 1%），没有持续上涨，GC 跟得上、没有泄漏迹象。
  *注意*：RSS 与 `free` 都是进程/系统的整体口径，**不等于 Java 堆使用量**；要看堆与 GC 停顿需要 `jstat` 或 GC 日志。
- **应用进程**：RSS 873 MB，44 个线程，CPU **441%**。
  *注意*：按 Linux 的进程 CPU 口径，441% ≈ 占用了 **4.41 个逻辑 CPU 的时间**，不能据此断言「4 个物理核已跑满」或「还有 45% 余量」。
- **日志不是瓶颈**：整轮压测下来日志目录只有 **12 KB** —— tio-boot 不按请求打 info 日志，测的是框架本身而不是磁盘。

### 6.4 数据解读

1. **四个接口的差距很小。**`/plaintext`（515,988）到 `/ok`（488,412）只差 **5.6%**，中间夹着一次 fastjson2 序列化（`/json` 511,801）和一次 `RespBodyVo` 包装（`/hello` 491,428）。在这个量级上，**返回体的序列化成本远小于框架的 I/O 与调度成本**，优化重点不在「怎么拼 JSON」。

2. **并发 400 是这台机器的甜点。**c100 / c400 / c1000 分别是 515,988 / 549,657 / 510,694 QPS：从 100 涨到 400 还有 6.5% 收益，再往上因为排队回落（P99 从 5.33 ms 涨到 11.70 ms）。

3. **ab 与 wrk 的差距来自工具本身，不是服务端。**同样打 `/plaintext` @ c100，wrk 报 515,988、ab 报 239,914。ab 是「一个请求一个线程」的模型，客户端先成为瓶颈。**跨工具比 QPS 没有意义，同一工具内的横向对比才有效**。

4. **连接复用是数量级差异。**c1000 下开/不开 keep-alive 是 188,207 与 37,278 QPS，差约 **5 倍**。生产环境务必确认前置 nginx 开了 `keepalive`，否则再快的后端也只能发挥一小部分。

5. **稳定性没有代价。**120 秒持续 54 万 QPS，延迟分布与短测一致、内存零增长。

---

## 7. 这个环境的等级与结论边界

### 7.1 等级：有组织的**单机探索性压测**

按「结果是否可复现、瓶颈是否可归因、结论能外推到多远」来分，压测环境大致可以这样排：

| 档位 | 特征 | 能支撑的结论 |
| --- | --- | --- |
| 开发机冒烟自测 | 随手跑，配置与错误都不记录 | 只说明「跑起来了」 |
| **有组织的探索性压测（本环境）** | 配置清楚、有并发梯度、有预热和短时持续测试；但**压测端与被测端同机**、无重复实验、无瓶颈证据 | 特定配置下的**观测值**；同环境内的代码级回归对比 |
| 可复现的受控基准 | 压测端不构成瓶颈、干扰受控、多轮重复取中位数、校验响应、两端资源指标齐全 | 指定配置与负载下的**容量**与横向对比结论 |
| 生产代表性容量验证 | 再叠加真实链路、业务混合、数据规模、长时间运行与故障场景 | 生产承载能力（以延迟与错误率目标定义） |
| 标准化可审计基准 | 遵循公开基准规范并可被独立复核（TechEmpower / SPEC 一类） | 跨框架、可认证的横向对比 |

**本环境位于第 2 档**。它明显高于「冒烟自测」：硬件、运行时、参数都有记录，有并发梯度、连接模式对照和 120 秒持续压测。但它**回答不了两个关键问题**：换个时间重复跑是否还是这个数？瓶颈到底在客户端还是在服务端？

> 换个分级口径（例如把「单机基准」单列一档）会把它叫作 L1，但落点是一样的——**同一个台阶，只是编号不同**。

### 7.2 偏差方向：不是简单的「偏高」或「偏低」

这一点容易被忽略：本环境里同时存在让数字**偏悲观**和**偏乐观**的因素，净方向不确定。

| 因素 | 方向 | 说明 |
| --- | --- | --- |
| 压测端与被测端同机抢 CPU | **偏悲观** | 负载发生器吃掉了一部分本该给 JVM 的算力 |
| 每档只跑一次、无重复 | **双向** | 单次抖动可能偏高也可能偏低 |
| 走 loopback、无网卡无 nginx | **偏乐观** | 省掉了真实链路与前置代理的成本 |
| 接口极小、无业务逻辑 | **偏乐观** | 没有数据库、鉴权、TLS 等真实开销 |
| 固定连接数的负载模型 | **偏乐观（对尾延迟）** | 服务端变慢时连接会少发请求，尾延迟不像真实到达模型那样被放大 |
| 同机 nginx/PG/Redis/ES 干扰 | **偏悲观** | 压测期间它们基本空闲，但仍有调度与缓存占用 |
| 没有 GC 日志与逐核数据 | 无固定方向 | 只是让原因**无法定位**，不能归因到具体瓶颈 |

所以正确的读法是：**这些数字不能按 CPU 比例外推到「压测端拆走之后服务端能到多少」**——方向相反的两类误差混在一起，净效应未知。

### 7.3 结论边界

**能支撑：**
- tio-boot 2.1.7 在 JDK 8 上处理这几个接口的**量级**：单机 50 万 QPS 上下、P99 十几毫秒以内；
- 四个接口之间的**相对**差异（< 6%，说明瓶颈在 I/O 与调度）；
- keep-alive 与不 keep-alive 的**相对**差距（约 5 倍）；
- 同一台机器上**改代码前后**的回归对比。

**不能支撑：**
- 「服务端的极限就是 55 万 QPS」——压测端同机，测到的是**两端一起**的能力；
- 「生产能稳定承载 54 万 QPS、P99 < 5 ms」——生产要多一跳 nginx、要出网卡、有真实业务逻辑；
- 「tio-boot 比框架 X 快 N 倍」——没有受控的对照实验；
- 「c400 就是最佳并发」——单轮结果分不清是真实拐点还是波动；
- 「没有 GC 问题或内存泄漏」——120 秒的窗口与 RSS 摘要都不足以证明；
- 绝对值的精确复现——没有多轮取中位数，同档换个时间跑会有百分比级波动。

### 7.4 想升到「可复现的受控基准」的最小改动

按性价比排序：

1. **保存完整输出并校验响应内容**：记录状态码、超时、连接错误，并单独校验返回体；固定代码版本与命令。成本最低，先做这个。
2. **充分预热 + 多轮重复**：预热 30~60 秒，每档正式测 60~120 秒、**至少 5 轮、交错并发档顺序**，报告中位数与范围（主结果不取最好一次）。这一条直接解决「重复跑是否还是这个数」。
3. **同步采集两端与系统指标**：每秒记录应用与压测端的 CPU、逐核利用率、上下文切换、内存、频率与温度，并补 GC 日志。10 秒一次的 load average 判断不了瓶颈。
4. **把压测端挪到另一台机器并验证其余量**：这是报告「整台服务器容量」最关键的一步。
   *坑*：换异机**不保证 QPS 上升**——新引入的网卡和链路可能成为新瓶颈，带宽预算要把请求行、响应头、响应体与协议开销一起算，不能只用「13 字节 × QPS」。
5. **安排受控窗口**：暂停无关服务与定时任务，固定电源策略并记录状态。
6. **补一条吞吐—延迟—错误率曲线**：在中低负载、接近饱和与过载处各测一次；若要宣称 P99 保障，再补**固定到达速率**的测试。

**升级不需要先买服务器、换 JDK 或画火焰图。** 最有价值的投入是让结果可重复、成功率可确认、瓶颈可识别。做到这些，这台小主机完全可以产出受控基准级的数据；在那之前，54 万 QPS 应当保留为一个**条件明确的本地观测值**。

---

## 8. 结论

- tio-boot 2.1.7 在 JDK 8、4 物理核小主机（探索性单机压测）上，`/plaintext` 观测到 **50 ~ 55 万 QPS**、**P99 < 12 ms**；120 秒持续压测 **54 万 QPS**，延迟与内存都不退化。
- 四个接口的吞吐差异 < 6%，说明瓶颈在 I/O 与调度，不在返回体的组装方式。
- 连接复用（keep-alive）在 c1000 下带来约 **5 倍**差距，是部署形态里最值得确认的一项。
- 这些是**条件明确的本地观测值**，不是服务端容量上限，也不是可对外认证的基准；要作为对外结论使用，请先按 §7.4 升级环境。

---

> **备注**：以上数据仅代表该次执行、该台机器与该套参数下的结果。换机器、换 JDK、改 JVM 参数或开启 per-request 日志，结论都会变。
>
> 本文 §5.2 与 §7 的偏差分析经另一个模型（Codex CLI，只读沙箱）独立复核后补全：它指出 ab 实际只跑了约 1 秒（属突发测试而非稳态）、2 万次预热在 50 万 QPS 下只相当于约 0.04 秒、441% CPU 不能读作「4 核跑满」，以及「换异机不保证 QPS 上升」。这些意见已反映在上文；原始结论（接口相对差异、keep-alive 差距、稳定性）未变。
