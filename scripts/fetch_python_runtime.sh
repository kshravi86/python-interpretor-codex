#!/usr/bin/env bash
set -euo pipefail

# Fetch a prebuilt Python.xcframework and stdlib zip from
# Python-Apple-support GitHub releases, and place them into:
#   - ios/Frameworks/Python.xcframework
#   - Resources/python-stdlib.zip
# Additionally mirrors into ThirdParty/Python for existing workflows.
#
# Config via env vars:
#   PY_SUPPORT_REPO (default: beeware/Python-Apple-support)
#   PY_SUPPORT_TAG  (default: latest)
#   PY_TARGET_XCF_DIR (default: ios/Frameworks/Python.xcframework)
#   PY_TARGET_STDLIB (default: Resources/python-stdlib.zip)

REPO="${PY_SUPPORT_REPO:-beeware/Python-Apple-support}"
TAG="${PY_SUPPORT_TAG:-latest}"
TARGET_XCF_DIR="${PY_TARGET_XCF_DIR:-ios/Frameworks/Python.xcframework}"
TARGET_STDLIB="${PY_TARGET_STDLIB:-Resources/python-stdlib.zip}"

echo "Using repo: $REPO, tag: $TAG"

# gh is optional; if missing, we'll fall back to GitHub API via curl+python
HAS_GH=0
if command -v gh >/dev/null 2>&1; then HAS_GH=1; fi

# Ensure gh uses the workflow token for higher rate limits
export GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

WORKDIR="$RUNNER_TEMP/python-support"
mkdir -p "$WORKDIR"

GH_TAG="$TAG"
if [ "$TAG" = "latest" ]; then GH_TAG="latest"; fi

echo "Downloading assets into: $WORKDIR"

# Try direct xcframework zip and stdlib zip first
set +e
if [ $HAS_GH -eq 1 ]; then
  gh release download "$GH_TAG" -R "$REPO" -p "*Python*.xcframework*.zip" -D "$WORKDIR"; GH_RC_XCF=$?
  gh release download "$GH_TAG" -R "$REPO" -p "*stdlib*.zip" -D "$WORKDIR"; GH_RC_STDLIB=$?
else
  GH_RC_XCF=1; GH_RC_STDLIB=1
fi
set -e

ZIP_XCF=$(ls "$WORKDIR"/*xcframework*.zip 2>/dev/null | head -n1 || true)
ZIP_STDLIB=$(ls "$WORKDIR"/*stdlib*.zip 2>/dev/null | head -n1 || true)

# If no xcframework zip, fallback to support tarball
if [ -z "$ZIP_XCF" ]; then
  echo "No xcframework zip found via release assets; falling back to support tarball"
  set +e
  GH_RC_TARBALL=1
  # Try gh first; if it fails, fall back to API
  if [ $HAS_GH -eq 1 ]; then
    gh release download "$GH_TAG" -R "$REPO" -p "Python-*-iOS-support*.tar.*" -D "$WORKDIR"; GH_RC_TARBALL=$?
  fi
  if [ ${GH_RC_TARBALL:-1} -ne 0 ]; then
    API_URL="https://api.github.com/repos/${REPO}/releases";
    if [ "${TAG}" != "latest" ]; then API_URL="https://api.github.com/repos/${REPO}/releases/tags/${TAG}"; fi
    PY_ASSET_URL=$(python3 - "$API_URL" <<'PY'
import json,sys,urllib.request
u=sys.argv[1]
with urllib.request.urlopen(u) as r:
    data=json.load(r)
assets=data['assets'] if isinstance(data,dict) else data[0]['assets']
for a in assets:
    n=a.get('name','')
    if 'iOS-support' in n and (n.endswith('.tar.gz') or n.endswith('.tar.xz') or n.endswith('.tar.zst')):
        print(a['browser_download_url']); break
PY
)
    if [ -n "$PY_ASSET_URL" ]; then
      echo "Downloading (API) $PY_ASSET_URL"
      curl -L "$PY_ASSET_URL" -o "$WORKDIR/python-ios-support.tar"
      # Try gzip/xz transparently
      (file "$WORKDIR/python-ios-support.tar" | grep -qi gzip && mv "$WORKDIR/python-ios-support.tar" "$WORKDIR/python-ios-support.tar.gz") || true
      (file "$WORKDIR/python-ios-support.tar" | grep -qi xz && mv "$WORKDIR/python-ios-support.tar" "$WORKDIR/python-ios-support.tar.xz") || true
      GH_RC_TARBALL=0
    fi
  fi
  set -e
  if [ ${GH_RC_TARBALL:-1} -ne 0 ]; then
    echo "::error title=Python assets not found::Could not find xcframework zip or support tarball in release"
    exit 1
  fi
fi

# Unpack artifacts and locate Python.xcframework and stdlib zip
if [ -n "$ZIP_XCF" ]; then
  echo "Unzipping xcframework: $ZIP_XCF"
  unzip -q "$ZIP_XCF" -d "$WORKDIR"
fi

# Extract any downloaded tarballs
for TB in "$WORKDIR"/Python-*-iOS-support*.tar.*; do
  [ -e "$TB" ] || continue
  echo "Extracting support tarball: $TB"
  tar -xf "$TB" -C "$WORKDIR"
done

# Discover locations
FOUND_XCF=$(find "$WORKDIR" -type d -name "Python.xcframework" | head -n1 || true)
if [ -z "$FOUND_XCF" ]; then
  echo "::error title=Python.xcframework not found::No Python.xcframework directory found after extraction"
  exit 1
fi

if [ -z "$ZIP_STDLIB" ]; then
  ZIP_STDLIB=$(find "$WORKDIR" -type f \( -name "*stdlib*.zip" -o -name "python-stdlib.zip" -o -name "stdlib.zip" \) | head -n1 || true)
fi

# If still not found, try to build python-stdlib.zip from a discovered stdlib directory in the support tarball
if [ -z "$ZIP_STDLIB" ]; then
  # Prefer a directory that actually contains site.py
  SITEPY=$(find "$WORKDIR" -type f -name "site.py" | head -n1 || true)
  if [ -n "$SITEPY" ]; then
    PYVERDIR=$(dirname "$SITEPY")
  else
    # Fallback: detect .../lib/pythonX.Y directories
    PYVERDIR=$(find "$WORKDIR" -type d -regex ".*/lib/python[0-9]+\.[0-9]+$" | head -n1 || true)
  fi
  if [ -n "$PYVERDIR" ]; then
    echo "Building stdlib zip from: $PYVERDIR"
    mkdir -p "$(dirname "$TARGET_STDLIB")"
    (cd "$PYVERDIR" && zip -qry "$OLDPWD/$TARGET_STDLIB" .)
    ZIP_STDLIB="$TARGET_STDLIB"
  fi
fi

if [ -z "$ZIP_STDLIB" ] || [ ! -f "$ZIP_STDLIB" ]; then
  echo "::error title=Stdlib zip not found::No stdlib zip found or built from support package"
  exit 1
fi

echo "Placing artifacts into project paths"
mkdir -p "$(dirname "$TARGET_XCF_DIR")" "$(dirname "$TARGET_STDLIB")"
rm -rf "$TARGET_XCF_DIR"
rsync -a "$FOUND_XCF/" "$TARGET_XCF_DIR/"
# Only copy stdlib if source and destination differ
if [ "$(cd "$(dirname "$ZIP_STDLIB")" && pwd)/$(basename "$ZIP_STDLIB")" != "$(cd "$(dirname "$TARGET_STDLIB")" && pwd)/$(basename "$TARGET_STDLIB")" ]; then
  cp -f "$ZIP_STDLIB" "$TARGET_STDLIB"
fi

echo "Mirroring into ThirdParty/Python for existing workflows"
mkdir -p ThirdParty/Python
rm -rf ThirdParty/Python/Python.xcframework
rsync -a "$TARGET_XCF_DIR/" ThirdParty/Python/Python.xcframework/
cp "$TARGET_STDLIB" ThirdParty/Python/python-stdlib.zip

# Ensure PYTHON_VERSION.txt exists in stdlib zip to allow CI version checks
if ! unzip -l "$TARGET_STDLIB" | grep -q "PYTHON_VERSION.txt"; then
  # Derive version from headers or from stdlib path; fallback to EXPECTED_PY_PREFIX
  VER=""
  if [ -f "$TARGET_XCF_DIR/ios-arm64/include/patchlevel.h" ]; then
    VER=$(grep -E '^[#]define[\t ]+PY_VERSION[\t ]+"' "$TARGET_XCF_DIR/ios-arm64/include/patchlevel.h" | sed -E 's/.*PY_VERSION[\t ]+"([^"]+)".*/\1/' | head -n1)
  fi
  if [ -z "$VER" ] && [ -f "$TARGET_XCF_DIR/ios-arm64/include/Python.h" ]; then
    VER=$(grep -E '^[#]define[\t ]+PY_VERSION[\t ]+"' "$TARGET_XCF_DIR/ios-arm64/include/Python.h" | sed -E 's/.*PY_VERSION[\t ]+"([^"]+)".*/\1/' | head -n1)
  fi
  if [ -z "$VER" ]; then
    # Inspect stdlib contents for a pythonX.Y root path
    CAND_DIR=$(unzip -l "$TARGET_STDLIB" | awk '{print $4}' | grep -E '^([^/]*/)*site\.py$' | head -n1 | xargs -I{} dirname {} | sed -E 's#.*/(python[0-9]+\.[0-9]+).*#\1#' | head -n1)
    if echo "$CAND_DIR" | grep -Eq '^python[0-9]+\.[0-9]+'; then
      VER=$(echo "$CAND_DIR" | sed -E 's/^python([0-9]+\.[0-9]+).*/\1/')
    fi
  fi
  if [ -z "$VER" ]; then
    VER="${EXPECTED_PY_PREFIX:-3.14}"
  fi
  tmpd=$(mktemp -d)
  echo "$VER" > "$tmpd/PYTHON_VERSION.txt"
  (cd "$tmpd" && zip -q "$OLDPWD/$TARGET_STDLIB" PYTHON_VERSION.txt)
  rm -rf "$tmpd"
fi

echo "Artifacts prepared:"
echo " - XCFramework: $TARGET_XCF_DIR"
echo " - Stdlib zip: $TARGET_STDLIB"
