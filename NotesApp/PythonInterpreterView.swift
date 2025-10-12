import SwiftUI

struct PythonInterpreterView: View {
    @State private var code: String = """
print('Hello from Python!')
for i in range(3):
    print(i)
"""
    @State private var output: String = ""
    @State private var isRunning: Bool = false
    @State private var lastError: String? = nil

    private let executor: PythonExecutor = OfflinePyodideExecutor()

    var body: some View {
        VStack(spacing: 0) {
            editor
            Divider()
            outputView
        }
        .navigationTitle("Python Runner")
        .toolbar { runToolbar }
    }

    private var editor: some View {
        TextEditor(text: $code)
            .font(.system(.body, design: .monospaced))
            .padding(.horizontal)
            .padding(.top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(UIColor.systemBackground))
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
        .background(Color(UIColor.secondarySystemBackground))
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
            await MainActor.run { self.output = combined }
        } catch {
            await MainActor.run {
                self.lastError = "Run failed: \(error.localizedDescription)"
            }
        }
        await MainActor.run { self.isRunning = false }
    }
}

#Preview { NavigationStack { PythonInterpreterView() } }
