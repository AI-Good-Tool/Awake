import Foundation
import Testing
@testable import Lidwake

private let releaseFixture = """
{
  "tag_name": "v0.2.1",
  "html_url": "https://github.com/AI-Good-Tool/Awake/releases/tag/v0.2.1",
  "body": "New release",
  "draft": false,
  "prerelease": false,
  "assets": [{
    "name": "Awake-0.2.1.dmg",
    "browser_download_url": "https://github.com/AI-Good-Tool/Awake/releases/download/v0.2.1/Awake-0.2.1.dmg",
    "size": 3,
    "digest": "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
  }]
}
"""

struct UpdateTests {
    @Test func stableVersionComparisonHandlesMultiDigitAndMissingPatchNumbers() throws {
        #expect(try #require(AppVersion("v0.2.10")) > #require(AppVersion("0.2.9")))
        #expect(try #require(AppVersion("1.0.0")) > #require(AppVersion("0.99.99")))
        #expect(AppVersion("0.2") == AppVersion("0.2.0"))
        #expect(AppVersion("0.2.0.0") == AppVersion("0.2"))
        for invalid in ["", "dev", "1", "0..2", "0.2.-1", "0.3.0-beta.1", "v0.2.1/evil", "0.2.１"] {
            #expect(AppVersion(invalid) == nil)
        }
    }

    @Test func installerMustBelongToThisRepositoryAndMatchReleaseVersion() throws {
        let decoder = JSONDecoder()
        let valid = try decoder.decode(AppRelease.self, from: Data(releaseFixture.utf8))
        try valid.validate()
        #expect(valid.installer?.name == "Awake-0.2.1.dmg")
        let replacements = [
            ("https://github.com/AI-Good-Tool/Awake/releases/download/", "https://example.com/AI-Good-Tool/Awake/releases/download/"),
            ("/releases/download/v0.2.1/", "/releases/download/v0.2.0/"),
            ("Awake-0.2.1.dmg", "../Awake-0.2.1.dmg"),
            ("sha256:ba7816bf", "sha512:ba7816bf"),
            ("\"size\": 3", "\"size\": 200000001")
        ]
        for (from, to) in replacements {
            let data = Data(releaseFixture.replacingOccurrences(of: from, with: to).utf8)
            let release = try decoder.decode(AppRelease.self, from: data)
            #expect(release.installer == nil)
        }
        for (from, to) in [("\"draft\": false", "\"draft\": true"),
                           ("\"prerelease\": false", "\"prerelease\": true"),
                           ("https://github.com/", "http://github.com/")] {
            let data = Data(releaseFixture.replacingOccurrences(of: from, with: to).utf8)
            let release = try decoder.decode(AppRelease.self, from: data)
            #expect(throws: UpdateError.self) { try release.validate() }
        }
    }

    @Test func corruptedOrTruncatedInstallerNeverPassesChecksumVerification() throws {
        let release = try JSONDecoder().decode(AppRelease.self, from: Data(releaseFixture.utf8))
        let asset = try #require(release.installer)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("awake-update-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("abc".utf8).write(to: url)
        try asset.verify(fileURL: url)
        try Data("abd".utf8).write(to: url)
        #expect(throws: UpdateError.self) { try asset.verify(fileURL: url) }
        try Data("ab".utf8).write(to: url)
        #expect(throws: UpdateError.self) { try asset.verify(fileURL: url) }
    }
}

private final class ReleaseResponseStore: @unchecked Sendable {
    private let lock = NSLock()
    private var response = (status: 200, data: Data(releaseFixture.utf8))

    func set(status: Int, data: Data) { lock.withLock { response = (status, data) } }
    func get() -> (status: Int, data: Data) { lock.withLock { response } }
}

private final class ReleaseURLProtocol: URLProtocol, @unchecked Sendable {
    static let responses = ReleaseResponseStore()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let result = Self.responses.get()
        let response = HTTPURLResponse(url: request.url!, statusCode: result.status,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: result.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

struct UpdateNetworkTests {
    @MainActor
    @Test func updateCheckerShowsNewVersionCurrentVersionAndRecoverableFailures() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReleaseURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = GitHubUpdateService(session: session)
        ReleaseURLProtocol.responses.set(status: 200, data: Data(releaseFixture.utf8))

        let checker = UpdateChecker(service: service, currentVersion: "0.2.0")
        await checker.checkForUpdates()
        #expect(checker.phase == .available)
        #expect(checker.release?.displayVersion == "0.2.1")
        #expect(checker.lastCheckedAt != nil)

        let current = UpdateChecker(service: service, currentVersion: "0.2.1")
        await current.checkForUpdates()
        #expect(current.phase == .current)
        let ahead = UpdateChecker(service: service, currentVersion: "0.3.0")
        await ahead.checkForUpdates()
        #expect(ahead.phase == .current)

        for status in [404, 403, 429, 503] {
            ReleaseURLProtocol.responses.set(status: status, data: Data())
            await checker.checkForUpdates()
            #expect(checker.phase == .failed)
            #expect(checker.errorMessage != nil)
            #expect(checker.release == nil)
            #expect(!checker.isBusy)
        }
        ReleaseURLProtocol.responses.set(status: 200, data: Data("malformed JSON".utf8))
        await checker.checkForUpdates()
        #expect(checker.phase == .failed)
        ReleaseURLProtocol.responses.set(status: 200, data: Data(releaseFixture.utf8))
        await checker.checkForUpdates()
        #expect(checker.phase == .available)
        #expect(checker.errorMessage == nil)
    }
}
