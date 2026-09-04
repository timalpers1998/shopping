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

## Backend checks without Docker
`npm run db:test` runs every migration plus the seed inside PGlite (in-process Postgres with pgvector) and exercises the feed: cold start, paging, quiz → taste vector, likes → re-ranking, following, saves, comments, redirects, anonymous merge.

## Milestones
- [x] M0 Bootstrap
- [x] M1 Static feed
- [~] M2 Live backend (schema, RPCs, functions written and validated in PGlite; awaiting hosted project link)
- [ ] M3 Auth + social
- [ ] M4 Composer (images)
- [ ] M5 Video
- [ ] M6 Comments
- [ ] M7 Onboarding quiz + redirect + ingest
