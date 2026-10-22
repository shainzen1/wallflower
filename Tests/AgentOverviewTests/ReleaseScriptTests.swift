import CryptoKit
import Foundation
import Testing
@testable import AgentOverview

/// The release tooling for in-app updates: `scripts/appcast.sh` (the Sparkle feed), the placeholder
/// key guard `scripts/check-update-key.sh` and `scripts/verify-update-signature.swift`.
@Suite("Updates: release scripts")
struct ReleaseScriptTests {
    private static let root = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let changelog = root.appending(path: "Tests/Fixtures/release/CHANGELOG.md")
    /// A well-formed EdDSA signature (base64 of 64 bytes); appcast.sh only checks its shape.
    private static let signature = Data(repeating: 1, count: 64).base64EncodedString()

    private struct Run {
        var status: Int32
        var output: String
        var error: String
    }

    private func run(_ executable: String, _ arguments: [String]) throws -> Run {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSTemporaryDirectory()]
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        let out = output.fileHandleForReading.readDataToEndOfFile()
        let err = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Run(status: process.terminationStatus, output: String(decoding: out, as: UTF8.self), error: String(decoding: err, as: UTF8.self))
    }

    private func appcast(version: String = "0.2.0", url: String = "https://example.com/download/v0.2.0/Wallflower-0.2.0.zip", extra: [String] = []) throws -> Run {
        try run(Self.root.appending(path: "scripts/appcast.sh").path, [
            "--version", version, "--build", "3", "--minimum-system", "26.0", "--url", url, "--length", "4242",
            "--signature", Self.signature, "--changelog", Self.changelog.path, "--date", "Mon, 02 Nov 2026 09:00:00 +0000",
        ] + extra)
    }

    @Test func appcastItem() throws {
        let result = try appcast(extra: ["--release-page", "https://example.com/releases"])
        #expect(result.status == 0, "\(result.error)")
        let document = try XMLDocument(xmlString: result.output)
        let items = try document.nodes(forXPath: "/rss/channel/item")
        #expect(items.count == 1, "one item: this release")
        func text(_ path: String) throws -> String? { try document.nodes(forXPath: "/rss/channel/item/\(path)").first?.stringValue }
        #expect(try text("title") == "Version 0.2.0")
        #expect(try text("pubDate") == "Mon, 02 Nov 2026 09:00:00 +0000")
        #expect(try text("sparkle:version") == "3")
        #expect(try text("sparkle:shortVersionString") == "0.2.0")
        #expect(try text("sparkle:minimumSystemVersion") == "26.0")
        #expect(try text("sparkle:fullReleaseNotesLink") == "https://example.com/releases")

        let enclosure = try #require(try document.nodes(forXPath: "/rss/channel/item/enclosure").first as? XMLElement)
        #expect(enclosure.attribute(forName: "url")?.stringValue == "https://example.com/download/v0.2.0/Wallflower-0.2.0.zip")
        #expect(enclosure.attribute(forName: "length")?.stringValue == "4242")
        #expect(enclosure.attribute(forName: "type")?.stringValue == "application/octet-stream")
        #expect(enclosure.attribute(forName: "sparkle:edSignature")?.stringValue == Self.signature)

        let notes = try #require(try text("description"))
        #expect(notes.contains("<h3>Added</h3>") && notes.contains("<h3>Fixed</h3>"))
        #expect(notes.contains("<li><strong>Faces</strong> learn a new trick with <code>--flag &lt;value&gt;</code> &amp; friends"))
        #expect(notes.contains("<a href=\"https://example.com/docs\">the docs</a>"))
        #expect(notes.contains("<a href=\"https://example.com/notes?a=1&amp;b=2\">link</a>"))
        #expect(notes.contains("<p>A short intro line that wraps onto a second line"))
        #expect(notes.contains("<li>An item that wraps onto a second line.</li>"))
        #expect(notes.contains("<li>A &lt; B &gt; C.</li>"))
        #expect(!notes.contains("not released yet") && !notes.contains("The first release"), "only this version's section")
        #expect(!notes.contains("example.com/compare"), "no link references")
    }

    @Test func unreleasedSectionWhileTheVersionHasNone() throws {
        let result = try appcast(version: "0.3.0")
        #expect(result.status == 0, "\(result.error)")
        #expect(result.output.contains("<li>Something not released yet.</li>"))
        #expect(result.error.contains("using [Unreleased]"))
        #expect(!result.output.contains("<sparkle:fullReleaseNotesLink>"), "only with --release-page")
    }

    @Test func appcastRefusesBadInput() throws {
        #expect(try appcast(url: "https://example.com/a\"b.zip").status == 1, "a quote in the URL")
        #expect(try appcast(url: "file:///Users/demo/Wallflower.zip").status == 1, "not http(s)")
        #expect(try appcast(extra: ["--signature", "abc"]).status == 1, "not a signature")
        #expect(try appcast(extra: ["--length", "0"]).status == 1)
        #expect(try appcast(version: "0.2").status == 0)
        #expect(try appcast(version: "v0.2.0").status == 1)
    }

    // MARK: Placeholder key guard

    private func plist(key: String?) throws -> URL {
        let folder = try TestSupport.makeTempFolder()
        let url = folder.appending(path: "Info.plist")
        var info: [String: Any] = ["CFBundleIdentifier": "dev.wallflower.Wallflower"]
        if let key { info["SUPublicEDKey"] = key }
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: url)
        return url
    }

    private func checkKey(_ key: String?) throws -> Run {
        let url = try plist(key: key)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        return try run(Self.root.appending(path: "scripts/check-update-key.sh").path, [url.path])
    }

    @Test func keyGuard() throws {
        let placeholder = try checkKey(AppUpdater.publicKeyPlaceholder)
        #expect(placeholder.status == 1 && placeholder.error.contains("still the placeholder"), "the script and AppUpdater agree on the placeholder")
        #expect(try checkKey(nil).status == 1)
        let privateKey = try checkKey(Data(count: 64).base64EncodedString())
        #expect(privateKey.status == 1 && privateKey.error.contains("never the private key"))
        #expect(try checkKey("not a key").status == 1)
        let key = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        let good = try checkKey(key)
        #expect(good.status == 0 && good.output.trimmingCharacters(in: .newlines) == key)
    }

    @Test func repoPlistIsRefusedWhileItHoldsThePlaceholder() throws {
        let info = try #require(NSDictionary(contentsOf: Self.root.appending(path: "Packaging/Info.plist")))
        let result = try run(Self.root.appending(path: "scripts/check-update-key.sh").path, [])
        if info["SUPublicEDKey"] as? String == AppUpdater.publicKeyPlaceholder {
            #expect(result.status == 1)
        } else {
            #expect(result.status == 0)
        }
    }

    // MARK: Signature check

    @Test func signatureMustMatchThePublicKey() throws {
        let folder = try TestSupport.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "Wallflower-0.2.0.zip")
        try Data("a release".utf8).write(to: file)
        let key = Curve25519.Signing.PrivateKey()
        let signature = try key.signature(for: Data("a release".utf8)).base64EncodedString()
        let script = Self.root.appending(path: "scripts/verify-update-signature.swift").path
        func verify(_ publicKey: Curve25519.Signing.PublicKey) throws -> Int32 {
            try run("/usr/bin/swift", [script, publicKey.rawRepresentation.base64EncodedString(), signature, file.path]).status
        }
        #expect(try verify(key.publicKey) == 0)
        #expect(try verify(Curve25519.Signing.PrivateKey().publicKey) == 1, "signed with another key")
        try Data("a changed release".utf8).write(to: file)
        #expect(try verify(key.publicKey) == 1, "changed after signing")
    }
}
