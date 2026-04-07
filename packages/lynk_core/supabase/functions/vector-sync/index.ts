import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

/**
 * LYNK-X UNIVERSAL VECTOR SYNC
 *
 * Automatically vectorizes new/updated content (Events, Ads, Forums, Profiles)
 * for semantic discovery and recommendation engines.
 *
 * Uses Supabase's built-in Edge Runtime AI (gte-small model) for zero-cost,
 * edge-side embeddings producing 384-dimensional vectors — matching the
 * `extensions.vector(384)` columns defined in the schema.
 */

const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL");

const supabase = createClient(SUPABASE_URL!, SUPABASE_SERVICE_ROLE_KEY!);

serve(async (req) => {
  try {
    const payload = await req.json();
    const { record, table } = payload;

    if (!record || !table) {
      return new Response(JSON.stringify({ error: "Invalid webhook payload" }), { status: 400 });
    }

    let input_text = "";

    // --- CONTEXT DISPATCHER ---
    // Build a rich semantic document per table type to ensure high-quality vector matching.
    switch (table) {
      case "events":
        // Use the JSONB accessor `location->>'name'` since location_name was removed.
        // The webhook record contains the raw JSONB so we access it as a JS object.
        input_text = [
          `Event: ${record.title ?? ""}`,
          `Details: ${record.description ?? ""}`,
          `Location: ${record.location?.name ?? "Unknown"}`,
          `Category: ${record.category_id ?? ""}`,
        ].join(". ");
        break;

      case "user_profile":
        input_text = [
          `Profile: ${record.user_name ?? "Anonymous"}`,
          `Legal Name: ${record.full_name ?? ""}`,
          `Bio: ${record.info?.bio ?? record.info?.tagline ?? ""}`,
        ].join(". ");
        break;

      case "ad_campaigns":
        // ad_campaigns has an embedding vector(384) column — fully supported.
        input_text = [
          `Ad Campaign: ${record.title ?? ""}`,
          `Goal: ${record.description ?? ""}`,
          `Target: ${JSON.stringify(record.targeting_rules ?? {})}`,
        ].join(". ");
        break;

      case "tags":
        input_text = `Tag: ${record.name ?? ""}. Context: ${record.slug ?? ""}`;
        break;

      case "forum_messages":
        // Used for semantic moderation and community search.
        input_text = `Forum Post: ${record.content ?? ""}`;
        break;

      default:
        // Silently ignore tables not configured for vectorization.
        return new Response(JSON.stringify({ status: "ignored_table", table }), { status: 200 });
    }

    if (!input_text || input_text.trim().length === 0) {
      return new Response(JSON.stringify({ status: "skipped_empty_content" }), { status: 200 });
    }

    // --- GENERATE EMBEDDING (384-dim via gte-small) ---
    // This model runs directly on the Supabase Edge Runtime at zero API cost.
    // Produces 384-dimensional vectors, matching the schema's `vector(384)` columns.
    const embeddingResponse = await supabase.functions.invoke("supabase-ai-embed", {
      body: { input: input_text, model: "gte-small" },
    });

    if (embeddingResponse.error) {
      throw new Error(`Embedding generation failed: ${embeddingResponse.error.message}`);
    }

    const embedding: number[] = embeddingResponse.data?.embedding;
    if (!embedding || embedding.length !== 384) {
      throw new Error(`Unexpected embedding shape: ${embedding?.length ?? "null"} (expected 384)`);
    }

    // --- WRITE BACK TO DATABASE ---
    const { error: updateError } = await supabase
      .from(table)
      .update({ embedding })
      .eq("id", record.id);

    if (updateError) {
      throw updateError;
    }

    return new Response(JSON.stringify({ success: true, table, id: record.id, dims: embedding.length }), {
      status: 200,
    });

  } catch (err) {
    console.error("VECTOR SYNC ERROR:", err);
    return new Response(JSON.stringify({ error: err.message }), { status: 500 });
  }
});
