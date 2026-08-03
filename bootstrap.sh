#!/usr/bin/env bash
set -euo pipefail

REPO_BASE="https://raw.githubusercontent.com/soapyywoapy/Qwythos-Claude-9B/main"
TGZ="tailscale_1.98.10_amd64.tgz"
SOCK="/tmp/tailscaled.sock"
STATE="/tmp/kaggle.state"
GIST_ID="${GIST_ID:-}"
GH_PAT="${GH_PAT:-}"

echo "[ts] downloading tailscale ..."
curl -fsSL -o /tmp/ts.tgz "$REPO_BASE/$TGZ"
tar -xzf /tmp/ts.tgz -C /usr/local/bin --strip-components=1
chmod +x /usr/local/bin/tailscale /usr/local/bin/tailscaled

# Pull persisted node key (if any) so we keep the same node/IP across wipes
if [ -n "$GIST_ID" ] && [ -n "$GH_PAT" ]; then
  echo "[ts] pulling persisted node key from gist $GIST_ID ..."
  RAW="https://gist.githubusercontent.com/soapyywoapy/$GIST_ID/raw/kaggle.state"
  if curl -fsSL -H "Authorization: Bearer $GH_PAT" -o "$STATE" "$RAW"; then
    echo "[ts] restored $(wc -c < "$STATE" 2>/dev/null || echo 0) bytes"
  else
    echo "[ts] no persisted key yet (first boot)"
    rm -f "$STATE"
  fi
fi

pkill tailscaled 2>/dev/null || true
rm -f "$SOCK"

nohup /usr/local/bin/tailscaled \
  --state="$STATE" \
  --socket="$SOCK" \
  --tun=userspace-networking \
  >/tmp/ts.log 2>&1 &

for i in $(seq 1 30); do [ -S "$SOCK" ] && break; sleep 1; done
[ -S "$SOCK" ] || { echo "tailscaled failed to start (see /tmp/ts.log)"; exit 1; }

if [ -s "$STATE" ]; then
  echo "[ts] reusing persisted node key"
  /usr/local/bin/tailscale --socket="$SOCK" up --hostname=kaggle --ssh
else
  echo "[ts] first boot - registering"
  /usr/local/bin/tailscale --socket="$SOCK" up --hostname=kaggle --ssh \
      --authkey="${TAILSCALE_AUTHKEY:?TAILSCALE_AUTHKEY not set}"
fi

# Persist the (possibly new) node key so the next wiped session keeps the same IP
if [ -n "$GIST_ID" ] && [ -n "$GH_PAT" ] && [ -s "$STATE" ]; then
  echo "[ts] saving node key to gist $GIST_ID"
  B64=$(base64 -w0 "$STATE")
  python3 - "$B64" "$GIST_ID" "$GH_PAT" <<'PY'
import base64, json, sys, urllib.request
b64, gid, pat = sys.argv[1], sys.argv[2], sys.argv[3]
content = base64.b64decode(b64).decode("utf-8", errors="replace")
body = json.dumps({"files": {"kaggle.state": {"content": content}}}).encode()
req = urllib.request.Request(f"https://api.github.com/gists/{gid}",
                             data=body, method="PATCH",
                             headers={"Authorization": f"Bearer {pat}",
                                      "Content-Type": "application/json"})
try:
    urllib.request.urlopen(req)
    print("[ts] gist updated OK")
except Exception as e:
    print(f"[ts] gist update FAILED: {e}")
PY
fi

/usr/local/bin/tailscale --socket="$SOCK" status || true
echo "done. connect with: tailscale ssh root@kaggle"
echo "node IP: $(/usr/local/bin/tailscale --socket="$SOCK" ip -4 kaggle 2>/dev/null | tail -1)"