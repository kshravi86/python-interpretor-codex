import SwiftUI

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var subtitle: String? = nil
    var systemImage: String = "drop.fill"
}

private struct ToastView: View {
    let toast: Toast
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.systemImage)
                .foregroundColor(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(.subheadline).bold()
                    .foregroundColor(.white)
                if let subtitle = toast.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial.opacity(0.35))
        .background(WaterTheme.tint.opacity(0.85))
        .clipShape(Capsule())
        .shadow(color: WaterTheme.tint.opacity(0.25), radius: 10, x: 0, y: 4)
        .padding(.horizontal, 16)
    }
}

private struct ToastPresenter: ViewModifier {
    @Binding var toast: Toast?
    let duration: TimeInterval

    @State private var isVisible = false

    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content
            if let toast = toast, isVisible {
                VStack { Spacer().frame(height: 12); ToastView(toast: toast); Spacer() }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onChange(of: toast) { _, newValue in
            guard newValue != nil else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { isVisible = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                withAnimation(.easeInOut(duration: 0.25)) { isVisible = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { toast = nil }
            }
        }
    }
}

extension View {
    func toast(_ toast: Binding<Toast?>, duration: TimeInterval = 1.6) -> some View {
        modifier(ToastPresenter(toast: toast, duration: duration))
    }
}

