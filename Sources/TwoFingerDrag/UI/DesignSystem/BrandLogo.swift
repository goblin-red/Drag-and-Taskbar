import SwiftUI
import AppKit

/// Логотип Goblin из ресурсов бандла (`logo.svg`).
struct BrandLogo: View {
    private static let image: NSImage? = Bundle.main
        .url(forResource: "logo", withExtension: "svg")
        .flatMap { NSImage(contentsOf: $0) }

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "hand.draw")
        }
    }
}
