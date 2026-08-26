#!/usr/bin/env bash
# Capture real Grimmory API responses as test fixtures.
#
# The authenticated endpoints can't be reached without your credentials, so this
# runs on your machine, not in CI. It writes into Tests/ScriptoriumTests/Fixtures.
#
#   ./Tools/capture-fixtures.sh http://192.168.1.21:6060 myusername
#
# You'll be prompted for the password; it is never echoed or stored.
#
# Review what you commit — these payloads contain real book metadata. Anything
# you'd rather keep out of git can be renamed to *.local.json, which is ignored.
set -euo pipefail

BASE="${1:?usage: capture-fixtures.sh <base-url> <username>}"
USER="${2:?usage: capture-fixtures.sh <base-url> <username>}"
OUT="$(cd "$(dirname "$0")/.." && pwd)/Tests/ScriptoriumTests/Fixtures"

read -rsp "Password for ${USER}: " PASS
echo

TOKEN="$(curl -sf -X POST "${BASE}/api/v1/auth/login" \
  -H 'Content-Type: application/json' \
  -d "$(printf '{"username":%s,"password":%s}' \
        "$(printf '%s' "$USER" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
        "$(printf '%s' "$PASS" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')")" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["accessToken"])')"
unset PASS

grab() {
  local name="$1" path="$2"
  if curl -sf -H "Authorization: Bearer ${TOKEN}" "${BASE}${path}" \
      | python3 -m json.tool > "${OUT}/${name}.json"; then
    echo "  captured ${name}.json"
  else
    echo "  FAILED   ${name} (${path})" >&2
  fi
}

echo "Capturing from ${BASE}:"
grab app-user-me       "/api/v1/app/users/me"
grab app-version       "/api/v1/version"
grab app-libraries     "/api/v1/app/libraries"
grab app-shelves       "/api/v1/app/shelves"
grab app-books-page    "/api/v1/app/books?page=0&size=5"
grab app-continue      "/api/v1/app/books/continue-reading"
grab app-filter-options "/api/v1/app/filter-options"

FIRST_ID="$(python3 -c '
import json,sys
try:
    d = json.load(open(sys.argv[1]))
    c = d.get("content") or []
    print(c[0]["id"] if c else "")
except Exception:
    print("")
' "${OUT}/app-books-page.json" 2>/dev/null || true)"

if [ -n "$FIRST_ID" ]; then
  grab app-book-detail "/api/v1/app/books/${FIRST_ID}"
  grab app-book-progress "/api/v1/app/books/${FIRST_ID}/progress"
fi

cat <<'NOTE'

Done. Now check the booleans:

  grep -oE '"(is)?(Admin|admin|Book|book|Primary|primary|Physical|isPhysical)"' \
    Tests/ScriptoriumTests/Fixtures/*.json | sort -u

Lombok strips the "is" prefix from primitive booleans but not boxed ones, so
this is the thing most likely to differ from what the Swift models assume.
Once confirmed, the dual-spelling decoding in BoolKeyDecoding.swift can go.
NOTE
