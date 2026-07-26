#!/bin/bash
# Print the kernels.conf entries that actually need rebuilding.
#
# A release used to rebuild every kernel of its component every time any one
# branch moved, which costs ~20 minutes per kernel for no result. This resolves
# each entry's upstream ref and compares it - together with a hash of the config
# file - against build-state.tsv, written after the last successful release.
#
# Two inputs decide it, and both matter:
#   - the source commit, so a moved branch or a retagged release rebuilds;
#   - the config hash, so editing configs/<name>.config rebuilds even when the
#     kernel source has not moved. Without that a config change would be
#     silently ignored, which is a worse failure than rebuilding too often.
#
# Skipping is safe for the APT repository: deb-packages/update-repo downloads
# assets from *every* citronics-kernel release, so a kernel that is not rebuilt
# stays available from the release that did build it.
#
# Honours the same ONLY_COMPONENT / SKIP_COMPONENT filters as release.sh.
# Output, one line per kernel that needs building:
#     <phone>\t<name>\t<source-sha>\t<config-sha256>
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
KERNELS_CONF="$ROOT_DIR/kernels.conf"
STATE_FILE="${BUILD_STATE_FILE:-$ROOT_DIR/build-state.tsv}"
CONFIGS_DIR="$ROOT_DIR/configs"

[ -f "$KERNELS_CONF" ] || { echo "ERROR: kernels.conf not found" >&2; exit 1; }

# Resolve a ref (branch or tag) to the commit the build will check out.
# An annotated tag must be dereferenced: ls-remote lists both the tag object
# and, as "<ref>^{}", the commit it points at - and the commit is what
# scripts/setlocalversion will report.
resolve_sha() {
	local repo=$1 ref=$2 lines sha
	lines=$(git ls-remote "$repo" "refs/heads/$ref" "refs/tags/$ref" "refs/tags/${ref}^{}" 2>/dev/null || true)
	sha=$(printf '%s\n' "$lines" | awk '$2 ~ /\^\{\}$/ { print $1; exit }')
	[ -n "$sha" ] || sha=$(printf '%s\n' "$lines" | awk 'NF { print $1; exit }')
	printf '%s' "$sha"
}

config_hash() {
	local f="$CONFIGS_DIR/$1.config"
	[ -f "$f" ] && sha256sum "$f" | cut -c1-16 || printf 'missing'
}

state_lookup() {  # $1 = name, $2 = column (2 = sha, 3 = config hash)
	[ -f "$STATE_FILE" ] || return 0
	awk -v n="$1" -v c="$2" '!/^#/ && $1 == n { print $c; exit }' "$STATE_FILE"
}

while read -r phone name repo ref arch component _rest; do
	case "$phone" in ''|\#*) continue ;; esac
	component=${component:-main}

	if [ -n "${ONLY_COMPONENT:-}" ] && [ "$component" != "$ONLY_COMPONENT" ]; then continue; fi
	if [ -n "${SKIP_COMPONENT:-}" ] && [ "$component" = "$SKIP_COMPONENT" ]; then continue; fi

	sha=$(resolve_sha "$repo" "$ref")
	if [ -z "$sha" ]; then
		echo "WARNING: cannot resolve $ref in $repo - building $name to be safe" >&2
		sha="unresolved"
	fi
	chash=$(config_hash "$name")

	old_sha=$(state_lookup "$name" 2)
	old_chash=$(state_lookup "$name" 3)

	if [ "$sha" = "unresolved" ]; then
		reason="ref could not be resolved"
	elif [ -z "$old_sha" ]; then
		reason="never built"
	elif [ "$sha" != "$old_sha" ]; then
		reason="source moved ${old_sha:0:12} -> ${sha:0:12}"
	elif [ "$chash" != "$old_chash" ]; then
		reason="config changed"
	else
		echo "up to date: $name at ${sha:0:12}" >&2
		continue
	fi

	echo "needs build: $name ($reason)" >&2
	printf '%s\t%s\t%s\t%s\n' "$phone" "$name" "$sha" "$chash"
done < "$KERNELS_CONF"
