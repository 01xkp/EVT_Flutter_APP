# ASR 单文件并发基线压测

## 目的

本工具测量现有 ASR 服务对同一长录音的完整文件上传能力，并分开记录：

- 上传请求耗时；
- 转写从提交成功到结果可用的耗时；
- 可选的 AI 总结耗时；
- 完整链路耗时、轮询次数和请求次数。

它不是分片上传实现。当前服务没有上传会话、分片序号、校验、合并完成接口；不得将 M4A 文件按字节拆分后提交为多个独立任务。

## 前置条件

- 仅使用已获准的非敏感测试录音，不使用用户录音或生产数据。
- 测试服务必须使用 HTTPS，并通过 `ASR_API_BASE_URL` 显式提供。
- 使用同一份约 30 分钟的录音、同一服务配置和同一 ASR 引擎完成所有对比。
- 每次运行都指定不同报告路径，避免覆盖先前结果。

## 命令

在项目根目录执行。`--jobs` 是本次总任务数，`--concurrency` 是同时运行的最大任务数，且并发数不能高于总任务数。加上 `--summary` 才会测量总结阶段。

```powershell
$env:ASR_API_BASE_URL = 'https://test-asr.example'

dart run tool/asr_benchmark.dart --audio D:\test-data\recording-30min.m4a --jobs 4 --concurrency 1 --summary --report build\asr-benchmark\c1.json
dart run tool/asr_benchmark.dart --audio D:\test-data\recording-30min.m4a --jobs 4 --concurrency 2 --summary --report build\asr-benchmark\c2.json
dart run tool/asr_benchmark.dart --audio D:\test-data\recording-30min.m4a --jobs 4 --concurrency 4 --summary --report build\asr-benchmark\c4.json
dart run tool/asr_benchmark.dart --audio D:\test-data\recording-30min.m4a --jobs 8 --concurrency 8 --summary --report build\asr-benchmark\c8.json
```

四条命令应依次执行，不要并行启动四组压测。若只想测上传和转写，移除 `--summary`。默认单任务总超时为 45 分钟，可使用 `--job-timeout-minutes <正整数>` 调整。

## 输出和退出码

终端仅输出完成、失败、超时数量、总耗时 P50 和报告文件名。不会输出音频路径、音频字节、转写正文、总结正文或原始服务响应。

| 退出码 | 含义 |
|---:|---|
| `0` | 所有任务完成。 |
| `1` | 至少一个任务失败或超时，报告仍会写入。 |
| `64` | 参数或环境配置无效，未开始网络请求。 |

报告为 JSON，包含每个任务的安全标识、阶段时长、状态、失败类别和请求计数；聚合部分包含总耗时、上传、转写、总结四组的样本数、最小值、平均值、最大值和 P50/P95/P99。

## 对比方法

以各报告的聚合字段进行比较，重点观察：

1. `report.aggregate.upload`：并发增加后上传 P95 是否明显上升。
2. `report.aggregate.transcription`：转写 P50/P95 与排队时间是否随并发增加而增长。
3. `report.aggregate.summary`：总结通常较短，应独立观察，不要混入转写耗时。
4. `failed_count`、`timed_out_count`、每任务 `request_count`：判断服务是否因负载开始失败或轮询放大。

后端提供 `创建会话 -> 上传带序号及校验的分片 -> 合并完成并返回一个 jobId` 后，新增分片传输实现并复用相同报告字段、录音样本、任务数和并发等级，才能进行单文件与分片的直接对比。
