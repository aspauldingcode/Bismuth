# Bismuth Quick Start Guide

Welcome to Bismuth, a translation layer for running classic PowerPC32 software on modern Apple Silicon.

> [!NOTE]
> **Long-Term Vision**: Bismuth's primary target is a fully featured GUI environment equipped with quality-of-life feature flags (similar to CrossOver). While the GUI is planned for a later release, the project currently provides a command-line interpreter backend (`BismuthInterpreter`) for developer preview, testing, and early experimentation.

## Running Bismuth (CLI/Developer Preview)

During this early development phase, you can interact with the translation engine using the command-line tool, `BismuthInterpreter`.

### Build

You can build the interpreter backend via Xcode:

1. Open `Bismuth.xcodeproj` in Xcode.
2. Select the `BismuthInterpreter` scheme.
3. Build the project.

Alternatively, you can build from the command line:

```bash
xcodebuild -scheme BismuthInterpreter -configuration Debug
```

If you prefer to build to a custom path (e.g., a local `./build` directory) for easier CLI access:

```bash
xcodebuild -scheme BismuthInterpreter -configuration Debug -derivedDataPath build
```

### Run

To run a PowerPC binary or application bundle using the CLI interpreter:

```bash
# Using a local build path:
./build/Build/Products/Debug/BismuthInterpreter [--trace] <path-to-binary-or-app> [arguments...]
```

* **CLI tools** execute directly in the terminal.
* **GUI applications** (`.app` bundles) launch within a temporary signed wrapper.

## Tracing and Debugging

The `--trace` flag enables Objective-C message tracing and Scarlet symbol resolver logs.

You can also use these environment variables:

| Variable | Description |
| :--- | :--- |
| BISMUTH_OBJC_TRACE | Trace Objective-C messages |
| BISMUTH_SCARLET_TRACE | Log symbol lookups via Scarlet |
| BISMUTH_COCOA_TRACE | Log Cocoa calls |
| BISMUTH_RESOLVE_TRACE | Log framework bridging |
| BISMUTH_RUNNER_TRACE | Print exit status and Program Counter (PC) |
| BISMUTH_CG_TRACE | Trace CoreGraphics calls |
| BISMUTH_NETWORK_TRACE | Trace network calls |
| BISMUTH_FRAMEWORK_TRACE | Trace AppKit and CoreServices |
| BISMUTH_EXIT_TRACE | Log process exits |
| BISMUTH_ALERT_TRACE | Trace modal alerts |

### Configuration Variables

* `BISMUTH_OBJC_TRACE_SELECTOR="method:"` - Trace only this selector
* `BISMUTH_OBJC_DEEP_TRACE_DEPTH="N"` - Limit call-stack depth
* `BISMUTH_OBJC_TRACE_DRAW_CALLBACKS=1` - Trace rendering callbacks
* `BISMUTH_AUTO_DISMISS_ALERTS=1` - Auto-dismiss dialog boxes

### Log Redirection

Set any of these to a file path to redirect trace logs:

* `BISMUTH_OBJC_TRACE_FILE`
* `BISMUTH_COCOA_TRACE_FILE`
* `BISMUTH_UI_TRACE_FILE`
* `BISMUTH_IO_TRACE_FILE`
* `BISMUTH_ERROR_LOG`

Good Luck, and have fun. 