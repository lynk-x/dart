import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

/**
 * LYNK-X NOTIFICATION DISPATCHER
 * 
 * Handles automated email (vía Resend) and push notifications (vía FCM) 
 * triggered by database webhooks on the public.delivery_queue table.
 */

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const DEFAULT_EMAIL_FROM = "Lynk-X <notifications@lynk-x.com>";

const supabase = createClient(SUPABASE_URL!, SUPABASE_SERVICE_ROLE_KEY!);

serve(async (req) => {
  try {
    const payload = await req.json();
    const { record } = payload; // Payload from Supabase Webhook

    if (!record) {
      return new Response(JSON.stringify({ error: "Missing record payload" }), { status: 400 });
    }

    const { 
      id: queue_id, 
      channel, 
      template_slug, 
      recipient, 
      info = {} 
    } = record;

    // Extract data from the consolidated info JSONB
    const template_data = info.data || {};
    const custom_subject = info.subject;
    const raw_body = info.body;

    let delivery_result;

    // --- CHANNEL: EMAIL (via Resend) ---
    if (channel === 'email') {
      let final_html = '';
      let final_subject = custom_subject || "Notification from Lynk-X";

      // If a template is specified, fetch and populate it from storage
      if (template_slug) {
        const { data: fileData, error: fileError } = await supabase.storage
          .from('system_templates')
          .download(`${template_slug}.html`);

        if (fileError) {
          throw new Error(`Template Fetch Failure: ${fileError.message}`);
        }

        final_html = await fileData.text();

        // Variable Injection (Handlebars-style replacement)
        if (template_data && typeof template_data === 'object') {
          Object.keys(template_data).forEach((key) => {
            const regex = new RegExp(`{{${key}}}`, "g");
            final_html = final_html.replace(regex, String(template_data[key]));
          });
        }
      } else {
        // Fallback to raw body if no template slug provided (mostly for manual/one-off alerts)
        final_html = raw_body || "Empty notification content.";
      }

      // Dispatch to Resend HTTP API
      const resendResponse = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${RESEND_API_KEY}`,
        },
        body: JSON.stringify({
          from: DEFAULT_EMAIL_FROM,
          to: [recipient],
          subject: final_subject,
          html: final_html,
        }),
      });

      delivery_result = await resendResponse.json();
      
      if (!resendResponse.ok) {
        throw new Error(`Resend API Error: ${JSON.stringify(delivery_result)}`);
      }
    }

    // --- CHANNEL: PUSH (via FCM Placeholder) ---
    else if (channel === 'push') {
       // Future implementation for FCM Push tokens
       delivery_result = { id: `push_${Date.now()}`, status: "pending_fcm" };
       console.log(`Push enqueued for device token: ${recipient}`);
    }

    // Update the queue record status and log the provider response to the new 'info' column
    await supabase
      .from('delivery_queue')
      .update({ 
        status: 'sent', 
        processed_at: new Date().toISOString(),
        info: { 
          ...info, 
          delivery_id: delivery_result.id || null, 
          provider: channel === 'email' ? 'resend' : 'system_push' 
        }
      })
      .eq('id', queue_id);

    return new Response(JSON.stringify({ success: true, delivery_id: delivery_result.id }), { status: 200 });

  } catch (err) {
    console.error("DISPATCH ERROR:", err);
    
    // We log the failure back to the database for visibility
    // But we don't update with 'sent' so it could technically be retried
    return new Response(JSON.stringify({ error: err.message }), { status: 500 });
  }
});
