# EVT 日志上报配置

实时日志页的“上传日志”仅上报当前 Debug 运行日志的脱敏快照。它不会自动后台上传，不会读取手机公共目录，也不会上传 `raw_packet_hex` 中的原始蓝牙字节。手动导出和公共目录镜像使用同一脱敏规则；完整原始包仅保留在应用私有 Debug 日志中。

App 通过 HTTPS 上传到 `https://log.moreuos.com/api/v1/diagnostic-logs`。上传 token 不写入仓库、资源文件或示例 APK；运行时会拒绝未配置、不可信、空或超过 20 MiB 的日志快照。

## 受控构建配置

在受控环境创建未提交的 Dart define 文件，例如 `tool/log-upload.local.env`：

```dotenv
EVT_LOG_UPLOAD_TOKEN=受保护的上传token
# 可选，默认值分别为 https://log.moreuos.com、aipin_evt、0.0.4+5。
EVT_LOG_API_BASE_URL=https://log.moreuos.com
EVT_LOG_APP_ID=aipin_evt
EVT_LOG_APP_VERSION=0.0.4+5
```

不要把 `EVT_LOG_DASHBOARD_TOKEN` 放入 App；它仅供看板查询和下载使用。上传 token 必须仅具备日志上传权限，并通过安全渠道交付。

构建内部 Debug 包：

```powershell
flutter build apk --debug --dart-define-from-file=tool/log-upload.local.env
```

`--dart-define` 会进入最终 APK。带上传 token 的包只能用于受控联调，不能分发给外部用户。面向正式环境时，应使用可撤销的短时上传凭证或 App 身份换取凭证的流程。

服务端、日志接入 API 和看板所需能力见[日志服务与看板服务端需求](evt-log-service-dashboard-requirements.md)。

## 上报行为

- 点击“上传日志”后会先要求确认，再生成不可变快照。
- 本地快照和上传请求中的文件名均使用 `aipin-YYYY-MM-DD-HH-MM-SS[-序号].log`；同一秒重复生成时使用数字序号。服务端负责用不透明存储键区分同名来源文件，并负责私有存储和写入原子性。
- 上传失败不会阻塞 BLE、认证、录音、下载或播放；用户可以再次点击重试。
- App 只记录上报状态、字节数和稳定错误码，不记录 token 或服务端原始错误信息。只有服务端返回 `status: "stored"` 才显示上传成功；例如 `quarantined` 会显示为服务端拒绝。
- 当前持久运行日志仅在 Debug 构建生成。Release/Profile 包的上传入口会提示“日志上报尚未配置”，因此不能用于日志上报。
