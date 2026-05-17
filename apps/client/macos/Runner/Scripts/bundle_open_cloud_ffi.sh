#!/bin/sh
set -eu

if ! command -v cargo >/dev/null 2>&1; then
  echo "error: cargo not found. Install Rust and ensure cargo is on PATH before building the macOS client." >&2
  exit 1
fi

if [ -z "${PROJECT_DIR:-}" ]; then
  echo "error: PROJECT_DIR is not set by Xcode." >&2
  exit 1
fi

REPO_ROOT="$(cd "$PROJECT_DIR/../../.." && pwd -P)"
if [ ! -f "$REPO_ROOT/Cargo.toml" ]; then
  echo "error: could not resolve repository root from PROJECT_DIR=$PROJECT_DIR." >&2
  exit 1
fi

case "${CONFIGURATION:-Debug}" in
  Debug)
    echo "Building open-cloud-ffi with Cargo debug profile..."
    (cd "$REPO_ROOT" && cargo build -p open-cloud-ffi)
    OPEN_CLOUD_FFI_DYLIB="$REPO_ROOT/target/debug/libopen_cloud_ffi.dylib"
    ;;
  *)
    if ! command -v lipo >/dev/null 2>&1; then
      echo "error: lipo not found. Build release/profile macOS bundles on macOS with Xcode command line tools installed." >&2
      exit 1
    fi

    X86_64_DARWIN_TARGET="x86_64-apple-darwin"
    ARM64_DARWIN_TARGET="aarch64-apple-darwin"
    X86_64_DYLIB="$REPO_ROOT/target/$X86_64_DARWIN_TARGET/release/libopen_cloud_ffi.dylib"
    ARM64_DYLIB="$REPO_ROOT/target/$ARM64_DARWIN_TARGET/release/libopen_cloud_ffi.dylib"
    UNIVERSAL_DYLIB_DIR="$REPO_ROOT/target/universal-apple-darwin/release"
    OPEN_CLOUD_FFI_DYLIB="$UNIVERSAL_DYLIB_DIR/libopen_cloud_ffi.dylib"

    echo "Building open-cloud-ffi release dylib for $X86_64_DARWIN_TARGET..."
    (cd "$REPO_ROOT" && cargo build --release --target "$X86_64_DARWIN_TARGET" -p open-cloud-ffi)
    echo "Building open-cloud-ffi release dylib for $ARM64_DARWIN_TARGET..."
    (cd "$REPO_ROOT" && cargo build --release --target "$ARM64_DARWIN_TARGET" -p open-cloud-ffi)

    if [ ! -f "$X86_64_DYLIB" ]; then
      echo "error: missing $X86_64_DYLIB after Cargo build." >&2
      exit 1
    fi
    if [ ! -f "$ARM64_DYLIB" ]; then
      echo "error: missing $ARM64_DYLIB after Cargo build." >&2
      exit 1
    fi

    mkdir -p "$UNIVERSAL_DYLIB_DIR"
    lipo -create "$X86_64_DYLIB" "$ARM64_DYLIB" -output "$OPEN_CLOUD_FFI_DYLIB"
    ;;
esac

if [ ! -f "$OPEN_CLOUD_FFI_DYLIB" ]; then
  echo "error: missing $OPEN_CLOUD_FFI_DYLIB after Cargo build." >&2
  exit 1
fi

if [ -z "${TARGET_BUILD_DIR:-}" ] || [ -z "${FRAMEWORKS_FOLDER_PATH:-}" ]; then
  echo "error: Xcode did not provide TARGET_BUILD_DIR or FRAMEWORKS_FOLDER_PATH." >&2
  exit 1
fi

FRAMEWORKS_DIR="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"
mkdir -p "$FRAMEWORKS_DIR"
DESTINATION_DYLIB="$FRAMEWORKS_DIR/libopen_cloud_ffi.dylib"
cp -f "$OPEN_CLOUD_FFI_DYLIB" "$DESTINATION_DYLIB"

if command -v codesign >/dev/null 2>&1; then
  SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-${CODE_SIGN_IDENTITY:--}}"
  if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY="-"
  fi
  codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$DESTINATION_DYLIB"
fi
echo "Bundled libopen_cloud_ffi.dylib into $FRAMEWORKS_DIR."
