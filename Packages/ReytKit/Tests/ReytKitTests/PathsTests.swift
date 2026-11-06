import Foundation
import Testing

@testable import ReytKit

@Suite("Paths")
struct PathsTests {
    private func makeBase() throws -> URL {
        let base = FileManager.default.temporaryDirectory.appending(path: "reyt-paths-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.resolvingSymlinksInPath()
    }

    @Test("layout shape")
    func shape() {
        let base = URL(fileURLWithPath: "/tmp/x")
        let p = Paths(base: base)
        let gen = p.generation("g1")
        #expect(p.dataRoot.path == "/tmp/x/Data")
        #expect(p.currentPointer.path == "/tmp/x/Data/current")
        #expect(gen.path == "/tmp/x/Data/g1")
        #expect(p.store(in: gen).path == "/tmp/x/Data/g1/store.sqlite")
        #expect(p.attachments(in: gen).path == "/tmp/x/Data/g1/attachments")
        #expect(p.deviceRoot.path == "/tmp/x/Device")
    }

    @Test("pointer file is read and validated")
    func pointer() throws {
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let p = Paths(base: base)
        #expect(p.currentGenerationID() == nil)
        try FileManager.default.createDirectory(at: p.dataRoot, withIntermediateDirectories: true)
        try "gen-2\n".write(to: p.currentPointer, atomically: true, encoding: .utf8)
        #expect(p.currentGenerationID() == "gen-2")
        try "../evil".write(to: p.currentPointer, atomically: true, encoding: .utf8)
        #expect(p.currentGenerationID() == nil)
    }

    @Test("launch resolution never starts a fresh generation over real data")
    func launchResolution() throws {
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let p = Paths(base: base)
        let fm = FileManager.default
        #expect(p.resolveLaunchGeneration() == .firstRun)

        // Pointer to an empty generation and nothing else: a crashed first run, reuse it.
        try fm.createDirectory(at: p.generation("g1"), withIntermediateDirectories: true)
        try "g1\n".write(to: p.currentPointer, atomically: true, encoding: .utf8)
        #expect(p.resolveLaunchGeneration() == .open("g1"))

        // A real generation exists.
        try Data().write(to: p.store(in: p.generation("g1")))
        #expect(p.resolveLaunchGeneration() == .open("g1"))

        // Pointer missing while a real generation exists: stop.
        try fm.removeItem(at: p.currentPointer)
        #expect(p.resolveLaunchGeneration() == .badPointer)

        // Pointer names a generation without a store while another holds data: stop.
        try fm.createDirectory(at: p.generation("g2"), withIntermediateDirectories: true)
        try "g2\n".write(to: p.currentPointer, atomically: true, encoding: .utf8)
        #expect(p.resolveLaunchGeneration() == .badPointer)

        // Unreadable pointer: stop.
        try "../evil".write(to: p.currentPointer, atomically: true, encoding: .utf8)
        #expect(p.resolveLaunchGeneration() == .badPointer)
    }

    @Test("good relative paths resolve inside attachments")
    func good() throws {
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let p = Paths(base: base)
        let gen = p.generation("g1")
        let url = try p.resolveAttachment(relativePath: "2026/abc.heic", in: gen)
        #expect(url.path == p.attachments(in: gen).appending(path: "2026/abc.heic").path)
    }

    @Test(
        "escape attempts are rejected",
        arguments: [
            "../store.sqlite", "a/../../b", "..", "/etc/passwd", "", ".", "a/./b", "a//b", "a\\..\\b", "~/x",
            "a/..", "nul\0byte", "a/",
        ])
    func escapes(_ rel: String) throws {
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let p = Paths(base: base)
        #expect(throws: PathError.unsafeRelativePath) {
            try p.resolveAttachment(relativePath: rel, in: p.generation("g1"))
        }
    }

    @Test("a symlink inside attachments that points outside is rejected")
    func symlink() throws {
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let p = Paths(base: base)
        let gen = p.generation("g1")
        let att = p.attachments(in: gen)
        try FileManager.default.createDirectory(at: att, withIntermediateDirectories: true)
        let outside = base.appending(path: "outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: att.appending(path: "link"), withDestinationURL: outside)
        #expect(throws: PathError.unsafeRelativePath) {
            try p.resolveAttachment(relativePath: "link/secret.heic", in: gen)
        }
    }

    @Test("generation id validation")
    func ids() {
        #expect(Paths.isValidGenerationID("A1-b_2"))
        for bad in ["", "..", "a/b", "a b", "é", String(repeating: "a", count: 65)] {
            #expect(!Paths.isValidGenerationID(bad))
        }
    }

    @Test("protection helpers do not throw when files are missing")
    func protection() throws {
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let p = Paths(base: base)
        try p.applyCompleteProtection(toGeneration: p.generation("g1"))
        try Paths.applyCompleteProtection(toDirectory: base)
    }
}
