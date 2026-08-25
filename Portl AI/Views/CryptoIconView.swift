import SwiftUI

/// Shared image cache for coin icons — avoids re-downloading on every view update
@MainActor
final class CoinImageCache {
    static let shared = CoinImageCache()
    private var cache: [String: UIImage] = [:]
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        // 50 MB disk cache, 20 MB memory cache
        config.urlCache = URLCache(
            memoryCapacity: 20 * 1024 * 1024,
            diskCapacity: 50 * 1024 * 1024
        )
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    func image(for urlString: String) async -> UIImage? {
        if let cached = cache[urlString] { return cached }

        // Deduplicate concurrent requests for the same URL
        if let existing = inFlight[urlString] {
            return await existing.value
        }

        let task = Task<UIImage?, Never> {
            guard let url = URL(string: urlString) else { return nil }
            do {
                let (data, _) = try await Self.session.data(from: url)
                let img = UIImage(data: data)
                if let img { cache[urlString] = img }
                return img
            } catch {
                return nil
            }
        }
        inFlight[urlString] = task
        let result = await task.value
        inFlight.removeValue(forKey: urlString)
        return result
    }
}

/// Reusable crypto icon that loads the coin's image from CoinGecko with caching
struct CryptoIconView: View {

    let imageURL: String?
    let symbol: String
    var size: CGFloat = 48

    @State private var loadedImage: UIImage?
    @State private var didAttemptLoad = false

    var body: some View {
        Group {
            if let loadedImage {
                Image(uiImage: loadedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else if didAttemptLoad {
                fallbackIcon
            } else {
                fallbackIcon
                    .onAppear { loadIcon() }
            }
        }
    }

    private func loadIcon() {
        guard let imageURL else {
            didAttemptLoad = true
            return
        }
        Task {
            let img = await CoinImageCache.shared.image(for: imageURL)
            loadedImage = img
            didAttemptLoad = true
        }
    }

    private var fallbackIcon: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.15))
            .frame(width: size, height: size)
            .overlay {
                Text(symbol.prefix(2).uppercased())
                    .font(.caption.bold())
                    .foregroundStyle(.tint)
            }
    }
}
