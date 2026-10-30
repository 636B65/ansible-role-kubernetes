#!/bin/bash
# Read release information from CHANGELOG.md.
#
#   changelog.sh version         Print the newest released version (X.Y.Z).
#   changelog.sh notes X.Y.Z     Print the changelog section of that version.
set -euo pipefail

changelog="${CHANGELOG:-CHANGELOG.md}"

case "${1:-}" in
    version)
        version="$(sed -n 's/^## \[\([0-9]\+\.[0-9]\+\.[0-9]\+\)\].*/\1/p' "${changelog}" | head -n 1)"
        if [ -z "${version}" ]; then
            echo "No released version heading such as '## [1.2.3] - YYYY-MM-DD' in ${changelog}." >&2
            exit 1
        fi
        echo "${version}"
        ;;
    notes)
        version="${2:?Usage: $0 notes X.Y.Z}"
        notes="$(awk -v heading="## [${version}]" '
            index($0, heading) == 1 { found = 1; next }
            found && /^## \[/ { exit }
            found && /^\[[^]]+\]: / { exit }
            found { print }
        ' "${changelog}")"
        if [ -z "${notes//[[:space:]]/}" ]; then
            echo "No changelog entries for ${version} in ${changelog}." >&2
            exit 1
        fi
        printf '%s\n' "${notes}" | sed -e '/./,$!d'
        ;;
    *)
        echo "Usage: $0 version | notes X.Y.Z" >&2
        exit 2
        ;;
esac
