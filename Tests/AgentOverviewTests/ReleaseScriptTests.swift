import CryptoKit
import Foundation
import ImageIO
import Testing
@testable import AgentOverview

/// The release tooling: `scripts/appcast.sh` (the Sparkle feed), the placeholder key guard
/// `scripts/check-update-key.sh`, `scripts/verify-update-signature.swift`, the signing choice in
/// `scripts/signing.sh` (with a fake `security`) and the disk image's committed layout.
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

    private func run(_ executable: String, _ arguments: [String], environment: [String: String] = [:]) throws -> Run {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSTemporaryDirectory()]
            .merging(environment) { _, new in new }
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

    // MARK: Signing identity

    private static let developerID = "Developer ID Application: Demo Person (ABCDE12345)"

    /// `release_identity` and `signing_summary` from signing.sh, with a fake `security` first on the PATH
    /// that prints `listing` for find-identity (or fails when it is nil).
    private func identity(listing: String?, environment: [String: String] = [:]) throws -> Run {
        let folder = try TestSupport.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let fake = folder.appending(path: "security")
        let body = listing.map { "cat <<'EOF'\n\($0)\nEOF\nexit 0" } ?? "echo 'security: no keychain' >&2\nexit 1"
        try Data("#!/bin/bash\n[[ \"$1\" == find-identity && \"$2 $3 $4\" == \"-v -p codesigning\" ]] || exit 2\n\(body)\n".utf8).write(to: fake)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        let script = Self.root.appending(path: "scripts/signing.sh").path
        return try run("/bin/bash", ["-c", "source \"$1\"; id=\"$(release_identity)\" || exit 1; echo \"[$id]\"; signing_summary \"$id\"", "bash", script],
                       environment: ["PATH": "\(folder.path):/usr/bin:/bin:/usr/sbin:/sbin"].merging(environment) { _, new in new })
    }

    private static func line(_ number: Int, _ name: String) -> String {
        "  \(number)) \(String(repeating: String(number), count: 40)) \"\(name)\""
    }

    @Test func developerIDIsFoundInTheKeychain() throws {
        let listing = [Self.line(1, "Apple Development: Demo Person (ZYXWV98765)"), Self.line(2, Self.developerID), "     2 valid identities found"]
        let result = try identity(listing: listing.joined(separator: "\n"))
        #expect(result.status == 0, "\(result.error)")
        #expect(result.output == "[\(Self.developerID)]\nDeveloper ID (\(Self.developerID)), notarized and stapled\n")

        // The same certificate in two keychains is still one identity.
        let twice = try identity(listing: [Self.line(1, Self.developerID), Self.line(2, Self.developerID)].joined(separator: "\n"))
        #expect(twice.output.hasPrefix("[\(Self.developerID)]\n"))
    }

    @Test func withoutADeveloperIDTheReleaseIsAdHoc() throws {
        let other = try identity(listing: Self.line(1, "Apple Development: Demo Person (ZYXWV98765)") + "\n     1 valid identities found")
        #expect(other.status == 0)
        #expect(other.output == "[]\nad hoc, NOT NOTARIZED (Gatekeeper will warn on the first launch)\n")
        #expect(try identity(listing: "     0 valid identities found").output.hasPrefix("[]\n"))
        #expect(try identity(listing: nil).output.hasPrefix("[]\n"), "security failing (no keychain) means ad hoc")
    }

    @Test func severalDeveloperIDsNeedAChoice() throws {
        let second = "Developer ID Application: Demo Studio (FGHIJ67890)"
        let listing = [Self.line(1, Self.developerID), Self.line(2, second)].joined(separator: "\n")
        let result = try identity(listing: listing)
        #expect(result.status == 1)
        #expect(result.error.contains("WALLFLOWER_SIGN_IDENTITY") && result.error.contains(Self.developerID) && result.error.contains(second))
        let chosen = try identity(listing: listing, environment: ["WALLFLOWER_SIGN_IDENTITY": second])
        #expect(chosen.status == 0 && chosen.output.hasPrefix("[\(second)]\n"))
    }

    @Test func theEnvironmentOverridesTheKeychain() throws {
        // Named explicitly: used without asking security (release.sh checks it is valid before building).
        let named = try identity(listing: nil, environment: ["WALLFLOWER_SIGN_IDENTITY": Self.developerID])
        #expect(named.output.hasPrefix("[\(Self.developerID)]\n"))
        // "-" forces ad hoc even with a Developer ID in the Keychain.
        let adHoc = try identity(listing: Self.line(1, Self.developerID), environment: ["WALLFLOWER_SIGN_IDENTITY": "-"])
        #expect(adHoc.output.hasPrefix("[]\nad hoc, NOT NOTARIZED"))
    }

    // MARK: Disk image

    @Test func diskImageLayoutMatchesTheBackgroundAndTheScript() throws {
        let folder = Self.root.appending(path: "Packaging/dmg")
        let store = try Data(contentsOf: folder.appending(path: "DS_Store"))
        func utf16(_ text: String) -> Data { Data(text.utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }) }
        // .DS_Store record names are UTF-16 big endian; the background alias holds the Carbon path.
        #expect(store.range(of: utf16("Wallflower.app")) != nil)
        #expect(store.range(of: utf16("Applications")) != nil)
        #expect(store.range(of: Data("Wallflower:.background.tiff".utf8)) != nil, "volume Wallflower, background at /.background.tiff")

        // The window is the background's size (the bounds sit in the embedded bwsp plist).
        let bounds = try #require(String(decoding: store, as: UTF8.self).firstMatch(of: /\{\{-?\d+, -?\d+\}, \{(\d+), (\d+)\}\}/))
        func pixels(_ name: String) throws -> (Int, Int) {
            let source = try #require(CGImageSourceCreateWithURL(folder.appending(path: name) as CFURL, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            return (image.width, image.height)
        }
        let size = try pixels("background.png")
        #expect(size.0 == Int(bounds.1) && size.1 == Int(bounds.2))
        let retina = try pixels("background@2x.png")
        #expect(retina.0 == 2 * size.0 && retina.1 == 2 * size.1)

        let script = try String(contentsOf: Self.root.appending(path: "scripts/make-dmg.sh"), encoding: .utf8)
        #expect(script.contains("VOLUME=\"Wallflower\"") && script.contains("\"$STAGE/.background.tiff\""))
        #expect(script.contains("\"$STAGE/$NAME.app\"") && script.contains("ln -s /Applications \"$STAGE/Applications\""))
    }

    @Test func makeDMGRefusesBadArguments() throws {
        let script = Self.root.appending(path: "scripts/make-dmg.sh").path
        let folder = try TestSupport.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let other = folder.appending(path: "Other.app")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        #expect(try run(script, []).status == 2)
        let wrongApp = try run(script, [other.path, folder.appending(path: "out.dmg").path])
        #expect(wrongApp.status == 1 && wrongApp.error.contains("is not a Wallflower.app bundle"))
        let app = folder.appending(path: "Wallflower.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let wrongOut = try run(script, [app.path, folder.appending(path: "out.zip").path])
        #expect(wrongOut.status == 1 && wrongOut.error.contains("must end in .dmg"))
    }
}
