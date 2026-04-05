import Foundation

struct SavedRoute: Codable, Equatable {
    let bundleID: String
    let appName: String
    let channelSlot: Int
    let volume: Float
    var pan: Float = 0.0

    // Backward-compatible decoding for sessions saved before pan was added
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try container.decode(String.self, forKey: .bundleID)
        appName = try container.decode(String.self, forKey: .appName)
        channelSlot = try container.decode(Int.self, forKey: .channelSlot)
        volume = try container.decode(Float.self, forKey: .volume)
        pan = try container.decodeIfPresent(Float.self, forKey: .pan) ?? 0.0
    }

    init(bundleID: String, appName: String, channelSlot: Int, volume: Float, pan: Float = 0.0) {
        self.bundleID = bundleID
        self.appName = appName
        self.channelSlot = channelSlot
        self.volume = volume
        self.pan = pan
    }
}

struct SessionData: Codable {
    let routes: [SavedRoute]
}

final class SessionStore {
    private let directory: URL
    private let filename = "session.json"

    private var fileURL: URL {
        directory.appendingPathComponent(filename)
    }

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            guard let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first else {
                self.directory = FileManager.default.temporaryDirectory.appendingPathComponent("SiggiSig")
                return
            }
            self.directory = appSupport.appendingPathComponent("SiggiSig")
        }
    }

    func save(routes: [SavedRoute]) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        let data = SessionData(routes: routes)
        let json = try JSONEncoder().encode(data)
        try json.write(to: fileURL, options: .atomic)
    }

    func load() throws -> [SavedRoute] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        let session = try JSONDecoder().decode(SessionData.self, from: data)
        return session.routes
    }
}
