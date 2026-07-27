# Quick Start

Welcome to Bismuth, a translation layer for running PowerPC32 Mac software on modern Apple Silicon.

> [!NOTE]
> **For general audience**: A graphical interface is in development for Bismuth but is not yet ready. It'll be equipped with runtime flags and other settings you might be looking for. The interpreter itself is available for testing if you are familiar with the command-line.

## Running BismuthInterpreter

To run a PowerPC executable or app binary using the CLI interpreter:

```bash
# Using a local build path:
./build/Build/Products/Debug/BismuthInterpreter [--trace] <path-to-binary-or-app> [arguments...]
```

* Both receive a temporary signature, so always take necessary precaution when running software you're not familiar with (functions that require elevated privileges will still need your credentials).

### Arguments

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
