# Embedded CPython Runtime

This app embeds CPython using prebuilt frameworks from the Python-Apple-support project and a zipped standard library. The Swift UI presents a code editor, and execution is handled by a small ObjC++ bridge that initializes Python and captures stdout/stderr.

## How it works

- `NotesApp/PythonBridge.h/.mm` sets `PYTHONHOME` to the app’s resource directory and uses `PyPreConfig`/`PyConfig` to initialize CPython.
- The module search paths include:
  - `python-stdlib.zip` or `stdlib.zip` (bundled in the app)
  - `site-packages` and `app_packages` in the app bundle
  - (post-init) the same folders mirrored under Application Support if present
- `pybridge_run` executes code and returns captured stdout/stderr strings.
- `CPythonExecutor.swift` runs a self-test (`2+2 == 4`) after initialization before running user code.

## Fetching the runtime assets

Use the helper script on macOS:

```
bash scripts/fetch_python_runtime.sh
```

This places:

- `ios/Frameworks/Python.xcframework` for Xcode to link/embed
- `ThirdParty/Python/python-stdlib.zip` for Xcode to bundle in Copy Resources

The Xcode project contains a copy phase that places the correct `Python.framework` slice into `My.app/Frameworks/` at build time.

## CI smoke tests

Two workflows verify that Python actually runs on a simulator:

- `.github/workflows/ios-simulator-smoke.yml` builds, boots a simulator, launches the app with an autorun snippet, and checks for `PY SMOKE: 4` in logs/files.
- `.github/workflows/ios-fastlane-smoke.yml` performs a similar check using Fastlane.

Both workflows are configured to run on pushes and pull requests to `main` and can be triggered manually.

## Troubleshooting

- Missing or wrong framework slice (e.g. device vs simulator): re-run `scripts/fetch_python_runtime.sh`.
- `python-stdlib.zip` not found: ensure the file is present and included in the target’s Copy Bundle Resources.
- Crashes on device: confirm `My.app/Frameworks/Python.framework` exists and is properly codesigned; inspect device logs.

