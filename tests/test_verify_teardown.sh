#!/usr/bin/env bash
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
stub=$(mktemp)
cat >"$stub" <<'STUB'
#!/usr/bin/env bash
# Stub: everything empty except volumes when LEFTOVER=volume.
case "$*" in
  *describe-volumes*) [ "${LEFTOVER:-}" = volume ] && echo '["vol-0abc"]' || echo '[]' ;;
  *) echo '[]' ;;
esac
STUB
chmod +x "$stub"
AWS_CMD=$stub "$here/../scripts/verify-teardown.sh" ap-south-1 >/dev/null; clean=$?
LEFTOVER=volume AWS_CMD=$stub "$here/../scripts/verify-teardown.sh" ap-south-1 >/dev/null; dirty=$?
rm "$stub"
[ "$clean" -eq 0 ] && [ "$dirty" -ne 0 ] && echo PASS || { echo "FAIL clean=$clean dirty=$dirty"; exit 1; }
