import SwiftUI

struct LogsView: View {
    @State private var logs: String = ""
    @State private var isLoading: Bool = true
    @State private var autoRefresh: Bool = false
    @State private var refreshTimer: Timer?
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView("Loading logs...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        ScrollViewReader { proxy in
                            VStack(alignment: .leading, spacing: 0) {
                                if logs.isEmpty {
                                    Text("No logs available")
                                        .foregroundStyle(.secondary)
                                        .padding()
                                } else {
                                    Text(logs)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                        .padding()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .id("bottom")
                            .onChange(of: logs) { _ in
                                if autoRefresh {
                                    withAnimation {
                                        proxy.scrollTo("bottom", anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                    .background(Color(.systemBackground))
                }
            }
            .navigationTitle("App Logs")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: copyLogs) {
                        Image(systemName: "doc.on.doc")
                    }
                    
                    Button(action: clearLogs) {
                        Image(systemName: "trash")
                    }
                    
                    Button(action: refreshLogs) {
                        Image(systemName: "arrow.clockwise")
                    }
                    
                    Toggle(isOn: $autoRefresh) {
                        Image(systemName: autoRefresh ? "timer" : "timer.slash")
                    }
                    .onChange(of: autoRefresh) { enabled in
                        if enabled {
                            startAutoRefresh()
                        } else {
                            stopAutoRefresh()
                        }
                    }
                }
            }
            .onAppear {
                AppLogger.log("LogsView appeared - loading logs")
                loadLogs()
            }
            .onDisappear {
                stopAutoRefresh()
            }
        }
    }
    
    private func loadLogs() {
        isLoading = true
        Task {
            let logContent = await readLogFile()
            await MainActor.run {
                self.logs = logContent
                self.isLoading = false
            }
        }
    }
    
    private func refreshLogs() {
        loadLogs()
    }
    
    private func copyLogs() {
        UIPasteboard.general.string = logs
    }
    
    private func clearLogs() {
        AppLogger.log("User requested log clear")
        Task {
            await clearLogFile()
            await MainActor.run {
                self.logs = ""
            }
        }
    }
    
    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            loadLogs()
        }
    }
    
    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private func readLogFile() async -> String {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .background).async {
                do {
                    guard let url = logFileURL() else {
                        continuation.resume(returning: "Error: Could not access log file location")
                        return
                    }
                    
                    if FileManager.default.fileExists(atPath: url.path) {
                        let content = try String(contentsOf: url, encoding: .utf8)
                        continuation.resume(returning: content)
                    } else {
                        continuation.resume(returning: "Log file does not exist yet. Run some Python code to generate logs.")
                    }
                } catch {
                    continuation.resume(returning: "Error reading log file: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func clearLogFile() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .background).async {
                do {
                    guard let url = logFileURL() else {
                        continuation.resume(returning: ())
                        return
                    }
                    
                    if FileManager.default.fileExists(atPath: url.path) {
                        try FileManager.default.removeItem(at: url)
                    }
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(returning: ())
                }
            }
        }
    }
    
    private func logFileURL() -> URL? {
        do {
            let url = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("log.txt")
            return url
        } catch {
            return nil
        }
    }
}

#Preview {
    LogsView()
}