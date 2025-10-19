import SwiftUI

// Placeholder view to satisfy legacy Xcode project references.
// The app's real entry is NotesAppApp/CodeSnakeApp and PythonInterpreterView.
// Keeping this file lightweight ensures builds succeed even if the project
// still lists ContentView.swift in Sources.
struct ContentView: View {
    var body: some View {
        Text("CodeSnake")
            .font(.headline)
            .foregroundStyle(.secondary)
            .padding()
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif

