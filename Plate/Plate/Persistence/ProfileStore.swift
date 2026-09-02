import Foundation

/// The user's profile, on disk as one small JSON file.
///
/// Separate from `LogStore` because its lifetime is different: it is read on nearly
/// every agent request and written rarely, so it stays resident and writes through
/// immediately rather than being debounced.
actor ProfileStore {
    static let shared = ProfileStore()

    private let url: URL
    private var cached: UserProfile

    init(url: URL? = nil) {
        let location = url ?? URL.applicationSupportDirectory.appending(path: "Plate/profile.json")
        self.url = location
        try? FileManager.default.createDirectory(
            at: location.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if let data = try? Data(contentsOf: location),
           let decoded = try? JSONDecoder.plate.decode(UserProfile.self, from: data) {
            cached = decoded
        } else {
            cached = UserProfile()
        }
    }

    func profile() -> UserProfile { cached }

    @discardableResult
    func update(_ mutate: (inout UserProfile) -> Void) -> UserProfile {
        mutate(&cached)
        if let data = try? JSONEncoder.plate.encode(cached) {
            try? data.write(to: url, options: [.atomic])
        }
        return cached
    }
}

extension JSONDecoder {
    static var plate: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension JSONEncoder {
    static var plate: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
