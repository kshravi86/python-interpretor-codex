import SwiftUI
import UIKit

struct PythonInterpreterView: View {
    @State private var code: String = """
print('Hello from Python!')
for i in range(3):
    print(i)
"""
    @State private var output: String = ""
    @State private var isRunning: Bool = false
    @State private var lastError: String? = nil
    @State private var autorunSavePath: String? = nil

    private let executor: PythonExecutor = {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--smoke-remote") {
            return RemotePythonExecutor()
        } else {
            return OfflinePyodideExecutor()
        }
    }()

    var body: some View {
        VStack(spacing: 0) {
            editor
            Divider()
            outputView
        }
        .navigationTitle("Python Runner")
        .toolbar { runToolbar }
        .onAppear { applyAutorunFromArgumentsIfNeeded() }
    }

    private var editor: some View {
        TextEditor(text: $code)
            .font(.system(.body, design: .monospaced))
            .padding(.horizontal)
            .padding(.top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        } catch {
            await MainActor.run {
                self.lastError = "Run failed: \(error.localizedDescription)"
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
}

#Preview { NavigationStack { PythonInterpreterView() } }
