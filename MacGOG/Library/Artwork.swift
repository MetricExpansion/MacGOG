import AppKit
import Foundation
import SwiftUI

/// Loads artwork through a `URLSession` whose cache lives in `~/Library/Caches/MacGOG`.
nonisolated final class ArtworkLoader: Sendable {
    private let session: URLSession

    init(cache: URL) {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 1024 * 1024 * 1024,
            directory: cache
        )
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: configuration)
    }

    func data(for url: URL) async throws -> Data {
        guard url.scheme == "https" else { throw URLError(.unsupportedURL) }
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }
}

extension EnvironmentValues {
    @Entry var artworkLoader: ArtworkLoader?
}

/// Remote artwork with a placeholder while it loads or when there is none.
struct ArtworkImage: View {
    let url: URL?
    var contentMode = ContentMode.fill
    /// Shown behind the image, and alone while it loads or when there is none.
    var placeholder = AnyShapeStyle(.quaternary)
    var showsPlaceholderIcon = true

    @Environment(\.artworkLoader) private var loader
    @State private var image: NSImage?

    var body: some View {
        // The image is an overlay so its pixel size never drives layout; it fills whatever frame
        // the caller gives.
        Rectangle()
            .fill(placeholder)
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .transition(.opacity)
                } else if showsPlaceholderIcon {
                    Image(systemName: "gamecontroller")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                }
            }
            .clipped()
            .task(id: url) {
                guard let url, let loader else {
                    image = nil
                    return
                }
                guard let data = try? await loader.data(for: url) else { return }
                withAnimation(.easeIn(duration: 0.15)) {
                    image = NSImage(data: data)
                }
            }
    }
}
