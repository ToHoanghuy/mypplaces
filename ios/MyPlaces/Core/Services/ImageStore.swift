import UIKit

/// Loads private `memory-media` objects through short-lived signed URLs (the storage policy
/// re-checks access on every sign), with a memory + disk cache keyed by storage path.
actor ImageStore {
    static let shared = ImageStore()

    private let memory = NSCache<NSString, UIImage>()
    private var inflight: [String: Task<UIImage?, Never>] = [:]
    private let directory: URL

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("media", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        memory.countLimit = 300
    }

    nonisolated func cached(_ path: String) -> UIImage? { memory.object(forKey: path as NSString) }

    func image(for path: String) async -> UIImage? {
        if let img = memory.object(forKey: path as NSString) { return img }
        if let task = inflight[path] { return await task.value }
        let file = fileURL(path)
        let task = Task<UIImage?, Never> {
            if let data = try? Data(contentsOf: file), let img = UIImage(data: data) { return img }
            do {
                let url = try await MyPlacesAPI.shared.signedURL(path: path)
                let (data, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode ?? 200 < 300, let img = UIImage(data: data) else { return nil }
                try? data.write(to: file, options: .atomic)
                return img
            } catch {
                return nil
            }
        }
        inflight[path] = task
        let result = await task.value
        inflight[path] = nil
        if let result { memory.setObject(result, forKey: path as NSString) }
        return result
    }

    /// Pre-fills the cache with bytes we just uploaded so the UI shows them instantly.
    func seed(path: String, data: Data) {
        try? data.write(to: fileURL(path), options: .atomic)
        if let img = UIImage(data: data) { memory.setObject(img, forKey: path as NSString) }
    }

    func clear() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileURL(_ path: String) -> URL {
        directory.appendingPathComponent(path.replacingOccurrences(of: "/", with: "_"))
    }
}
