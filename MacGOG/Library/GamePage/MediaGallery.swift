import SwiftUI
import SwiftyGOG

/// Screenshots and artwork in a grid as wide as the column, folded to two rows until expanded.
/// Clicking one opens it full size.
struct MediaGallery: View {
    let images: [GalaxyImage]
    let open: (Int) -> Void

    @State private var showsAll = false

    /// Images shown before "Show All".
    private static let foldedCount = 6

    var body: some View {
        PageSection("Media") {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { index, image in
                        Button {
                            open(index)
                        } label: {
                            Color.clear
                                .aspectRatio(16 / 9, contentMode: .fit)
                                .overlay {
                                    ArtworkImage(
                                        url: image.thumbnail,
                                        placeholder: AnyShapeStyle(.white.opacity(0.08))
                                    )
                                }
                                .clipShape(.rect(cornerRadius: 12))
                                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .help("Show full size")
                        .accessibilityLabel("Image \(index + 1) of \(images.count)")
                    }
                }
                if images.count > Self.foldedCount {
                    Button(showsAll ? "Show Fewer" : "Show All \(images.count)") {
                        withAnimation(.snappy) { showsAll.toggle() }
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }

    private var shown: [GalaxyImage] {
        showsAll ? images : Array(images.prefix(Self.foldedCount))
    }
}

/// Shows one image of a gallery at full size, with the others a click or arrow key away.
struct MediaViewer: View {
    struct Request: Identifiable {
        let id = UUID()
        let images: [GalaxyImage]
        let index: Int
    }

    let request: Request

    @Environment(\.dismiss) private var dismiss
    @State private var index = 0

    var body: some View {
        ZStack {
            Color.black
            // The thumbnail is usually cached, so it shows at once while the full size loads.
            ArtworkImage(
                url: request.images[index].thumbnail,
                contentMode: .fit,
                placeholder: AnyShapeStyle(.clear),
                showsPlaceholderIcon: false
            )
            ArtworkImage(
                url: request.images[index].full,
                contentMode: .fit,
                placeholder: AnyShapeStyle(.clear),
                showsPlaceholderIcon: false
            )
            .id(index)
            HStack {
                navigationButton("chevron.left", disabled: index == 0) { index -= 1 }
                Spacer()
                navigationButton("chevron.right", disabled: index == request.images.count - 1) { index += 1 }
            }
            .padding(20)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.glass)
            .keyboardShortcut(.cancelAction)
            .padding(16)
        }
        .overlay(alignment: .bottom) {
            Text("\(index + 1) of \(request.images.count)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule)
                .padding(16)
        }
        .frame(minWidth: 960, idealWidth: 1280, minHeight: 600, idealHeight: 800)
        .environment(\.colorScheme, .dark)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) {
            index = max(index - 1, 0)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            index = min(index + 1, request.images.count - 1)
            return .handled
        }
        .onAppear { index = request.index }
    }

    private func navigationButton(_ symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View
    {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .frame(width: 28, height: 36)
        }
        .buttonStyle(.glass)
        .disabled(disabled)
        .opacity(disabled ? 0 : 1)
    }
}
