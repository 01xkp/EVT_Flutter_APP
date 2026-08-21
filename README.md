# AIPIN 智能录音

面向普通用户的 Android/iOS 智能录音设备伴侣。首次打开可选择连接设备或直接使用手机本机录音；应用不提供账户、云同步、设备音频播放或硬件录音控制。

## 运行

```powershell
flutter pub get
flutter run
```

Android debug 包：

```powershell
flutter build apk --debug
```

## 使用流程

1. 首次使用选择“连接我的设备”或“先用本机录音”。
2. 首页显示当前设备连接与录音状态；连接页负责查找、选择和连接附近设备。
3. “录音”只启动离线 M4A 本机录音，可暂停、继续、结束保存，且不依赖设备连接。
4. “记录”在本机录音和设备活动之间切换；设备活动仅展示已完成的设备检查。
5. 设备详情可查看连接、设备录音状态与电量，并支持断开、重连及进入“设备检查”。

## 工程验证

底层仍保留真实 BLE 广播、GATT 服务、状态订阅、状态读取和观察证据流程，供“设备检查”上下文使用。它不产生或同步设备录音文件，也不会向设备发送开始或结束录音指令。

缺失字段、未知协议事件、CRC 错误和无法读取的状态一律显示为“不可验证”，不会被推断为通过。模拟数据或缺少设备身份的结果会在仓储层被拒绝保存。

## 设备 Profile

`assets/config/device_profile.json` 是唯一的设备配置来源，包含广播过滤规则及状态读取/订阅使用的 GATT UUID。设置页会展示该 Profile 的就绪状态。

Profile 未完整配置时，扫描规则仍可使用，但连接后的状态验证会被阻止。变更 Profile 后需重新运行应用。

## 平台权限

- Android：声明并在扫描前请求 `BLUETOOTH_SCAN` 和 `BLUETOOTH_CONNECT`；录音开始时请求 `RECORD_AUDIO`，并以 microphone 前台服务维持后台录制。旧版 Android 保留 `ACCESS_FINE_LOCATION` 声明（最高 API 30）。
- iOS：`Info.plist` 声明 `NSBluetoothAlwaysUsageDescription`、`NSMicrophoneUsageDescription` 和 audio 后台模式。当前 Flutter iOS 工程采用 Swift Package Manager，`permission_handler` 会据此自动启用蓝牙权限。
- 未授权、蓝牙不可用或连接中断会显示可恢复诊断，不会制造可观察状态。

## 本地证据

证据通过 Drift 存储在应用沙盒中的 `evt_evidence` 数据库，包含设备身份、判定、原因、来源快照/事件、人工备注和诊断载荷。应用不上传、同步或共享该数据库；需要导出时应通过受控的内部流程读取诊断载荷。

## 本机录音

- 本机录音支持离线 M4A 录制、后台/锁屏连续录制、本地播放、重命名、删除和异常恢复。
- 录音音频保存在应用私有目录，Drift 只保存标题、时长、状态和文件相对路径等元数据。
- 手机本机录音与设备自有的硬件录音完全独立，不向设备发送开始或结束录音指令，也不会将本机音频混入设备证据。

## 工程结构

```text
lib/app                 应用壳层、依赖注入、主题
lib/core/ble            Profile、传输契约、平台 BLE 适配器
lib/core/protocol       EVT 帧、CRC、事件解码
lib/core/persistence    Drift 数据库与表
lib/core/design_system  单色主题与复用组件
lib/features/*          发现、会话、观察、证据、设置的分层实现
```

## 验证

```powershell
dart format --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
```

在真机上额外验证权限请求、蓝牙关闭、广播过滤、GATT 首读、订阅状态、断开重连和本地证据保存。iOS 构建和真机验证需在 macOS/Xcode 环境执行。
