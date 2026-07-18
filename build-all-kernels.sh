#!/bin/bash
set -e

if [ -z "${1:-}" ]; then
  echo "ERROR: Phone argument required" >&2
  echo "Usage: $0 <phone> [kernel-name-filter]" >&2
  exit 1
fi
PHONE="$1"

CONFIG_LOCALVERSION="-citronics-lime-${PHONE}"

ROOT_DIR=$(pwd)

TAG=$(git describe --tags --exact-match 2>/dev/null) || TAG=""
if [ -n "$TAG" ]; then
  PKG_VERSION=${TAG#v}
  # Release candidates: v3.2-rc1 -> 3.2~rc1 so dpkg sorts the RC before the final 3.2
  PKG_VERSION=${PKG_VERSION//-rc/\~rc}
else
  PKG_VERSION=$(git describe --tags --always 2>/dev/null || echo "0.0")
  PKG_VERSION=${PKG_VERSION#v}
  echo "WARNING: No exact git tag on current commit. Using version: $PKG_VERSION" >&2
  echo "         For releases, tag first: git tag v2.0" >&2
fi

CONFIGS_DIR="$ROOT_DIR/configs"
SOURCES_DIR="$ROOT_DIR/sources"
OUTPUT_BASE="$ROOT_DIR/output"
BUILD_BASE="$ROOT_DIR/build"
KERNELS_CONF="$ROOT_DIR/kernels.conf"

if [ ! -f "$KERNELS_CONF" ]; then
  echo "ERROR: kernels.conf not found" >&2
  exit 1
fi

# Allow building a single kernel: ./build-all-kernels.sh <phone> msm8x74-6.15.y
FILTER="${2:-}"

mkdir -p "$SOURCES_DIR"

# Collect available kernel names for validation
AVAILABLE_KERNELS=()
while IFS= read -r line; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line// /}" ]] && continue
  PHONE_COL=$(echo "$line" | awk '{print $1}')
  [ "$PHONE_COL" = "$PHONE" ] && AVAILABLE_KERNELS+=("$(echo "$line" | awk '{print $2}')")
done < "$KERNELS_CONF"

# Validate filter against available kernels
if [ -n "$FILTER" ]; then
  FOUND=0
  for k in "${AVAILABLE_KERNELS[@]}"; do
    [ "$k" = "$FILTER" ] && FOUND=1 && break
  done
  if [ "$FOUND" -eq 0 ]; then
    echo "ERROR: Unknown kernel '$FILTER'" >&2
    echo "Available kernels:" >&2
    for k in "${AVAILABLE_KERNELS[@]}"; do
      echo "  - $k" >&2
    done
    exit 1
  fi
fi

BUILD_COUNT=0

while IFS= read -r line; do
  # Skip comments and empty lines
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line// /}" ]] && continue

  LINE_PHONE=$(echo "$line" | awk '{print $1}')
  NAME=$(echo "$line" | awk '{print $2}')
  REPO_URL=$(echo "$line" | awk '{print $3}')
  BRANCH=$(echo "$line" | awk '{print $4}')
  KERN_ARCH=$(echo "$line" | awk '{print $5}')
  KERN_ARCH="${KERN_ARCH:-arm}"
  COMPONENT=$(echo "$line" | awk '{print $6}')
  COMPONENT="${COMPONENT:-main}"
  
  if [ "$KERN_ARCH" = "arm64" ]; then
    ARCH="arm64"
    CROSS_COMPILE="aarch64-linux-gnu-"
  else
    ARCH="arm"
    CROSS_COMPILE="arm-linux-gnueabihf-"
  fi
  
  if [ "$LINE_PHONE" != "$PHONE" ]; then continue; fi

  # If filter is set, skip non-matching kernels
  if [ -n "$FILTER" ] && [ "$NAME" != "$FILTER" ]; then
    continue
  fi

  # Optional component filtering (set by release.sh for rc releases).
  # Both unset -> build everything, unchanged behaviour.
  if [ -n "${ONLY_COMPONENT:-}" ] && [ "$COMPONENT" != "$ONLY_COMPONENT" ]; then
    continue
  fi
  if [ -n "${SKIP_COMPONENT:-}" ] && [ "$COMPONENT" = "$SKIP_COMPONENT" ]; then
    continue
  fi

  CONFIG_FILE="${CONFIGS_DIR}/${NAME}.config"
  SOURCE_DIR="${SOURCES_DIR}/${NAME}"
  OUTPUT_DIR="${OUTPUT_BASE}/${NAME}"
  BUILD_DIR="${BUILD_BASE}/${NAME}"

  rm -rf "$OUTPUT_DIR"

  if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config file not found: $CONFIG_FILE" >&2
    exit 1
  fi

  echo "🔁 Building kernel: $NAME"
  echo "   Repo:   $REPO_URL (branch: $BRANCH)"
  echo "   Config: $CONFIG_FILE"
  echo "   Component: $COMPONENT"

  # Clone or fetch the kernel source
  if [ -d "$SOURCE_DIR/.git" ]; then
    echo "   Fetching updates..."
    git -C "$SOURCE_DIR" fetch origin "$BRANCH"
    git -C "$SOURCE_DIR" checkout FETCH_HEAD -- .
  else
    echo "   Cloning..."
    rm -rf "$SOURCE_DIR"
    git clone --depth 1 --single-branch --branch "$BRANCH" "$REPO_URL" "$SOURCE_DIR"
  fi

  # Clean up any previous build dir
  rm -rf "$BUILD_DIR"
  mkdir -p "$BUILD_DIR"

  # Copy source to build dir (avoid polluting the cached clone)
  cp -a "$SOURCE_DIR/." "$BUILD_DIR/"

  cd "$BUILD_DIR"

  # Setup build environment
  export ARCH="$ARCH"
  export CROSS_COMPILE="$CROSS_COMPILE"
  export DEBEMAIL="info@citronics.eu"
  export DEBFULLNAME="Citronics"

  # Copy config and build
  cp "$CONFIG_FILE" .config
  make olddefconfig

  echo "🚧 Building kernel .deb packages for $NAME"
  make -j$(nproc) \
       LOCALVERSION="$CONFIG_LOCALVERSION" \
       KDEB_PKGVERSION="$PKG_VERSION" \
       deb-pkg

  # Move packages to output
  mkdir -p "$OUTPUT_DIR"
  cd "$BUILD_DIR/.."
  mv ./*.deb "$OUTPUT_DIR/" 2>/dev/null || true

  # Also check build dir parent for debs (different kernel versions place them differently)
  cd "$BUILD_DIR"
  mv ../*.deb "$OUTPUT_DIR/" 2>/dev/null || true

  rm -f "$OUTPUT_DIR"/*-dbg_*.deb "$OUTPUT_DIR"/linux-libc-dev_*.deb

  BUILD_COUNT=$((BUILD_COUNT + 1))
  echo "✅ Done: $OUTPUT_DIR"
  cd "$ROOT_DIR"
done < "$KERNELS_CONF"

if [ "$BUILD_COUNT" -eq 0 ]; then
  echo "ERROR: No kernels were built." >&2
  exit 1
fi

echo ""
echo "🎉 $BUILD_COUNT kernel(s) built successfully."
echo "Output:"
ls -la "$OUTPUT_BASE"/*/
