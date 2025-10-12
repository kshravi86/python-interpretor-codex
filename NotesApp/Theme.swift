import SwiftUI

enum WaterTheme {
    static let tint: Color = Color.blue

    static let primary: Color = Color.blue
    static let secondary: Color = Color.cyan
    static let accent: Color = Color.indigo

    static func gradient(for scheme: ColorScheme) -> LinearGradient {
        switch scheme {
        case .light:
            // Sky‑blue gradient for a brighter, energetic feel
            return LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.64, blue: 0.92), // cyan‑sky
                    Color(red: 0.14, green: 0.44, blue: 0.95)  // deep sky blue
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        default:
            // Deeper blues in dark mode for contrast
            return LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.23, blue: 0.58),
                    Color(red: 0.03, green: 0.15, blue: 0.38)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    static func cardBackground() -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(.systemBackground))
    }

    static func softStroke(corner: CGFloat = 16) -> some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
    }
}
