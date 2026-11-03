import SwiftUI
import UIKit

extension Color {
    /// Primary interactive ink: black in Light Mode, white in Dark Mode.
    static let pinaxPlum = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .white : .black
    })

    static let pinaxRose = Color.primary

    /// The sketchbook's page, behind every board and detail.
    static let pinaxCanvas = Sketchbook.paper

    /// A sheet laid on the page.
    static let pinaxCardSurface = Sketchbook.sheet

    /// Behind an image while it loads.
    static let pinaxPreviewSurface = Sketchbook.wash

    init(pinaxHex hex: String?) {
        let cleaned = (hex ?? "")
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        guard cleaned.count == 6, Scanner(string: cleaned).scanHexInt64(&value) else {
            self = .accentColor
            return
        }

        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
