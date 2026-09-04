// Optional style tagger: asks Claude to label a post with the quiz vocabulary from its cover image + caption + products.
// Enabled with STYLE_TAGGER_ENABLED=true and ANTHROPIC_API_KEY. Used before embedding so captions like "sunday fit" still rank.
import Anthropic from "@anthropic-ai/sdk";
import { z } from "zod";
import { zodOutputFormat } from "@anthropic-ai/sdk/helpers/zod";

export const STYLE_VOCAB = [
  "minimalist", "old_money", "streetwear", "athleisure", "workwear", "scandi", "model_off_duty", "gorpcore", "coastal",
  "cottagecore", "y2k", "preppy", "glam", "vintage", "boho", "grunge", "coquette", "western",
  "casual", "denim", "tailored", "formal", "resort", "loungewear", "outdoor", "sporty",
] as const;

const Tags = z.object({
  style_tags: z.array(z.enum(STYLE_VOCAB)).min(1).max(6),
  garments: z.array(z.string()).max(6),
  colors: z.array(z.string()).max(4),
  occasion: z.array(z.string()).max(3),
  audience: z.enum(["womens", "mens", "unisex", "unknown"]),
  price_impression: z.enum(["budget", "mid", "premium", "luxury", "unknown"]),
});
export type StyleTags = z.infer<typeof Tags>;

export const taggerEnabled = () => Deno.env.get("STYLE_TAGGER_ENABLED") === "true" && !!Deno.env.get("ANTHROPIC_API_KEY");

const SYSTEM = `You label fashion, home and beauty posts for a shopping feed. Pick style tags only from the allowed vocabulary; choose the 2-5 that best describe the look. Garments, colors and occasion are short lowercase phrases. Say "unknown" when the image and text do not support a judgement.`;

let client: Anthropic | null = null;

export async function tagPost(input: { imageUrl?: string | null; caption: string; products: string[]; category: string }): Promise<StyleTags | null> {
  if (!taggerEnabled()) return null;
  client ??= new Anthropic({ apiKey: Deno.env.get("ANTHROPIC_API_KEY") });
  const text = `Category: ${input.category}\nCaption: ${input.caption || "(none)"}\nTagged products: ${input.products.join("; ") || "(none)"}`;
  const content: Anthropic.ContentBlockParam[] = [];
  if (input.imageUrl && /^https:\/\//.test(input.imageUrl)) content.push({ type: "image", source: { type: "url", url: input.imageUrl } });
  content.push({ type: "text", text });
  try {
    const res = await client.messages.parse({
      model: "claude-opus-5",
      max_tokens: 1024,
      output_config: { effort: "low", format: zodOutputFormat(Tags) },
      system: SYSTEM,
      messages: [{ role: "user", content }],
    });
    if (res.stop_reason === "refusal") return null;
    return res.parsed_output ?? null;
  } catch (e) {
    console.error("[tagger] failed:", (e as Error).message);
    return null;
  }
}
