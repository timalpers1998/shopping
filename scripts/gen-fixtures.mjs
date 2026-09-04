// Generates Feed/Resources/Fixtures/feed_*.json with placeholder imagery. Run: node scripts/gen-fixtures.mjs
import { writeFileSync, mkdirSync } from "node:fs";
import { createHash } from "node:crypto";

const uuid = (s) => { const h = createHash("sha1").update(s).digest("hex"); return `${h.slice(0,8)}-${h.slice(8,12)}-4${h.slice(13,16)}-a${h.slice(17,20)}-${h.slice(20,32)}`; };
const pic = (seed, w = 1080, h = 1440) => `https://picsum.photos/seed/${seed}/${w}/${h}`;
// Tag-based fashion placeholders (loremflickr pools are small, so keep lock indexes low). Falls back to picsum.
const TAG_BY_STYLE = { minimalist: "outfit", old_money: "blazer", streetwear: "hoodie", athleisure: "sneaker", workwear: "suit", scandi: "sweater", model_off_duty: "jeans", gorpcore: "jacket", coastal: "clothes", cottagecore: "skirt", y2k: "tshirt", preppy: "shirt", glam: "fashion", vintage: "denim", boho: "wardrobe", grunge: "leather", coquette: "model", western: "boots" };
const TAG_BY_WORD = [["coat","jacket"],["loafer","shoes"],["jean","jeans"],["hoodie","hoodie"],["cargo","clothes"],["jordan","sneaker"],["legging","clothing"],["zip","hoodie"],["blazer","blazer"],["tank","tshirt"],["tee","tshirt"],["pant","jeans"],["shell","jacket"],["cardigan","sweater"],["xt-6","sneaker"],["dress","fashion"],["skirt","skirt"],["tote","handbag"],["linen","shirt"],["trench","jacket"],["cashmere","sweater"],["ballet","shoes"],["bow","fashion"],["boot","boots"],["flannel","shirt"],["polo","shirt"],["chino","clothes"],["hoody","hoodie"],["sweater","sweater"],["sequin","fashion"],["slip","fashion"],["leather","leather"],["set","clothing"],["samba","sneaker"],["bag","handbag"]];
const hashNum = (s) => { let h = 0; for (const ch of s) h = (h * 31 + ch.charCodeAt(0)) >>> 0; return h; };
const GOOD_TAGS = ["lookbook", "ootd", "clothing", "fashion", "model"];
const tagFor = (text, styles = []) => GOOD_TAGS[hashNum(text || "x") % GOOD_TAGS.length];
const postTag = (audience) => audience === "mens" ? "menswear" : "ootd";
const img = (tag, seed, w = 1080, h = 1440) => `https://loremflickr.com/${w}/${h}/${tag}?lock=${1 + (hashNum(seed) % 9)}`;

const daysAgo = (d) => new Date(Date.now() - d * 86400e3).toISOString();

const authors = {
  mia:   { id: uuid("author-mia"),   handle: "mia.styles",   display_name: "Mia Chen",       kind: "creator", is_verified: true,  avatar_url: img("model", "mia", 200, 200) },
  theo:  { id: uuid("author-theo"),  handle: "theo.fits",    display_name: "Theo Alvarez",   kind: "creator", is_verified: false, avatar_url: img("model", "theo", 200, 200) },
  june:  { id: uuid("author-june"),  handle: "june.wardrobe",display_name: "June Okafor",    kind: "creator", is_verified: true,  avatar_url: img("model", "june", 200, 200) },
  everlane: { id: uuid("author-everlane"), handle: "everlane", display_name: "Everlane", kind: "brand", is_verified: true, avatar_url: pic("everlane", 200, 200) },
  aritzia:  { id: uuid("author-aritzia"),  handle: "aritzia",  display_name: "Aritzia",  kind: "brand", is_verified: true, avatar_url: pic("aritzia", 200, 200) },
  arcteryx: { id: uuid("author-arcteryx"), handle: "arcteryx", display_name: "Arc'teryx", kind: "brand", is_verified: true, avatar_url: pic("arcteryx", 200, 200) },
};

const P = (slug, title, brand, merchant, cents, url) => ({ id: uuid("product-" + slug), title, brand, merchant, price_cents: cents, currency: "USD", url, image_url: img(tagFor(title), "p-" + slug, 600, 800) });
const products = {
  camelCoat: P("camel-coat", "Double-faced wool wrap coat", "Toteme", "toteme-studio.com", 129000, "https://toteme-studio.com/products/signature-wool-cashmere-coat"),
  loafers: P("loafers", "Leather penny loafers", "Coach", "coach.com", 19500, "https://www.coach.com/products/leather-loafer"),
  jeans: P("jeans", "501 Original straight jeans", "Levi's", "levi.com", 9800, "https://www.levi.com/US/en_US/clothing/women/jeans/501-original-fit-womens-jeans/p/125010400"),
  hoodie: P("hoodie", "Stock logo hoodie", "Stüssy", "stussy.com", 13000, "https://www.stussy.com/products/stock-logo-hood"),
  cargos: P("cargos", "Wide-leg cargo pants", "Carhartt WIP", "carhartt-wip.com", 14800, "https://www.carhartt-wip.com/en/men-pants/jet-cargo-pant"),
  jordans: P("jordans", "Air Jordan 1 Mid", "Nike", "nike.com", 12500, "https://www.nike.com/t/air-jordan-1-mid-shoes"),
  leggings: P("leggings", "Align high-rise pant 25\"", "Lululemon", "lululemon.com", 9800, "https://shop.lululemon.com/p/womens-leggings/Align-Pant-2"),
  zipup: P("zipup", "Scuba oversized half-zip", "Lululemon", "lululemon.com", 11800, "https://shop.lululemon.com/p/women-hoodies/Scuba-Oversized-Half-Zip"),
  blazer: P("blazer", "Oversized wool blazer", "Aritzia", "aritzia.com", 22800, "https://www.aritzia.com/us/en/product/oversized-wool-blazer/"),
  tank: P("tank", "Contour tank", "Aritzia", "aritzia.com", 4800, "https://www.aritzia.com/us/en/product/contour-tank/"),
  tee: P("tee", "Organic cotton box-cut tee", "Everlane", "everlane.com", 3500, "https://www.everlane.com/products/womens-organic-cotton-box-cut-tee"),
  trousers: P("trousers", "The way-high drape pant", "Everlane", "everlane.com", 11800, "https://www.everlane.com/products/womens-way-high-drape-pant"),
  shell: P("shell", "Beta LT jacket", "Arc'teryx", "arcteryx.com", 45000, "https://arcteryx.com/us/en/shop/womens/beta-lt-jacket"),
  fleece: P("fleece", "Covert cardigan", "Arc'teryx", "arcteryx.com", 20000, "https://arcteryx.com/us/en/shop/mens/covert-cardigan"),
  trailrunners: P("trail", "XT-6 sneakers", "Salomon", "salomon.com", 20000, "https://www.salomon.com/en-us/shop/product/xt-6.html"),
  midi: P("midi", "Floral smocked midi dress", "Reformation", "thereformation.com", 27800, "https://www.thereformation.com/products/midi-dress"),
  cardigan: P("cardigan", "Cable knit cardigan", "J.Crew", "jcrew.com", 12800, "https://www.jcrew.com/p/womens/categories/clothing/sweaters/cardigans"),
  babyTee: P("babytee", "Rhinestone baby tee", "Princess Polly", "princesspolly.com", 3200, "https://us.princesspolly.com/products/baby-tee"),
  miniSkirt: P("mini", "Low-rise denim mini skirt", "Urban Outfitters", "urbanoutfitters.com", 5900, "https://www.urbanoutfitters.com/shop/bdg-denim-mini-skirt"),
  raffia: P("raffia", "Raffia tote bag", "Madewell", "madewell.com", 9800, "https://www.madewell.com/the-raffia-tote"),
  linenSet: P("linen", "Linen shirt and short set", "Madewell", "madewell.com", 14800, "https://www.madewell.com/linen-set"),
};

const post = (slug, author, kind, caption, tags, prods, days, n = 1, stats) => ({
  id: uuid("post-" + slug), kind, caption, created_at: daysAgo(days), category: "fashion", style_tags: tags,
  author: { ...author, is_following: false },
  media: Array.from({ length: n }, (_, i) => ({ id: uuid(`media-${slug}-${i}`), type: kind === "video" ? "video" : "image",
    url: kind === "video" ? "https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4" : img(postTag(undefined), `${slug}-${i}`),
    thumbnail_url: img(postTag(undefined), `${slug}-${i}`, 540, 720), width: 1080, height: kind === "video" ? 1920 : 1440, duration_seconds: kind === "video" ? 15 : null, position: i })),
  products: prods.map((p, i) => ({ ...p, position: i })),
  stats: stats ?? { likes: 100 + (slug.length * 137) % 4000, comments: (slug.length * 13) % 90, saves: 40 + (slug.length * 59) % 900 },
  viewer: { liked: false, saved: false },
});

const A = authors, Q = products;
const forYou = [
  post("camel-coat-fall", A.mia, "carousel", "the perfect camel coat for fall 🍂 wearing it with my go-to loafers and straight jeans", ["old_money", "minimalist", "workwear"], [Q.camelCoat, Q.loafers, Q.jeans], 0.2, 3),
  post("street-fit-1", A.theo, "image", "sunday fit. hoodie + cargos + the 1s, that's it that's the post", ["streetwear"], [Q.hoodie, Q.cargos, Q.jordans], 0.5),
  post("aritzia-blazer", A.aritzia, "image", "The Oversized Blazer, back in camel. Layer it over everything.", ["workwear", "model_off_duty"], [Q.blazer, Q.tank], 1),
  post("gym-to-brunch", A.june, "video", "gym to brunch in the same set, no notes", ["athleisure"], [Q.leggings, Q.zipup], 1.5),
  post("everlane-basics", A.everlane, "carousel", "New season basics. The box-cut tee and the drape pant, together at last.", ["minimalist"], [Q.tee, Q.trousers], 2, 2),
  post("gorp-hike", A.theo, "carousel", "trail day. shell + fleece + XT-6s. the gorpcore starter pack honestly", ["gorpcore"], [Q.shell, Q.fleece, Q.trailrunners], 2.5, 3),
  post("cottage-picnic", A.mia, "image", "picnic dress season is here 🌸", ["cottagecore", "coastal"], [Q.midi], 3),
  post("preppy-cardigan", A.june, "image", "cable knit + jeans, the uniform for cold mornings", ["preppy", "workwear"], [Q.cardigan, Q.jeans], 3.5),
  post("y2k-night", A.mia, "carousel", "going out y2k style. the baby tee is $32?? insane", ["y2k", "glam"], [Q.babyTee, Q.miniSkirt], 4, 2),
  post("arcteryx-beta", A.arcteryx, "video", "Beta LT. Lighter, packable, built for the wet season.", ["gorpcore"], [Q.shell], 4.5),
  post("coastal-weekend", A.june, "carousel", "linen set + raffia tote = the whole coastal weekend", ["coastal"], [Q.linenSet, Q.raffia], 5, 2),
  post("street-fit-2", A.theo, "image", "cargo pants are undefeated", ["streetwear"], [Q.cargos, Q.jordans], 6),
];
const fashion = forYou.slice().reverse();
const following = [forYou[0], forYou[4], forYou[6]];

mkdirSync("Feed/Resources/Fixtures", { recursive: true });
const write = (name, items) => writeFileSync(`Feed/Resources/Fixtures/${name}.json`, JSON.stringify({ request_id: name, next_cursor: null, items }, null, 2));
write("feed_for_you", forYou); write("feed_fashion", fashion); write("feed_following", following);
write("feed_home", []); write("feed_beauty", []);
console.log("fixtures written:", forYou.length, "for_you posts");
