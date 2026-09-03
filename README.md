# Feed — a personalized shopping feed for iPhone

A never-ending, hyper-personalized vertical feed of shoppable posts from creators and brands. Tap a product to buy on the merchant's site. No in-app checkout.

## Stack
- iOS: SwiftUI, iOS 17+, XcodeGen, supabase-swift, Nuke
- Backend: Supabase (Postgres + pgvector, Auth, Storage, Edge Functions)

## Setup
1. `brew install xcodegen supabase/tap/supabase`
2. `cp Feed/Config/Secrets.example.xcconfig Feed/Config/Secrets.xcconfig` and fill in the project URL and anon key.
3. `make run` (builds and launches on the iPhone 17 Pro simulator; `make run SIM="iPhone 17"` for another device).
4. Backend: `supabase link --project-ref <ref>` then `supabase db push` and `supabase functions deploy`.

## Milestones
- [x] M0 Bootstrap
- [x] M1 Static feed
- [ ] M2 Live backend
- [ ] M3 Auth + social
- [ ] M4 Composer (images)
- [ ] M5 Video
- [ ] M6 Comments
- [ ] M7 Onboarding quiz + redirect + ingest
