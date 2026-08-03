#!/usr/bin/env bash
set -euo pipefail

REPO_BASE="https://raw.githubusercontent.com/soapyywoapy/Qwythos-Claude-9B/main"
TGZ="tailscale_1.98.10_amd64.tgz"
SOCK="/tmp/tailscaled.sock"
STATE="/tmp/kaggle.state"
STATE_LINK="${KAGGLE_STATE_URL:-}"
GH_PAT="${GH_PAT:-}"

echo "[ts] downloading tailscale ..."
curl -fsSL -o /tmp/ts.tgz "$REPO_BASE/$TGZ"
tar -xzf /tmp/ts.tgz -C /usr/local/bin --strip-components=1
chmod +x /usr/local/bin/tailscale /usr/local/bin/tailscaled

if [ -n "$STATE_LINK" ]; then
  if [ -n "$GH_PAT" ]; then
    curl -fsSL -H "Authorization: Bearer $GH_PAT" -o "$STATE" "$STATE_LINK" || rm -f "$STATE"
  else
    curl -fsSL -o "$STATE" "$STATE_LINK" || rm -f "$STATE"
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
  echo "[ts] first boot — registering"
  /usr/local/bin/tailscale --socket="$SOCK" up --hostname=kaggle --ssh \
      --authkey="${TAILSCALE_AUTHKEY:?TAILSCALE_AUTHKEY not set}"
fi

/usr/local/bin/tailscale --socket="$SOCK" status || true
echo "done. connect with: tailscale ssh root@kaggle"
