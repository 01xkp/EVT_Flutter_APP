# 真实固件 V1.5 联调说明

## App 协议范围

本 App 仅实现 V1.5 用户态接口：`0x01`、`0x02`、`0x05`、`0x06`、`0x07`、`0x08`、`0x09`、`0x11`、`0x21`、`0x22`、`0x23`、`0x26`，以及独立 WQOTA 服务 `7033/2001/2002`。Factory、UART、`0x03`、`0x04`、`0x0A`、`0x0B`、`0x24`、`0x25`、`0x27`、`0x28` 和业务 `0x31` 不在用户 App 范围内。

## 设备准备

1. V1.5 正式设备广播应同时包含精确名称 `AIPIN_[0-9A-F]{4}`、恰好 8 字节的厂商数据 `A3 89 + BtAddressRaw[6]` 和服务 UUID `0000AF30-0000-1000-8000-00805F9B34FB`。当前 App 为真机排查暂时关闭该严格过滤，仅隐藏名称为空或全为空白的设备；恢复 `filterByV15Advertisement` 后，任一项缺失或格式不符的设备都不会展示。
2. GATT 服务发现后，App 会根据真实 Characteristic 属性决定是否允许操作。基础连接要求：`FB11` 可读、`FA16` 可 Indicate、`FA11` 和 `FA19` 均同时可 Write With Response 和 Indicate。`FB11` 只在认证后按授权范围读取。
3. 认证后 `0x01` 返回的 `ProtocolVersion` 必须为 `3`，否则 App 主动断开。
4. 每个可选入口还需实际存在对应属性：

| 功能 | 必需 GATT 属性 |
| --- | --- |
| 配置与隐私 | `FA12 Write + Indicate`、`FA16 Write + Indicate` |
| 设备录音控制 | `FA17 Write + Indicate` |
| 文件导入与归档确认 | `FF12 Write + Indicate`、`FF13 Write + Notify`、`FF16 Write + Indicate` |
| 实时音频 | `FA12 Write + Indicate`、`FA17 Write + Indicate`、`FA18 Notify` |
| WQOTA | `7033/2001 Write Without Response`、`7033/2002 Notify` |

## 连接和认证流程

1. App 扫描名称非空的广播设备；恢复严格过滤开关后，将按上述三项广播身份过滤。
2. App 连接、发现服务并订阅业务响应特征后进入 `authenticationReady`。此阶段不读取 `FB11`，也不发送 `0x01`、`0x06` 或文件命令。
3. 未绑定设备走 `0x09` 的 `bindRequest -> bindConfirm`；已绑定设备走 `authenticate -> authenticationResult`。每次 `0x09` 都需要由票据服务签发一次性 ticket 和 32 字节 proof key；App 会先按本次帧长校验 ATT MTU，且不生成、不保存、不记录 ticket 或 proof key。
4. 固件要求加密的 GATT 操作会由 Android/iOS 系统触发配对。`flutter_reactive_ble` 不提供显式 bonding 状态或发起 API；若系统返回认证或加密不足，App 提示用户在系统弹窗完成配对后重试，并记录 `pairing_required=true` 诊断日志。
5. `0x09` 成功后，App 请求最大可用 MTU。Android 请求 `ATT_MTU=517`；iOS 由 CoreBluetooth 自动协商，插件返回的是 Write Without Response 的最大负载，App 会加上 3 字节 ATT 头换算为 ATT MTU。换算后的 ATT MTU 小于 `136` 时，App 不会发送 `0x01`，会明确提示 MTU 不足并断开。
6. MTU 准入通过后，App 通过 `FA11` 发送 `0x01`；只有 V3 信息回包后会话才进入 `observable`，随后仅同步 grant scope 允许的状态、配置和文件信息。
7. 固件返回的 grant scope 决定文件、配置、实时音频、OTA 和清除入口是否可用。
8. grant 仅在固件返回的 `session_ttl_seconds` 内有效；断开连接、到期或重新认证失败后，App 会立即撤销本地 scope，必须重新认证。

## ATT MTU 准入

每个协议帧必须在单次 GATT Write 或 Indicate/Notify 内完整传输。App 在 V3 准入和每个可变长度写入前请求并校验 ATT MTU；小于所需值时不会写入半帧，也不会开始接收不可能完整到达的 `0x81`。

| 操作 | 最小 ATT MTU |
| --- | --- |
| `0x01 -> 0x81` V3 准入 | `136`（覆盖 30B 兼容保留区和录音态的最大合法 Indicate） |
| `0x09` BIND/AUTH begin | `35 + ticketLength` |
| `0x09` BIND/AUTH confirm | `35` |
| `0x09` CLEAR confirm | `57 + ticketLength` |
| `0x22` 文件列表 | `31` |
| `0x26/0x01` 文件元数据 | `57` |
| `0x23` 文件读取 | 首段 `26`；断点读取 `32` |
| `0x26/0x02` 归档确认 | `37` |
| WQOTA E2 | `30` |

## 文件流程

1. `0x22` 分页读取列表，始终保留原始 `FileName[17]` 槽位。
2. `0x26/0x01` 读取元数据，`0x23` 按断点下载。
3. App 校验完整文件长度和 CRC-32/ISO-HDLC。
4. App 将音频和元数据发送给归档服务；只有服务返回 `durable: true` 才发送 `0x26/0x02`。
5. `0x26/0x02` 使用同一 `FileName[17]`、大小和 CRC32；设备成功回包的 FileState 必须为 `3` 或 `4`。
6. 认证同步的 `0x02` 会写入当前 UTC，同时保留 `0x01` 中设备报告的 `PowerOff` 和 `ChargingMode`；App 不会把它们重置为默认值，但会将 `AudioStream` 明确写为 `0`，避免异常断开后的实时音频流残留。

## WQOTA 安全边界

1. OTA 页面必须已有 `ota` scope，并且已发现 `2001/2002` 的真实属性。
2. App 在当前连接上请求最大可用 MTU，以实际协商值计算 `E5` 数据块：`N = min(655, ATT_MTU - 20)`。`E2` 的特征值本身为 27B，包含 3B ATT 头后单帧要求 `ATT_MTU >= 30`；未达到时，Android 或 iOS 都会拒绝开始 OTA，不能把帧拆成多次 Write Without Response。
3. App 使用 `E1 -> E2 -> E3 -> E5 -> E6 -> E8 -> reboot -> 0x01`。`E5` 的整帧永远只写入一次 BLE Write Without Response。
4. 当前固件若 `E8 state=0` 会早于异步整镜像验证完成，固件包服务必须返回 `wqota_final_verification_supported: false`。App 会在传输前拒绝该包，不会把该状态当作成功或发送 reboot。
5. 只有目标固件已经修复为“`E8 state=0` 仅在最终 CRC 验证成功后返回”时，固件包服务才可返回 `wqota_final_verification_supported: true`。升级后仍必须重连并由 `0x01` 验证 `expected_business_version`。

## HTTPS 服务配置

生产或真实联调构建使用三个 HTTPS Dart Define。HTTP 地址会被 Provider 视为未配置，不会降级发送安全材料。

```powershell
flutter run `
  --dart-define=DEVICE_TICKET_API_BASE_URL=https://device-api.example.com `
  --dart-define=DEVICE_ARCHIVE_API_BASE_URL=https://archive-api.example.com `
  --dart-define=FIRMWARE_PACKAGE_API_BASE_URL=https://firmware-api.example.com
```

### 票据服务

`POST {DEVICE_TICKET_API_BASE_URL}/v1/device-tickets`

```json
{
  "device_id": "BLE device identifier",
  "action": 32,
  "transaction_id": 42,
  "device_payload_base64": "..."
}
```

```json
{
  "ticket_base64": "...",
  "proof_key_base64": "32-byte Base64 value"
}
```

`action` 是 `0x09` 的 action 值。服务必须将 ticket 绑定到设备、action、transaction_id 和短时有效期；proof key 必须刚好 32 字节。

### 归档服务

`POST {DEVICE_ARCHIVE_API_BASE_URL}/v1/device-archives`，`multipart/form-data`：

| 字段 | 含义 |
| --- | --- |
| `device_id` | BLE device identifier |
| `file_name_slot_base64` | 设备返回的完整 `FileName[17]` |
| `file_size_bytes` | 下载后校验的字节数 |
| `file_crc32` | 下载后校验的 CRC-32/ISO-HDLC，无符号十进制 |
| `recording_start_utc`、`duration_seconds`、`recording_session_id`、`segment_index` | `0x26/0x01` 元数据 |
| `audio` | 校验完成的原始音频文件 |

只有已实际持久化内容后才返回：

```json
{"durable": true, "archive_id": "server receipt"}
```

`durable` 不为 `true` 时 App 保留本地文件且不会发送设备归档确认。

### 固件包服务

`GET {FIRMWARE_PACKAGE_API_BASE_URL}/v1/firmware-packages?device_id={id}`

```json
{
  "vendor_id": 4660,
  "product_id": 22136,
  "image_version": 2,
  "expected_business_version": "1.0.2",
  "payload_crc32": 1438416925,
  "wqota_request_prefix_flags": [112, 7, 110, 193],
  "wqota_response_prefix_flags": [112, 7, 110, 1],
  "wqota_final_verification_supported": true,
  "payload_url": "https://firmware-api.example.com/payloads/aipin-1.0.2.bin"
}
```

`payload_url` 必须为 HTTPS。服务要按目标 VID/PID、镜像版本和实际固件抓包向量返回清单；App 会在设备连接后再次校验 VID/PID、payload CRC、前缀向量和最终业务版本。

## 日志和真机清单

Debug 包的安全日志会保存在应用支持目录的 `logs/aipin-YYYY-MM-DD.log`，单文件最大 5 MiB，保留最近 7 个文件。日志会脱敏 ticket、proof、token、设备 ID 和二进制音频/固件内容。

每个 Android 10/11、Android 12+、iOS 13+ 真机至少验证：扫描过滤、首次连接、服务发现属性、V3 拒绝、绑定或认证、配置写入、录音控制、文件断点续传和归档确认、实时音频启停、断连重连、OTA MTU、OTA 最终校验、重启后版本核验。没有票据服务、归档服务、固件包服务或固件抓包向量时，对应入口必须保持“未配置/不可用”，不能以模拟成功代替。
