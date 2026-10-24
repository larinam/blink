import Foundation
import Testing
@testable import Blink

@Suite("State directory ownership")
struct StateDirectoryLockTests {
    @Test("A second writer is refused without changing the saved bytes")
    func contentionAndRelease() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BlinkLease-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        var owner: StateDirectoryLock? = try StateDirectoryLock(directory: directory)
        let saved = directory.appendingPathComponent("state.json")
        let original = Data("existing state".utf8)
        try original.write(to: saved)
        #expect(throws: StateDirectoryLock.Failure.alreadyRunning) {
            try StateDirectoryLock(directory: directory)
        }
        #expect(try Data(contentsOf: saved) == original)
        #expect(owner != nil)
        owner = nil
        // A persistent lock file is harmless; kernel ownership ends on close/exit.
        let nextOwner = try StateDirectoryLock(directory: directory)
        withExtendedLifetime(nextOwner) {
            #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(".instance.lock").path))
        }
    }

    @Test("Independent development state directories can run together")
    func isolatedDirectories() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BlinkLease-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try StateDirectoryLock(directory: directory.appendingPathComponent("first"))
        let second = try StateDirectoryLock(directory: directory.appendingPathComponent("second"))
        withExtendedLifetime((first, second)) {}
    }

    @Test("A directory alias cannot bypass ownership")
    func directoryAlias() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BlinkLease-\(UUID())")
        let alias = directory.appendingPathExtension("alias")
        defer {
            try? FileManager.default.removeItem(at: alias)
            try? FileManager.default.removeItem(at: directory)
        }
        let owner = try StateDirectoryLock(directory: directory)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: directory)
        withExtendedLifetime(owner) {
            #expect(throws: StateDirectoryLock.Failure.alreadyRunning) {
                try StateDirectoryLock(directory: alias)
            }
            return ()
        }
    }

    @Test("An unusable data directory fails closed")
    func invalidDirectory() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("BlinkLease-\(UUID())")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data().write(to: file)
        #expect(throws: (any Error).self) { try StateDirectoryLock(directory: file) }
    }
}
