import Foundation
import Testing
@testable import AgentOverview

@Suite("GitHeadReader")
struct GitHeadReaderTests {
    @Test func headContents() {
        #expect(GitHeadReader.branch(headContents: "ref: refs/heads/main\n") == "main")
        #expect(GitHeadReader.branch(headContents: "ref: refs/heads/feature/x/y") == "feature/x/y")
        #expect(GitHeadReader.branch(headContents: "0123456789abcdef0123456789abcdef01234567\n") == nil, "detached")
        #expect(GitHeadReader.branch(headContents: "ref: refs/tags/v1") == nil)
        #expect(GitHeadReader.branch(headContents: "") == nil)
    }

    @Test func normalRepositoryAndSubfolder() throws {
        let folder = try TestSupport.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let git = folder.appending(path: ".git", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: git, withIntermediateDirectories: true)
        try Data("ref: refs/heads/demo-branch\n".utf8).write(to: git.appending(path: "HEAD"))
        #expect(GitHeadReader.branch(cwd: folder.path) == "demo-branch")

        let sub = folder.appending(path: "Sources/Deep", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        #expect(GitHeadReader.branch(cwd: sub.path) == "demo-branch")
    }

    @Test func worktreePointerAbsoluteAndRelative() throws {
        let folder = try TestSupport.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let gitDir = folder.appending(path: "repo/.git/worktrees/wt", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try Data("ref: refs/heads/wt-branch\n".utf8).write(to: gitDir.appending(path: "HEAD"))

        let absolute = folder.appending(path: "wt-absolute", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: absolute, withIntermediateDirectories: true)
        try Data("gitdir: \(gitDir.path)\n".utf8).write(to: absolute.appending(path: ".git"))
        #expect(GitHeadReader.branch(cwd: absolute.path) == "wt-branch")

        let relative = folder.appending(path: "wt-relative", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: relative, withIntermediateDirectories: true)
        try Data("gitdir: ../repo/.git/worktrees/wt\n".utf8).write(to: relative.appending(path: ".git"))
        #expect(GitHeadReader.branch(cwd: relative.path) == "wt-branch")
    }

    @Test func noRepositoryGivesNil() throws {
        let folder = try TestSupport.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // The temp folder sits outside any repository; walking up must stop at the root.
        #expect(GitHeadReader.branch(cwd: folder.path) == nil)
        #expect(GitHeadReader.branch(cwd: "/nonexistent/path/for/test") == nil)
    }
}
