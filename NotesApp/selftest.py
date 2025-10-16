import zlib, sys
print("SELFTEST:OK", zlib.crc32(b"abc"), sys.version.split()[0])

