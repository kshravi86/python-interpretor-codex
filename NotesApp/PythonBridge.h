// Minimal C bridge to CPython C-API for iOS embedding.
#pragma once

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Initialize the embedded interpreter.
// resource_dir: path to app bundle resources. We'll look for python-stdlib.zip in this directory.
// errbuf: optional buffer to receive an error message on failure.
int pybridge_initialize(const char* resource_dir, char* errbuf, size_t errbuf_len);

// Execute Python code, capturing stdout/stderr.
// Returned buffers are malloc'd; caller must free via pybridge_free.
int pybridge_run(const char* code, char** out_stdout, char** out_stderr, int* exit_code);

// Execute a Python file at the given absolute path, capturing stdout/stderr.
// Returned buffers are malloc'd; caller must free via pybridge_free.
int pybridge_run_file(const char* path, char** out_stdout, char** out_stderr, int* exit_code);

// Free memory allocated by this bridge.
void pybridge_free(void* p);

// Optional: register streaming output callbacks for stdout/stderr.
// Each time Python writes to sys.stdout/sys.stderr, the corresponding callback is invoked
// with a UTF-8 chunk. The user pointer is passed through unchanged.
typedef void (*pybridge_output_cb)(const char* utf8_chunk, void* user);
void pybridge_set_output_handlers(pybridge_output_cb stdout_cb, pybridge_output_cb stderr_cb, void* user);

// Request that the currently executing Python code stop as soon as possible.
// This sets a pending KeyboardInterrupt in the interpreter. Returns 0 if the
// interrupt was queued successfully.
int pybridge_request_stop(void);

#ifdef __cplusplus
}
#endif
