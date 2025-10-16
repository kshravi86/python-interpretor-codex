#!/usr/bin/env python3
import sys, pathlib, zipfile, compileall

def main():
    lib = pathlib.Path(sys.base_prefix) / "Lib"
    compileall.compile_dir(str(lib), force=True, quiet=1, legacy=True)
    out = pathlib.Path("python-stdlib.zip")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        for p in lib.rglob("*"):
            zf.write(p, p.relative_to(lib))
        zf.writestr("PYTHON_VERSION.txt", sys.version.split()[0])
    print(f"Wrote {out} with PYTHON_VERSION.txt={sys.version.split()[0]}")

if __name__ == "__main__":
    main()

