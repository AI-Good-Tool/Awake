import CryptoKit
import Foundation

/// Stable numeric versions are compared component by component, never as decimals or strings.
struct AppVersion: Comparable, Equatable, Sendable {
    let components: [Int]

    init?(_ string: String) {
        var value = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("v") { value.removeFirst() }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...4).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count else { return nil }
        var normalized = numbers
        while normalized.count > 2, normalized.last == 0 { normalized.removeLast() }
        components = normalized
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = lhs.components.indices.contains(index) ? lhs.components[index] : 0
            let right = rhs.components.indices.contains(index) ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

struct AppRelease: Decodable, Sendable {
    struct Asset: Decodable, Sendable {
        let name: String
        let browserDownloadURL: URL
        let size: Int64
        let digest: String?

        enum CodingKeys: String, CodingKey {
            case name, size, digest
            case browserDownloadURL = "browser_download_url"
        }

        func verify(fileURL: URL) throws {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            guard (attributes[.size] as? NSNumber)?.int64Value == size else {
                throw UpdateError.invalidDownload
            }
            guard let digest, digest.hasPrefix("sha256:") else { throw UpdateError.missingChecksum }
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard "sha256:\(actual)" == digest.lowercased() else { throw UpdateError.invalidDownload }
        }
    }

    let tagName: String
    let htmlURL: URL
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case body, draft, prerelease, assets
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }

    var version: AppVersion? { AppVersion(tagName) }

    var displayVersion: String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }

    func validate() throws {
        guard !draft, !prerelease, version != nil,
              htmlURL.scheme == "https", htmlURL.host == "github.com",
              htmlURL.user == nil, htmlURL.password == nil, htmlURL.port == nil,
              htmlURL.path == "/AI-Good-Tool/Awake/releases/tag/\(tagName)" else {
            throw UpdateError.invalidRelease
        }
    }

    /// Only offer the exact installer from this repository and tag, with a SHA-256 digest.
    var installer: Asset? {
        assets.first { asset in
            let url = asset.browserDownloadURL
            guard let digest = asset.digest, digest.hasPrefix("sha256:") else { return false }
            let hash = digest.dropFirst(7)
            return asset.name == "Awake-\(displayVersion).dmg"
                && url.scheme == "https" && url.host == "github.com"
                && url.user == nil && url.password == nil && url.port == nil
                && url.query == nil && url.fragment == nil
                && url.path == "/AI-Good-Tool/Awake/releases/download/\(tagName)/\(asset.name)"
                && asset.size > 0 && asset.size <= 200_000_000
                && hash.count == 64 && hash.allSatisfy(\.isHexDigit)
        }
    }
}

enum UpdateError: LocalizedError {
    case http(Int), invalidRelease, noRelease, missingChecksum, invalidDownload

    var errorDescription: String? {
        switch self {
        case .http(403), .http(429): "GitHub 请求频率受限，请稍后重试，或打开发布页面。"
        case .http(let status): "暂时无法检查更新（HTTP \(status)），请稍后重试。"
        case .noRelease: "尚无可用的正式版本，请稍后重试。"
        case .invalidRelease: "发布信息不完整或格式不受支持，请打开发布页面查看。"
        case .missingChecksum: "此安装包没有可用的校验信息，请从发布页面下载。"
        case .invalidDownload: "安装包校验失败，文件可能不完整，请重新下载。"
        }
    }
}

struct GitHubUpdateService: Sendable {
    let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func latestRelease() async throws -> AppRelease {
        var request = URLRequest(url: Brand.latestReleaseAPIURL)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Awake-macOS", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { throw UpdateError.noRelease }
        guard status == 200 else { throw UpdateError.http(status) }
        guard data.count <= 2_000_000 else { throw UpdateError.invalidRelease }
        guard let release = try? JSONDecoder().decode(AppRelease.self, from: data) else {
            throw UpdateError.invalidRelease
        }
        try release.validate()
        return release
    }

    func download(_ asset: AppRelease.Asset) async throws -> URL {
        var request = URLRequest(url: asset.browserDownloadURL)
        request.timeoutInterval = 120
        let (temporaryURL, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw UpdateError.http(status) }
        try Task.checkCancellation()
        try asset.verify(fileURL: temporaryURL)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Awake-Updates", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(asset.name)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }
}
