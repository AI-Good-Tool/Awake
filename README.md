<p align="center">
  <img src="Assets/Brand/AppIcon.png" width="128" alt="醒咖 Awake 应用图标">
</p>

<h1 align="center">醒咖 Awake</h1>

<p align="center">一杯咖啡的时间，Mac 保持清醒。</p>

<p align="center">
  <a href="https://github.com/AI-Good-Tool/Awake/releases/latest">下载最新版</a> ·
  <a href="#快速开始">快速开始</a> ·
  <a href="#界面与功能">界面预览</a> ·
  <a href="#开发与打包">开发与打包</a>
</p>

<p align="center">
  <a href="https://github.com/AI-Good-Tool/Awake/actions/workflows/ci.yml"><img src="https://github.com/AI-Good-Tool/Awake/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/AI-Good-Tool/Awake/releases"><img src="https://img.shields.io/github/v/release/AI-Good-Tool/Awake" alt="GitHub Release"></a>
  <img src="https://img.shields.io/badge/macOS-26%2B-black" alt="macOS 26 及以上">
  <img src="https://img.shields.io/badge/架构-Apple%20Silicon%20%7C%20Intel-orange" alt="Universal">
</p>

醒咖 Awake 是一个原生 SwiftUI / AppKit 菜单栏防休眠工具。下载还没完成、项目正在编译，或正在投屏演示时，让 Mac 按你的规则保持唤醒；任务结束后，单击菜单栏咖啡杯即可暂停。

- **四种模式**：关闭、屏幕常亮、后台运行、演示模式。
- **App 白名单**：指定应用位于前台时才启用保持唤醒策略。
- **定时规则**：按星期和时间段自动切换策略，支持跨午夜。
- **保护策略**：低电量、严重或危险温度下自动释放保持唤醒策略。
- **菜单栏控制**：左键暂停／恢复，右键打开完整菜单；空心杯与实心杯区分状态，运行颜色可自定义。
- **闭盖保护与恢复**：可选系统级闭盖后台运行，独立看门进程和开机恢复规则提供保护。
- **本地诊断**：查看异常退出记录、导出当前状态，方便排查问题。

## 快速开始

### 下载安装

前往 [Releases](https://github.com/AI-Good-Tool/Awake/releases/latest)，选择一种安装方式：

| 文件 | 适合场景 | 安装方法 |
| --- | --- | --- |
| `Awake-<版本>.dmg` | 日常安装，推荐 | 打开 DMG，将「醒咖 Awake」拖到 Applications |
| `Awake-<版本>.pkg` | 希望使用 macOS 安装向导 | 打开 PKG，按向导安装到 `/Applications` |
| `Awake-<版本>.zip` | 手动解压安装 | 解压后把应用移到「应用程序」 |
| `SHA256SUMS.txt` | 检查下载文件是否完整 | 在下载目录执行 `shasum -a 256 -c SHA256SUMS.txt` |

**系统要求：macOS 26 或更新版本。** Release 中主应用和安全看门进程均为 Universal 二进制，支持 Apple Silicon 与支持 macOS 26 的 Intel Mac。校验文件同时列出三种安装包；只下载其中一种时，可单独比对该文件的 SHA-256。

当前版本使用 **ad-hoc 应用签名**，尚未配置 Apple Developer ID 签名与公证，PKG 也没有 Installer 证书签名。首次打开可能出现开发者无法验证的提示。确认下载来源为本仓库后，可到「系统设置 → 隐私与安全性」允许打开。

### 三步使用

1. 打开「醒咖 Awake」，在菜单栏找到咖啡杯图标。
2. 右键图标 →「打开设置」，选择需要的默认策略。
3. 左键图标可随时暂停／恢复；退出应用会释放保持唤醒策略，并尝试恢复由本应用管理的闭盖设置。

| 模式 | 屏幕行为 | 适合做什么 |
| --- | --- | --- |
| 关闭 | 遵循系统设置 | 结束任务，恢复正常省电行为 |
| 屏幕常亮 | 保持屏幕点亮，并阻止系统空闲睡眠 | 阅读、监控面板、临时展示 |
| 后台运行 | 允许屏幕自动熄灭，阻止系统空闲睡眠 | 下载、编译、同步、长时间运算 |
| 演示模式 | 同时保持屏幕点亮与系统唤醒 | 投屏、会议、演示 |

## 界面与功能

以下为新版应用的真实窗口截图。图中的「终端」是拍摄时临时添加的白名单示例；新安装不会预置此条目。截图中的蓝色运行图标来自旧设置迁移，新安装默认使用暖琥珀色。

### 状态总览

策略来源、当前前台应用、电池与供电状态、温度和闭盖条件集中展示。可以直接切换默认策略，也能自定义菜单栏运行图标颜色。

<img src="docs/images/overview.png" width="880" alt="醒咖 Awake 总览：屏幕常亮、供电信息和菜单栏图标设置">

### 按应用、按时间自动唤醒

在「白名单」中添加当前前台应用，或手动填写应用名称和 Bundle ID。开启后，只有匹配的应用在前台时才使用指定策略。

在「定时」中配置规则名称、星期、开始／结束时间和运行模式。使用工作日 09:00—18:00 等规则前，需要同时启用定时规则总开关与具体条目。

| App 白名单 | 定时规则 |
| --- | --- |
| <img src="docs/images/whitelist.png" width="440" alt="白名单页：使用终端作为 Bundle ID 示例"> | <img src="docs/images/schedule.png" width="440" alt="定时页：工作日 09:00 至 18:00 的屏幕常亮规则"> |

策略优先级为：**低电量／温度保护 → 命中的定时规则 → App 白名单 → 手动模式**。多条定时规则同时命中时，使用列表中最先匹配的规则。暂停会停止当前保持唤醒策略，恢复后重新评估规则。

### 保护策略与闭盖运行

低电量保护默认阈值为 20%；使用电池且未充电时，达到阈值会停止保持唤醒。温度保护会在系统热状态为严重或危险时生效。

默认模式使用 macOS 电源 assertion；**防止空闲睡眠不等于能绕过系统闭盖限制**。标准闭盖运行通常需要外接显示器、外接输入设备及电源，具体行为由 macOS 决定。

可选的「强制闭盖后台运行」会请求管理员授权，安装仅允许切换 `pmset disablesleep 0/1` 的本机规则，并在启用策略时预先应用系统级闭盖保护：

- 暂停、选择关闭或退出时，会尝试恢复由本应用管理的系统睡眠设置。
- 独立 `AwakeWatchdog` 进程在主程序异常退出后尝试恢复系统睡眠。
- 开机恢复规则在启动时重置 `disablesleep`；移除授权规则可在设置内操作。
- 本应用不会自动接管由其他软件开启的闭盖设置。闭盖长任务仍需留意散热、供电与设备摆放，不要将运行中的电脑放入密闭包内。

<details>
<summary>查看保护策略与闭盖设置截图</summary>

<img src="docs/images/protection.png" width="880" alt="保护策略：低电量、温度保护、开机启动和可选强制闭盖后台运行">

</details>

### 本地诊断

「诊断」标签可查看和清除异常退出记录，并导出 `Awake-Diagnostics.json`。导出文件包含当前策略、电源信息、前台应用名称／Bundle ID 和本地异常记录；提交问题前请先检查内容。

本地日志位于 `~/Library/Logs/Awake.log`。程序包含崩溃后的监督恢复与重启次数限制；主动退出不会自动重启。

## 从 Lidwake 升级

先从旧版菜单中正常退出，再安装并打开醒咖 Awake：

- 首次启动自动复制旧偏好、白名单、定时规则与闭盖保护归属记录；已有的新应用设置优先保留。
- **开机启动需要在新版设置中重新开启。**
- 新 Bundle ID 为 `com.local.awake`，主程序为 `Awake`，辅助进程为 `AwakeWatchdog`。
- 安全锁、恢复记录目录和已安装的授权文件沿用旧标识，以免遗留保护记录或让两个版本同时控制系统睡眠。
- 内部 Swift 模块暂时保留 `Lidwake` 名称，不影响应用名称与安装包标识。

## 开发与打包

需要 **Xcode 26 或更新版本、Swift 6.2+、macOS 26+**。项目使用 Swift Package Manager，没有第三方 Swift 依赖。

```bash
git clone https://github.com/AI-Good-Tool/Awake.git
cd "Awake"

# 构建 Debug .app 并启动；Codex Run 按钮使用同一入口
bash "./script/build_and_run.sh"

# 运行测试；使用完整 Xcode 工具链
env DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcrun swift test

# 当前架构的 Release .app 和 ZIP
bash "./scripts/package-local.sh"

# 一次构建 Universal .app，再输出 DMG、PKG、ZIP 和 SHA256SUMS.txt
bash "./scripts/package-release.sh"
```

独立打包可运行 `bash "./scripts/package-dmg.sh"` 或 `bash "./scripts/package-pkg.sh"`。输出均在 `dist/`；应用为 `dist/醒咖 Awake.app`。PKG 固定安装到 `/Applications`，不安装额外后台服务，不修改电源设置，也不会启动应用；闭盖授权由用户在应用内单独开启。

运行脚本支持 `--verify`、`--debug`、`--logs` 和 `--telemetry`，后两者查看本地应用日志。品牌、版本与安装包名称在 `scripts/app-config.sh` 中维护，应用 UI 文案在 `Sources/Lidwake/Brand.swift` 中集中维护。

图标原图为 `Assets/Brand/AppIcon.png`，由内置 imagegen 生成，完整提示词保存在 `Assets/Brand/imagegen-prompt.txt`；打包脚本负责生成 16—1024 像素的 ICNS 图标。

## 自动构建与发布

- 推送 `main` 或提交 Pull Request：运行测试与打包脚本语法检查。
- 推送 `v<版本>` 标签：在 GitHub Actions 的 macOS runner 上运行测试，构建 Universal DMG、PKG、ZIP，验证签名与架构并生成校验文件，最后发布到 [Releases](https://github.com/AI-Good-Tool/Awake/releases)。
- 也可在 [Release 工作流](https://github.com/AI-Good-Tool/Awake/actions/workflows/release.yml) 中手动输入已有版本标签重跑。
- 标签必须与 `scripts/app-config.sh` 中的版本一致。全部构建产物就绪后，工作流才将 Release 从草稿发布。

发布新版本时，更新版本号、构建号及 `docs/release-notes.md`，提交并推送后创建对应标签：

```bash
git tag "v<版本>"
git push origin "v<版本>"
```

当前工作流不依赖签名证书密钥；若后续配置正式分发，可在此流程上补充 Developer ID Application / Installer 签名与 Apple 公证。
