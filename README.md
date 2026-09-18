# AIPIN 声存

当前 `evt` 分支是 AIPIN 智能录音设备的 V1.6 EVT BLE 联调构建。它包含设备发现、连接、V1 六字节认证、设备状态与配置、设备录音控制、设备文件下载、本地查看，以及 Debug 日志的手动上报；不包含手机本机录音、AI/ASR、账户、生产云服务、实时音频、文件归档或 OTA。

当前版本 `0.0.4+5`，修改和验证结果见 [v0.0.4 变更说明](docs/releases/2026-09-15-v0.0.4.md)。

设备 BLE 功能入口、按钮效果和预期界面见 [EVT App 图解使用说明（离线 HTML）](docs/EVT-App-功能使用说明-v0.0.4.html)。日志上报入口、预期界面和看板联调链路见 [日志上报与看板联调说明（离线 HTML）](docs/EVT-App-日志上报与看板联调说明-v0.0.4.html)，本轮验证见 [全功能审查记录](docs/qa/2026-09-15-evt-final-review.md)。

语音转写、对齐、说话人、检索与总结算法库能力说明见 [开源语音转写、对齐、说话人、检索与总结算法库能力整理](docs/qa/asr-algorithm-capability-guide.md)。

## 运行

```powershell
flutter pub get
flutter run
```

Android Debug APK：

```powershell
flutter build apk --debug
```

应用包名为 `com.aigutta.aipin`。

## EVT 联调功能

1. 当前 EVT 调试构建的手动扫描不以 V1.6 名称格式、厂商数据和服务 UUID 三要素作为准入条件，只显示名称非空的 BLE 设备；用户主动连接后才严格校验 EVT GATT 合约。自动回连同样不要求扫描结果同时具备三要素，只会在扫描结果中匹配本地已记录的同一设备，优先使用 `A3 89 + 6B` 中的物理地址，缺失时回退平台连接 ID。
2. 连接后验证九个必需 EVT 特征及属性；先订阅 `FA11` 和 `FA19`，读取未认证身份，再在当前连接认证成功后订阅其余业务特征。
3. 用户通过 `FA19 / 0x09` 输入 V1 六字节认证码，进行认证、首次绑定或恢复初始认证码。V1.6 的绑定成功后会在同一连接自动追加一次 `Action=0` 认证。
4. 认证成功后订阅业务通道、协商 MTU，读取 `ProtocolVersion`（当前联调暂不拦截版本值），写入 EVT 基线时间和录音配置。
5. 读取设备状态、电量、存储、设备时间、默认隐私时长和可选文件数量；支持设置录音授权和默认隐私时长。
6. 控制设备开始、暂停、继续和结束录音。
7. 通过 `0x22` 读取设备文件列表，通过 `0x23` 请求并接收连续 `0xA3` Notify 数据下载 `.m4a` 或 `.ogg` 文件，并支持断连后续传。
8. 在前台对非用户主动断开的已认证设备自动回连；应用进入后台时停止扫描和回连。

EVT 仅允许 `0x01`、`0x02`、`0x05`、`0x06`、`0x07`、`0x09`、`0x11`、`0x21`、`0x22`、`0x23`。不会订阅 `FA18`，不会发送 `0x08`、`0x26`、`0x09` V2 或任何 WQOTA、Factory/UART 指令。安全码输入仍由 EVT 联调页面提供；V1.6 规定的 HTTPS 取码服务尚未接入本构建。

完整的广播、GATT、命令帧、超时和真机验收规则见 [真实固件联调说明](docs/real-firmware-integration.md)。

## 平台说明

- Android 6-11：扫描前按系统要求请求定位权限，并要求系统定位服务开启。
- Android 12 及以上：扫描前请求“附近设备”中的蓝牙扫描和连接权限。
- Android 使用 legacy scan，适配 EVT 的主广播加 Scan Response 结构。
- iOS：已配置 `NSBluetoothAlwaysUsageDescription` 和 `bluetooth-central`。iOS 无法由 App 直接开启系统蓝牙，用户需在控制中心或系统设置中开启后重新扫描。
- iOS 的 BLE `connectionId` 是 CoreBluetooth UUID，不会被当作硬件 MAC；回连使用广播 Manufacturer Data 中的稳定物理地址匹配。
- 固件默认 `.ogg/Opus` 文件可以在 Android 播放；iOS 可下载保存但不会尝试用 AVFoundation 播放 Ogg/Opus。iOS 若需本地播放，固件需输出 M4A/AAC，或另行引入 Ogg 解码方案。

## 调试日志

Debug 构建会将完整 EVT 联调日志写入应用支持目录：

```text
<App Support>/logs/aipin-YYYY-MM-DD.log
```

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
