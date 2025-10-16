// ObjC++ bridge for embedding CPython on iOS with streaming output and stop.
#include "PythonBridge.h"

#if __has_include(<Python/Python.h>) || __has_include(<Python.h>)
#  if __has_include(<Python/Python.h>)
#    include <Python/Python.h>
#  else
#    include <Python.h>
#  endif
#  define HAS_CPYTHON 1
#else
#  define HAS_CPYTHON 0
#endif

#include <stdlib.h>
#include <string.h>
#include <string>
#import <Foundation/Foundation.h>

static int g_initialized = 0;

static pybridge_output_cb g_stdout_cb = nullptr;
static pybridge_output_cb g_stderr_cb = nullptr;
static void* g_cb_user = nullptr;

extern "C" {
static void set_error(char* buf, size_t len, const char* msg) {
    if (!buf || len == 0) return;
    size_t n = strlen(msg);
    if (n >= len) n = len - 1;
    memcpy(buf, msg, n);
    buf[n] = '\0';
}
}

#if HAS_CPYTHON
// Simple writer type that forwards write() calls to callbacks and accumulates output.
typedef struct {
    PyObject_HEAD
    int is_err;
} PbWriter;

static PyTypeObject PbWriterType;
static bool g_writer_ready = false;
static std::string g_accum_out;
static std::string g_accum_err;

static PyObject* PbWriter_write(PbWriter* self, PyObject* args) {
    const char* s = nullptr;
    Py_ssize_t n = 0;
    if (!PyArg_ParseTuple(args, "s#", &s, &n)) {
        Py_RETURN_NONE;
    }
    if (s && n > 0) {
        if (self->is_err) {
            g_accum_err.append(s, (size_t)n);
            if (g_stderr_cb) g_stderr_cb(s, g_cb_user);
        } else {
            g_accum_out.append(s, (size_t)n);
            if (g_stdout_cb) g_stdout_cb(s, g_cb_user);
        }
    }
    Py_RETURN_NONE;
}

static PyObject* PbWriter_flush(PbWriter* self, PyObject* args) {
    (void)self; (void)args; Py_RETURN_NONE;
}

static PyMethodDef PbWriter_methods[] = {
    {"write", (PyCFunction)PbWriter_write, METH_VARARGS, (char*)"Write text"},
    {"flush", (PyCFunction)PbWriter_flush, METH_VARARGS, (char*)"Flush"},
    {NULL, NULL, 0, NULL}
};

static int ensure_writer_type(void) {
    if (g_writer_ready) return 0;
    memset(&PbWriterType, 0, sizeof(PbWriterType));
    PbWriterType.ob_base = PyVarObject_HEAD_INIT(NULL, 0)
    PbWriterType.tp_name = (char*)"iosbridge.PbWriter";
    PbWriterType.tp_basicsize = sizeof(PbWriter);
    PbWriterType.tp_flags = Py_TPFLAGS_DEFAULT;
    PbWriterType.tp_methods = PbWriter_methods;
    if (PyType_Ready(&PbWriterType) < 0) {
        return -1;
    }
    g_writer_ready = true;
    return 0;
}

static PyObject* new_writer(int is_err) {
    if (ensure_writer_type() != 0) return NULL;
    PbWriter* w = PyObject_New(PbWriter, &PbWriterType);
    if (!w) return NULL;
    w->is_err = is_err;
    return (PyObject*)w;
}
#endif // HAS_CPYTHON

extern "C" {
int pybridge_initialize(const char* resource_dir, char* errbuf, size_t errbuf_len) {
#if HAS_CPYTHON
    if (g_initialized) return 0;

    // Version alignment: ensure embedded CPython matches expected prefix if provided
    #ifdef EXPECTED_PYVER_PREFIX
    {
        const char* ver = Py_GetVersion();
        const char* pref = EXPECTED_PYVER_PREFIX;
        size_t n = strlen(pref);
        if (strncmp(ver, pref, n) != 0) {
            set_error(errbuf, errbuf_len, "CPython version mismatch");
            return -1;
        }
    }
    #endif

    if (resource_dir && *resource_dir) {
        setenv("PY_BRIDGE_RESOURCE_DIR", resource_dir, 1);
        setenv("PYTHONHOME", resource_dir, 1);
        // Also set via API for maximum compatibility
        wchar_t *wHome = Py_DecodeLocale(resource_dir, NULL);
        if (wHome) {
            Py_SetPythonHome(wHome);
            // Will be freed after initialization below
        }
    }

    Py_Initialize();
    if (!Py_IsInitialized()) {
        set_error(errbuf, errbuf_len, "Py_Initialize failed");
        return -1;
    }

    #ifdef PyEval_InitThreads
    PyEval_InitThreads();
    #endif
    PyGILState_STATE g = PyGILState_Ensure();

    // Resolve Application Support directory via Foundation
    NSString *appSupportPath = nil;
    @autoreleasepool {
        NSArray<NSString*> *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
        if (paths.count > 0) {
            appSupportPath = paths.firstObject;
            if (appSupportPath.length > 0) {
                setenv("PY_BRIDGE_APP_SUPPORT", appSupportPath.UTF8String, 1);
            }
        }
    }

    const char* py =
        "import os, sys\n"
        "res = os.environ.get('PY_BRIDGE_RESOURCE_DIR') or ''\n"
        "app_sup = os.environ.get('PY_BRIDGE_APP_SUPPORT') or ''\n"
        "# Add stdlib zip(s)\n"
        "candidates = []\n"
        "if res: candidates.append(os.path.join(res, 'python-stdlib.zip'))\n"
        "if res: candidates.append(os.path.join(res, 'stdlib.zip'))\n"
        "for p in candidates:\n"
        "    if os.path.exists(p) and p not in sys.path:\n"
        "        sys.path.insert(0, p)\n"
        "# Add site-packages style dirs\n"
        "site_dirs = []\n"
        "if res: site_dirs.append(os.path.join(res, 'site-packages'))\n"
        "if res: site_dirs.append(os.path.join(res, 'app_packages'))\n"
        "if app_sup: site_dirs.append(os.path.join(app_sup, 'site-packages'))\n"
        "if app_sup: site_dirs.append(os.path.join(app_sup, 'app_packages'))\n"
        "for p in site_dirs:\n"
        "    if os.path.isdir(p) and p not in sys.path:\n"
        "        sys.path.insert(0, p)\n";
    int rc = PyRun_SimpleString(py);
    PyGILState_Release(g);
    // Free the wide home string if we created one
    if (resource_dir && *resource_dir) {
        wchar_t *wHome = Py_DecodeLocale(resource_dir, NULL);
        if (wHome) PyMem_RawFree(wHome);
    }
    if (rc != 0) {
        set_error(errbuf, errbuf_len, "Failed to set sys.path for stdlib/site-packages");
        return -2;
    }
    g_initialized = 1;
    return 0;
#else
    set_error(errbuf, errbuf_len, "CPython headers unavailable");
    return -1;
#endif
}

void pybridge_set_output_handlers(pybridge_output_cb stdout_cb, pybridge_output_cb stderr_cb, void* user) {
    g_stdout_cb = stdout_cb;
    g_stderr_cb = stderr_cb;
    g_cb_user = user;
}

int pybridge_request_stop(void) {
#if HAS_CPYTHON
    PyGILState_STATE g = PyGILState_Ensure();
    #if defined(PyErr_SetInterruptEx)
        PyErr_SetInterruptEx(0);
    #elif defined(PyErr_SetInterrupt)
        PyErr_SetInterrupt();
    #endif
    PyGILState_Release(g);
    return 0;
#else
    return -1;
#endif
}

int pybridge_run(const char* code, char** out_stdout, char** out_stderr, int* exit_code) {
#if HAS_CPYTHON
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

    g_accum_out.clear();
    g_accum_err.clear();

    PyGILState_STATE g = PyGILState_Ensure();

    // Use io.StringIO to capture stdout/stderr to minimize risk of crashes from custom writers
    PyObject *sys = NULL, *io = NULL, *old_out = NULL, *old_err = NULL, *new_out = NULL, *new_err = NULL;
    PyObject* builtins = NULL; PyObject* globals = NULL; PyObject* locals = NULL;
    int rc = 0;

    sys = PyImport_ImportModule("sys");
    if (!sys) { rc = -10; goto done; }

    io = PyImport_ImportModule("io");
    if (!io) { rc = -10; goto done; }
    old_out = PyObject_GetAttrString(sys, "stdout");
    old_err = PyObject_GetAttrString(sys, "stderr");
    new_out = PyObject_CallMethod(io, "StringIO", NULL);
    new_err = PyObject_CallMethod(io, "StringIO", NULL);
    if (!new_out || !new_err) { rc = -11; goto done; }
    if (PyObject_SetAttrString(sys, "stdout", new_out) != 0) { rc = -12; goto done; }
    if (PyObject_SetAttrString(sys, "stderr", new_err) != 0) { rc = -13; goto done; }

    // Execute code
    builtins = PyEval_GetBuiltins();
    globals = PyDict_New();
    locals = globals; // simple REPL-like scope
    if (builtins && globals) PyDict_SetItemString(globals, "__builtins__", builtins);
    {
        PyObject* res = PyRun_StringFlags(code, Py_file_input, globals, locals, NULL);
        if (!res) {
            rc = -1;
            if (exit_code) *exit_code = 1;
            PyErr_Print();
        } else {
            Py_DECREF(res);
            if (exit_code) *exit_code = 0;
        }
    }

    // Collect outputs from StringIO
    if (out_stdout && new_out) {
        PyObject* s = PyObject_CallMethod(new_out, "getvalue", NULL);
        const char* u = s ? PyUnicode_AsUTF8(s) : NULL;
        if (u) {
            size_t n = strlen(u);
            char* dup = (char*)malloc(n + 1);
            if (dup) { memcpy(dup, u, n); dup[n] = '\0'; }
            *out_stdout = dup;
        }
        Py_XDECREF(s);
    }
    if (out_stderr && new_err) {
        PyObject* s = PyObject_CallMethod(new_err, "getvalue", NULL);
        const char* u = s ? PyUnicode_AsUTF8(s) : NULL;
        if (u) {
            size_t n = strlen(u);
            char* dup = (char*)malloc(n + 1);
            if (dup) { memcpy(dup, u, n); dup[n] = '\0'; }
            *out_stderr = dup;
        }
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
    Py_XDECREF(globals);

    PyGILState_Release(g);
    return rc;
#else
    if (out_stdout) *out_stdout = NULL;
    if (out_stderr) {
        const char* msg = "CPython runtime not available";
        size_t n = strlen(msg);
        char* e = (char*)malloc(n + 2);
        if (e) { memcpy(e, msg, n); e[n] = '\n'; e[n+1] = '\0'; }
        *out_stderr = e;
    }
    if (exit_code) *exit_code = 1;
    return -1;
#endif
}

void pybridge_free(void* p) {
    if (p) free(p);
}

int pybridge_run_file(const char* path, char** out_stdout, char** out_stderr, int* exit_code) {
#if HAS_CPYTHON
    // Read the file into memory and delegate to pybridge_run
    if (!path) return -1;
    FILE* f = fopen(path, "rb");
    if (!f) {
        const char* msg = "Could not open Python file";
        if (out_stderr) {
            size_t n = strlen(msg);
            char* e = (char*)malloc(n + 2);
            if (e) { memcpy(e, msg, n); e[n] = '\n'; e[n+1] = '\0'; }
            *out_stderr = e;
        }
        if (exit_code) *exit_code = 1;
        return -1;
    }
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (len < 0) { fclose(f); return -1; }
    std::string buf;
    buf.resize((size_t)len);
    size_t rd = fread(buf.data(), 1, (size_t)len, f);
    fclose(f);
    if (rd != (size_t)len) return -1;
    return pybridge_run(buf.c_str(), out_stdout, out_stderr, exit_code);
#else
    if (exit_code) *exit_code = 1;
    return -1;
#endif
}
} // extern "C"
