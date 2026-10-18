#!/usr/bin/env bash
# The same jq filter as apply.yml's add-only gate, fed hand-made plan JSON.
set -uo pipefail
gate() { jq -r '[.resource_changes[] | select((.change.actions - ["create","no-op","read"]) | length > 0) | .address] | .[]' "$1"; }
d=$(mktemp -d)
echo '{"resource_changes":[{"address":"a","change":{"actions":["create"]}},{"address":"b","change":{"actions":["no-op"]}}]}' > "$d/add.json"
echo '{"resource_changes":[{"address":"sg","change":{"actions":["update"]}}]}' > "$d/upd.json"
echo '{"resource_changes":[{"address":"vol","change":{"actions":["delete","create"]}}]}' > "$d/rep.json"
if [ -z "$(gate "$d/add.json")" ] && [ "$(gate "$d/upd.json")" = sg ] && [ "$(gate "$d/rep.json")" = vol ]; then
  rm -r "$d"; echo "add-only gate: PASS"
else
  rm -r "$d"; echo "add-only gate: FAIL"; exit 1
fi
