醒咖 Awake 是一款原生 macOS 菜单栏防休眠工具：屏幕常亮、后台任务和演示模式，可搭配 App 白名单、定时规则、低电量与温度保护。

本版本采用新的咖啡杯图标与「醒咖 Awake」名称，Bundle ID 为 `com.local.awake`，支持从 Lidwake 自动迁移设置。

### 下载与安装

- **DMG**：打开磁盘映像，把「醒咖 Awake」拖到 Applications。
- **PKG**：使用 macOS 安装器安装到 `/Applications`。
- **ZIP**：解压后将应用移到「应用程序」。
- **SHA256SUMS.txt**：以上文件的 SHA-256 校验值。

系统要求：**macOS 26 或更新版本**。应用与安全看门进程均为 **Universal 二进制（Apple Silicon / Intel）**。

### 首次使用与升级

本次分发采用 ad-hoc 应用签名；PKG 没有 Developer ID Installer 签名，也未进行 Apple 公证。macOS 可能显示无法验证开发者或无法检查恶意软件的提示。确认来自本仓库后，可在「系统设置 → 隐私与安全性」中允许打开。

升级前请从旧应用菜单正常退出。新版首次启动会复制旧偏好、白名单与规则；开机启动需要在新版设置中重新开启。

默认保持唤醒使用 macOS 电源 assertion，不能保证绕过系统闭盖限制。「强制闭盖后台运行」需要显式开启与管理员授权，会修改 `pmset disablesleep`；暂停、关闭或退出时会尝试恢复，独立看门进程处理异常退出，开机恢复规则提供额外保护。

使用说明与实机截图见 [README](https://github.com/AI-Good-Tool/Awake#readme)。
