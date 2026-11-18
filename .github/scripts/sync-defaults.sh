#!/bin/bash
# Copy the pinned component versions from defaults/main.yml to the places that
# repeat them: the "Component versions" table in README.md and the defaults in
# meta/argument_specs.yml. Renovate only updates defaults/main.yml and runs
# this script after each update (postUpgradeTasks in renovate.json).
#
#   sync-defaults.sh          update the files
#   sync-defaults.sh --check  only report differences; exit 1 if there are any
set -euo pipefail

cd "$(dirname "$0")/../.."
check=false
[[ "${1:-}" == "--check" ]] && check=true

readme="README.md"
specs="meta/argument_specs.yml"
status=0

while IFS= read -r line; do
    name="${line%%:*}"
    value="$(sed -E 's/^[a-z_]+: "([^"]*)".*/\1/' <<<"$line")"

    for file in "$readme" "$specs"; do
        if [[ "$file" == "$readme" ]]; then
            # | `name` | `value` |
            pattern="^(\| \`${name}\` \| \`)[^\`]*(\` \|)$"
            replacement="\1${value}\2"
            current="$(sed -nE "s/${pattern}/X/p" "$file")"
            [[ -n "$current" ]] || continue
            has="$(grep -cE "^\| \`${name}\` \| \`${value}\` \|$" "$file" || true)"
        else
            # Every "      name:" (one per entry point) must be followed, within
            # the same option, by "        default: value".
            has="$(awk -v n="      ${name}:" -v v="        default: ${value}" '
                $0 == n { inside = 1; seen++; next }
                inside && /^      [a-z_]+:$/ { inside = 0 }
                inside && $0 == v { ok++; inside = 0 }
                END { print (seen > 0 && ok == seen) ? 1 : 0 }' "$file")"
            present="$(grep -cx "      ${name}:" "$file" || true)"
            [[ "$present" != "0" ]] || continue
        fi

        if [[ "$has" != "0" ]]; then
            continue
        fi
        if $check; then
            echo "${file}: ${name} is not ${value} (defaults/main.yml)" >&2
            status=1
        elif [[ "$file" == "$readme" ]]; then
            sed -i -E "s/${pattern}/${replacement}/" "$file"
            echo "${file}: ${name} = ${value}"
        else
            awk -v n="      ${name}:" -v v="${value}" '
                $0 == n { inside = 1; print; next }
                inside && /^      [a-z_]+:$/ { inside = 0 }
                inside && /^        default: / { print "        default: " v; inside = 0; next }
                { print }' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
            echo "${file}: ${name} = ${value}"
        fi
    done
done < <(grep -E '^kubernetes_[a-z_]*version: "[^"]*"' defaults/main.yml)

exit "$status"
