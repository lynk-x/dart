import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

/**
 * LYNK-X M-PESA STK PUSH INITIATOR
 *
 * Triggers a Safaricom Lipa na M-Pesa Online (STK Push) prompt
 * on the buyer's phone. The actual payment confirmation arrives
 * asynchronously via the `handle-payment-webhook` function.
 *
 * Flow:
 * 1. Authenticate caller (must be a signed-in user)
 * 2. Get M-Pesa OAuth token from Daraja API
 * 3. Lock tickets via `lock_tickets_for_checkout` RPC
 * 4. Initiate STK Push
 * 5. Create a pending transaction record (provider_ref = CheckoutRequestID)
 * 6. Return CheckoutRequestID for client-side realtime listener
 *
 * Required env vars:
 *   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
 *   MPESA_CONSUMER_KEY, MPESA_CONSUMER_SECRET
 *   MPESA_SHORTCODE, MPESA_PASSKEY
 *   MPESA_CALLBACK_URL (the handle-payment-webhook URL with ?provider=mpesa)
 *   MPESA_ENV ("sandbox" | "production")
 */

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const MPESA_CONSUMER_KEY = Deno.env.get("MPESA_CONSUMER_KEY")!;
const MPESA_CONSUMER_SECRET = Deno.env.get("MPESA_CONSUMER_SECRET")!;
const MPESA_SHORTCODE = Deno.env.get("MPESA_SHORTCODE")!;
const MPESA_PASSKEY = Deno.env.get("MPESA_PASSKEY")!;
const MPESA_CALLBACK_URL = Deno.env.get("MPESA_CALLBACK_URL")!;
const MPESA_ENV = Deno.env.get("MPESA_ENV") || "sandbox";

const DARAJA_BASE = MPESA_ENV === "production"
  ? "https://api.safaricom.co.ke"
  : "https://sandbox.safaricom.co.ke";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // --- 1. AUTH ---
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return json({ error: "Missing authorization" }, 401);
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Verify the caller's JWT
    const userClient = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) {
      return json({ error: "Unauthorized" }, 401);
    }

    // --- 2. PARSE REQUEST ---
    const body = await req.json();
    const { phone, amount, currency, metadata } = body;

    if (!phone || !amount || amount <= 0) {
      return json({ error: "Missing or invalid phone/amount" }, 400);
    }

    // Normalize phone to 254XXXXXXXXX format
    const normalizedPhone = normalizeKenyanPhone(phone);
    if (!normalizedPhone) {
      return json({ error: "Invalid Kenyan phone number" }, 400);
    }

    // --- 3. LOCK TICKETS (optional — if items contain tier info) ---
    if (metadata?.items?.length) {
      for (const item of metadata.items) {
        if (item.tier_id && item.quantity) {
          const { error: lockError } = await supabase.rpc("lock_tickets_for_checkout", {
            p_tier_id: item.tier_id,
            p_quantity: item.quantity,
            p_user_id: user.id,
          });

          if (lockError) {
            return json({ error: `Tickets unavailable: ${lockError.message}` }, 409);
          }
        }
      }
    }

    // --- 4. GET M-PESA OAuth TOKEN ---
    const token = await getMpesaToken();

    // --- 5. INITIATE STK PUSH ---
    const timestamp = formatTimestamp(new Date());
    const password = btoa(`${MPESA_SHORTCODE}${MPESA_PASSKEY}${timestamp}`);

    const stkResponse = await fetch(`${DARAJA_BASE}/mpesa/stkpush/v1/processrequest`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({
        BusinessShortCode: MPESA_SHORTCODE,
        Password: password,
        Timestamp: timestamp,
        TransactionType: "CustomerPayBillOnline",
        Amount: Math.ceil(amount), // M-Pesa requires whole KES
        PartyA: normalizedPhone,
        PartyB: MPESA_SHORTCODE,
        PhoneNumber: normalizedPhone,
        CallBackURL: MPESA_CALLBACK_URL,
        AccountReference: `LYNKX-${Date.now().toString(36).toUpperCase()}`,
        TransactionDesc: "Lynk-X Ticket Purchase",
      }),
    });

    const stkData = await stkResponse.json();

    if (stkData.ResponseCode !== "0") {
      console.error("STK Push failed:", stkData);
      return json({
        success: false,
        error: stkData.errorMessage || stkData.ResponseDescription || "STK Push failed",
      }, 400);
    }

    const checkoutRequestId = stkData.CheckoutRequestID;

    // --- 6. CREATE PENDING TRANSACTION ---
    const { error: txError } = await supabase.from("transactions").insert({
      sender_account_id: user.id,
      amount,
      currency: currency || "KES",
      status: "pending",
      reason: "ticket_sale",
      category: "outgoing",
      provider_ref: checkoutRequestId,
      metadata: {
        phone: normalizedPhone,
        mpesa_merchant_request_id: stkData.MerchantRequestID,
        items: metadata?.items || [],
        promo_code: metadata?.promo_code || null,
      },
    });

    if (txError) {
      console.error("Failed to create transaction record:", txError);
      // Non-fatal: the webhook handler can still reconcile via provider_ref
    }

    // --- 7. RETURN CHECKOUT ID ---
    return json({
      success: true,
      checkoutRequestId,
      message: "STK Push sent to phone",
    });

  } catch (err) {
    console.error("mpesa-stk-push error:", err);
    return json({ error: err.message || "Internal server error" }, 500);
  }
});

// ─── Helpers ──────────────────────────────────────────────────────────────────

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/**
 * Normalizes a Kenyan phone number to 254XXXXXXXXX format.
 * Accepts: 0712345678, +254712345678, 254712345678
 */
function normalizeKenyanPhone(phone: string): string | null {
  const cleaned = phone.replace(/[\s\-()]/g, "");
  const match = cleaned.match(/^(?:\+?254|0)([17]\d{8})$/);
  return match ? `254${match[1]}` : null;
}

/**
 * Gets an OAuth access token from the Safaricom Daraja API.
 */
async function getMpesaToken(): Promise<string> {
  const credentials = btoa(`${MPESA_CONSUMER_KEY}:${MPESA_CONSUMER_SECRET}`);

  const response = await fetch(
    `${DARAJA_BASE}/oauth/v1/generate?grant_type=client_credentials`,
    {
      method: "GET",
      headers: { Authorization: `Basic ${credentials}` },
    },
  );

  if (!response.ok) {
    throw new Error(`M-Pesa OAuth failed: ${response.status}`);
  }

  const data = await response.json();
  return data.access_token;
}

/**
 * Formats a date as YYYYMMDDHHmmss for Daraja API timestamps.
 */
function formatTimestamp(date: Date): string {
  const pad = (n: number) => n.toString().padStart(2, "0");
  return (
    date.getFullYear().toString() +
    pad(date.getMonth() + 1) +
    pad(date.getDate()) +
    pad(date.getHours()) +
    pad(date.getMinutes()) +
    pad(date.getSeconds())
  );
}
