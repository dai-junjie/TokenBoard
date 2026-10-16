import Foundation

public protocol SnapshotStore: Sendable {
    func load() -> LabforgeSnapshot?
    func save(_ snapshot: LabforgeSnapshot)
}

public final class FileSnapshotStore: SnapshotStore, @unchecked Sendable {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = appSupport.appendingPathComponent("LabforgeMenuBar", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("snapshot.json")
    }

    public func load() -> LabforgeSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return try? decoder.decode(LabforgeSnapshot.self, from: data)
    }

    public func save(_ snapshot: LabforgeSnapshot) {
        guard let data = try? encoder.encode(snapshot) else {
            return
        }
        try? data.write(to: fileURL, options: .atomic)
    }
}

public final class InMemorySnapshotStore: SnapshotStore, @unchecked Sendable {
    public private(set) var snapshot: LabforgeSnapshot?

    public init(snapshot: LabforgeSnapshot? = nil) {
        self.snapshot = snapshot
    }

    public func load() -> LabforgeSnapshot? {
        snapshot
    }

    public func save(_ snapshot: LabforgeSnapshot) {
        self.snapshot = snapshot
    }
}
