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

// Free memory allocated by this bridge.
void pybridge_free(void* p);

#ifdef __cplusplus
}
#endif
