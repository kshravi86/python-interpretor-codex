# Python Runner iOS App

An iOS SwiftUI app that lets you write small Python snippets, run them, and see the output. This replaces the previous quiz/hydration UI with a simple code editor and output pane.

## Features

- Monospaced code editor using `TextEditor`
- Run button executes code via a remote Python executor API (Piston-compatible)
- Displays stdout, stderr, and exit code

## Project Structure

```
NotesApp/
  NotesAppApp.swift           # App entry; shows PythonInterpreterView
  PythonInterpreterView.swift # Editor UI + output
  PythonExecutor.swift        # Remote executor implementation (Piston schema)
  Assets.xcassets/            # App icons and assets
```

## Offline Execution (Pyodide)

The app embeds a local HTML host and runs Python fully offline via Pyodide inside a `WKWebView`. No network is required at runtime once assets are bundled.

What’s included
- `NotesApp/Pyodide/index.html` – lightweight host that boots Pyodide and wires stdout/stderr.
- `NotesApp/OfflinePyodideExecutor.swift` – manages a hidden `WKWebView` and executes code.

Bring your own Pyodide assets
1. Download a Pyodide release (e.g., 0.24+): https://github.com/pyodide/pyodide/releases
2. Unzip and copy contents of the `pyodide/` folder (must include `pyodide.js`, `pyodide.wasm`, and packages) into `NotesApp/PyodideAssets/`.
3. Ensure Xcode shows `PyodideAssets` as a blue folder in the target and is included in “Copy Bundle Resources”. This repo already includes a placeholder `.keep` to keep the folder.

On launch, `index.html` loads `../PyodideAssets/pyodide.js` from the app bundle and initializes Pyodide with `indexURL` pointing to that folder.

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 5.9+

## Build & Run

1. Open `NotesApp.xcodeproj` in Xcode
2. Select a simulator or device
3. Run

If you prefer remote execution instead, swap `OfflinePyodideExecutor()` for `RemotePythonExecutor()` in `NotesApp/PythonInterpreterView.swift:15`.
