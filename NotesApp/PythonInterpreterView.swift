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
    @State private var breakpoints: Set<Int> = []
    @State private var navigateToLine: Int? = nil
    @State private var showingBreakpoints: Bool = false

    private let executor: PythonExecutor = OfflinePyodideExecutor()

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
        .onAppear { loadPersisted(); loadPersistedBreakpoints(); applyAutorunFromArgumentsIfNeeded() }
        .onChange(of: code) { _ in persist(); loadPersistedBreakpoints() }
        .onChange(of: breakpoints) { _ in persistBreakpoints() }
        .preferredColorScheme(useDarkAppearance ? .dark : nil)
        .sheet(isPresented: $showingBreakpoints) { breakpointsSheet }
    }

    private var editor: some View {
        CodeEditorView(text: $code, breakpoints: $breakpoints, navigateToLine: $navigateToLine, fontSize: fontSize, isDark: useDarkAppearance, theme: useDarkSyntaxTheme ? SyntaxHighlighter.Theme.defaultDark() : SyntaxHighlighter.Theme.defaultLight())
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
                    Button(s.title) { code = s.code }
                }
            }
            .buttonStyle(.bordered)

            HStack {
                Image(systemName: "textformat.size")
                Slider(value: $fontSize, in: 12...22)
                    .frame(width: 140)
            }
            Menu {
                Button("Light Theme") { useDarkAppearance = false; useDarkSyntaxTheme = false }
                Button("Dark Theme") { useDarkAppearance = true; useDarkSyntaxTheme = true }
            } label: {
                Label("Theme", systemImage: useDarkSyntaxTheme ? "moon.fill" : "sun.max.fill")
            }
            .buttonStyle(.bordered)
            Button {
                showingBreakpoints = true
            } label: {
                Label("Breakpoints", systemImage: "bookmark.circle")
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
                UIPasteboard.general.string = output
            } label: {
                Label("Copy Output", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
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
                Task { await runCode() }
            } label: {
                if isRunning { ProgressView() } else { Text("Run") }
            }
            .disabled(isRunning || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func runCode() async {
        isRunning = true
        lastError = nil
        output = ""
        runDuration = nil
        let start = Date()
        do {
            let result = try await executor.execute(code: code)
            var combined = ""
            if let status = result.exitCode { combined += "[exit \(status)]\n" }
            if !result.stdout.isEmpty { combined += result.stdout }
            if !result.stderr.isEmpty {
                if !combined.isEmpty { combined += (combined.hasSuffix("\n") ? "" : "\n") }
                combined += result.stderr
            }
            if combined.isEmpty { combined = "(no output)" }
            let finalCombined = combined
            await MainActor.run { self.output = finalCombined }
            if let _ = autorunSavePath {
                writeAutorunOutput(finalCombined)
            }
            await MainActor.run { self.runDuration = Date().timeIntervalSince(start) }
        } catch {
            await MainActor.run {
                self.lastError = "Run failed: \(error.localizedDescription)"
                self.runDuration = Date().timeIntervalSince(start)
            }
            if let _ = autorunSavePath {
                writeAutorunOutput("ERROR: \(error.localizedDescription)")
            }
        }
        await MainActor.run { self.isRunning = false }
    }

    private func applyAutorunFromArgumentsIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--autorun-b64"), i + 1 < args.count {
            let b64 = args[i + 1]
            if let data = Data(base64Encoded: b64), let snippet = String(data: data, encoding: .utf8) {
                self.code = snippet
            }
            if let j = args.firstIndex(of: "--autorun-save"), j + 1 < args.count {
                self.autorunSavePath = args[j + 1]
            }
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
        } catch {
            // ignore write errors for smoke
        }
    }

    private func persist() {
        UserDefaults.standard.set(code, forKey: "editor.code")
    }
    private func loadPersisted() {
        if let s = UserDefaults.standard.string(forKey: "editor.code"), !s.isEmpty {
            code = s
        }
    }

    private var breakpointsSheet: some View {
        NavigationView {
            List {
                if breakpoints.isEmpty {
                    Text("No breakpoints").foregroundStyle(.secondary)
                }
                ForEach(Array(breakpoints).sorted(), id: \.self) { line in
                    HStack {
                        Text("Line \(line)")
                        Spacer()
                        Button("Go") { navigateToLine = line }
                        Button(role: .destructive) { breakpoints.remove(line) } label: { Text("Remove") }
                    }
                }
            }
            .navigationTitle("Breakpoints")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear All") { breakpoints.removeAll() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showingBreakpoints = false }
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
        let arr = Array(breakpoints)
        UserDefaults.standard.set(arr, forKey: key)
    }

    private func loadPersistedBreakpoints() {
        let key = "breakpoints." + codeKey()
        if let arr = UserDefaults.standard.array(forKey: key) as? [Int] {
            let lines = max(1, code.split(separator: "\n", omittingEmptySubsequences: false).count)
            breakpoints = Set(arr.filter { $0 >= 1 && $0 <= lines })
        } else {
            breakpoints.removeAll()
        }
    }
}

#Preview { NavigationStack { PythonInterpreterView() } }
