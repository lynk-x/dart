import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

/**
 * LYNK-X PAYMENT WEBHOOK HANDLER
 *
 * Central hub for processing asynchronous payment confirmations
 * from multi-regional providers (M-Pesa, Stripe, Interswitch, etc.).
 *
 * Logic flow:
 * 1. Verify provider signature (HMAC-SHA256 for Stripe)
 * 2. Log raw payload for idempotency & audit
 * 3. Idempotency check against external_event_id
 * 4. Reconcile internal wallet state via RPC
 */

const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const STRIPE_WEBHOOK_SECRET = Deno.env.get("STRIPE_WEBHOOK_SECRET");

const supabase = createClient(SUPABASE_URL!, SUPABASE_SERVICE_ROLE_KEY!);

serve(async (req) => {
  let logEntryId: string | null = null;

  try {
    const url = new URL(req.url);
    const provider_name = url.searchParams.get("provider"); // e.g. 'mpesa', 'stripe'

    if (!provider_name) {
      return new Response(JSON.stringify({ error: "Missing provider parameter" }), { status: 400 });
    }

    // --- 1. SIGNATURE VERIFICATION ---
    // Verify the cryptographic signature before reading the body to prevent spoofing.
    if (provider_name === "stripe") {
      const sig = req.headers.get("stripe-signature");
      if (!sig || !STRIPE_WEBHOOK_SECRET) {
        return new Response(JSON.stringify({ error: "Missing Stripe signature" }), { status: 401 });
      }
      // Stripe requires the raw body bytes for HMAC verification.
      const rawBody = await req.text();
      const isValid = await verifyStripeSignature(rawBody, sig, STRIPE_WEBHOOK_SECRET);
      if (!isValid) {
        return new Response(JSON.stringify({ error: "Invalid Stripe signature" }), { status: 401 });
      }
      // Re-parse after verification since we consumed the stream.
      var raw_payload = JSON.parse(rawBody);
    } else {
      var raw_payload = await req.json();
    }

    // --- 2. IDEMPOTENCY CHECK ---
    // Check if this provider event ID has already been processed.
    const external_event_id = extractExternalId(raw_payload, provider_name);

    if (external_event_id) {
      const { data: existing } = await supabase
        .from("payment_webhooks_log")
        .select("id")
        .eq("external_event_id", external_event_id)
        .maybeSingle();

      if (existing) {
        return new Response(JSON.stringify({ message: "Duplicate event ignored" }), { status: 200 });
      }
    }

    // --- 3. PERSIST RAW LOG ---
    // Log first (before any processing) so that even failed reconciliations are auditable.
    const { data: logEntry, error: logError } = await supabase
      .from("payment_webhooks_log")
      .insert({
        provider_name,        // Text name from query param, matches new schema column
        external_event_id,
        payload: raw_payload,
        status: "pending",
      })
      .select("id")
      .single();

    if (logError) throw logError;
    logEntryId = logEntry.id;

    // --- 4. INTERNAL STATE RECONCILIATION ---
    const mapped = mapProviderToInternal(raw_payload, provider_name);

    if (mapped.is_success) {
      // Resolve the internal Top-Up by reference (provider_ref set at checkout creation time)
      const { data: topup } = await supabase
        .from("wallet_top_ups")
        .select("id")
        .eq("provider_ref", mapped.internal_ref)
        .eq("status", "pending")
        .maybeSingle();

      if (topup) {
        // Atomic balance credit: locks the row, increments balance, marks completed.
        const { error: fulfillmentError } = await supabase.rpc("fulfill_wallet_top_up", {
          p_top_up_id: topup.id,
          p_final_status: "completed",
        });

        if (fulfillmentError) {
          // Mark log entry as failed for investigation — do not crash the response.
          await supabase
            .from("payment_webhooks_log")
            .update({ status: "failed", error_message: fulfillmentError.message })
            .eq("id", logEntryId);
          throw fulfillmentError;
        }
      }

      // Mark log entry as processed.
      await supabase
        .from("payment_webhooks_log")
        .update({ status: "processed", processed_at: new Date().toISOString() })
        .eq("id", logEntryId);
    }

    return new Response(JSON.stringify({ received: true }), { status: 200 });

  } catch (err) {
    console.error("WEBHOOK FATAL ERROR:", err);
    // Mark log entry as failed if we have one.
    if (logEntryId) {
      await supabase
        .from("payment_webhooks_log")
        .update({ status: "failed", error_message: String(err.message) })
        .eq("id", logEntryId);
    }
    return new Response(JSON.stringify({ error: err.message }), { status: 500 });
  }
});

/**
 * Verifies a Stripe webhook signature using HMAC-SHA256.
 * Stripe sends: `t=<timestamp>,v1=<signature>` in the stripe-signature header.
 */
async function verifyStripeSignature(
  rawBody: string,
  sigHeader: string,
  secret: string,
): Promise<boolean> {
  try {
    const parts = Object.fromEntries(sigHeader.split(",").map((p) => p.split("=")));
    const timestamp = parts["t"];
    const expectedSig = parts["v1"];
    if (!timestamp || !expectedSig) return false;

    const payload = `${timestamp}.${rawBody}`;
    const key = await crypto.subtle.importKey(
      "raw",
      new TextEncoder().encode(secret),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"],
    );
    const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload));
    const computed = Array.from(new Uint8Array(sig))
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");
    return computed === expectedSig;
  } catch {
    return false;
  }
}

/**
 * Maps varying provider webhooks to a unified Lynk-X internal state.
 */
function mapProviderToInternal(payload: any, provider: string) {
  switch (provider) {
    case "mpesa": {
      // Safaricom Daraja API has two entirely different payload structures:
      
      // 1. STK PUSH (Lipa na M-Pesa Online) Callback
      if (payload.Body && payload.Body.stkCallback) {
        const stk = payload.Body.stkCallback;
        const meta = stk.CallbackMetadata?.Item || [];
        const amountObj = meta.find((item: any) => item.Name === "Amount");
        return {
          is_success: stk.ResultCode === 0,
          internal_ref: stk.CheckoutRequestID, // Usually stored when initiating checkout
          amount: amountObj ? amountObj.Value : 0,
          currency: "KES",
        };
      }
      
      // 2. C2B (Paybill / Till Number) Validation/Confirmation Callback
      return {
        // C2B callbacks only fire on success (unless validation URL rejects)
        is_success: true, 
        internal_ref: payload.BillRefNumber, // The account number typed by the user
        amount: payload.TransAmount,
        currency: "KES",
      };
    }

    case "stripe":
      // Stripe checkout.session.completed event
      return {
        is_success: payload.type === "checkout.session.completed",
        internal_ref: payload.data?.object?.client_reference_id,
        amount: (payload.data?.object?.amount_total ?? 0) / 100,
        currency: payload.data?.object?.currency?.toUpperCase() ?? "USD",
      };
      
    default:
      return { is_success: false, internal_ref: null };
  }
}

/**
 * Extracts the primary tracing ID from the provider payload for idempotency.
 */
function extractExternalId(payload: any, provider: string): string | null {
  if (provider === "stripe") return payload.id ?? null;
  
  if (provider === "mpesa") {
    // Check STK Push structure
    if (payload.Body && payload.Body.stkCallback) {
      const meta = payload.Body.stkCallback.CallbackMetadata?.Item || [];
      const receiptObj = meta.find((item: any) => item.Name === "MpesaReceiptNumber");
      return receiptObj ? receiptObj.Value : payload.Body.stkCallback.CheckoutRequestID;
    }
    // Check C2B structure
    return payload.TransID ?? null;
  }
  
  return null;
}
