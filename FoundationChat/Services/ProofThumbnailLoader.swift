import Foundation
import ImageIO
import UIKit

/// Small, cached thumbnails for collection proof photos.
///
/// Each list row used to resolve the file URL over the network and then let
/// `AsyncImage` download the full camera photo for a 72 pt tile, with no
/// memory cache, so scrolling back re-downloaded everything. This resolves a
/// storage id once, downsamples to the tile size with ImageIO, and keeps the
/// result in memory. Concurrent requests for the same id share one load.
actor ProofThumbnailLoader {
    static let shared = ProofThumbnailLoader()

    private nonisolated(unsafe) let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 400
        return cache
    }()
    private var urls: [String: URL] = [:]
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    /// Synchronous hit for the first frame, so cached rows never flash a spinner.
    nonisolated func cached(_ storageId: String) -> UIImage? {
        images.object(forKey: storageId as NSString)
    }

    func thumbnail(storageId: String, token: String, maxPixel: Int) async -> UIImage? {
        if let hit = images.object(forKey: storageId as NSString) { return hit }
        if let running = inFlight[storageId] { return await running.value }
        let task = Task<UIImage?, Never> { [weak self] in
            guard let self else { return nil }
            guard let url = await self.resolveURL(storageId: storageId, token: token),
                  let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true
            else { return nil }
            return Self.downsample(data, maxPixel: maxPixel)
        }
        inFlight[storageId] = task
        let image = await task.value
        inFlight[storageId] = nil
        if let image { images.setObject(image, forKey: storageId as NSString) }
        return image
    }

    private func resolveURL(storageId: String, token: String) async -> URL? {
        if let known = urls[storageId] { return known }
        guard let url = try? await PostSalesStorageService.getFileURL(token: token, storageId: storageId) else {
            return nil
        }
        urls[storageId] = url
        return url
    }

    nonisolated static func downsample(_ data: Data, maxPixel: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
