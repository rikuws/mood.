import SwiftUI
import UIKit

extension Color {
    static let pinaxPlum = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            UIColor(
                red: 113.0 / 255.0,
                green: 105.0 / 255.0,
                blue: 183.0 / 255.0,
                alpha: 1
            )
        } else {
            UIColor(
                red: 48.0 / 255.0,
                green: 42.0 / 255.0,
                blue: 98.0 / 255.0,
                alpha: 1
            )
        }
    })

    static let pinaxRose = Color(
        red: 226.0 / 255.0,
        green: 93.0 / 255.0,
        blue: 139.0 / 255.0
    )

    static let pinaxCanvas = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            UIColor(red: 20.0 / 255.0, green: 19.0 / 255.0, blue: 25.0 / 255.0, alpha: 1)
        } else {
            UIColor(red: 244.0 / 255.0, green: 244.0 / 255.0, blue: 242.0 / 255.0, alpha: 1)
        }
    })

    static let pinaxCardSurface = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            UIColor(red: 32.0 / 255.0, green: 31.0 / 255.0, blue: 37.0 / 255.0, alpha: 1)
        } else {
            .white
        }
    })

    static let pinaxPreviewSurface = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            UIColor(red: 41.0 / 255.0, green: 39.0 / 255.0, blue: 47.0 / 255.0, alpha: 1)
        } else {
            UIColor(red: 232.0 / 255.0, green: 231.0 / 255.0, blue: 228.0 / 255.0, alpha: 1)
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
