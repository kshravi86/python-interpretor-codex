// Minimal C bridge for embedding CPython on iOS.
#include "PythonBridge.h"
#include <Python.h>
#include <stdlib.h>
#include <string.h>

static int g_initialized = 0;

static void set_error(char* buf, size_t len, const char* msg) {
    if (!buf || len == 0) return;
    size_t n = strlen(msg);
    if (n >= len) n = len - 1;
    memcpy(buf, msg, n);
    buf[n] = '\0';
}

int pybridge_initialize(const char* resource_dir, char* errbuf, size_t errbuf_len) {
    if (g_initialized) return 0;

    // Best-effort: setenv used by Python to find stdlib zip on sys.path later.
    if (resource_dir && *resource_dir) {
        setenv("PY_BRIDGE_RESOURCE_DIR", resource_dir, 1);
    }

    // Initialize Python runtime.
    Py_Initialize();
    if (!Py_IsInitialized()) {
        set_error(errbuf, errbuf_len, "Py_Initialize failed");
        return -1;
    }

    // Ensure GIL ready (guard for versions where API is removed)
    #ifdef PyEval_InitThreads
    PyEval_InitThreads();
    #endif
    PyGILState_STATE g = PyGILState_Ensure();

    // Prime sys.path with bundled stdlib zip if present.
    const char* py =
        "import os, sys\n"
        "res = os.environ.get('PY_BRIDGE_RESOURCE_DIR') or ''\n"
        "candidates = []\n"
        "if res: candidates.append(os.path.join(res, 'python-stdlib.zip'))\n"
        "if res: candidates.append(os.path.join(res, 'stdlib.zip'))\n"
        "for p in candidates:\n"
        "    if os.path.exists(p) and p not in sys.path:\n"
        "        sys.path.insert(0, p)\n";
    int rc = PyRun_SimpleString(py);
    PyGILState_Release(g);
    if (rc != 0) {
        set_error(errbuf, errbuf_len, "Failed to set sys.path for stdlib zip");
        return -2;
    }
    g_initialized = 1;
    return 0;
}

static char* dup_pystring(PyObject* s) {
    if (!s) return NULL;
    const char* u = PyUnicode_AsUTF8(s);
    if (!u) return NULL;
    size_t n = strlen(u);
    char* out = (char*)malloc(n + 1);
    if (!out) return NULL;
    memcpy(out, u, n);
    out[n] = '\0';
    return out;
}

int pybridge_run(const char* code, char** out_stdout, char** out_stderr, int* exit_code) {
    if (!g_initialized) {
        char buf[128];
        int rc = pybridge_initialize(NULL, buf, sizeof(buf));
        if (rc != 0) {
            if (out_stderr) {
                size_t n = strlen(buf);
                char* e = (char*)malloc(n + 2);
                if (e) { memcpy(e, buf, n); e[n] = '\n'; e[n+1] = '\0'; }
                *out_stderr = e;
            }
            if (exit_code) *exit_code = 1;
            return rc;
        }
    }

    if (out_stdout) *out_stdout = NULL;
    if (out_stderr) *out_stderr = NULL;
    if (exit_code) *exit_code = 0;

    PyGILState_STATE g = PyGILState_Ensure();

    PyObject *sys = NULL, *io = NULL, *old_out = NULL, *old_err = NULL, *new_out = NULL, *new_err = NULL;
    int rc = 0;

    sys = PyImport_ImportModule("sys");
    io = PyImport_ImportModule("io");
    if (!sys || !io) { rc = -10; goto done; }

    old_out = PyObject_GetAttrString(sys, "stdout");
    old_err = PyObject_GetAttrString(sys, "stderr");
    new_out = PyObject_CallMethod(io, "StringIO", NULL);
    new_err = PyObject_CallMethod(io, "StringIO", NULL);
    if (!new_out || !new_err) { rc = -11; goto done; }
    if (PyObject_SetAttrString(sys, "stdout", new_out) != 0) { rc = -12; goto done; }
    if (PyObject_SetAttrString(sys, "stderr", new_err) != 0) { rc = -13; goto done; }

    // Execute code
    PyObject* builtins = PyEval_GetBuiltins();
    PyObject* globals = PyDict_New();
    PyObject* locals = globals; // simple REPL-like scope
    if (builtins && globals) PyDict_SetItemString(globals, "__builtins__", builtins);
    PyObject* res = PyRun_StringFlags(code, Py_file_input, globals, locals, NULL);
    if (!res) {
        rc = -1;
        if (exit_code) *exit_code = 1;
        PyErr_Print();
    } else {
        Py_DECREF(res);
        if (exit_code) *exit_code = 0;
    }

    // Collect outputs
    if (out_stdout && new_out) {
        PyObject* s = PyObject_CallMethod(new_out, "getvalue", NULL);
        *out_stdout = dup_pystring(s);
        Py_XDECREF(s);
    }
    if (out_stderr && new_err) {
        PyObject* s = PyObject_CallMethod(new_err, "getvalue", NULL);
        *out_stderr = dup_pystring(s);
        Py_XDECREF(s);
    }

done:
    if (sys && old_out) PyObject_SetAttrString(sys, "stdout", old_out);
    if (sys && old_err) PyObject_SetAttrString(sys, "stderr", old_err);
    Py_XDECREF(old_out);
    Py_XDECREF(old_err);
    Py_XDECREF(new_out);
    Py_XDECREF(new_err);
    Py_XDECREF(sys);
    Py_XDECREF(io);

    PyGILState_Release(g);
    return rc;
}

void pybridge_free(void* p) {
    if (p) free(p);
}
