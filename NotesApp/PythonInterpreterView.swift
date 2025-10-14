import SwiftUI
import UIKit
import CryptoKit

struct PythonInterpreterView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var code: String = """
print('Hello from Python!')
for i in range(3):
    print(i)
"""
    @State private var output: String = ""
    @State private var isRunning: Bool = false
    @State private var lastError: String? = nil
    @State private var autorunSavePath: String? = nil
    @State private var fontSize: CGFloat = 15
    @State private var runDuration: Double? = nil
    @State private var useDarkAppearance: Bool = false
    @State private var useDarkSyntaxTheme: Bool = false
    @State private var breakpoints: [Int: String] = [:]
    @State private var navigateToLine: Int? = nil
    @State private var showingBreakpoints: Bool = false
    @State private var editingBreakpointLine: Int? = nil
    @State private var editingCondition: String = ""
    @State private var showEditConditionSheet: Bool = false
    @State private var showingLogs: Bool = false
    @State private var logContent: String = ""

    private let executor: PythonExecutor = CPythonExecutor()

    var body: some View {
        VStack(spacing: 0) {
            headerControls
            editor
            Divider()
            outputView
            consoleControls
        }
        .navigationTitle("Python Runner")
        .toolbar { runToolbar }
        .onAppear { AppLogger.log("InterpreterView appear"); loadPersisted(); loadPersistedBreakpoints(); applyAutorunFromArgumentsIfNeeded() }
        .onChange(of: code) { _ in 
            AppLogger.log("Code changed from editor; persisting and refreshing breakpoints")
            persist(); loadPersistedBreakpoints() 
        }
        .onChange(of: fontSize) { newValue in
            AppLogger.log("Font size changed: \(newValue)")
        }
        .onChange(of: breakpoints) { _ in persistBreakpoints() }
        .preferredColorScheme(useDarkAppearance ? .dark : nil)
        .sheet(isPresented: $showingBreakpoints) { breakpointsSheet }
        .sheet(isPresented: $showEditConditionSheet) { conditionEditorSheet }
        .sheet(isPresented: $showingLogs) { 
            NavigationView {
                VStack {
                    ScrollView {
                        Text(logContent)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Color(.systemBackground))
                }
                .navigationTitle("App Logs")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { showingLogs = false }
                    }
                }
                .onAppear {
                    loadLogContent()
                }
            }
        }
    }

    private var editor: some View {
        CodeEditorView(text: $code, breakpoints: $breakpoints, navigateToLine: $navigateToLine, fontSize: fontSize, isDark: useDarkAppearance, theme: useDarkSyntaxTheme ? SyntaxHighlighter.Theme.defaultDark() : SyntaxHighlighter.Theme.defaultLight(), onEditCondition: { line in
            editingBreakpointLine = line
            editingCondition = breakpoints[line] ?? ""
            showEditConditionSheet = true
        })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
    }

    private var outputView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let lastError {
                    Text(lastError)
                        .foregroundStyle(.red)
                        .font(.system(.footnote, design: .monospaced))
                        .padding(.bottom, 4)
                }
                if let dur = runDuration {
                    Text(String(format: "Ran in %.2fs", dur))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if !output.isEmpty {
                    Text(output)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else if !isRunning {
                    Text("Output will appear here…")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .background(Color(.secondarySystemBackground))
        .frame(maxWidth: .infinity, maxHeight: 220)
    }

    private var headerControls: some View {
        HStack(spacing: 12) {
            Menu("Examples") {
                ForEach(SnippetsCatalog.all) { s in
                    Button(s.title) { 
                        AppLogger.log("Example selected: \(s.title)")
                        code = s.code 
                    }
                }
            }
            .buttonStyle(.bordered)

            HStack {
                Image(systemName: "textformat.size")
                Slider(value: $fontSize, in: 12...22)
                    .frame(width: 140)
            }
            Menu {
                Button("Light Theme") { 
                    AppLogger.log("Theme set to Light")
                    useDarkAppearance = false; useDarkSyntaxTheme = false 
                }
                Button("Dark Theme") { 
                    AppLogger.log("Theme set to Dark")
                    useDarkAppearance = true; useDarkSyntaxTheme = true 
                }
            } label: {
                Label("Theme", systemImage: useDarkSyntaxTheme ? "moon.fill" : "sun.max.fill")
            }
            .buttonStyle(.bordered)
            Button {
                AppLogger.log("Breakpoints sheet opened")
                showingBreakpoints = true
            } label: {
                Label("Breakpoints", systemImage: "bookmark.circle")
            }
            .buttonStyle(.bordered)
            
            Button {
                AppLogger.log("Logs sheet opened")
                showingLogs = true
            } label: {
                Label("Logs", systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(.bordered)

            Spacer()

            if isRunning { ProgressView().scaleEffect(0.9) }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }

    private var consoleControls: some View {
        HStack(spacing: 12) {
            Button {
                AppLogger.log("Copy Output tapped, length=\(output.count)")
                UIPasteboard.general.string = output
            } label: {
                Label("Copy Output", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                AppLogger.log("Clear console tapped")
                output = ""; lastError = nil; runDuration = nil
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }

    @ToolbarContentBuilder
    private var runToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                AppLogger.log("RUN button tapped - about to call runCode()")
                Task { 
                    AppLogger.log("Task started for runCode()")
                    await runCode() 
                    AppLogger.log("runCode() task completed")
                }
            } label: {
                if isRunning { ProgressView() } else { Text("Run") }
            }
            .disabled(isRunning || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func runCode() async {
        AppLogger.log("=== PythonInterpreterView.runCode() START ===")
        AppLogger.log("Code to execute (length: \(code.count) chars):")
        AppLogger.log("Code content: '\(code)'")
        
        await MainActor.run {
            AppLogger.log("Setting UI state: isRunning = true")
            self.isRunning = true
            self.lastError = nil
            self.output = ""
            self.runDuration = nil
        }
        
        let start = Date()
        AppLogger.log("Execution started at: \(start)")
        
        do {
            AppLogger.log("About to call executor.execute() with CPythonExecutor")
            AppLogger.log("Executor type: \(type(of: executor))")
            
            let result = try await executor.execute(code: code)
            
            AppLogger.log("=== EXECUTION RESULT RECEIVED ===")
            AppLogger.log("Exit code: \(result.exitCode ?? -999)")
            AppLogger.log("Stdout length: \(result.stdout.count) bytes")
            AppLogger.log("Stderr length: \(result.stderr.count) bytes")
            
            if !result.stdout.isEmpty {
                AppLogger.log("Stdout content: '\(result.stdout)'")
            }
            if !result.stderr.isEmpty {
                AppLogger.log("Stderr content: '\(result.stderr)'")
            }
            
            // Combine output
            AppLogger.log("Combining output strings...")
            var combined = ""
            if let status = result.exitCode { 
                combined += "[exit \(status)]\n" 
                AppLogger.log("Added exit code to output: \(status)")
            }
            if !result.stdout.isEmpty { 
                combined += result.stdout 
                AppLogger.log("Added stdout to combined output")
            }
            if !result.stderr.isEmpty {
                if !combined.isEmpty { combined += (combined.hasSuffix("\n") ? "" : "\n") }
                combined += result.stderr
                AppLogger.log("Added stderr to combined output")
            }
            if combined.isEmpty { 
                combined = "(no output)" 
                AppLogger.log("No output generated, using placeholder text")
            }
            
            let finalCombined = combined
            AppLogger.log("Final combined output length: \(finalCombined.count) chars")
            AppLogger.log("Final combined output: '\(finalCombined)'")
            
            await MainActor.run { 
                AppLogger.log("Updating UI with execution result")
                self.output = finalCombined 
            }
            
            if let autorunPath = autorunSavePath {
                AppLogger.log("Writing autorun output to: \(autorunPath)")
                writeAutorunOutput(finalCombined)
            }
            
            let duration = Date().timeIntervalSince(start)
            await MainActor.run { 
                AppLogger.log("Setting execution duration: \(duration)s")
                self.runDuration = duration 
            }
            
            AppLogger.log("Execution completed successfully")
            
        } catch {
            AppLogger.log("=== EXECUTION FAILED WITH ERROR ===")
            AppLogger.log("Error type: \(type(of: error))")
            AppLogger.log("Error description: '\(error.localizedDescription)'")
            AppLogger.log("Error domain: \((error as NSError).domain)")
            AppLogger.log("Error code: \((error as NSError).code)")
            AppLogger.log("Error userInfo: \((error as NSError).userInfo)")
            
            let errorMessage: String
            if error.localizedDescription.contains("not configured") || error.localizedDescription.contains("not available") {
                errorMessage = "Python runtime not configured. This build may not include Python support."
                AppLogger.log("Using runtime not configured error message")
            } else {
                errorMessage = "Run failed: \(error.localizedDescription)"
                AppLogger.log("Using generic error message")
            }
            
            AppLogger.log("Final error message: '\(errorMessage)'")
            
            let duration = Date().timeIntervalSince(start)
            await MainActor.run {
                AppLogger.log("Setting error state in UI")
                self.lastError = errorMessage
                self.runDuration = duration
            }
            
            if let autorunPath = autorunSavePath {
                AppLogger.log("Writing autorun error to: \(autorunPath)")
                writeAutorunOutput("ERROR: \(error.localizedDescription)")
            }
        }
        
        await MainActor.run { 
            AppLogger.log("Setting UI state: isRunning = false")
            self.isRunning = false 
        }
        
        let totalDuration = Date().timeIntervalSince(start)
        AppLogger.log("=== PythonInterpreterView.runCode() COMPLETE ===")
        AppLogger.log("Total execution time: \(totalDuration)s")
    }

    private func applyAutorunFromArgumentsIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--autorun-b64"), i + 1 < args.count {
            AppLogger.log("Autorun argument detected")
            let b64 = args[i + 1]
            if let data = Data(base64Encoded: b64), let snippet = String(data: data, encoding: .utf8) {
                AppLogger.log("Decoded autorun snippet, length=\(snippet.count)")
                self.code = snippet
            }
            if let j = args.firstIndex(of: "--autorun-save"), j + 1 < args.count {
                self.autorunSavePath = args[j + 1]
                AppLogger.log("Autorun save path set: \(self.autorunSavePath ?? "nil")")
            }
            AppLogger.log("Scheduling autorun via Task")
            Task { await runCode() }
        }
    }

    private func writeAutorunOutput(_ text: String) {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let name = autorunSavePath?.isEmpty == false ? autorunSavePath! : "autorun.txt"
        let url = docs.appendingPathComponent(name)
        do {
            try text.data(using: .utf8)?.write(to: url)
            AppLogger.log("Autorun output written to \(url.path)")
        } catch {
            AppLogger.log("Failed writing autorun output: \(error.localizedDescription)")
        }
    }

    private func persist() {
        AppLogger.log("Persisting editor code, length=\(code.count)")
        UserDefaults.standard.set(code, forKey: "editor.code")
    }
    private func loadPersisted() {
        if let s = UserDefaults.standard.string(forKey: "editor.code"), !s.isEmpty {
            AppLogger.log("Loaded persisted editor code, length=\(s.count)")
            code = s
        } else {
            AppLogger.log("No persisted editor code found")
        }
    }

    private var breakpointsSheet: some View {
        NavigationView {
            List {
                if breakpoints.isEmpty {
                    Text("No breakpoints").foregroundStyle(.secondary)
                }
                ForEach(Array(breakpoints.keys).sorted(), id: \.self) { line in
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Line \(line)")
                            if let cond = breakpoints[line], !cond.isEmpty {
                                Text(cond).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Go") { 
                            AppLogger.log("Breakpoint Go tapped (line \(line))")
                            navigateToLine = line 
                        }
                        Button("Edit") { 
                            AppLogger.log("Breakpoint Edit tapped (line \(line))")
                            editingBreakpointLine = line; editingCondition = breakpoints[line] ?? ""; showEditConditionSheet = true 
                        }
                        Button(role: .destructive) { 
                            AppLogger.log("Breakpoint Remove tapped (line \(line))")
                            breakpoints.removeValue(forKey: line) 
                        } label: { Text("Remove") }
                    }
                }
            }
            .navigationTitle("Breakpoints")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear All") { 
                        AppLogger.log("Clear All breakpoints tapped")
                        breakpoints.removeAll() 
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { 
                        AppLogger.log("Breakpoints sheet dismissed")
                        showingBreakpoints = false 
                    }
                }
            }
        }
    }

    private var conditionEditorSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("Condition (expr == value)")) {
                    TextField("e.g., i == 3", text: $editingCondition)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }
            }
            .navigationTitle("Edit Breakpoint")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { 
                        AppLogger.log("Edit condition cancelled")
                        showEditConditionSheet = false 
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let line = editingBreakpointLine {
                            let trimmed = editingCondition.trimmingCharacters(in: .whitespacesAndNewlines)
                            AppLogger.log("Saving breakpoint condition at line \(line): '" + trimmed + "'")
                            breakpoints[line] = trimmed
                        }
                        showEditConditionSheet = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear") {
                        if let line = editingBreakpointLine { 
                            AppLogger.log("Clearing breakpoint condition at line \(line)")
                            breakpoints[line] = "" 
                        }
                        showEditConditionSheet = false
                    }
                }
            }
        }
    }

    private func codeKey() -> String {
        let data = Data(code.utf8)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func persistBreakpoints() {
        let key = "breakpoints." + codeKey()
        var dict: [String: String] = [:]
        for (k,v) in breakpoints { dict[String(k)] = v }
        UserDefaults.standard.set(dict, forKey: key)
    }

    private func loadPersistedBreakpoints() {
        let key = "breakpoints." + codeKey()
        if let dict = UserDefaults.standard.dictionary(forKey: key) as? [String: String] {
            let lines = max(1, code.split(separator: "\n", omittingEmptySubsequences: false).count)
            var bp: [Int: String] = [:]
            for (k, v) in dict { if let i = Int(k), i >= 1 && i <= lines { bp[i] = v } }
            AppLogger.log("Loaded persisted breakpoints: \(bp.count)")
            breakpoints = bp
        } else { breakpoints.removeAll() }
    }
    
    private func loadLogContent() {
        Task {
            let content = await readLogFile()
            AppLogger.log("Loaded log content for sheet, characters=\(content.count)")
            await MainActor.run {
                self.logContent = content
            }
        }
    }
    
    private func readLogFile() async -> String {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .background).async {
                do {
                    guard let url = self.logFileURL() else {
                        AppLogger.log("Failed to resolve log file URL")
                        continuation.resume(returning: "Error: Could not access log file location")
                        return
                    }
                    
                    if FileManager.default.fileExists(atPath: url.path) {
                        AppLogger.log("Reading log file at: \(url.path)")
                        let content = try String(contentsOf: url, encoding: .utf8)
                        continuation.resume(returning: content)
                    } else {
                        AppLogger.log("Log file does not exist yet at: \(url.path)")
                        continuation.resume(returning: "Log file does not exist yet. Run some Python code to generate logs.")
                    }
                } catch {
                    AppLogger.log("Error reading log file: \(error.localizedDescription)")
                    continuation.resume(returning: "Error reading log file: \(error.localizedDescription)")
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

#Preview { NavigationStack { PythonInterpreterView() } }
