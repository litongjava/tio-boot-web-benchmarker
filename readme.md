# tio-boot-web-benchmarker

## 1. 测试概述

本文档主要通过 ApacheBench (ab) 和 wrk 两种工具，对基于 [tio-boot][^1] 搭建的本地服务器进行高并发访问压力测试，以评估其在大规模请求场景下的性能表现和稳定性。

---

## 2. 环境与测试代码

### 2.1 环境信息

- **服务器软件**：t-io
- **服务器主机名**：localhost
- **服务器端口**：80
- **操作系统**：Linux
- **JDK**：1.8
- **测试工具**：
  - ApacheBench (ab)
  - wrk

### 2.2 关键依赖

```xml
<dependencies>
  <dependency>
    <groupId>com.litongjava</groupId>
    <artifactId>tio-boot</artifactId>
    <version>${tio.boot.version}</version>
  </dependency>
  <dependency>
    <groupId>org.projectlombok</groupId>
    <artifactId>lombok</artifactId>
    <version>${lombok-version}</version>
    <scope>provided</scope>
  </dependency>
  <dependency>
    <groupId>com.alibaba.fastjson2</groupId>
    <artifactId>fastjson2</artifactId>
    <version>2.0.12</version>
  </dependency>
  <dependency>
    <groupId>com.litongjava</groupId>
    <artifactId>jfinal-aop</artifactId>
    <version>1.3.4</version>
  </dependency>
  <dependency>
    <groupId>com.litongjava</groupId>
    <artifactId>hotswap-classloader</artifactId>
    <version>${hotswap-classloader.version}</version>
  </dependency>
</dependencies>
```

### 2.3 启动类与测试接口

#### 启动类

```java
package com.litongjava.tio.web.hello;

import com.litongjava.annotation.AComponentScan;
import com.litongjava.tio.boot.TioApplication;

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

#### 控制器

```java
package com.litongjava.tio.web.hello.controller;

import com.litongjava.annotation.RequestPath;
import com.litongjava.model.body.RespBodyVo;

@RequestPath
public class OkController {

  @RequestPath("/ok")
  public RespBodyVo ok() {
    return RespBodyVo.ok();
  }
}
```

---

## 3. ApacheBench 压力测试

### 3.1 测试命令

```bash
ab -c1000 -n10000000 http://localhost/ok
```

- **并发级别（-c）**：1000
- **请求总数（-n）**：10,000,000
- **目标 URL**：`http://localhost/ok`

### 3.2 测试结果

以下结果与实际测试日志保持一致：

```
Time taken for tests:   890.415 seconds
Complete requests:      10000000
Failed requests:        0
Total transferred:      1750000000 bytes
HTML transferred:       430000000 bytes
Requests per second:    11230.72 [#/sec] (mean)
Time per request:       89.042 [ms] (mean)
Time per request:       0.089 [ms] (mean, across all concurrent requests)
Transfer rate:          1919.31 [Kbytes/sec] received

Connection Times (ms)
              min  mean[+/-sd] median   max
Connect:        0   48 133.9     32    7099
Processing:     2   41  14.7     40    3373
Waiting:        0   30  14.4     28    3364
Total:          4   89 137.1     73    7145

Percentage of the requests served within a certain time (ms)
  50%     73
  66%     77
  75%     79
  80%     80
  90%     85
  95%     88
  98%     95
  99%   1087
 100%   7145 (longest request)
```

#### 3.2.1 关键指标

- **测试耗时**：**890.415 秒**
- **完成请求数**：10,000,000
- **失败请求数**：0
- **平均每秒请求数 (QPS)**：**11,230.72 [#/sec]**
- **每个请求平均耗时**：**89.042 ms**
- **单个请求平均耗时（并发含义）**：**0.089 ms**
- **传输速率**：**1919.31 Kbytes/sec**

#### 3.2.2 分析

1. **吞吐量**：在 1000 并发、共 10,000,000 个请求场景下，平均 QPS 达到 11,230+，无失败请求，展示了较强的并发处理能力。
2. **响应速度**：大多数请求能在 100 ms 以内完成，说明在高负载下仍保持了较好的响应速度。
3. **波动情况**：标准偏差相对较大（特别是 `Connect` 和 `Total` 阶段），有少量请求出现较高延迟（长尾效应），需要关注网络抖动或系统资源争用等因素。
4. **可优化方向**：
   - **配置优化**：如增大线程池、网络参数调优等。
   - **系统监控**：CPU、内存、带宽等可能成为瓶颈，需要配合监控工具（如 top、nmon、jvisualvm 等）来定位问题。
   - **长时间稳定性测试**：若需处理持续高负载的场景，仍需做更多持续性压测。

---

## 4. wrk 压力测试

### 4.1 测试命令

```bash
wrk -t8 -c100 -d30s http://localhost/ok
```

- **线程数（-t）**：8
- **并发连接数（-c）**：100
- **压测时长（-d）**：30 秒

### 4.2 测试结果

```
Running 30s test @ http://localhost/ok
  8 threads and 100 connections
  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency     5.52ms   12.28ms 422.98ms   92.53%
    Req/Sec     5.31k     0.97k   14.37k    77.97%
  1,268,823 requests in 30.10s, 211.76MB read
Requests/sec:  42154.00
Transfer/sec:      7.04MB
```

#### 4.2.1 关键指标

- **测试时长**：30 秒
- **总请求数**：1,268,823
- **平均请求速率**：42,154 [#/sec]
- **平均延迟**：5.52 ms
- **吞吐量（Transfer/sec）**：7.04 MB/s

#### 4.2.2 分析

1. **QPS 表现**：在 8 线程、100 并发连接下，QPS 超过 42k，展现了更高的吞吐能力。
2. **延迟表现**：平均延迟约 5.52 ms，说明对于当前并发压力，服务器仍能快速响应。
3. **可进一步提升的方向**：
   - **线程数与连接数调优**：结合实际硬件资源、网络环境，在 wrk 的参数上可进行不同组合测试。
   - **应用层面优化**：缓存、业务逻辑、序列化方式等都会影响处理效率。

---

## 5. 总结与建议

1. **高并发场景下的出色性能**

   - 从 `ab` 的 1000 并发、10,000,000 请求，到 `wrk` 的 8 线程、100 并发，都显示出较好的吞吐量和稳定性；多数请求在较短时间内完成。

---

> **备注**：以上测试数据仅代表在特定环境与参数配置下的结果，不同机器性能、网络环境以及操作系统配置都会对测试结果产生影响。建议在生产环境中进行更全面、持续的多维度压力测试，结合指标监控与调优，才能获得最优的性能表现。
