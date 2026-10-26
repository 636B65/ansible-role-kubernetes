#!/bin/bash
# Run the site playbook twice against a real lab cluster and fail if the
# second run changes anything. Extra arguments are passed to both runs.
#
#   tests/idempotence.sh -i inventory.yml examples/site.yml --ask-vault-pass
set -euo pipefail

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <ansible-playbook arguments>" >&2
    exit 2
fi

log_directory="$(mktemp -d)"
trap 'rm -rf "${log_directory}"' EXIT

echo "First run: converge the cluster"
ansible-playbook "$@" | tee "${log_directory}/first.log"

echo "Second run: every task must report ok or skipped"
ansible-playbook "$@" | tee "${log_directory}/second.log"

recap="$(sed -n '/^PLAY RECAP/,$p' "${log_directory}/second.log")"
if printf '%s\n' "${recap}" | grep -Eq 'changed=[1-9]|failed=[1-9]|unreachable=[1-9]'; then
    echo
    echo "Idempotence check failed. Tasks that reported changes:"
    awk '/^TASK \[/ { task = $0 } /^changed: / { print task; print "  " $0 }' \
        "${log_directory}/second.log"
    exit 1
fi

echo "Idempotence check passed."
