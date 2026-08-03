#!/usr/bin/env bash
# Minimal launcher: download + run bootstrap with known constants.
# Usage:
#   export GH_PAT=ghp_...          (gist scope)
#   export TAILSCALE_AUTHKEY=tskey-...   (only needed on first boot)
#   bash run.sh
set -euo pipefail
export GIST_ID="${GIST_ID:-f9a76b295b2478659df3a897469ffee2}"
curl -fsSL -o /tmp/bootstrap.sh https://raw.githubusercontent.com/soapyywoapy/Qwythos-Claude-9B/main/bootstrap.sh
bash /tmp/bootstrap.sh