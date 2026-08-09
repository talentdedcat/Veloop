import CoreGraphics
import Foundation
import ImageIO

final class ImagePreviewLoader {
    static let maximumPixelSize = 320
    static let maximumCacheCost = 6 * 1_024 * 1_024

    private let blobReader: PreviewBlobReading
    private let cache = NSCache<NSString, CGImageBox>()
    private let lock = NSLock()
    private var costs: [String: Int] = [:]
    private var order: [String] = []
    private var totalCost = 0
    private var generation: UInt64 = 0

    init(blobReader: PreviewBlobReading) {
        self.blobReader = blobReader
        cache.totalCostLimit = Self.maximumCacheCost
    }

    var cachedCost: Int {
        lock.withPreviewLock { totalCost }
    }

    func image(for blobHash: String) throws -> CGImage? {
        if let cached = cachedImage(for: blobHash) {
            return cached
        }
        let requestedGeneration = lock.withPreviewLock { generation }
        let data = try blobReader.data(for: blobHash)
        guard let image = autoreleasepool(invoking: { Self.downsample(data) }) else {
            return nil
        }
        insert(image, for: blobHash, generation: requestedGeneration)
        return image
    }

    func clear() {
        lock.withPreviewLock {
            generation &+= 1
            cache.removeAllObjects()
            costs.removeAll(keepingCapacity: false)
            order.removeAll(keepingCapacity: false)
            totalCost = 0
        }
    }

    private func cachedImage(for hash: String) -> CGImage? {
        lock.withPreviewLock {
            guard let image = cache.object(forKey: hash as NSString)?.image else {
                if let oldCost = costs.removeValue(forKey: hash) {
                    totalCost -= oldCost
                    order.removeAll { $0 == hash }
                }
                return nil
            }
            order.removeAll { $0 == hash }
            order.append(hash)
            return image
        }
    }

    private func insert(_ image: CGImage, for hash: String, generation requestedGeneration: UInt64) {
        let cost = image.bytesPerRow * image.height
        lock.withPreviewLock {
            guard generation == requestedGeneration else { return }
            if let previousCost = costs.removeValue(forKey: hash) {
                totalCost -= previousCost
                order.removeAll { $0 == hash }
            }
            while totalCost + cost > Self.maximumCacheCost, let oldest = order.first {
                order.removeFirst()
                cache.removeObject(forKey: oldest as NSString)
                totalCost -= costs.removeValue(forKey: oldest) ?? 0
            }
            cache.setObject(CGImageBox(image), forKey: hash as NSString, cost: cost)
            costs[hash] = cost
            order.append(hash)
            totalCost += cost
        }
    }

    private static func downsample(_ data: Data) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

private final class CGImageBox: NSObject {
    let image: CGImage

    init(_ image: CGImage) {
        self.image = image
    }
}

private extension NSLock {
    func withPreviewLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
