import SwiftUI

struct NoteDetailView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "drop")
                .font(.largeTitle)
                .foregroundColor(.blue)
            Text("This screen is no longer used.")
            Text("Use the Today tab to log drinks.")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .navigationTitle("Hydration")
    }
}

#Preview {
    NoteDetailView()
}
