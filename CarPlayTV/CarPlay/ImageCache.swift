import UIKit

/// In-memory cache of downscaled artwork for CarPlay list items.
@MainActor
final class ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSURL, UIImage>()

    func image(for url: URL, fitting size: CGSize) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        guard let (data, _) = try? await Net.session.data(from: url),
              let image = UIImage(data: data) else { return nil }

        let scale = min(size.width / image.size.width, size.height / image.size.height, 1)
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: target).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        cache.setObject(resized, forKey: url as NSURL)
        return resized
    }
}
