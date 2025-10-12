import SwiftUI

struct AnimatedProgressBar: View {
    var value: Double
    var total: Double

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let ratio = total > 0 ? max(0.0, min(1.0, value / total)) : 0
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.15))
                Capsule(style: .continuous)
                    .fill(LinearGradient(colors: [.blue, .indigo], startPoint: .leading, endPoint: .trailing))
                    .frame(width: width * ratio)
                    .shadow(color: .blue.opacity(0.25), radius: 6, x: 0, y: 2)
            }
            .animation(.easeInOut(duration: 0.35), value: value)
        }
        .frame(height: 10)
        .clipShape(Capsule())
    }
}

