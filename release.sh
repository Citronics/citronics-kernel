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

# Only rebuild what actually moved. changed-kernels.sh compares each entry's
# upstream commit and its config hash against build-state.tsv; CI passes the
# result in through CHANGED_TSV so the branch cannot shift between the check and
# the build. Skipping is safe for APT: deb-packages/update-repo collects assets
# from every release, so a kernel that is not rebuilt stays available from the
# release that built it.
CHANGED_TSV=${CHANGED_TSV:-}
if [ -z "$CHANGED_TSV" ]; then
  CHANGED_TSV=$(mktemp)
  ./changed-kernels.sh > "$CHANGED_TSV"
fi

if [ ! -s "$CHANGED_TSV" ]; then
  echo "No kernel source or config changed for this release type - nothing to build."
  echo "Not creating a release."
  exit 0
fi

ONLY_KERNELS=$(awk '{print $2}' "$CHANGED_TSV" | sort -u | tr '\n' ' ')
export ONLY_KERNELS
echo "Kernels to build:$ONLY_KERNELS"

PHONES=$(awk '{print $1}' "$CHANGED_TSV" | sort -u)

for PHONE in $PHONES; do
  echo "Building kernels for $PHONE..."
  ./build-all-kernels.sh "$PHONE"
done

# Collect artifacts only from the kernels built for this release so stale
# output dirs (other release types, manual backups) are never attached.
NAMES=$(awk '{print $2}' "$CHANGED_TSV" | sort -u)

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
  case " $ONLY_KERNELS " in
    *" $NAME "*) ;;
    *) continue ;;
  esac

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

# Record what this release built so the next run can skip it. Written only after
# gh release create succeeded: a failed release must not mark a kernel as built.
STATE_FILE=${BUILD_STATE_FILE:-build-state.tsv}
TMP_STATE=$(mktemp)
{
  echo "# kernel-name	source-sha	config-hash - written by release.sh, consumed by changed-kernels.sh"
  # keep entries this release did not touch
  if [ -f "$STATE_FILE" ]; then
    awk 'NR==FNR { built[$2]=1; next } !/^#/ && NF && !($1 in built) { print }' \
      "$CHANGED_TSV" "$STATE_FILE"
  fi
  awk '{ printf "%s\t%s\t%s\n", $2, $3, $4 }' "$CHANGED_TSV"
} > "$TMP_STATE"
mv "$TMP_STATE" "$STATE_FILE"
echo "Updated $STATE_FILE:"
cat "$STATE_FILE"

echo "Done. Release $TAG published."
