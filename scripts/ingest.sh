#!/usr/bin/env bash
# Ingest a product CSV into the hosted project as brand posts.
# Usage: EMBED_WEBHOOK_SECRET=... scripts/ingest.sh <project-ref> [csv] [brand-handle] [brand-name]
set -euo pipefail
REF="${1:?project ref}"; CSV="${2:-scripts/sample-catalog.csv}"; HANDLE="${3:-sampleco}"; NAME="${4:-Sample Co}"
ROWS=$(node -e '
const fs=require("fs");const [h,...l]=fs.readFileSync(process.argv[1],"utf8").trim().split("\n");
const parse=s=>{const o=[];let c="",q=false;for(const ch of s){if(ch==="\""){q=!q}else if(ch===","&&!q){o.push(c);c=""}else c+=ch}o.push(c);return o};
const keys=parse(h);console.log(JSON.stringify(l.map(r=>Object.fromEntries(parse(r).map((v,i)=>[keys[i],v])))));' "$CSV")
curl -sS -X POST "https://$REF.supabase.co/functions/v1/ingest-catalog" \
  -H "content-type: application/json" -H "x-embed-secret: ${EMBED_WEBHOOK_SECRET:?set EMBED_WEBHOOK_SECRET}" \
  -d "{\"network\":\"generic\",\"brand\":{\"handle\":\"$HANDLE\",\"display_name\":\"$NAME\",\"avatar_url\":\"https://picsum.photos/seed/$HANDLE/200/200\"},\"category\":\"fashion\",\"source\":{\"rows\":$ROWS}}"
echo
