#!/bin/sh
# Fails if this addon's copy of FrostSuite-1.0 or the suite's shared test/tool files differ from the canonical copy.
# Usage: tools/check_suite_lib.sh [canonical folder]   (default /workspace/wow-addons/frost-suite-lib)
set -e
cd "$(dirname "$0")/.."
CANON=${1:-/workspace/wow-addons/frost-suite-lib}
status=0
for f in FrostSuite.lua VERSION; do cmp -s "$CANON/$f" "Libs/FrostSuite/$f" || { echo "DRIFT: Libs/FrostSuite/$f"; status=1; }; done
for f in tests/mock_wow.lua tests/mock_secrets.lua tests/test_frostsuite.lua tools/check_suite_lib.sh tools/verify_unit_events.py tools/verify_media.sh; do
  cmp -s "$CANON/$f" "$f" || { echo "DRIFT: $f"; status=1; }
done
[ $status -eq 0 ] && echo "FrostSuite-1.0 r$(cat Libs/FrostSuite/VERSION) in sync"
exit $status
