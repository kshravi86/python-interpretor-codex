import SwiftUI

struct ErrorLogView: View {
    @State private var entries: [ErrorLogEntry] = []

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView("No Errors Logged", systemImage: "checkmark.seal", description: Text("Great job! We'll show crashes and errors here."))
            } else {
                ForEach(entries) { e in
                    NavigationLink(destination: ErrorDetailView(entry: e)) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(e.kind.rawValue.capitalized, systemImage: icon(for: e.kind))
                                    .labelStyle(.titleAndIcon)
                                Spacer()
                                Text(e.date.formatted(date: .abbreviated, time: .standard))
                                    .foregroundStyle(.secondary)
                                    .font(.footnote)
                            }
                            Text(e.title)
                                .font(.subheadline)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Error Logs")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    ErrorLogger.shared.clear()
                    load()
                } label: { Label("Clear", systemImage: "trash") }
                .disabled(entries.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { load() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            }
        }
        .onAppear { load() }
    }

    private func load() { entries = ErrorLogger.shared.logs().reversed() }

    private func icon(for kind: ErrorLogEntry.Kind) -> String {
        switch kind {
        case .error: return "exclamationmark.triangle"
        case .exception: return "bolt.trianglebadge.exclamationmark"
        case .signal: return "waveform.path.ecg"
        case .message: return "text.bubble"
        }
    }
}

private struct ErrorDetailView: View {
    let entry: ErrorLogEntry
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(entry.kind.rawValue.capitalized, systemImage: "doc.text.magnifyingglass")
                    Spacer()
                    Text(entry.date.formatted(date: .abbreviated, time: .standard))
                        .foregroundStyle(.secondary)
                }
                .font(.headline)
                Text(entry.title)
                    .font(.body)
                if let d = entry.details, !d.isEmpty {
                    Divider()
                    Text(d)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .padding()
        }
        .navigationTitle("Log Detail")
    }
}

