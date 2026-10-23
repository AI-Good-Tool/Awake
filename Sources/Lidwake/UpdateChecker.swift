import AppKit
import Combine
import Foundation

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    enum Phase {
        case idle, checking, current, available, downloading, downloaded, failed
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var release: AppRelease?
    @Published private(set) var downloadedURL: URL?
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastCheckedAt: Date?

    private let service: GitHubUpdateService
    private let currentVersion: String?
    private var downloadTask: Task<Void, Never>?

    init(service: GitHubUpdateService = GitHubUpdateService(), currentVersion: String? = Brand.version) {
        self.service = service
        self.currentVersion = currentVersion
    }

    var isBusy: Bool { phase == .checking || phase == .downloading }

    var title: String {
        switch phase {
        case .idle: "检查更新"
        case .checking: "正在检查更新…"
        case .current: "当前已是最新版本"
        case .available: "发现新版本 \(release?.displayVersion ?? "")"
        case .downloading: "正在下载并校验…"
        case .downloaded: "安装包已准备好"
        case .failed: "暂时无法完成更新"
        }
    }

    func checkForUpdates() async {
        guard !isBusy else { return }
        phase = .checking
        errorMessage = nil
        release = nil
        downloadedURL = nil
        do {
            let latest = try await service.latestRelease()
            try Task.checkCancellation()
            release = latest
            lastCheckedAt = Date()
            guard let currentVersion, let current = AppVersion(currentVersion), let remote = latest.version else {
                phase = .available
                return
            }
            phase = remote > current ? .available : .current
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .failed
            errorMessage = error.localizedDescription
        }
    }

    func downloadUpdate() {
        guard !isBusy, let asset = release?.installer else { return }
        phase = .downloading
        errorMessage = nil
        downloadedURL = nil
        downloadTask = Task {
            defer { downloadTask = nil }
            do {
                let url = try await service.download(asset)
                downloadedURL = url
                phase = .downloaded
            } catch {
                if Task.isCancelled {
                    phase = .available
                } else {
                    phase = .failed
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func cancelDownload() { downloadTask?.cancel() }

    func openInstaller() {
        guard let downloadedURL else { return }
        guard NSWorkspace.shared.open(downloadedURL) else {
            errorMessage = "无法打开安装包，请在访达中显示后手动打开。"
            return
        }
    }

    func revealInstaller() {
        guard let downloadedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([downloadedURL])
    }
}
