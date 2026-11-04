# 智能枕头 iOS App

「贾维斯家庭」AI 自适应助眠枕的 iPhone 端。通过局域网连接枕头的 ESP32（`/api/status`、`/api/command`、热点配网 `/api/wifi`），
在手机上完成主动助眠闭环：躺下自动开始 → 播放助眠噪声 → 安静后逐步变轻并停止 → 夜醒再轻声陪伴 → 早上生成报告。

## 编译

没有 Mac 也可以：推送到 GitHub 后，`.github/workflows/build-ipa.yml` 会在云端 macOS 上用 XcodeGen 生成工程并编译出未签名的
`SmartPillow.ipa`，在 Actions 页面的 Artifacts 里下载。

本地有 Mac 时：

```bash
brew install xcodegen
xcodegen generate
open SmartPillow.xcodeproj
```

## 安装到 iPhone（免费 Apple ID 自签）

1. Windows 上安装 iTunes（官网版）和 Sideloadly，iPhone 用数据线连接电脑。
2. 把 `SmartPillow.ipa` 拖进 Sideloadly，填自己的 Apple ID，点 Start。
3. iPhone：设置 → 通用 → VPN 与设备管理 → 信任自己的 Apple ID；
   首次还需要 设置 → 隐私与安全性 → 开发者模式 → 打开并重启。
4. 免费 Apple ID 签名 7 天有效，到期后用 Sideloadly 重新安装一次即可，数据保留。

## 结构

| 文件 | 作用 |
|---|---|
| `PillowClient.swift` | 轮询状态、发送命令、扫描局域网找枕头、热点配网 |
| `SoundEngine.swift` | 实时生成粉 / 棕 / 白噪音和海浪声，音量平滑渐变，支持后台播放 |
| `AssistEngine.swift` | 助眠闭环状态机和整晚记录 |
| `TonightView` / `ReportsView` / `DeviceView` / `SetupView` | 界面 |
