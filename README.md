# AIPIN 声存 · DVT V1.6

当前 `dvt` 分支基于 V1.6 EVT BLE 联调能力，保留设备发现、连接、六字节安全码认证、状态配置、设备录音控制、文件下载、本地播放、日志与回连；新增 DVT 文件元数据、CRC32 校验与归档、独立 WQOTA 升级、实时音频带宽验证，以及从 EVT 合并而来的 Debug 脱敏日志手动上报。应用版本为 `0.0.2+3`，包名为 `com.aigutta.aipin`。

设备 BLE 功能入口和 DVT 预期界面见 [DVT App 图解使用说明（离线 HTML）](docs/DVT-App-功能使用说明-v0.0.2.html)。日志上报入口、预期界面和看板联调链路见 [日志上报与看板联调说明（离线 HTML）](docs/EVT-App-日志上报与看板联调说明-v0.0.4.html)，历史 EVT 验证见 [全功能审查记录](docs/qa/2026-09-15-evt-final-review.md)。

本分支不包含手机麦克风录音、AI/ASR、V2/F2 认证、Factory/UART、直接删除或格式化指令。协议版本值只记录，不作为连接阻断条件。

## 运行

```powershell
flutter pub get
flutter run
flutter build apk --debug
```

APK：`build/app/outputs/flutter-apk/app-debug.apk`。

## 联调入口

- 设备详情：认证/绑定/受控解绑，状态、电量、存储、UTC、录音授权、隐私时长、设备录音控制。
- 设备录音文件：列表、元数据、校验保存、云端归档后释放设备源文件。
- DVT 实时音频验证：开启/关闭 FA18 数据流，显示接收字节、帧数、时长和吞吐。
- DVT 固件升级：读取 HTTPS 升级清单、校验镜像、分窗口上传、取消/恢复、重连后核验版本。
- 实时日志：查看并导出完整 Debug 收发链路。

详细接口、逐步操作、平台限制和待提供的固件/服务端材料，见 [DVT V1.6 联调说明](docs/dvt-v1.6-integration.md)。历史 EVT 文档描述的是原分支，不能作为本分支接口白名单。

## 真实联调前提

设备须提供 FF16 Write + Indicate。音频和 OTA 特征按需开放；没有这些可选特征时仍可使用其他 DVT 功能。

归档服务默认未配置；不会把本地保存当成云端成功。可使用 `--dart-define=DVT_ARCHIVE_URL=https://...` 配置与联调说明一致的应用后端适配接口。这是本 App 定义的后端对接边界，不是固件文档规定的 HTTP 路由。

OTA 必须由固件团队提供升级清单、真实帧头抓包依据，以及 E8=0 已代表最终整镜像校验通过的实现确认。缺失时不会发送镜像。实时音频固定 480B 块要求 ATT MTU 至少 489；容量不足时阻止开启并给出原因。

## 平台

Android 6–11 使用定位权限和系统定位开关；Android 12+ 使用附近设备权限。扫描只隐藏无名称设备，连接后严格验证 GATT。iOS 使用 CoreBluetooth UUID 连接，不把 UUID 当 MAC，也不提供直接开启蓝牙的私有 API。

Android 对 CCC 显式区分 Notify/Indicate；iOS 检查 CoreBluetooth 能力和订阅完成回调。业务回包与 WQOTA 独立解析。

## Debug 日志与手动上报

单个日志段最大 20 MiB，保留最近 8 个日志段。BLE 文件导入期间的日志会以最多 200 ms 一批落盘，避免大量 `0x23` 数据包写日志拖慢传输；公共下载目录镜像最多每 10 秒同步一次。点击“导出日志”先写完待保存内容，再生成独立脱敏快照并尝试公开保存；生命周期落盘只等待应用私有日志，不等待存储权限。设备详情页的“实时日志”可查看当前路径和导出日志。Android 10+ Debug 的后台镜像位置为：

```text
Download/AIPIN/logs/aipin-YYYY-MM-DD.log.txt
```

手动导出文件名精确到秒，例如 `aipin-2026-09-15-17-27-08.log.txt`，同秒重复导出追加 `-01`、`-02`。Android 6–9 与 iOS 使用 `.log` 后缀；iOS 保存到 `Documents/AIPIN/logs`。内部导出副本另保留最近 8 份，公共目录中的历史导出不随内部保留策略删除。

Android 6–9 仅在用户导出且需要权限时请求存储权限；应用私有日志不受该权限影响。当前 EVT Debug 包会在私有 canonical 日志的 `raw_packet_hex` 中保留 App 到设备和设备到 App 的完整原始字节，因此其中可能包含认证码、文件名和音频数据，仅可用于受控联调，不得对外分享。手动导出、副本镜像和上传快照都会移除该字段；结构化字段仍只保留脱敏设备引用，不写入完整 MAC 或 CoreBluetooth UUID；Release/Profile 构建不会持久化该日志。

实时日志页的“上传日志”仅由用户手动触发。它会从当前私有日志生成独立脱敏快照后通过 HTTPS API 上传，不会触发 Android 公共目录镜像或存储权限申请。上传 token 仅能通过受控 Debug 构建注入；详细配置见[日志上报配置](docs/qa/evt-log-upload-configuration.md)，服务端和看板边界见[日志服务与看板服务端需求](docs/qa/evt-log-service-dashboard-requirements.md)。

## 验证

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-fatal-infos
flutter test --reporter compact
flutter build apk --debug
git diff --check
```

Windows 可完成 Android 构建和 Flutter 测试。iOS 编译、签名及真机 BLE 验证必须在 macOS/Xcode 环境完成。

## 工程结构

```text
lib/app                    应用壳、依赖注入与主题
lib/core/ble               广播过滤、GATT Profile 与平台 BLE 传输
lib/core/protocol          EVT 帧、CRC、命令队列与协议解码
lib/core/persistence       本地设备记录、下载断点和证据存储
lib/features/device_*      发现、会话、回连、日志和文件导入
lib/features/local_recording  仅保存和播放从设备导入的音频
```
