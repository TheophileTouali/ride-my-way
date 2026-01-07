import { onCall, onRequest } from "firebase-functions/v2/https";
import Stripe from "stripe";

// --- ENV ---
const STRIPE_SECRET_KEY = process.env.STRIPE_SECRET_KEY;
if (!STRIPE_SECRET_KEY) {
  throw new Error("Missing STRIPE_SECRET_KEY in environment.");
}

// Domaine prod (ex: https://www.ridemyway.net) – injecté via functions/.env
const WEB_BASE_URL_ENV = process.env.WEB_BASE_URL;

// --- Stripe (timeout pour éviter des requêtes qui pendent) ---
const stripe = new Stripe(STRIPE_SECRET_KEY, {
  // pas d'apiVersion forcée => évite conflits de types
  timeout: 20000, // 20s
});

// ---------------- Helpers (robustesse sans régression) ----------------
const REGION = "europe-west1";

function setCors(res: any) {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "GET, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
}

function normalizeBaseUrl(url?: string): string | undefined {
  if (typeof url !== "string") return undefined;
  const trimmed = url.trim();
  if (!trimmed) return undefined;
  return trimmed.replace(/\/+$/, ""); // supprime / finaux
}

function cleanId(value: unknown): string | undefined {
  const v = Array.isArray(value) ? value[0] : value;
  if (typeof v !== "string") return undefined;
  const cleaned = v.trim().replace(/['"]/g, ""); // enlève ' et "
  return cleaned.length ? cleaned : undefined;
}

function stripeStatusCode(err: any): number {
  // StripeError expose parfois statusCode
  if (err && typeof err.statusCode === "number") return err.statusCode;
  return 500;
}

/**
 * ✅ Crée un PaymentIntent (mobile / PaymentSheet) OU une Checkout Session (web).
 * Attend un montant en CENTIMES (integer) côté client.
 */
export const createPaymentIntent = onCall({ region: REGION }, async (request) => {
  try {
    const {
      amount, // int en centimes
      currency = "eur",
      from,
      to,
      vehicle,
      distance,
      baseUrl, // présent uniquement sur web
      timestamp, // ISO string (heure de départ prévue) – envoyé par le client web
    } = request.data ?? {};

    if (!request.auth) throw new Error("User must be authenticated.");

    const amountCents = Number(amount);
    if (!Number.isInteger(amountCents) || amountCents <= 0) {
      throw new Error("Invalid 'amount': expected a positive integer in cents.");
    }

    const isWeb = typeof baseUrl === "string" && baseUrl.trim().length > 0;

    // ======== MOBILE (PaymentSheet): pré-autorisation (capture manuelle)
    if (!isWeb) {
      const pi = await stripe.paymentIntents.create({
        amount: amountCents,
        currency,
        capture_method: "manual",
        automatic_payment_methods: { enabled: true },
        metadata: {
          userId: String(request.auth.uid),
          from: String(from ?? ""),
          to: String(to ?? ""),
          vehicle: String(vehicle ?? ""),
          distance: String(distance ?? ""),
          platform: "mobile",
        },
      });

      return {
        clientSecret: pi.client_secret,
        paymentIntentId: pi.id,
      };
    }

    // ======== WEB (Checkout): pré-autorisation (capture manuelle)
    // 1) on privilégie baseUrl côté client (si fournie)
    // 2) sinon on prend WEB_BASE_URL du .env
    // 3) sinon fallback dernier recours (prod)
    const DEFAULT_WEB_BASE_URL =
      normalizeBaseUrl(WEB_BASE_URL_ENV) || "https://www.ridemyway.net";

    const finalBaseUrl =
      normalizeBaseUrl(String(baseUrl)) || DEFAULT_WEB_BASE_URL;

    const clientTimestamp =
      typeof timestamp === "string" && timestamp.length > 0
        ? timestamp
        : new Date().toISOString();

    console.log("[Stripe] createPaymentIntent web finalBaseUrl:", finalBaseUrl);

    const session = await stripe.checkout.sessions.create({
      mode: "payment",
      payment_method_types: ["card"],
      payment_intent_data: {
        capture_method: "manual",
        metadata: {
          userId: String(request.auth.uid),
          from: String(from ?? ""),
          to: String(to ?? ""),
          vehicle: String(vehicle ?? ""),
          distance: String(distance ?? ""),
          platform: "web",
        },
      },
      line_items: [
        {
          price_data: {
            currency,
            product_data: {
              name: "Réservation Ride My Way",
              description: `${String(from ?? "")} → ${String(to ?? "")}`,
            },
            unit_amount: amountCents,
          },
          quantity: 1,
        },
      ],
      success_url:
        `${finalBaseUrl}/#/payment-success?session_id={CHECKOUT_SESSION_ID}` +
        `&from=${encodeURIComponent(String(from ?? ""))}` +
        `&to=${encodeURIComponent(String(to ?? ""))}` +
        `&vehicle=${encodeURIComponent(String(vehicle ?? ""))}` +
        `&price=${amountCents / 100}` +
        `&distance=${encodeURIComponent(String(distance ?? ""))}` +
        `&timestamp=${encodeURIComponent(clientTimestamp)}`,
      cancel_url: `${finalBaseUrl}/#/payment-cancel`,
    });

    return {
      checkoutUrl: session.url,
      paymentIntentId:
        typeof session.payment_intent === "string"
          ? session.payment_intent
          : undefined,
    };
  } catch (err: any) {
    console.error("❌ createPaymentIntent error:", err);
    throw new Error(err?.message ?? "Internal error (Stripe/Functions).");
  }
});

/**
 * ✅ Vérifie l'état d'un PaymentIntent
 * GET /verifyPaymentIntent?pi=pi_xxx
 * OU  /verifyPaymentIntent?session_id=cs_xxx
 */
export const verifyPaymentIntent = onRequest(
  { region: REGION },
  async (req, res): Promise<void> => {
    setCors(res);
    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }

    try {
      if (req.method !== "GET") {
        res.status(405).json({ error: "Method not allowed" });
        return;
      }

      const pi = cleanId(req.query.pi);
      const sessionId = cleanId(req.query.session_id);

      if (!pi && !sessionId) {
        res
          .status(400)
          .json({ error: "Missing 'pi' or 'session_id' query parameter" });
        return;
      }

      let paymentIntent: Stripe.PaymentIntent;

      if (pi) {
        console.log("[Stripe] verify PI:", pi);
        paymentIntent = await stripe.paymentIntents.retrieve(pi);
      } else {
        console.log("[Stripe] verify session:", sessionId);
        const session = await stripe.checkout.sessions.retrieve(sessionId!);
        const paymentIntentId =
          typeof session.payment_intent === "string"
            ? session.payment_intent
            : (session.payment_intent as Stripe.PaymentIntent | null)?.id;

        if (!paymentIntentId) {
          res
            .status(404)
            .json({ error: "No payment_intent found on session" });
          return;
        }

        console.log("[Stripe] verify PI from session:", paymentIntentId);
        paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId);
      }

      res.json({
        id: paymentIntent.id,
        status: paymentIntent.status,
        amount: paymentIntent.amount,
        currency: paymentIntent.currency,
        capture_method: paymentIntent.capture_method,
        metadata: paymentIntent.metadata,
      });
      return;
    } catch (err: any) {
      console.error("❌ verifyPaymentIntent error:", err);
      res.status(stripeStatusCode(err)).json({ error: err?.message ?? "Internal error" });
      return;
    }
  }
);

/**
 * ✅ Capture un paiement autorisé (requires_capture)
 * GET /capturePaymentIntent?pi=pi_xxx
 */
export const capturePaymentIntent = onRequest(
  { region: REGION },
  async (req, res): Promise<void> => {
    setCors(res);
    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }

    try {
      if (req.method !== "GET") {
        res.status(405).json({ error: "Method not allowed" });
        return;
      }

      const pi = cleanId(req.query.pi);
      if (!pi) {
        res.status(400).json({ error: "Missing 'pi' query parameter" });
        return;
      }

      console.log("[Stripe] capture PI:", pi);

      const paymentIntent = await stripe.paymentIntents.retrieve(pi);

      // Robustesse: assure qu'on est en manual capture
      if (paymentIntent.capture_method !== "manual") {
        res.status(400).json({ error: "PaymentIntent is not manual capture" });
        return;
      }

      // Robustesse: double appel (déjà capturé)
      if (paymentIntent.status === "succeeded" || (paymentIntent.amount_received ?? 0) > 0) {
        res.status(409).json({
          error: "Payment already captured",
          currentStatus: paymentIntent.status,
        });
        return;
      }

      if (paymentIntent.status !== "requires_capture") {
        res.status(400).json({
          error: `Invalid status: ${paymentIntent.status}`,
          currentStatus: paymentIntent.status,
        });
        return;
      }

      const captured = await stripe.paymentIntents.capture(pi);
      res.json({
        id: captured.id,
        status: captured.status,
        amount: captured.amount,
        currency: captured.currency,
      });
      return;
    } catch (err: any) {
      console.error("❌ capturePaymentIntent error:", err);
      res
        .status(stripeStatusCode(err))
        .json({ error: err?.message ?? "Internal error capturing PaymentIntent" });
      return;
    }
  }
);

/**
 * ❌ Annule une pré-autorisation (avant capture)
 * GET /cancelPaymentIntent?pi=pi_xxx
 */
export const cancelPaymentIntent = onRequest(
  { region: REGION },
  async (req, res): Promise<void> => {
    setCors(res);
    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }

    try {
      if (req.method !== "GET") {
        res.status(405).json({ error: "Method not allowed" });
        return;
      }

      const pi = cleanId(req.query.pi);
      if (!pi) {
        res.status(400).json({ error: "Missing 'pi' query parameter" });
        return;
      }

      console.log("[Stripe] cancel PI:", pi);

      const paymentIntent = await stripe.paymentIntents.retrieve(pi);

      if (
        paymentIntent.status !== "requires_capture" &&
        paymentIntent.status !== "requires_payment_method"
      ) {
        res.status(400).json({
          error: `Cannot cancel: current status = ${paymentIntent.status}`,
        });
        return;
      }

      const canceled = await stripe.paymentIntents.cancel(pi);
      res.json({
        id: canceled.id,
        status: canceled.status,
        amount: canceled.amount,
        currency: canceled.currency,
      });
      return;
    } catch (err: any) {
      console.error("❌ cancelPaymentIntent error:", err);
      res
        .status(stripeStatusCode(err))
        .json({ error: err?.message ?? "Internal error canceling PaymentIntent" });
      return;
    }
  }
);
