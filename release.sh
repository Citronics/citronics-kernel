#!/bin/bash
set -e

if [ -z "${1:-}" ]; then
  echo "ERROR: Phone argument required" >&2
  echo "Usage: $0 <phone> [kernel-name-filter]" >&2
  exit 1
fi
PHONE="$1"

TAG=$(git describe --tags --exact-match)
VERSION=${TAG#v}

echo "Building citronics-kernel packages $VERSION for $PHONE..."
./build-all-kernels.sh "$PHONE" "${2:-}"

DEBS=$(find output/ \( -name "linux-image-*-citronics-lime-${PHONE}*.deb" -o -name "linux-headers-*-citronics-lime-${PHONE}*.deb" \) | grep -v dbg)
if [ -z "$DEBS" ]; then
  echo "ERROR: No .deb files found in output/"
  exit 1
fi

echo "Packages to release:"
echo "$DEBS"
echo ""

echo "Creating GitHub release $TAG..."
# shellcheck disable=SC2086
gh release create "$TAG" $DEBS \
  --repo Citronics/citronics-kernel \
  --title "citronics-kernel $VERSION ($PHONE)" \
  --notes "Kernel image and headers for Citronics Lime $VERSION"

echo "Done. Release $TAG published."
