#!/usr/bin/env bash
# One-shot backend deploy to a hosted Supabase project. Prereq: `npx supabase login` done once on this machine.
# Usage: scripts/deploy.sh <project-ref> [--seed]
set -euo pipefail
cd "$(dirname "$0")/.."
REF="${1:?usage: scripts/deploy.sh <project-ref> [--seed]}"
SEED="${2:-}"
ENVF="supabase/.env"

npx supabase link --project-ref "$REF"

if [[ "$SEED" == "--seed" ]]; then
  npx supabase db push --include-seed --yes
else
  npx supabase db push --yes
fi

# Shared secret between Postgres (pg_net webhook) and the embed function. Generated once, kept in gitignored supabase/.env.
if [[ -f "$ENVF" ]] && grep -q EMBED_WEBHOOK_SECRET "$ENVF"; then
  SECRET=$(grep EMBED_WEBHOOK_SECRET "$ENVF" | cut -d= -f2)
else
  SECRET=$(openssl rand -hex 24)
  echo "EMBED_WEBHOOK_SECRET=$SECRET" >> "$ENVF"
fi
npx supabase secrets set EMBED_WEBHOOK_SECRET="$SECRET" IP_SALT="$(openssl rand -hex 8)"
# Optional: Claude style tagger for posts without style tags (set ANTHROPIC_API_KEY in supabase/.env to enable).
if grep -q '^ANTHROPIC_API_KEY=' "$ENVF" 2>/dev/null; then
  npx supabase secrets set ANTHROPIC_API_KEY="$(grep '^ANTHROPIC_API_KEY=' "$ENVF" | cut -d= -f2-)" STYLE_TAGGER_ENABLED=true
fi

npx supabase functions deploy embed scrape-product merge-anonymous ingest-catalog
npx supabase functions deploy redirect --no-verify-jwt

# Write the app's Secrets.xcconfig with the public (anon) key only.
ANON=$(npx supabase projects api-keys --project-ref "$REF" -o json | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);const k=j.find(x=>x.name==="anon"||x.name==="publishable"||/anon|publishable/.test(x.name));console.log(k?k.api_key:"")})')
if [[ -n "$ANON" ]]; then
  cat > Feed/Config/Secrets.xcconfig <<XC
SUPABASE_URL = https:/\$()/$REF.supabase.co
SUPABASE_ANON_KEY = $ANON
REDIRECT_BASE_URL = https:/\$()/$REF.supabase.co/functions/v1/redirect
XC
  echo "Wrote Feed/Config/Secrets.xcconfig"
else
  echo "Could not read the anon key automatically; copy it from the dashboard into Feed/Config/Secrets.xcconfig" >&2
fi

# Bootstrap app_settings and embed everything that is pending.
EMBED_WEBHOOK_SECRET="$SECRET" curl -sS -X POST "https://$REF.supabase.co/functions/v1/embed" -H "content-type: application/json" -H "x-embed-secret: $SECRET" -d '{"mode":"bootstrap"}'; echo
EMBED_WEBHOOK_SECRET="$SECRET" scripts/post-deploy-embed.sh "$REF"
echo "Deploy complete. Remaining dashboard steps: enable Anonymous sign-ins and Email OTP under Authentication → Providers."
