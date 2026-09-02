import Foundation
import UIKit
import OSLog

/// Generates the studio photograph for a food, or reports that it can't.
///
/// Requests are de-duplicated by cache key, which matters more than it sounds: logging
/// "two eggs and eggs benedict" in one turn, or opening a catalog of thirty days that
/// all contain oatmeal, would otherwise fan out into a lot of identical paid requests.
actor FoodImageService {
    static let shared = FoodImageService()

    enum Provider: String, Sendable {
        case gemini
        case openAI

        var displayName: String {
            switch self {
            case .gemini: return "Gemini"
            case .openAI: return "OpenAI"
            }
        }
    }

    enum Failure: LocalizedError {
        case noProvider
        case renderFailed
        case http(status: Int, message: String)
        case noImageInResponse

        var errorDescription: String? {
            switch self {
            case .noProvider: return "No image key configured."
            case .renderFailed: return "Could not render this dish."
            case .http(let status, let message):
                return message.isEmpty ? "Image request failed (\(status))." : message
            case .noImageInResponse: return "The response contained no image."
            }
        }
    }

    private let cache: ImageCache
    private let logger = Logger(subsystem: "com.plate.Plate", category: "Imagery")
    private var inFlight: [String: Task<String, Error>] = [:]

    init(cache: ImageCache = .shared) {
        self.cache = cache
    }

    /// Whichever provider is configured. Gemini first — it is the faster and cheaper
    /// of the two for this job.
    nonisolated var provider: Provider? {
        if Credentials.has(.gemini) { return .gemini }
        if Credentials.has(.openAI) { return .openAI }
        return nil
    }

    /// True when a real photography backend is configured. Imagery itself is always
    /// available — the renderer needs nothing.
    nonisolated var isConfigured: Bool { provider != nil }

    /// Returns the cache file name for this food, producing it if needed.
    ///
    /// With a key configured this is a generated photograph; without one it is a local
    /// render of the same dish. Both end up as a cached JPEG, so every entry in the app
    /// has a real image file behind it and the rest of the UI needs no special case.
    func image(for entry: FoodEntry) async throws -> String {
        if let provider {
            let key = ImageCache.key(forFood: entry.name, kind: .photographed)
            if cache.hasImage(for: key) { return key }
            if let existing = inFlight[key] { return try await existing.value }

            let prompt = ImagePromptRecipe.prompt(
                for: entry.name,
                detail: entry.detail,
                quantity: entry.quantity
            )

            let task = Task<String, Error> { [cache, logger] in
                let data: Data
                switch provider {
                case .gemini: data = try await Self.generateWithGemini(prompt: prompt)
                case .openAI: data = try await Self.generateWithOpenAI(prompt: prompt)
                }
                guard cache.write(data, for: key) != nil else { throw Failure.noImageInResponse }
                logger.info("Photographed \(entry.name, privacy: .public)")
                return key
            }

            inFlight[key] = task
            defer { inFlight[key] = nil }
            return try await task.value
        }

        return try await renderedKey(forFood: entry.name)
    }

    /// Renders a dish locally and caches it. Also the path used by anything that wants
    /// an image for a food that is not a logged entry.
    func renderedKey(forFood name: String) async throws -> String {
        let key = ImageCache.key(forFood: name, kind: .rendered)
        if cache.hasImage(for: key) { return key }
        if let existing = inFlight[key] { return try await existing.value }

        let task = Task<String, Error> { [cache] in
            let recipe = FoodSceneRecipe(food: name)
            // Off the cooperative pool: this is a long, blocking GPU wait, and leaving
            // it on a shared executor stalls unrelated work.
            let image: UIImage? = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: FoodSceneRenderer.shared.render(recipe))
                }
            }
            guard let image, let data = image.jpegData(compressionQuality: 0.9),
                  cache.write(data, for: key) != nil
            else { throw Failure.renderFailed }
            return key
        }

        inFlight[key] = task
        defer { inFlight[key] = nil }
        return try await task.value
    }

    /// Convenience for views that want a rendered dish directly.
    nonisolated func renderedImage(forFood name: String) async -> UIImage? {
        let key = ImageCache.key(forFood: name, kind: .rendered)
        if let cached = ImageCache.shared.image(for: key) { return cached }
        guard (try? await renderedKey(forFood: name)) != nil else { return nil }
        return ImageCache.shared.image(for: key)
    }

    // MARK: Gemini
    //
    // The Interactions API. Nano Banana (gemini-3.1-flash-image) is the current
    // generalist image model; Imagen is being retired and is deliberately not used.

    private static func generateWithGemini(prompt: String) async throws -> Data {
        guard let key = Credentials.value(for: .gemini) else { throw Failure.noProvider }

        var request = URLRequest(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/interactions")!
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Header rather than a `?key=` query parameter — credentials do not belong in
        // a URL, where they end up in logs and proxies.
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")

        let body: JSONValue = [
            "model": "gemini-3.1-flash-image",
            "input": .array([.object(["type": "text", "text": .string(prompt)])]),
            "response_format": .object([
                "type": "image",
                "mime_type": "image/jpeg",
                "aspect_ratio": "1:1",
                "image_size": "1K"
            ])
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data: data)

        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        // Walk the steps rather than indexing [0]: a response can lead with a
        // non-image step, and hard-coding the position breaks the moment it does.
        guard let steps = decoded["interaction"]?["steps"]?.array else {
            throw Failure.noImageInResponse
        }
        for step in steps {
            for block in step["content"]?.array ?? [] where block["type"]?.string == "image" {
                if let base64 = block["data"]?.string, let bytes = Data(base64Encoded: base64) {
                    return bytes
                }
            }
        }
        throw Failure.noImageInResponse
    }

    // MARK: OpenAI

    private static func generateWithOpenAI(prompt: String) async throws -> Data {
        guard let key = Credentials.value(for: .openAI) else { throw Failure.noProvider }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/images/generations")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let body: JSONValue = [
            "model": "gpt-image-1-mini",
            "prompt": .string(prompt),
            "size": "1024x1024",
            "quality": "medium",
            "output_format": "jpeg",
            "n": 1
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data: data)

        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        guard let base64 = decoded["data"]?.array?.first?["b64_json"]?.string,
              let bytes = Data(base64Encoded: base64)
        else { throw Failure.noImageInResponse }
        return bytes
    }

    // MARK: Shared

    private static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode != 200 else { return }
        let decoded = try? JSONDecoder().decode(JSONValue.self, from: data)
        let message = decoded?["error"]?["message"]?.string
            ?? decoded?["error"]?["status"]?.string
            ?? ""
        throw Failure.http(status: http.statusCode, message: message)
    }
}
