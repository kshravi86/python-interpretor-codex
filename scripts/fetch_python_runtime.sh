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

if ! command -v gh >/dev/null 2>&1; then
  echo "::error title=GitHub CLI missing::The gh CLI is required on the runner"
  exit 1
fi

# Ensure gh uses the workflow token for higher rate limits
export GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

WORKDIR="$RUNNER_TEMP/python-support"
mkdir -p "$WORKDIR"

if [ "$TAG" = "latest" ]; then
  GH_FLAGS=(--latest)
else
  GH_FLAGS=(--tag "$TAG")
fi

echo "Downloading assets into: $WORKDIR"

# Try direct xcframework zip and stdlib zip first
set +e
gh release download "${GH_FLAGS[@]}" -R "$REPO" -p "*Python*.xcframework*.zip" -D "$WORKDIR"
GH_RC_XCF=$?
gh release download "${GH_FLAGS[@]}" -R "$REPO" -p "*stdlib*.zip" -D "$WORKDIR"
GH_RC_STDLIB=$?
set -e

ZIP_XCF=$(ls "$WORKDIR"/*xcframework*.zip 2>/dev/null | head -n1 || true)
ZIP_STDLIB=$(ls "$WORKDIR"/*stdlib*.zip 2>/dev/null | head -n1 || true)

# If no xcframework zip, fallback to support tarball
if [ -z "$ZIP_XCF" ]; then
  echo "No xcframework zip found via release assets; falling back to support tarball"
  set +e
  gh release download "${GH_FLAGS[@]}" -R "$REPO" -p "Python-*-iOS-support*.tar.*" -D "$WORKDIR"
  GH_RC_TARBALL=$?
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

if [ -z "$ZIP_STDLIB" ]; then
  echo "::error title=Stdlib zip not found::No stdlib zip found in release assets"
  exit 1
fi

echo "Placing artifacts into project paths"
mkdir -p "$(dirname "$TARGET_XCF_DIR")" "$(dirname "$TARGET_STDLIB")"
rm -rf "$TARGET_XCF_DIR"
rsync -a "$FOUND_XCF/" "$TARGET_XCF_DIR/"
cp "$ZIP_STDLIB" "$TARGET_STDLIB"

echo "Mirroring into ThirdParty/Python for existing workflows"
mkdir -p ThirdParty/Python
rm -rf ThirdParty/Python/Python.xcframework
rsync -a "$TARGET_XCF_DIR/" ThirdParty/Python/Python.xcframework/
cp "$TARGET_STDLIB" ThirdParty/Python/python-stdlib.zip

# Ensure PYTHON_VERSION.txt exists in stdlib zip to allow CI version checks
if ! unzip -l "$TARGET_STDLIB" | grep -q "PYTHON_VERSION.txt"; then
  # Derive version from patchlevel.h in the device slice if possible
  VER=""
  if [ -f "$TARGET_XCF_DIR/ios-arm64/include/patchlevel.h" ]; then
    VER=$(grep -E '^[#]define[\t ]+PY_VERSION[\t ]+"' "$TARGET_XCF_DIR/ios-arm64/include/patchlevel.h" | sed -E 's/.*PY_VERSION[\t ]+"([^"]+)".*/\1/' | head -n1)
  elif [ -f "$TARGET_XCF_DIR/ios-arm64/include/Python.h" ]; then
    VER=$(grep -E '^[#]define[\t ]+PY_VERSION[\t ]+"' "$TARGET_XCF_DIR/ios-arm64/include/Python.h" | sed -E 's/.*PY_VERSION[\t ]+"([^"]+)".*/\1/' | head -n1)
  fi
  if [ -z "$VER" ]; then
    # Fallback to expected prefix if provided, else mark unknown
    VER="${EXPECTED_PY_PREFIX:-unknown}"
  fi
  tmpd=$(mktemp -d)
  echo "$VER" > "$tmpd/PYTHON_VERSION.txt"
  (cd "$tmpd" && zip -q "$OLDPWD/$TARGET_STDLIB" PYTHON_VERSION.txt)
  rm -rf "$tmpd"
fi

echo "Artifacts prepared:"
echo " - XCFramework: $TARGET_XCF_DIR"
echo " - Stdlib zip: $TARGET_STDLIB"
