// Generates supabase/seed.sql (dev content) with the same deterministic ids as the app fixtures. Run: node scripts/gen-seed.mjs
import { writeFileSync } from "node:fs";
import { createHash } from "node:crypto";

const uuid = (s) => { const h = createHash("sha1").update(s).digest("hex"); return `${h.slice(0,8)}-${h.slice(8,12)}-4${h.slice(13,16)}-a${h.slice(17,20)}-${h.slice(20,32)}`; };
const pic = (seed, w = 1080, h = 1440) => `https://picsum.photos/seed/${seed}/${w}/${h}`;
// Tag-based fashion placeholders (loremflickr pools are small, so keep lock indexes low). Falls back to picsum.
const TAG_BY_STYLE = { minimalist: "outfit", old_money: "blazer", streetwear: "hoodie", athleisure: "sneaker", workwear: "suit", scandi: "sweater", model_off_duty: "jeans", gorpcore: "jacket", coastal: "clothes", cottagecore: "skirt", y2k: "tshirt", preppy: "shirt", glam: "fashion", vintage: "denim", boho: "wardrobe", grunge: "leather", coquette: "model", western: "boots" };
const TAG_BY_WORD = [["coat","jacket"],["loafer","shoes"],["jean","jeans"],["hoodie","hoodie"],["cargo","clothes"],["jordan","sneaker"],["legging","clothing"],["zip","hoodie"],["blazer","blazer"],["tank","tshirt"],["tee","tshirt"],["pant","jeans"],["shell","jacket"],["cardigan","sweater"],["xt-6","sneaker"],["dress","fashion"],["skirt","skirt"],["tote","handbag"],["linen","shirt"],["trench","jacket"],["cashmere","sweater"],["ballet","shoes"],["bow","fashion"],["boot","boots"],["flannel","shirt"],["polo","shirt"],["chino","clothes"],["hoody","hoodie"],["sweater","sweater"],["sequin","fashion"],["slip","fashion"],["leather","leather"],["set","clothing"],["samba","sneaker"],["bag","handbag"]];
const hashNum = (s) => { let h = 0; for (const ch of s) h = (h * 31 + ch.charCodeAt(0)) >>> 0; return h; };
const tagFor = (text, styles = []) => "lookbook";
const postTag = (audience) => audience === "mens" ? "menswear" : "ootd";
const img = (tag, seed, w = 1080, h = 1440) => `https://loremflickr.com/${w}/${h}/${tag}?lock=${1 + (hashNum(seed) % 9)}`;

const q = (s) => s == null ? "null" : `'${String(s).replace(/'/g, "''")}'`;
const arr = (a) => `'{${a.map((x) => `"${x}"`).join(",")}}'`;

const users = {
  mia: { id: uuid("user-mia"), email: "mia@example.com", name: "Mia Chen" },
  theo: { id: uuid("user-theo"), email: "theo@example.com", name: "Theo Alvarez" },
  june: { id: uuid("user-june"), email: "june@example.com", name: "June Okafor" },
};
const authors = [
  { id: uuid("author-mia"), kind: "creator", handle: "mia.styles", name: "Mia Chen", verified: true, owner: users.mia.id, bio: "old money on a mid budget. nyc." },
  { id: uuid("author-theo"), kind: "creator", handle: "theo.fits", name: "Theo Alvarez", verified: false, owner: users.theo.id, bio: "streetwear + trails. la." },
  { id: uuid("author-june"), kind: "creator", handle: "june.wardrobe", name: "June Okafor", verified: true, owner: users.june.id, bio: "capsule wardrobes, coastal weekends." },
  { id: uuid("author-everlane"), kind: "brand", handle: "everlane", name: "Everlane", verified: true, owner: null, bio: "Modern basics, radical transparency.", site: "https://www.everlane.com" },
  { id: uuid("author-aritzia"), kind: "brand", handle: "aritzia", name: "Aritzia", verified: true, owner: null, bio: "Everyday luxury.", site: "https://www.aritzia.com" },
  { id: uuid("author-arcteryx"), kind: "brand", handle: "arcteryx", name: "Arc'teryx", verified: true, owner: null, bio: "Built for the mountains.", site: "https://arcteryx.com" },
];
const A = Object.fromEntries(authors.map((a) => [a.handle, a]));

const P = (slug, title, brand, merchant, cents, url, author = null, desc = "") => ({ id: uuid("product-" + slug), slug, title, brand, merchant, cents, url, author, desc });
const products = [
  P("camel-coat", "Double-faced wool wrap coat", "Toteme", "toteme-studio.com", 129000, "https://toteme-studio.com/products/signature-wool-cashmere-coat", null, "Signature wool-cashmere coat with a wrap front and tie belt."),
  P("loafers", "Leather penny loafers", "Coach", "coach.com", 19500, "https://www.coach.com/products/leather-loafer"),
  P("jeans", "501 Original straight jeans", "Levi's", "levi.com", 9800, "https://www.levi.com/US/en_US/clothing/women/jeans/501-original-fit-womens-jeans/p/125010400"),
  P("hoodie", "Stock logo hoodie", "Stüssy", "stussy.com", 13000, "https://www.stussy.com/products/stock-logo-hood"),
  P("cargos", "Wide-leg cargo pants", "Carhartt WIP", "carhartt-wip.com", 14800, "https://www.carhartt-wip.com/en/men-pants/jet-cargo-pant"),
  P("jordans", "Air Jordan 1 Mid", "Nike", "nike.com", 12500, "https://www.nike.com/t/air-jordan-1-mid-shoes"),
  P("leggings", "Align high-rise pant 25\"", "Lululemon", "lululemon.com", 9800, "https://shop.lululemon.com/p/womens-leggings/Align-Pant-2"),
  P("zipup", "Scuba oversized half-zip", "Lululemon", "lululemon.com", 11800, "https://shop.lululemon.com/p/women-hoodies/Scuba-Oversized-Half-Zip"),
  P("blazer", "Oversized wool blazer", "Aritzia", "aritzia.com", 22800, "https://www.aritzia.com/us/en/product/oversized-wool-blazer/", A.aritzia.id, "Relaxed double-breasted blazer in Italian wool."),
  P("tank", "Contour tank", "Aritzia", "aritzia.com", 4800, "https://www.aritzia.com/us/en/product/contour-tank/", A.aritzia.id),
  P("tee", "Organic cotton box-cut tee", "Everlane", "everlane.com", 3500, "https://www.everlane.com/products/womens-organic-cotton-box-cut-tee", A.everlane.id),
  P("trousers", "The way-high drape pant", "Everlane", "everlane.com", 11800, "https://www.everlane.com/products/womens-way-high-drape-pant", A.everlane.id),
  P("shell", "Beta LT jacket", "Arc'teryx", "arcteryx.com", 45000, "https://arcteryx.com/us/en/shop/womens/beta-lt-jacket", A.arcteryx.id, "Lightweight GORE-TEX shell for wet weather."),
  P("fleece", "Covert cardigan", "Arc'teryx", "arcteryx.com", 20000, "https://arcteryx.com/us/en/shop/mens/covert-cardigan", A.arcteryx.id),
  P("trail", "XT-6 sneakers", "Salomon", "salomon.com", 20000, "https://www.salomon.com/en-us/shop/product/xt-6.html"),
  P("midi", "Floral smocked midi dress", "Reformation", "thereformation.com", 27800, "https://www.thereformation.com/products/midi-dress"),
  P("cardigan", "Cable knit cardigan", "J.Crew", "jcrew.com", 12800, "https://www.jcrew.com/p/womens/categories/clothing/sweaters/cardigans"),
  P("babytee", "Rhinestone baby tee", "Princess Polly", "princesspolly.com", 3200, "https://us.princesspolly.com/products/baby-tee"),
  P("mini", "Low-rise denim mini skirt", "Urban Outfitters", "urbanoutfitters.com", 5900, "https://www.urbanoutfitters.com/shop/bdg-denim-mini-skirt"),
  P("raffia", "Raffia tote bag", "Madewell", "madewell.com", 9800, "https://www.madewell.com/the-raffia-tote"),
  P("linen", "Linen shirt and short set", "Madewell", "madewell.com", 14800, "https://www.madewell.com/linen-set"),
  P("trench", "Classic cotton trench coat", "Ralph Lauren", "ralphlauren.com", 39800, "https://www.ralphlauren.com/women-clothing-coats/trench"),
  P("cashmere", "Cashmere crewneck", "Everlane", "everlane.com", 13000, "https://www.everlane.com/products/womens-cashmere-crew", A.everlane.id),
  P("ballet", "Satin ballet flats", "Miu Miu", "miumiu.com", 85000, "https://www.miumiu.com/us/en/p/ballet-flats"),
  P("bows", "Ribbon bow hair clip set", "Free People", "freepeople.com", 2800, "https://www.freepeople.com/shop/bow-clips"),
  P("boots", "Western leather boots", "Free People", "freepeople.com", 24800, "https://www.freepeople.com/shop/western-boots"),
  P("flannel", "Oversized plaid flannel", "Urban Outfitters", "urbanoutfitters.com", 6900, "https://www.urbanoutfitters.com/shop/bdg-flannel"),
  P("docs", "1460 smooth leather boots", "Dr. Martens", "drmartens.com", 17000, "https://www.drmartens.com/us/en/1460-smooth-leather-lace-up-boots"),
  P("polo", "Classic fit mesh polo", "Ralph Lauren", "ralphlauren.com", 11000, "https://www.ralphlauren.com/men-clothing-polo-shirts"),
  P("chinos", "Slim-fit chinos", "J.Crew", "jcrew.com", 8900, "https://www.jcrew.com/p/mens/categories/clothing/pants/chinos"),
  P("puffer", "Thorium hoody", "Arc'teryx", "arcteryx.com", 50000, "https://arcteryx.com/us/en/shop/womens/thorium-hoody", A.arcteryx.id),
  P("ganni-dress", "Printed cotton midi dress", "Ganni", "ganni.com", 29500, "https://www.ganni.com/en-us/printed-cotton-midi-dress"),
  P("cos-knit", "Oversized merino sweater", "COS", "cos.com", 13500, "https://www.cos.com/en_usd/women/knitwear/oversized-merino-sweater"),
  P("sequin", "Sequin mini dress", "Zara", "zara.com", 8990, "https://www.zara.com/us/en/sequin-mini-dress"),
  P("slip", "Satin slip dress", "Reformation", "thereformation.com", 24800, "https://www.thereformation.com/products/slip-dress"),
  P("leather", "Leather moto jacket", "AllSaints", "allsaints.com", 49900, "https://www.us.allsaints.com/women/leather-jackets/"),
  P("set", "Ribbed matching set", "Alo Yoga", "aloyoga.com", 15600, "https://www.aloyoga.com/products/ribbed-set"),
  P("sneakers", "Samba OG", "adidas", "adidas.com", 10000, "https://www.adidas.com/us/samba-og-shoes"),
  P("tote", "Medium leather tote", "Coach", "coach.com", 39500, "https://www.coach.com/products/tote"),
  P("linen-shirt", "Linen oversized shirt", "COS", "cos.com", 9900, "https://www.cos.com/en_usd/women/shirts/linen-shirt"),
];
const Q = Object.fromEntries(products.map((p) => [p.slug, p]));

const post = (slug, author, kind, caption, tags, prods, days, n = 1, audience = "womens") => ({
  id: uuid("post-" + slug), slug, author, kind, caption, tags, prods, days, n, audience,
});
const posts = [
  post("camel-coat-fall", A["mia.styles"], "carousel", "the perfect camel coat for fall 🍂 wearing it with my go-to loafers and straight jeans", ["old_money", "minimalist", "workwear"], ["camel-coat", "loafers", "jeans"], 0.2, 3),
  post("street-fit-1", A["theo.fits"], "image", "sunday fit. hoodie + cargos + the 1s, that's it that's the post", ["streetwear"], ["hoodie", "cargos", "jordans"], 0.5, 1, "mens"),
  post("aritzia-blazer", A.aritzia, "image", "The Oversized Blazer, back in camel. Layer it over everything.", ["workwear", "model_off_duty"], ["blazer", "tank"], 1),
  post("gym-to-brunch", A["june.wardrobe"], "video", "gym to brunch in the same set, no notes", ["athleisure"], ["leggings", "zipup"], 1.5),
  post("everlane-basics", A.everlane, "carousel", "New season basics. The box-cut tee and the drape pant, together at last.", ["minimalist"], ["tee", "trousers"], 2, 2, "unisex"),
  post("gorp-hike", A["theo.fits"], "carousel", "trail day. shell + fleece + XT-6s. the gorpcore starter pack honestly", ["gorpcore"], ["shell", "fleece", "trail"], 2.5, 3, "unisex"),
  post("cottage-picnic", A["mia.styles"], "image", "picnic dress season is here 🌸", ["cottagecore", "coastal"], ["midi"], 3),
  post("preppy-cardigan", A["june.wardrobe"], "image", "cable knit + jeans, the uniform for cold mornings", ["preppy", "workwear"], ["cardigan", "jeans"], 3.5),
  post("y2k-night", A["mia.styles"], "carousel", "going out y2k style. the baby tee is $32?? insane", ["y2k", "glam"], ["babytee", "mini"], 4, 2),
  post("arcteryx-beta", A.arcteryx, "video", "Beta LT. Lighter, packable, built for the wet season.", ["gorpcore"], ["shell"], 4.5, 1, "unisex"),
  post("coastal-weekend", A["june.wardrobe"], "carousel", "linen set + raffia tote = the whole coastal weekend", ["coastal"], ["linen", "raffia"], 5, 2),
  post("street-fit-2", A["theo.fits"], "image", "cargo pants are undefeated", ["streetwear"], ["cargos", "jordans"], 6, 1, "mens"),
  post("trench-season", A["mia.styles"], "image", "trench season officially open. quiet luxury for less than you think", ["old_money", "workwear"], ["trench", "cashmere"], 7),
  post("balletcore", A["june.wardrobe"], "carousel", "bows, satin flats, soft pink. balletcore is not a phase", ["coquette"], ["ballet", "bows"], 8, 2),
  post("western-boots", A["mia.styles"], "image", "denim on denim + the western boots I can't stop wearing", ["western", "vintage"], ["boots", "jeans"], 9),
  post("grunge-fall", A["theo.fits"], "carousel", "flannel, black denim, docs. it's giving 1994", ["grunge", "vintage"], ["flannel", "docs"], 10, 2, "unisex"),
  post("preppy-weekend", A["theo.fits"], "image", "polo + chinos for the club (i don't belong to a club)", ["preppy"], ["polo", "chinos"], 11, 1, "mens"),
  post("puffer-drop", A.arcteryx, "image", "Thorium Hoody. Warm, light, packs into its own pocket.", ["gorpcore"], ["puffer"], 12, 1, "unisex"),
  post("ganni-print", A["june.wardrobe"], "image", "scandi girl summer: one printed midi and you're done", ["scandi", "coastal"], ["ganni-dress"], 13),
  post("cos-knit", A["mia.styles"], "image", "the oversized knit that does all the work", ["scandi", "minimalist"], ["cos-knit", "trousers"], 14),
  post("sequin-night", A["june.wardrobe"], "carousel", "sequins for a tuesday. why not", ["glam", "y2k"], ["sequin"], 15, 2),
  post("slip-dress", A["mia.styles"], "image", "slip dress + leather jacket = date night forever", ["glam", "model_off_duty"], ["slip", "leather"], 16),
  post("alo-set", A["june.wardrobe"], "video", "ribbed set for pilates and everything after", ["athleisure"], ["set", "sneakers"], 17),
  post("samba-fit", A["theo.fits"], "image", "sambas with everything. that's the rule", ["streetwear", "minimalist"], ["sneakers", "jeans"], 18, 1, "unisex"),
  post("coach-tote", A["mia.styles"], "carousel", "the work tote that fits a laptop and my whole life", ["workwear", "old_money"], ["tote", "blazer"], 19, 2),
  post("linen-shirt", A.everlane, "image", "Linen for the last warm week. Wear it open.", ["coastal", "minimalist"], ["linen-shirt", "trousers"], 20, 1, "unisex"),
  post("boho-festival", A["june.wardrobe"], "carousel", "festival fits: fringe, suede, and boots that can take a beating", ["boho", "western"], ["boots", "midi"], 21, 2),
  post("clean-girl", A["mia.styles"], "image", "white tank, straight jeans, slicked back. model off duty on a monday", ["model_off_duty", "minimalist"], ["tank", "jeans"], 22),
  post("aritzia-office", A.aritzia, "carousel", "Office-ready: the Contour Tank under the Oversized Blazer.", ["workwear"], ["blazer", "tank"], 23, 2),
  post("everlane-cashmere", A.everlane, "image", "Grade-A cashmere, no markup. The crew is back in six colors.", ["minimalist", "old_money"], ["cashmere"], 24, 1, "unisex"),
];

let sql = `-- Dev seed. Generated by scripts/gen-seed.mjs; do not edit by hand.\n-- Creators sign in with email OTP; passwords here are placeholders for local stacks only.\n`;
sql += `set session_replication_role = replica;\n`; // skip triggers? no: we want triggers. revert below
sql = sql.replace("set session_replication_role = replica;\n", "");

sql += `insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous)\nvalues\n`;
sql += Object.values(users).map((u) => `  (${q(u.id)}, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', ${q(u.email)}, crypt('password', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', ${q(JSON.stringify({ full_name: u.name }))}::jsonb, now(), now(), false)`).join(",\n") + `\non conflict (id) do nothing;\n`;
sql += `insert into auth.identities (id, user_id, provider_id, provider, identity_data, created_at, updated_at, last_sign_in_at)\nvalues\n`;
sql += Object.values(users).map((u) => `  (gen_random_uuid(), ${q(u.id)}, ${q(u.id)}, 'email', ${q(JSON.stringify({ sub: u.id, email: u.email, email_verified: true }))}::jsonb, now(), now(), now())`).join(",\n") + `\non conflict do nothing;\n\n`;

sql += `insert into public.authors (id, kind, handle, display_name, bio, avatar_url, website_url, verified, owner_user_id, source_network)\nvalues\n`;
sql += authors.map((a) => `  (${q(a.id)}, ${q(a.kind)}, ${q(a.handle)}, ${q(a.name)}, ${q(a.bio)}, ${q(a.kind === "creator" ? img("model", "avatar-" + a.handle, 200, 200) : pic("avatar-" + a.handle, 200, 200))}, ${q(a.site ?? null)}, ${a.verified}, ${q(a.owner)}, ${a.kind === "brand" ? "'manual'" : "null"})`).join(",\n") + `\non conflict (id) do nothing;\n\n`;

sql += `insert into public.products (id, author_id, merchant, brand, title, description, image_url, price_cents, currency, url, source_network, category)\nvalues\n`;
sql += products.map((p) => `  (${q(p.id)}, ${q(p.author)}, ${q(p.merchant)}, ${q(p.brand)}, ${q(p.title)}, ${q(p.desc || null)}, ${q(img(tagFor(p.title), "p-" + p.slug, 600, 800))}, ${p.cents}, 'USD', ${q(p.url)}, 'manual', 'fashion')`).join(",\n") + `\non conflict (id) do nothing;\n\n`;

sql += `insert into public.posts (id, author_id, kind, caption, category, audience, style_tags, status, source, published_at)\nvalues\n`;
sql += posts.map((p) => `  (${q(p.id)}, ${q(p.author.id)}, ${q(p.kind)}, ${q(p.caption)}, 'fashion', ${q(p.audience)}, ${arr(p.tags)}, 'published', 'app', now() - interval '${p.days} days')`).join(",\n") + `\non conflict (id) do nothing;\n\n`;

const media = [];
for (const p of posts) for (let i = 0; i < p.n; i++) media.push({ id: uuid(`media-${p.slug}-${i}`), post: p.id, pos: i, kind: p.kind === "video" ? "video" : "image",
  url: p.kind === "video" ? "https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4" : img(postTag(p.audience), `${p.slug}-${i}`),
  thumb: img(postTag(p.audience), `${p.slug}-${i}`, 540, 720), w: 1080, h: p.kind === "video" ? 1920 : 1440, dur: p.kind === "video" ? 15000 : null });
sql += `insert into public.post_media (id, post_id, position, kind, external_url, thumbnail_url, width, height, duration_ms)\nvalues\n`;
sql += media.map((m) => `  (${q(m.id)}, ${q(m.post)}, ${m.pos}, ${q(m.kind)}, ${q(m.url)}, ${q(m.thumb)}, ${m.w}, ${m.h}, ${m.dur ?? "null"})`).join(",\n") + `\non conflict (id) do nothing;\n\n`;

sql += `insert into public.post_products (post_id, product_id, position)\nvalues\n`;
sql += posts.flatMap((p) => p.prods.map((s, i) => `  (${q(p.id)}, ${q(Q[s].id)}, ${i})`)).join(",\n") + `\non conflict do nothing;\n\n`;

// some social proof so counters are non-zero
sql += `insert into public.follows (user_id, author_id) values\n` + [
  [users.mia.id, A.everlane.id], [users.mia.id, A.aritzia.id], [users.theo.id, A.arcteryx.id], [users.june.id, A["mia.styles"].id], [users.theo.id, A["mia.styles"].id],
].map(([u, a]) => `  (${q(u)}, ${q(a)})`).join(",\n") + `\non conflict do nothing;\n`;
sql += `insert into public.likes (user_id, post_id) select u, p from (values\n` + posts.slice(0, 12).flatMap((p) => Object.values(users).map((u) => `  (${q(u.id)}::uuid, ${q(p.id)}::uuid)`)).join(",\n") + `) v(u, p)\non conflict do nothing;\n`;
sql += `insert into public.saves (user_id, post_id) select u, p from (values\n` + posts.slice(0, 6).map((p) => `  (${q(users.june.id)}::uuid, ${q(p.id)}::uuid)`).join(",\n") + `) v(u, p)\non conflict do nothing;\n\n`;
sql += `-- Stagger baseline engagement so trending is not flat.\nupdate public.post_stats s set impressions = 200 + (abs(hashtext(s.post_id::text)) % 800), likes = (abs(hashtext(s.post_id::text)) % 60), saves = (abs(hashtext(s.post_id::text)) % 25), click_outs = (abs(hashtext(s.post_id::text)) % 12);\n`;

writeFileSync("supabase/seed.sql", sql);
console.log("seed.sql written:", posts.length, "posts,", products.length, "products");
