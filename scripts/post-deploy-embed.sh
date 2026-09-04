#!/usr/bin/env bash
# Runs the embedding sweep until nothing is pending. Usage: EMBED_WEBHOOK_SECRET=... scripts/post-deploy-embed.sh <project-ref>
set -euo pipefail
REF="${1:?project ref}"
for i in $(seq 1 80); do
  OUT=$(curl -sS -X POST "https://$REF.supabase.co/functions/v1/embed" -H "content-type: application/json" -H "x-embed-secret: ${EMBED_WEBHOOK_SECRET:?set EMBED_WEBHOOK_SECRET}" -d '{"mode":"sweep","limit":25}')
  echo "$OUT"
  echo "$OUT" | grep -q '"processed":0' && break
done
