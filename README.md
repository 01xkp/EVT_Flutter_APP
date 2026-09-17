# AIPIN 声存 · DVT V1.6

当前 `dvt` 分支从 `evt@9e1841c` 切出，保留原有设备连接、六字节安全码认证、状态配置、录音控制、日志与回连，增加 V1.6 DVT 文件元数据、CRC32 校验与归档、独立 WQOTA 升级，以及实时音频带宽验证。应用版本维持 `0.0.2+3`，包名为 `com.aigutta.aipin`。

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

Android 对 CCC 显式区分 Notify/Indicate；iOS 检查 CoreBluetooth 能力和订阅完成回调。业务回包与 WQOTA 独立解析。当前 Windows 环境可验证 Android 构建；iOS 编译签名及真机联调需在 macOS/Xcode 完成。
