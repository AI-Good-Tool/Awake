import SwiftUI

struct AboutSettingsView: View {
    @ObservedObject private var updater = UpdateChecker.shared

    private let accent = Color(red: 0.40, green: 0.49, blue: 0.46)

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    CoffeeCupLogoView(size: 88)
                    Text(Brand.appName)
                        .font(.system(size: 27, weight: .semibold, design: .rounded))
                    HStack(spacing: 12) {
                        Text("版本 \(Brand.versionText)")
                            .monospacedDigit()
                            .textSelection(.enabled)
                        Divider().frame(height: 12)
                        Link("GitHub ↗", destination: Brand.repositoryURL)
                            .foregroundStyle(accent)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    Text(Brand.tagline)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    aboutLink("作者主页", detail: "访问 vs2pk0 的 GitHub 主页", symbol: "person.crop.circle", url: Brand.authorURL)
                    aboutLink("开源仓库", detail: "查看源码与使用说明", symbol: "chevron.left.forwardslash.chevron.right", url: Brand.repositoryURL)
                    aboutLink("问题反馈", detail: "提交问题或改进建议", symbol: "bubble.left.and.text.bubble.right", url: Brand.issuesURL)
                    aboutLink("发布记录", detail: "查看版本说明与所有安装包", symbol: "clock.arrow.circlepath", url: Brand.releasesURL)
                }

                updateCard

                Text("原生 macOS 菜单栏工具 · 让长任务从容继续")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func aboutLink(_ title: String, detail: String, symbol: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(accent)
                    .frame(width: 42, height: 42)
                    .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.06)))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var updateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Group {
                    if updater.isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: updater.phase == .current || updater.phase == .downloaded
                              ? "checkmark.circle" : "arrow.triangle.2.circlepath")
                            .font(.system(size: 21, weight: .medium))
                            .foregroundStyle(accent)
                    }
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(updater.title).font(.headline)
                    Text(updateDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(updater.phase == .idle ? "检查更新" : "重新检查") {
                    Task { await updater.checkForUpdates() }
                }
                .disabled(updater.isBusy)
            }

            if let message = updater.errorMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if let release = updater.release, updater.phase == .available || updater.phase == .failed {
                if let notes = release.body, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack {
                    if let asset = release.installer {
                        Button("下载更新（\(ByteCountFormatter.string(fromByteCount: asset.size, countStyle: .file))）") {
                            updater.downloadUpdate()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                    }
                    Link("查看发布说明 ↗", destination: release.htmlURL)
                        .foregroundStyle(accent)
                }
            }

            if updater.phase == .downloading {
                HStack {
                    Text("完成后可打开 DMG，将新版拖入「应用程序」。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("取消下载") { updater.cancelDownload() }
                }
            }

            if updater.phase == .downloaded {
                Text("已通过 SHA-256 校验。安装前请从菜单栏正常退出醒咖，再替换应用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("打开安装包…") { updater.openInstaller() }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                    Button("在访达中显示") { updater.revealInstaller() }
                }
            }

            if updater.phase == .failed, updater.release == nil {
                Link("打开发布页面 ↗", destination: Brand.releasesURL)
                    .font(.callout)
                    .foregroundStyle(accent)
            }

            if let checkedAt = updater.lastCheckedAt, updater.phase != .failed {
                Text("上次检查：\(checkedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.06)))
    }

    private var updateDetail: String {
        switch updater.phase {
        case .idle: "从 GitHub Releases 获取最新正式版本。"
        case .checking: "正在连接 GitHub，请稍候。"
        case .current: "当前版本 \(Brand.version ?? "开发版")，暂时没有更新。"
        case .available: "下载后按 macOS 提示安装，设置会保留。"
        case .downloading: "正在下载官方安装包并验证完整性。"
        case .downloaded: "点击打开安装包，完成本次更新。"
        case .failed: "可重试检查，或直接前往发布页面。"
        }
    }
}
