import SwiftUI

struct LogsView: View {
    @State private var logs: String = ""
    @State private var crashLogs: String = ""
    @State private var isLoading: Bool = true
    @State private var autoRefresh: Bool = false
    @State private var refreshTimer: Timer?
    @State private var showingCrashLogs: Bool = false
    
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
                                let displayText = showingCrashLogs ? crashLogs : logs
                                if displayText.isEmpty {
                                    Text(showingCrashLogs ? "No crash logs available" : "No logs available")
                                        .foregroundStyle(.secondary)
                                        .padding()
                                } else {
                                    Text(displayText)
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
            .navigationTitle(showingCrashLogs ? "Crash Logs" : "App Logs")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: toggleLogType) {
                        Image(systemName: showingCrashLogs ? "exclamationmark.triangle" : "doc.text")
                    }
                    
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
                loadCrashLogs()
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
            let crashLogContent = await readCrashLogFile()
            await MainActor.run {
                self.logs = logContent
                self.crashLogs = crashLogContent
                self.isLoading = false
            }
        }
    }
    
    private func refreshLogs() {
        loadLogs()
    }
    
    private func copyLogs() {
        let textToCopy = showingCrashLogs ? crashLogs : logs
        UIPasteboard.general.string = textToCopy
    }
    
    private func clearLogs() {
        AppLogger.log("User requested log clear")
        Task {
            if showingCrashLogs {
                await clearCrashLogFile()
                await MainActor.run {
                    self.crashLogs = ""
                }
            } else {
                await clearLogFile()
                await MainActor.run {
                    self.logs = ""
                }
            }
        }
    }
    
    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            loadLogs()
            if showingCrashLogs {
                loadCrashLogs()
            }
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
    
    private func crashLogURL() -> URL? {
        do {
            let url = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("crash_log.txt")
            return url
        } catch {
            return nil
        }
    }
    
    private func toggleLogType() {
        showingCrashLogs.toggle()
        if showingCrashLogs {
            loadCrashLogs()
        }
    }
    
    private func loadCrashLogs() {
        Task {
            let crashLogContent = await readCrashLogFile()
            await MainActor.run {
                self.crashLogs = crashLogContent
            }
        }
    }
    
    private func readCrashLogFile() async -> String {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .background).async {
                do {
                    guard let url = crashLogURL() else {
                        continuation.resume(returning: "Error: Could not access crash log file location")
                        return
                    }
                    
                    if FileManager.default.fileExists(atPath: url.path) {
                        let content = try String(contentsOf: url, encoding: .utf8)
                        continuation.resume(returning: content)
                    } else {
                        continuation.resume(returning: "No crash logs available yet.")
                    }
                } catch {
                    continuation.resume(returning: "Error reading crash log file: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func clearCrashLogFile() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .background).async {
                do {
                    guard let url = crashLogURL() else {
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
}

#Preview {
    LogsView()
}