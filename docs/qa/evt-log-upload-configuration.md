# EVT 日志上报配置

实时日志页的“上传日志”仅上报当前 Debug 运行日志的脱敏快照。它不会自动后台上传，不会读取手机公共目录，也不会上传 `raw_packet_hex` 中的原始蓝牙字节。手动导出和公共目录镜像使用同一脱敏规则；完整原始包仅保留在应用私有 Debug 日志中。

App 使用 SFTP 上传，但私钥、账号、服务器地址、远端目录和主机指纹都不写入仓库、资源文件或示例 APK。运行时会拒绝未配置、目录越界或主机指纹不匹配的上报请求。

## 受控构建配置

在受控环境创建未提交的 `tool/log-upload.local.json`：

```json
{
  "AIPIN_LOG_UPLOAD_SFTP_HOST": "sftp.example.internal",
  "AIPIN_LOG_UPLOAD_SFTP_PORT": "2222",
  "AIPIN_LOG_UPLOAD_SFTP_USERNAME": "restricted-log-user",
  "AIPIN_LOG_UPLOAD_SFTP_DIRECTORY": "/files",
  "AIPIN_LOG_UPLOAD_SFTP_HOST_FINGERPRINT": "SHA256:服务器提供的主机指纹",
  "AIPIN_LOG_UPLOAD_SFTP_PRIVATE_KEY_BASE64": "私钥文件的Base64内容"
}
```

`AIPIN_LOG_UPLOAD_SFTP_HOST_FINGERPRINT` 必须由服务器管理员通过受信任渠道提供，格式为 OpenSSH SHA-256 指纹。不要首次连接时接受未知主机，也不要关闭主机身份校验。

私钥需要是服务器已授权的未加密 OpenSSH/Ed25519、RSA 或 EC 私钥。将私钥编码为 Base64 后放入本地 JSON；JSON 已被 `.gitignore` 排除。

构建内部 Debug 包：

```powershell
flutter build apk --debug --dart-define-from-file=tool/log-upload.local.json
```

`--dart-define` 会进入最终 APK。带私钥的包只能用于受控联调，不能分发给外部用户。面向正式环境时，应改为服务端签发短时凭证或 HTTPS 上传网关，由网关持有 SFTP 私钥。

服务端、日志接入 API 和看板所需能力见[日志服务与看板服务端需求](evt-log-service-dashboard-requirements.md)。

## 上报行为

- 点击“上传日志”后会先要求确认，再生成不可变快照。
- 本地快照使用秒级名称；远端文件追加随机请求标识，并先写入 `.part` 临时文件，成功后原子改名为 `.log`。
- 上传失败不会阻塞 BLE、认证、录音、下载或播放；用户可以再次点击重试。
- App 只记录上报状态、字节数和稳定错误码，不记录服务器地址、目录、账号、私钥或服务端原始错误信息。
- 当前持久运行日志仅在 Debug 构建生成。Release/Profile 包的上传入口会提示“日志上报尚未配置”，因此不能用于日志上报。
