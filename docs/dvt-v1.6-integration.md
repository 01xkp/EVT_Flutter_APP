# AIPIN · DVT V1.6 App 与固件联调

本分支：`dvt`，基于 `evt@9e1841c`。协议依据：`智能吊坠设备-App通讯协议_安全码简化与修订标注版_V1.6_20260914修正版.html`。沿用应用版本 0.0.2+3；不修改固件 ProtocolVersion=3 的线上含义，继续只记录版本值、不按值拦截。

## 1. 范围与入口

| 功能 | 页面入口 | App 的处理 | 固件交互 |
| --- | --- | --- | --- |
| 发现与连接 | 设备 → 查找设备 | 隐藏无名称广播，按当前平台连接 ID 去重；用户选中后严格发现 GATT | GAP / GATT |
| 回连 | 历史设备 | 前台扫描到已记录设备后按退避策略回连；主动断开不立即回连 | 优先广播物理地址，其次平台 ID |
| 认证 | 设备详情 → 认证设备 | 输入 6 位可打印文本或 12 位十六进制，均转换为原始 6B；文本保留大小写，十六进制不发送 ASCII 12B | FA19，09 Action=00 |
| 首次绑定 | 设备详情 → 首次绑定设备 | 发 Action=01，等待用户按设备按键；成功后同连接再发 Action=00 | FA19，09 / 89 |
| 状态与配置 | 设备详情 | 刷新设备身份、固件版本、电量、存储、UTC、状态与隐私默认时长；设置录音授权和隐私时长 | 01 / 02 / 05 / 06 / 11 / 可选21 |
| 设备录音控制 | 设备详情 → 设备录音 | 开始、暂停、继续、结束；等待符合目标状态的 87，不能把 GATT 写成功当成业务成功 | FA17，07 / 87 |
| 文件列表 | 设备录音文件 | 逐页读取，Count=0 才结束；重复文件键报错 | FF12，22 / A2 |
| 元数据 | 每个文件 → 元数据 | 显示原始文件键、UTC、会话号、段号、时钟质量、修正值、大小、CRC32、状态 | FF16，26 Sub=01 / A6 |
| 保存到 App | 每个文件 → 保存到 App | 先读元数据，再连续下载；按偏移落盘，持久化断点；EOF、大小和 CRC32 都通过后加入本地录音 | FF13，23 / A3 Notify |
| 归档并释放 | 每个文件 → 归档并释放 | 确认弹窗 → 本地完整性复核 → 云端可靠保存回执 → 设备归档确认 | FF16，26 Sub=02 / A6 |
| 受控解绑 | 设备详情 → 设备管理 → 解绑设备 | 预检空闲状态、全部文件归档状态；发 Action=02，等待最终结果；超时按未知结果处理 | FA19，09 / 89 |
| 实时音频验证 | 设备详情 → DVT 实时音频验证 | 电量/授权/隐私/任务互斥检查 → CCC → 完整配置 AudioStream=1 → 按需开始录音 → 字节统计 | FA18，88 Notify |
| OTA | 设备详情 → DVT 固件升级 | HTTPS 获取清单及镜像 → SHA256/CRC32 → 设备准入 → 窗口传输 → 最终校验 → 重启 → 重连认证核验版本 | 独立7033/2001/2002 WQOTA |
| 日志 | 设备详情右上角 | 实时显示、保存、导出；查看页面提供实际存储地址 | App/原生/协议层共同记录 |

保留原有主题与页面布局。没有恢复手机麦克风录音或 AI 服务。禁止 `03/04/24/25/27/28/31`、V2/F2 认证及 Factory/UART；不引入私有蓝牙设置接口。

## 2. GATT 订阅与收发顺序

业务 UUID 使用 `0000xxxx-1212-EFDE-1523-785FEABCD123`。WQOTA 使用标准蓝牙 UUID 基址 `0000xxxx-0000-1000-8000-00805F9B34FB`。

| 服务 | 特征 | 操作 | 订阅时点 / 响应 |
| --- | --- | --- | --- |
| FA10 | FA11 | Write + Indicate | 认证前订阅；01→81 |
| FA10 | FA19 | Write + Indicate | 认证前订阅；09→89 |
| FA10 | FA12 | Read + Write + Indicate | Action=00 成功后；02→82，Read 返回 UTC |
| FA10 | FA15 | Write + Indicate | 认证后；05→85 存储 |
| FA10 | FA16 | Write + Indicate | 认证后；06→86 状态及配置 |
| FA10 | FA17 | Write + Indicate | 认证后；07→87，含设备主动录音状态 |
| FB10 | FB11 | Read + Indicate | 认证后；91 电量 |
| FF10 | FF12 | Write + Indicate | 认证后；22→A2 列表 |
| FF10 | FF13 | Write + Notify | 认证后；23→A3 文件流 |
| FF10 | FF16 | Write + Indicate | DVT 必需；认证后订阅；26→A6 |
| FF10 | FF11 | 可选 Write + Indicate | 21→A1，仅兼容文件数量 |
| FA10 | FA18 | 可选 Notify | 进入音频验证按需订阅；只收88，不向FA18写请求 |
| 7033 | 2001 | 可选 Write Without Response | 同连接已认证才允许 WQOTA 写入 |
| 7033 | 2002 | 可选 Notify | 进入 OTA 后先订阅并等待系统确认 |

App 分层：页面触发 → Session 权限/状态/MTU检查 → 单业务命令队列 → BLE transport → Android/iOS 原生。回程：原生回调 → 按特征独立组帧 → 长度/CRC校验 → CMD/SubCmd匹配 → 业务校验 → 状态/页面更新。FF16 共用现有业务命令队列，不新建相互竞争的业务通道；WQOTA 完全独立。

认证前仅 FA11/FA19 开启 CCC。GATT 连接成功、CCC 成功均不代表认证成功。每次实际写入前再次校验连接代次和授权，防止排队期间断连后仍发送旧请求。断连清理等待者、订阅、音频及 OTA 客户端。

## 3. 文件元数据与归档字节

业务帧：`ED | Length:u16LE | CMD | Content | CRC16:u16LE`。Length=CMD+Content+CRC，CRC16/CCITT-FALSE 覆盖 CMD+Content。所有业务整数为小端；固定槽没有隐式对齐字节。

### GET_META

请求：`26 | 01 | 11 | FileName[17]`。其中 01 为子命令，11 为数据长度 17。FileName 是从 22 返回的不透明固定槽，最多16字节ASCII及零终止，其余补零；禁止重命名、重编码或重建发送槽。

成功响应：`A6 | 01 | 00 | 29 | Data[41]`。下表偏移从 Data 起算，不包含 CMD/SubCmd/Result/DataLength。

| 偏移 | 长度 | 字段 |
| --- | --- | --- |
| 0 | 17 | FileName，必须与请求一致 |
| 17 | 4 | StartUtc，u32LE UTC Unix 秒 |
| 21 | 4 | RecordingSessionId，非零u32LE |
| 25 | 2 | SegmentIndex，u16LE |
| 27 | 1 | ClockQuality：0未校准、1 App校准、2 RTC |
| 28 | 4 | UtcCorrectionMs，s32LE |
| 32 | 4 | FileSize，u32LE |
| 36 | 4 | FileCrc32，u32LE |
| 40 | 1 | FileState |

V1.6 不含 DurationS，不能按 V1.5 的45B解码。完整响应50B，ATT MTU最低53。实际会话因81长身份回包还需满足认证前99、认证后136的要求。

完整 GET_META 请求示例：

```text
ED 16 00 26 01 11 36 61 37 62 65 37 30 34 5F 30 30 31 2E 6F 67 67 00 C5 36
```

### 下载

先读取 GET_META。23 的请求 Content 为17B文件槽，或23B的`FileName[17] + Offset:u32LE + ChunkSize:u16LE`。响应 CMD 固定 A3；数据为`Offset:u32LE + DataLength:u16LE + Data[N]`。D=0 才是 EOF。

每块不超过 `min(480, ATT_MTU-32)`。只允许一条活动文件流。App 只接受连续偏移，以实际落盘数据为断点，整文件 CRC32 与元数据匹配才成功。CRC32/ISO-HDLC 测试值：ASCII `123456789` → `CBF43926`。未完成/CRC不符时不归档，不删除设备源文件。

### ARCHIVE_CONFIRM

请求 Content：`02 | 1A | FileName[17] | Size:u32LE | CRC32:u32LE | 01`，共28B。最后01表示云端归档成功；不能用于本地保存或排队成功。

成功响应：`A6 | 02 | 00 | 01 | FileState`。

- `06 DELETE`：设备源文件已删除。完整帧 `ED 07 00 A6 02 00 01 06 72 48`。
- `04 RECLAIMABLE`：归档接受，但设备物理删除失败，留待设备回收。完整帧 `ED 07 00 A6 02 00 01 04 30 68`。
- `03 DEVICE_CONFIRMED`：旧状态，不能当作 V1.6 释放成功。

相同文件槽、大小、CRC三元组重试必须幂等。App 对26使用5秒业务等待，不盲目重传；超时关闭含糊连接，重新认证后恢复处理。回包丢失不等于设备未删除，不能声称源文件必然保留。

本地 CRC 校验通过后，App 持久化元数据、原始三元组和文件相对路径。文件页的“本地待归档确认 → 继续归档”独立于设备文件列表显示；App 重启或设备已删除源文件后仍可操作。恢复时再次检查本地文件大小/CRC，确认云端可靠保存后重发原三元组，不要求再次 GET_META 或下载。只有收到状态4/6后才清除恢复记录。本地文件缺失或被修改时拒绝确认，并记录具体原因。

## 4. 云端归档对接边界

固件 V1.6 没有规定 HTTP 路由。本 App 提供可注入的 `DvtArchiveGateway`，默认失败关闭；用户仍能校验保存本地录音。HTTPS取安全码服务也仍未接入，联调阶段由操作者手动输入真实安全码。

可选 `HttpsDvtArchiveGateway` 是本项目约定的后端适配格式，后端必须明确实现后才能配置 `DVT_ARCHIVE_URL`。不是声称现有服务器已经支持。

请求：HTTPS POST；Content-Type `application/octet-stream`；body 为录音原文件；`X-DVT-File-Metadata` 为 UTF-8 JSON 的 base64url，包含 device_id、name_slot 数组、file_size、crc32、recording_session_id、segment_index。重试须按 device_id+文件三元组去重，不能创建重复归档。

服务端必须校验上传的实际长度和 CRC32，持久化音频及元数据后，才返回 2xx 和以下 JSON：

```json
{"durable":true,"archive_id":"真实存储记录ID","device_id":"与请求一致","name_slot":[17个字节],"file_size":12345,"crc32":123456789}
```

示意中的“17个字节”须替换成真实数字数组。App核对所有字段，任何不符、非2xx、超时或缺少durable=true都不发设备归档确认。云端URL和凭据不写日志。上传总体上限5分钟，响应上限64KB；不自动跟随重定向，不降低iOS ATS。

## 5. 实时音频验证

在已认证设备详情打开“DVT 实时音频验证”，点击开始。App读取电量、授权/隐私/同步状态和录音状态。电量0且未充电时不开始；这只是 App 验证策略，协议没有固定百分比门槛。

FA18 CCC确认后写完整12B配置，AudioStream=1；若设备原来停止，再发07=1并等待正确87。页面只统计校验通过的88 Content字节、帧数和平均吞吐，最多每秒更新统计。没有音频序号，不能推算丢包率，也不伪造应用层ACK。

停止/返回时发完整02 AudioStream=0；只结束本验证启动的录音，原本就在进行的录音继续。关闭无法确认时主动断连，确保连接的音频输出不继续。订阅报错/断连向页面报告失败。

V1.6规定480B固定音频块，未承诺随MTU缩小。当前按完整486B业务帧要求ATT MTU≥489，不足时明确拒绝开启，保留其他功能。Android和iOS都使用实际系统返回值；iOS无法强行协商到489。若固件另提供跨Notify分片实现，需要双方冻结相应约定和测试向量后再放开此限制。

## 6. WQOTA 完整流程

OTA不使用ED帧，不经业务31。线上帧：`prefix[3] | flags[1] | opcode | DataLen:u16BE | Data | 33`；字段大端；块CRC32和镜像CRC32也大端。目标prefix/flags必须来自真实抓包，不能按C位域猜字节序。

1. 用户输入HTTPS升级清单地址，App下载清单和payload，核对SHA256、CRC32、VID/PID范围和抓包声明。清单≤64KB，镜像≤32MiB。
2. 同一连接已通过09 Action=00，设备录音和同步处于空闲。独立订阅2002并等待原生CCC。
3. 02 GET_DEVICE_INFO，检查返回TLV及镜像VID/PID。
4. E1必须返回offset=0、len=18；E2发送sn+18B镜像头。只有status=0且result=03允许继续。
5. E3使用不同SN，按设备返回的offset/len窗口开始或恢复。文件偏移包含18B镜像头。
6. E5单次BLE Write Without Response发送完整一帧；每块数据最多`min(655, ATT_MTU-20)`。窗口内分块，填满后等待下一窗口；严格核对SN、下一偏移、长度与delay_ms。
7. 窗口结束后发E6，再轮询E8。E6不代表校验通过。只有目标固件明确修复异步校验问题后，才允许把E8=0作为已校验；否则清单校验即阻止发送镜像。
8. 最终校验通过后03 type=0提交重启。页面显示等待重连，不显示最终成功。
9. 返回设备页，重连并重新认证。再次打开升级页面、加载同一清单，点击“重连后核验版本”。App核对持久化的镜像身份和业务01的软件版本，一致后清除升级检查点并显示完成。
10. 用户取消时等待当前请求结束再发E4；不能与E5并发。断连/超时保留断点；不会用取消指令破坏可恢复状态。12秒接收等待或本地写失败都有明确日志。

升级清单是本 App 的文件分发格式，不改变固件线上协议。示例模板字段如下，所有值必须由固件团队提供真实值：

```text
payload_url: HTTPS payload地址（不含18B镜像头）
payload_sha256: 64位十六进制SHA256
payload_crc32: CRC32十进制整数
vid / pid / version: u16整数
expected_business_version: 重启后01应返回的ASCII软件版本
wire_format.capture_id: 固件版本及抓包记录编号
wire_format.request_prefix_flags: 真实4字节数组
wire_format.response_prefix_flags: 真实4字节数组
e8_final_verification_supported: 固件确已保证最终CRC完成才返回0时才为true
```

这些声明需要固件提供依据；App无法单靠清单证明固件已修复E8语义。

## 7. 平台与异常联调

解绑前将设备身份及“待恢复”标记写入本地，不保存安全码。写入失败则不发送解绑；设备确认成功后才清除标记。App 重启后重新连接同一设备会恢复 Action=02 流程，需要操作者再次提供同一安全码，不会误授予普通业务权限。

| 项目 | Android | iOS |
| --- | --- | --- |
| 连接身份 | 通常为MAC，仍以插件连接ID为准 | CoreBluetooth UUID，不是MAC |
| 扫描权限 | 6–11定位；12+附近设备 | Bluetooth权限说明 |
| 开启蓝牙 | 按系统授权流程 | 用户在系统中开启，无私有API |
| CCC | 明确区分0100 Notify / 0200 Indicate | 检查属性并等待CoreBluetooth订阅回调；属性冲突不猜测 |
| 文件MTU | 使用系统实际值分块 | 使用系统实际值分块 |
| OTA MTU | E2最低30，E5按实际值计算 | 不假定可设置到247/517 |
| 后台 | 沿用停止主动扫描/回连策略，不承诺进程永生 | bluetooth-central不代表锁屏/杀进程无限运行 |

日志关键字：`dvt_file_*`（元数据、断点、CRC、本地保存）、`dvt_archive_*`（云端回执）、`dvt_audio_*`（实时接收）、`wqota_*`（CCC、发送、回包、等待、匹配、超时）、`evt_command_*`（业务队列）。Debug原始字节保留在CMD/BLE的raw_packet_hex中；各阶段另附中文reason。请在同一次会话中对齐App和固件时间戳。

联调验收应覆盖：未认证拒绝业务、绑定按键超时、错误安全码、FF16缺失或错误CCC、元数据旧45B、不同文件键、CRC错误、断点恢复、EOF缺失、归档HTTP失败/回执不匹配、设备归档ACK丢失后重试、解绑过程中断电、音频MTU不足/取消/断连、OTA窗口乱序/SN错误/断连恢复/主动取消/E8未完成/重连版本不一致。

自动化通过只证明覆盖路径在模拟环境下符合实现，不代替真实固件、实际网络服务和iOS真机验证。真实OTA还需提供目标镜像、目标抓包与最终校验修复证据；当前仓库没有这些外部材料。

## 8. 本次验证记录（2026-09-15）

下列为初版 DVT 基线记录。2026-09-16 的接收链路修复、EVT 交互对齐及最新 552 项测试结果见 [DVT 审查记录](qa/dvt-2026-09-16-review.md)。

- `flutter test --no-pub --reporter expanded`：508 项通过。
- `flutter analyze --no-pub`：无问题。
- Android 原生 `:reactive_ble_mobile:testDebugUnitTest`：通过。
- `flutter build apk --debug --no-pub`：构建成功；版本0.0.2+3，APK位于 `build/app/outputs/flutter-apk/app-debug.apk`。
- 未进行真实设备升级、真实云端归档或 iOS 编译签名；不能将这些结果标记为真机验收通过。
