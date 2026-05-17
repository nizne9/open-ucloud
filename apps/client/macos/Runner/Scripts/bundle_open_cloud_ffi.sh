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
    CARGO_PROFILE="debug"
    echo "Building open-cloud-ffi with Cargo debug profile..."
    (cd "$REPO_ROOT" && cargo build -p open-cloud-ffi)
    ;;
  *)
    CARGO_PROFILE="release"
    echo "Building open-cloud-ffi with Cargo release profile..."
    (cd "$REPO_ROOT" && cargo build --release -p open-cloud-ffi)
    ;;
esac

OPEN_CLOUD_FFI_DYLIB="$REPO_ROOT/target/$CARGO_PROFILE/libopen_cloud_ffi.dylib"
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
cp -f "$OPEN_CLOUD_FFI_DYLIB" "$FRAMEWORKS_DIR/libopen_cloud_ffi.dylib"
echo "Bundled libopen_cloud_ffi.dylib into $FRAMEWORKS_DIR."
