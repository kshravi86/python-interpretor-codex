import SwiftUI

struct CelebrationOverlay: View {
    @Binding var isVisible: Bool

    @State private var scale: CGFloat = 0.6
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            Color.black.opacity(opacity * 0.35).ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
                    .scaleEffect(scale)
                    .overlay(confetti)

                Text("Goal Reached!")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 3)

                Text("Nice work staying hydrated today")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
            }
            .padding(24)
            .background(.ultraThinMaterial.opacity(0.2))
            .background(Color.blue.opacity(0.75))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .blue.opacity(0.25), radius: 20, x: 0, y: 8)
        }
        .onAppear { animateInThenOut() }
    }

    private var confetti: some View {
        ZStack {
            ForEach(0..<12) { i in
                let angle = Double(i) / 12.0 * 2.0 * Double.pi
                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 4, height: 10)
                    .offset(x: CGFloat(cos(angle)) * 30, y: CGFloat(sin(angle)) * 30)
                    .rotationEffect(.degrees(Double(i) * 30))
                    .opacity(opacity)
            }
        }
    }

    private func animateInThenOut() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
            scale = 1.0
            opacity = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeInOut(duration: 0.35)) {
                opacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                isVisible = false
                scale = 0.6
            }
        }
    }
}

