#!/bin/bash
set -e

# RELEASE_TAG lets CI pass the tag it just created explicitly: when several
# tags point at the same commit (auto-build tags on an unchanged master),
# git describe picks an arbitrary one and the release collides.
TAG=${RELEASE_TAG:-$(git describe --tags --exact-match 2>/dev/null)} || true
[ -n "$TAG" ] || {
  echo "ERROR: No git tag on current commit. Tag first: git tag v2.1" >&2
  exit 1
}
VERSION=${TAG#v}

# Tags like v3.2-rc1 are release candidates: build only the rc-component
# kernels and publish as a GitHub prerelease. Normal tags build everything
# except rc kernels, exactly as before rc support existed.
PRERELEASE_FLAG=""
if [[ "$TAG" == *-rc* ]]; then
  PRERELEASE_FLAG="--prerelease"
  export ONLY_COMPONENT="rc"
  echo "Release candidate tag detected: building rc kernels only, publishing as a prerelease."
else
  export SKIP_COMPONENT="rc"
fi

echo "Building citronics-kernel $VERSION..."

PHONES=$(awk -v only="${ONLY_COMPONENT:-}" -v skip="${SKIP_COMPONENT:-}" '
  !/^[[:space:]]*#/ && NF {
    comp = (NF >= 6) ? $6 : "main"
    if (only != "" && comp != only) next
    if (skip != "" && comp == skip) next
    print $1
  }' kernels.conf | sort -u)

if [ -z "$PHONES" ]; then
  echo "ERROR: no kernels.conf entries match this release type" >&2
  exit 1
fi

for PHONE in $PHONES; do
  echo "Building kernels for $PHONE..."
  ./build-all-kernels.sh "$PHONE"
done

# Collect artifacts only from the kernels built for this release so stale
# output dirs (other release types, manual backups) are never attached.
NAMES=$(awk -v only="${ONLY_COMPONENT:-}" -v skip="${SKIP_COMPONENT:-}" '
  !/^[[:space:]]*#/ && NF {
    comp = (NF >= 6) ? $6 : "main"
    if (only != "" && comp != only) next
    if (skip != "" && comp == skip) next
    print $2
  }' kernels.conf | sort -u)

DEBS=""
for NAME in $NAMES; do
  [ -d "output/$NAME" ] || continue
  FOUND=$(find "output/$NAME" \( -name "linux-image-*.deb" -o -name "linux-headers-*.deb" \) ! -name "*dbg*" ! -name "*libc*")
  DEBS="$DEBS$FOUND"$'\n'
done
DEBS=$(printf '%s' "$DEBS" | sed '/^$/d')
if [ -z "$DEBS" ]; then
  echo "ERROR: No .deb files found in output/" >&2
  exit 1
fi

echo "Packages to release:"
echo "$DEBS"

NOTES="Kernel images and headers for all boards — version $VERSION"$'\n'$'\n'"Component breakdown:"$'\n'

MAIN_KERNELS=""
EXPERIMENTAL_KERNELS=""
RC_KERNELS=""

while IFS= read -r line; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line// /}" ]] && continue

  NAME=$(echo "$line" | awk '{print $2}')
  COMPONENT=$(echo "$line" | awk '{print $6}')
  COMPONENT="${COMPONENT:-main}"

  # Keep the notes consistent with what was actually built
  if [ -n "${ONLY_COMPONENT:-}" ] && [ "$COMPONENT" != "$ONLY_COMPONENT" ]; then
    continue
  fi
  if [ -n "${SKIP_COMPONENT:-}" ] && [ "$COMPONENT" = "$SKIP_COMPONENT" ]; then
    continue
  fi

  if [ "$COMPONENT" = "main" ]; then
    MAIN_KERNELS="$MAIN_KERNELS$NAME"$'\n'
  elif [ "$COMPONENT" = "rc" ]; then
    RC_KERNELS="$RC_KERNELS$NAME"$'\n'
  else
    EXPERIMENTAL_KERNELS="$EXPERIMENTAL_KERNELS$NAME"$'\n'
  fi
done < kernels.conf

if [ -n "$MAIN_KERNELS" ]; then
  NOTES="${NOTES}Stable (main):"$'\n'"$MAIN_KERNELS"$'\n'
fi

if [ -n "$RC_KERNELS" ]; then
  NOTES="${NOTES}Release candidate (rc):"$'\n'"$RC_KERNELS"$'\n'
fi

if [ -n "$EXPERIMENTAL_KERNELS" ]; then
  NOTES="${NOTES}Experimental:"$'\n'"$EXPERIMENTAL_KERNELS"
fi

echo "Creating GitHub release $TAG..."
# shellcheck disable=SC2086
gh release create "$TAG" $DEBS \
  --repo Citronics/citronics-kernel \
  --title "citronics-kernel $VERSION" \
  --notes "$NOTES" \
  $PRERELEASE_FLAG

echo "Done. Release $TAG published."
