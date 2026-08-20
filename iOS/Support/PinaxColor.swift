import SwiftUI
import UIKit

extension Color {
    /// Primary interactive ink: black in Light Mode, white in Dark Mode.
    static let pinaxPlum = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .white : .black
    })

    static let pinaxRose = Color.primary

    static let pinaxCanvas = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            .black
        } else {
            UIColor(white: 0.96, alpha: 1)
        }
    })

    static let pinaxCardSurface = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            UIColor(white: 0.067, alpha: 1)
        } else {
            .white
        }
    })

    static let pinaxPreviewSurface = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            UIColor(white: 0.102, alpha: 1)
        } else {
            UIColor(white: 0.941, alpha: 1)
        }
    })

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
