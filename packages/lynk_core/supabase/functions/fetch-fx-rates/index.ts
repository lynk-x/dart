import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const EXCHANGERATE_API_URL = "https://v6.exchangerate-api.com/v6/";

serve(async (req) => {
  // 1. Authorization Gate (Only allow authenticated triggers or specific keys)
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401 });
  }

  const supabaseClient = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  );
  
  const API_KEY = Deno.env.get('EXCHANGERATE_API_KEY');
  
  if (!API_KEY) {
    console.error("Missing EXCHANGERATE_API_KEY");
    return new Response(JSON.stringify({ error: "Missing API Key" }), { status: 500 });
  }

  try {
    console.log("Fetching latest FX rates...");
    const res = await fetch(`${EXCHANGERATE_API_URL}${API_KEY}/latest/USD`);
    const data = await res.json();

    if (data.result !== "success") {
      throw new Error(`API Error: ${data['error-type']}`);
    }

    const rates = data.conversion_rates;

    // Dynamically process all currencies returned by the provider
    const updates = Object.keys(rates).map(curr => ({
      currency: curr,
      rate_to_usd: rates[curr],
      updated_at: new Date().toISOString()
    }));

    const { error } = await supabaseClient
      .from('fx_rates')
      .upsert(updates, { onConflict: 'currency' });

    if (error) throw error;

    return new Response(JSON.stringify({ success: true, updated: updates.length }), {
      headers: { "Content-Type": "application/json" },
      status: 200,
    });
  } catch (err: any) {
    console.error("FX Sync Fail:", err);
    return new Response(JSON.stringify({ error: err.message }), { status: 500 });
  }
})
