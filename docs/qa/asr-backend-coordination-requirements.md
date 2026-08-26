# AIPIN 长录音 ASR 后端配合清单

**目标**：支持 App 对长录音（包括约 30 分钟 M4A/AAC）的可靠上传、断点续传、一次转写、一次 AI 总结，并可与现有完整文件上传基线做同条件压测对比。

**结论**：真实分片上传必须由后端提供上传会话、分片校验、合并和任务创建能力。客户端不能把 M4A 按字节切开后调用现有 `POST /api/jobs`；每一段会被当作独立文件，且多数分段不是可直接解码的音频文件，不能得到同一条完整转写。

## 1. 现有接口与生产需求的差异

当前已联调的测评服务仅提供：

```text
POST /api/jobs                         完整 multipart 文件上传
GET  /api/jobs/{jobId}                 转写状态
GET  /api/jobs/{jobId}/results         转写结果
POST /api/meeting-notes                基于转写生成概要
GET  /api/meeting-notes/{noteId}/generation-tasks/{taskId}
GET  /api/meeting-notes/{noteId}
```

其中 `POST /api/jobs` 强制要求 `reference_files`，属于测评接口。App 目前以空文本附件临时兼容，不能作为生产协议。现有服务也没有上传会话、分片序号、分片校验、补传、合并完成或转写任务删除接口。

## 2. 后端交付优先级

| 优先级 | 后端交付 | App 获得的能力 |
|---|---|---|
| P0 | 稳定 HTTPS 域名、鉴权、仅音频的完整文件提交、稳定状态/结果结构 | 可替代临时测评服务，先完成完整文件基线压测和正式联调 |
| P0 | 明确转写和总结的状态枚举、失败码、进度、删除策略 | App 能可靠后台轮询、恢复和展示失败原因 |
| P1 | 上传会话、分片上传、查询已收分片、完成合并 | 长录音可断点续传，网络切换后无需从头上传 |
| P1 | 合并后只创建一个 ASR 任务，支持幂等和清理 | 一个录音只产生一份转写和总结，不重复扣费或重复计算 |
| P2 | 任务事件推送或回调、服务端性能指标 | 可减少轮询并定位上传、排队、转写各阶段瓶颈 |

## 3. P0：先提供可生产联调的完整文件协议

若 P1 分片接口尚未完成，后端应先提供不依赖参考文本的产品接口，例如：

```text
POST /v1/asr-jobs
Content-Type: multipart/form-data
Authorization: Bearer <token>
Idempotency-Key: <uuid>
```

请求字段：

| 字段 | 必填 | 说明 |
|---|---:|---|
| `audio` | 是 | 一条完整 M4A/AAC 文件；服务端须明确支持的 MIME 与最大大小 |
| `language` | 否 | 默认 `zh`；支持 `auto` 时应明确语言识别行为 |
| `source` | 是 | 固定为 `app_recording`，用于业务统计，不包含用户内容 |
| `duration_ms` | 否 | 客户端测得的时长，仅作校验和诊断，服务端不得盲目信任 |

成功响应应为 `201` 或幂等重放时 `200`：

```json
{
  "job_id": "asr_01J...",
  "status": "queued",
  "created_at": "2026-08-26T10:56:00Z",
  "request_id": "req_01J..."
}
```

不能再要求 `reference_files`、`relative_path`、`variant` 或 `engine` 作为 App 创建总结的业务入参；这些均是测评管线的内部字段。

## 4. P1：分片上传协议

建议后端采用下列版本化接口。分片是原始文件字节的传输分段，服务端按照序号无损拼接回原始 M4A 文件后，才调用 ASR。

### 4.1 创建上传会话

```text
POST /v1/audio-uploads
Authorization: Bearer <token>
Idempotency-Key: <uuid>
```

```json
{
  "file_name": "2026-08-26_105600.m4a",
  "content_type": "audio/mp4",
  "total_bytes": 104857600,
  "file_sha256": "<64 位小写 SHA-256>",
  "duration_ms": 1800000,
  "language": "zh",
  "source": "app_recording"
}
```

响应：

```json
{
  "upload_id": "upl_01J...",
  "status": "uploading",
  "part_size_bytes": 5242880,
  "max_concurrent_parts": 2,
  "expires_at": "2026-08-27T10:56:00Z",
  "request_id": "req_01J..."
}
```

约定：

- `part_size_bytes` 由服务端下发，客户端不得自行猜测；5 MiB 仅为首版推荐值。
- 后端须声明最大文件大小、最大分片数、允许的音频格式，以及会话有效期。
- 同一 `Idempotency-Key` 和相同请求必须返回同一个 `upload_id`；同一个键但请求内容不同应返回 `409`。
- 可以改用对象存储预签名 URL，但仍须保持以下“序号、校验、查询、完成”语义，并由业务 API 验证归属。

### 4.2 上传一个分片

```text
PUT /v1/audio-uploads/{uploadId}/parts/{partNumber}
Authorization: Bearer <token>
Content-Type: application/octet-stream
Content-Length: <part bytes>
X-Part-SHA256: <64 位小写 SHA-256>
Idempotency-Key: <uploadId>-<partNumber>-<sha256>
```

- `partNumber` 从 `1` 开始，连续递增。
- 非最后一片长度必须等于 `part_size_bytes`；最后一片可小于该值。
- 请求体只包含该分片字节，不做 Base64 编码。
- 同一序号、相同哈希的重试返回成功，不能再保存一份或重复计费；同一序号但哈希不同返回 `409`。

成功响应：

```json
{
  "upload_id": "upl_01J...",
  "part_number": 3,
  "received_bytes": 15728640,
  "part_sha256": "<64 位小写 SHA-256>",
  "request_id": "req_01J..."
}
```

### 4.3 查询会话并断点续传

```text
GET /v1/audio-uploads/{uploadId}
Authorization: Bearer <token>
```

```json
{
  "upload_id": "upl_01J...",
  "status": "uploading",
  "part_size_bytes": 5242880,
  "total_bytes": 104857600,
  "received_part_numbers": [1, 2, 3],
  "expires_at": "2026-08-27T10:56:00Z",
  "request_id": "req_01J..."
}
```

客户端在应用重启、网络切换、请求超时后先查询此接口，只重传服务端未确认的分片。后端不能用“连接断开即删除全部分片”的策略，否则分片上传没有断点续传价值。

### 4.4 完成上传、校验合并并创建转写任务

```text
POST /v1/audio-uploads/{uploadId}/complete
Authorization: Bearer <token>
Idempotency-Key: <uuid>
```

```json
{
  "part_count": 20,
  "total_bytes": 104857600,
  "file_sha256": "<创建会话时的 SHA-256>"
}
```

后端必须按以下顺序处理：

1. 验证会话归属、有效期、分片连续性、每片哈希、总大小和整文件哈希。
2. 以二进制原样合并文件，校验合并后的 M4A/AAC 可解析；不在上传完成阶段转码或拆成多个 ASR 任务。
3. 只创建一个 `asr_job_id` 并入队；同一个完成请求重试返回相同任务 ID。
4. 合并或校验失败时保留可恢复的会话与明确错误，除非会话已过期或用户主动删除。

成功响应：

```json
{
  "upload_id": "upl_01J...",
  "status": "completed",
  "asr_job_id": "asr_01J...",
  "asr_status": "queued",
  "request_id": "req_01J..."
}
```

## 5. 转写与总结任务协议

### 5.1 转写状态和结果

```text
GET /v1/asr-jobs/{jobId}
GET /v1/asr-jobs/{jobId}/result
```

状态必须固定为：`queued`、`preprocessing`、`transcribing`、`completed`、`failed`、`cancelled`。其中前三个为非终态，后三个为终态。`progress` 应在 `0` 至 `100` 内且不倒退；不能提供可信进度时返回 `null`，不要伪造百分比。

```json
{
  "job_id": "asr_01J...",
  "status": "transcribing",
  "progress": 42,
  "queued_at": "2026-08-26T10:56:10Z",
  "started_at": "2026-08-26T10:57:01Z",
  "updated_at": "2026-08-26T11:02:36Z",
  "error": null,
  "request_id": "req_01J..."
}
```

已完成时，`GET /result` 返回稳定的产品字段：

```json
{
  "job_id": "asr_01J...",
  "text": "完整转写文本",
  "segments": [
    {"start_ms": 0, "end_ms": 3200, "text": "第一段"}
  ],
  "language": "zh",
  "duration_ms": 1800000,
  "request_id": "req_01J..."
}
```

`segments` 可在首版先不提供，但 `text` 必须完整，不能因服务端分段只返回首段。结果接口在未完成时应返回 `409` 或 `202`，而不是返回不完整正文。

### 5.2 AI 总结

总结应只依赖 `job_id`，不再透出 `relative_path`、`variant`、`engine` 等内部实现字段：

```text
POST /v1/asr-jobs/{jobId}/summaries
GET  /v1/summary-jobs/{summaryJobId}
GET  /v1/summary-jobs/{summaryJobId}/result
```

创建总结请求建议支持 `Idempotency-Key`。同一 `job_id` 未删除的重复提交应返回同一个 `summary_job_id`，避免重复调用模型。

总结结果使用可编辑的 Markdown 正文：

```json
{
  "summary_job_id": "sum_01J...",
  "status": "completed",
  "content_markdown": "## 会议摘要\n\n语音内容整理结果",
  "request_id": "req_01J..."
}
```

首版不应强制添加标签、待办、标题等模型字段；App 当前的总结页面以语音内容的 Markdown 为主，用户可在端内编辑。

## 6. 统一错误、删除与安全要求

| 场景 | HTTP 状态 | 后端返回与客户端动作 |
|---|---:|---|
| 请求参数、总大小或分片序号错误 | `400` / `422` | 返回稳定 `code` 和用户可读 `message`，客户端不自动重试 |
| 未认证或无资源归属 | `401` / `403` | 不泄露资源是否存在，客户端要求重新认证 |
| 会话、任务不存在 | `404` | 客户端停止轮询并提示任务不可用 |
| 会话已过期 | `410` | 返回 `UPLOAD_EXPIRED`，客户端创建新会话并重新上传 |
| 分片冲突、缺片或重复完成参数不一致 | `409` | 返回 `missing_part_numbers` 或冲突原因，客户端先查询会话再恢复 |
| 文件过大或类型不支持 | `413` / `415` | 返回服务端限制，客户端不重复上传 |
| 限流 | `429` | 返回 `Retry-After`，客户端按该时间退避 |
| 瞬态服务异常 | `5xx` | 返回 `request_id`；客户端可有限次数重试上传或轮询 |

所有业务错误使用统一结构：

```json
{
  "code": "UPLOAD_PART_CHECKSUM_MISMATCH",
  "message": "分片校验失败，请重试该分片。",
  "request_id": "req_01J...",
  "retryable": true
}
```

还需要：

- 全程 HTTPS，生产地址稳定；临时 Cloudflare Quick Tunnel 不可进入正式 App 配置。
- 每个会话、分片、任务和结果按登录用户或设备租户做服务端授权，不能只凭 ID 访问。
- 对象存储和数据库加密，日志、埋点和压测报告不得写入音频字节、转写正文或总结正文。
- `DELETE /v1/audio-uploads/{uploadId}` 删除未完成会话及分片；`DELETE /v1/asr-jobs/{jobId}` 取消任务并删除对应原音频、转写和总结。删除须幂等，并明确异步删除完成状态。
- 明确音频、转写、总结、失败会话的保留期限与自动清理策略；研究 Beta 数据须支持试验结束后的自动清理。

## 7. 性能、可观测性与验收配合

后端需在响应中返回 `request_id`，并可按 `request_id` 查询服务端日志。服务端监控至少拆分：上传接收、对象存储、合并校验、排队、ASR 执行、总结执行、失败码和队列深度。不得记录音频或文本正文。

App 当前的临时兜底方式是将超过 5 分钟的录音导出为多个可独立播放的 M4A 文件，逐个创建 ASR 任务后按分段顺序合并转写文本。这不是字节分片上传：无法断点续传，也无法基于多个 `job_id` 生成一份可信的 AI 总结。后端完成 P1 后，应以同一份已授权的约 30 分钟 M4A、同一 ASR 引擎和同一环境，对完整文件、临时多任务方案及正式上传会话分别采集上传、转写、总结的 P50/P95/P99、失败数、超时数、请求数和服务端 `request_id` 对照。

验收通过条件：

1. 网络中断、App 重启后能够查询会话并只补传缺失分片。
2. 重试任意已成功分片和完成请求不会产生重复对象、重复 ASR 任务或重复模型调用。
3. 完成上传后始终只生成一个完整音频对应的一条转写任务。
4. 30 分钟样本在约定并发下能得到完整转写正文，服务端能解释上传、排队、转写和总结分别耗时多少。
5. 删除、过期、鉴权失败和校验失败都有可验证的服务端行为与稳定错误码。
