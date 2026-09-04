# Feed — a personalized shopping feed for iPhone

A never-ending, hyper-personalized vertical feed of shoppable posts from creators and brands. Tap a product to buy on the merchant's site. No in-app checkout.

## Stack
- iOS: SwiftUI, iOS 17+, XcodeGen, supabase-swift, Nuke
- Backend: Supabase (Postgres + pgvector, Auth, Storage, Edge Functions)

## Setup
1. `brew install xcodegen supabase/tap/supabase`
2. `cp Feed/Config/Secrets.example.xcconfig Feed/Config/Secrets.xcconfig` and fill in the project URL and anon key.
3. `make run` (builds and launches on the iPhone 17 Pro simulator; `make run SIM="iPhone 17"` for another device).
4. Backend (hosted Supabase): run `npx supabase login` once, then `scripts/deploy.sh <project-ref> --seed`. The script links, pushes migrations + dev seed, deploys edge functions, writes `Feed/Config/Secrets.xcconfig`, and runs the embedding sweep.
5. In the Supabase dashboard: Authentication → Providers → enable **Anonymous sign-ins** and Email (OTP). Add `feed://auth/callback` to redirect URLs.

## Purchase-history import (Gmail)
Order emails are read and parsed on the phone; only brand, product, price, date and photo reach the backend. To enable the Gmail button, create an OAuth client of type **iOS** in Google Cloud (APIs & Services → Credentials, bundle id `com.timalpers.shopping`, enable the Gmail API) and put the client id in `Feed/Config/Secrets.xcconfig` as `GOOGLE_OAUTH_CLIENT_ID` / `GOOGLE_OAUTH_REVERSED_CLIENT_ID`. In "Testing" publishing status up to 100 listed test users can connect; public launch needs Google's OAuth verification for the `gmail.readonly` scope. Fixtures mode uses the sample inbox in `Feed/Resources/Fixtures/emails/`.

## Tests
- Unit: `xcodebuild test -scheme Feed -only-testing:FeedTests ...`
- UI (fixtures, no backend): `-only-testing:FeedUITests` covers feed paging, carousel, click-out, like, comments, profile, pager, settings, composer (seeded draft), onboarding quiz. Screenshots land in `/tmp/*.png`.

## Content
- Dev seed: `npm run fixtures` regenerates `Feed/Resources/Fixtures/*.json` and `supabase/seed.sql`.
- Real catalogs: `node scripts/ingest-shopify.mjs --ref <project-ref>` pulls public Shopify product feeds for the brands in `scripts/shopify-brands.json` and ingests them as brand posts with the merchant's photos (`EMBED_WEBHOOK_SECRET` from `supabase/.env`). `scripts/ingest.sh` does the same for a CSV.
- Style tagger: with `ANTHROPIC_API_KEY` in `supabase/.env`, `scripts/deploy.sh` enables a Claude pass that labels untagged posts (image + caption + products) with the quiz vocabulary before embedding, so lazy captions still rank.

## Backend checks without Docker
`npm run db:test` runs every migration plus the seed inside PGlite (in-process Postgres with pgvector) and exercises the feed: cold start, paging, quiz → taste vector, likes → re-ranking, following, saves, comments, redirects, anonymous merge.

## Milestones
- [x] M0 Bootstrap
- [x] M1 Static feed
- [~] M2 Live backend (schema, RPCs, functions written and validated in PGlite; awaiting hosted project link)
- [x] M3 Auth + social (Apple + email OTP sheet, anonymous merge, profiles, saved, post pager, settings, dev menu)
- [x] M4 Composer (photos/video picker, resize/export, product link scraping, create_post)
- [x] M5 Video (player pool, autoplay muted, loop, tap to unmute)
- [x] M6 Comments (sheet, optimistic insert, delete own)
- [~] M7 Onboarding quiz done; redirect + ingest functions written, awaiting hosted deploy
- [x] M8 Purchase-history import (on-device Gmail scan, parser, review grid, taste blend, Settings delete)
