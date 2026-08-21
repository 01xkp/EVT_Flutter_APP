# EVT BLE Workbench

用于 AIPIN 设备 EVT 阶段的 Android/iOS 内部联调工具。应用只验证真实 BLE 广播、GATT 服务、状态订阅和状态读取，不提供设备绑定、账户或云同步能力。

## 运行

```powershell
flutter pub get
flutter run
```

Android debug 包：

```powershell
flutter build apk --debug
```

## 联调流程

1. 授予蓝牙扫描与连接权限，开始扫描。
2. 选择匹配 `AIPIN`、厂商前缀 `A3 89`、服务 `AF30` 的设备并连接。
3. 等待服务发现、状态订阅和首个状态读取完成。只有页面显示“状态可观察”后才能记录或开始验证。
4. 在“验证场景”中选择设备访问、VAD 录音、电池与充电、待机功耗、恢复或物理反馈。场景判定只消费当前会话收到的真实快照和协议事件。
5. 保存验证结果，或通过底部“记录观察”补充 LED、按键和异常的人工备注；在“证据记录”中查看、展开或删除本地证据。

缺失字段、未知协议事件、CRC 错误和无法读取的状态一律显示为“不可验证”，不会被推断为通过。模拟数据或缺少设备身份的结果会在仓储层被拒绝保存。

## 设备 Profile

`assets/config/device_profile.json` 是唯一的设备配置来源，包含广播过滤规则及状态读取/订阅使用的 GATT UUID。设置页会展示该 Profile 的就绪状态。

Profile 未完整配置时，扫描规则仍可使用，但连接后的状态验证会被阻止。变更 Profile 后需重新运行应用。

## 平台权限

- Android：声明并在扫描前请求 `BLUETOOTH_SCAN` 和 `BLUETOOTH_CONNECT`；旧版 Android 保留 `ACCESS_FINE_LOCATION` 声明（最高 API 30）。
- iOS：`Info.plist` 声明 `NSBluetoothAlwaysUsageDescription`。当前 Flutter iOS 工程采用 Swift Package Manager，`permission_handler` 会据此自动启用蓝牙权限。
- 未授权、蓝牙不可用或连接中断会显示可恢复诊断，不会制造可观察状态。

## 本地证据

证据通过 Drift 存储在应用沙盒中的 `evt_evidence` 数据库，包含设备身份、判定、原因、来源快照/事件、人工备注和诊断载荷。应用不上传、同步或共享该数据库；需要导出时应通过受控的内部流程读取诊断载荷。

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
