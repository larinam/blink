import BlinkCore
import Foundation

struct StateStore {
    private struct Envelope: Codable {
        let version: Int
        let state: EngineState
    }
    let directory: URL
    var file: URL { directory.appendingPathComponent("state.json") }

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else if let override = ProcessInfo.processInfo.environment["BLINK_STATE_DIR"] {
            self.directory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            self.directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Blink", isDirectory: true)
        }
    }

    func load() throws -> EngineState? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: file))
        guard envelope.version == 1 else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: "This saved state belongs to a different version of Blink."])
        }
        return envelope.state
    }

    func save(_ state: EngineState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(Envelope(version: 1, state: state))
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
