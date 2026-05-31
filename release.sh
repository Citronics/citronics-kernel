#!/bin/bash
set -e

TAG=$(git describe --tags --exact-match 2>/dev/null) || {
  echo "ERROR: No git tag on current commit. Tag first: git tag v2.1" >&2
  exit 1
}
VERSION=${TAG#v}

echo "Building citronics-kernel $VERSION for all boards..."

PHONES=$(awk '!/^[[:space:]]*#/ && NF {print $1}' kernels.conf | sort -u)

for PHONE in $PHONES; do
  echo "Building kernels for $PHONE..."
  ./build-all-kernels.sh "$PHONE"
done

DEBS=$(find output/ \( -name "linux-image-*.deb" -o -name "linux-headers-*.deb" \) | grep -v dbg | grep -v libc)
if [ -z "$DEBS" ]; then
  echo "ERROR: No .deb files found in output/" >&2
  exit 1
fi

echo "Packages to release:"
echo "$DEBS"

NOTES="Kernel images and headers for all boards — version $VERSION"$'\n'$'\n'"Component breakdown:"$'\n'

MAIN_KERNELS=""
EXPERIMENTAL_KERNELS=""

while IFS= read -r line; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line// /}" ]] && continue
  
  NAME=$(echo "$line" | awk '{print $2}')
  COMPONENT=$(echo "$line" | awk '{print $6}')
  COMPONENT="${COMPONENT:-main}"
  
  if [ "$COMPONENT" = "main" ]; then
    MAIN_KERNELS="$MAIN_KERNELS$NAME"$'\n'
  else
    EXPERIMENTAL_KERNELS="$EXPERIMENTAL_KERNELS$NAME"$'\n'
  fi
done < kernels.conf

if [ -n "$MAIN_KERNELS" ]; then
  NOTES="${NOTES}Stable (main):"$'\n'"$MAIN_KERNELS"$'\n'
fi

if [ -n "$EXPERIMENTAL_KERNELS" ]; then
  NOTES="${NOTES}Experimental:"$'\n'"$EXPERIMENTAL_KERNELS"
fi

echo "Creating GitHub release $TAG..."
# shellcheck disable=SC2086
gh release create "$TAG" $DEBS \
  --repo Citronics/citronics-kernel \
  --title "citronics-kernel $VERSION" \
  --notes "$NOTES"

echo "Done. Release $TAG published."
