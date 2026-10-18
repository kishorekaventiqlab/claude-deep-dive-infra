#!/usr/bin/env bash
# Stubbed AWS. Modes: clean; LEFTOVER=volume (a describe-volumes filter still finds one); TAGGED=stale (the tagging index
# lists a volume that no longer exists); TAGGED=live (it lists a volume that still exists); TAGGED=denied (the existence
# check is refused, which must never count as gone).
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
stub=$(mktemp)
cat >"$stub" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *get-resources*) [ -n "${TAGGED:-}" ] && echo "arn:aws:ec2:ap-south-1:111111111111:volume/vol-0stale" || true ;;
  *describe-volumes*--volume-ids*)
    case "${TAGGED:-}" in
      stale)  echo "An error occurred (InvalidVolume.NotFound) when calling the DescribeVolumes operation" >&2; exit 254 ;;
      denied) echo "An error occurred (UnauthorizedOperation) when calling the DescribeVolumes operation" >&2; exit 254 ;;
      *)      echo '{"Volumes":[{"VolumeId":"vol-0stale"}]}' ;;
    esac ;;
  *describe-volumes*) [ "${LEFTOVER:-}" = volume ] && echo '["vol-0abc"]' || echo '[]' ;;
  *) echo '[]' ;;
esac
STUB
chmod +x "$stub"
run() { env "$@" AWS_CMD=$stub "$here/../scripts/verify-teardown.sh" ap-south-1 >/dev/null; echo $?; }
clean=$(run X=1); dirty=$(run LEFTOVER=volume); stale=$(run TAGGED=stale); live=$(run TAGGED=live); denied=$(run TAGGED=denied)
rm "$stub"
if [ "$clean" -eq 0 ] && [ "$dirty" -ne 0 ] && [ "$stale" -eq 0 ] && [ "$live" -ne 0 ] && [ "$denied" -ne 0 ]; then
  echo PASS
else
  echo "FAIL clean=$clean dirty=$dirty stale=$stale live=$live denied=$denied"; exit 1
fi
