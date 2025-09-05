import { onCall, onRequest } from "firebase-functions/v2/https";
import Stripe from "stripe";

// La clé est injectée depuis .env par Firebase (tu as "Loaded env from .env" au déploiement)
const STRIPE_SECRET_KEY = process.env.STRIPE_SECRET_KEY;
if (!STRIPE_SECRET_KEY) {
  throw new Error("Missing STRIPE_SECRET_KEY in environment.");
}

// Instanciation Stripe (sans apiVersion => évite les conflits de types)
const stripe = new Stripe(STRIPE_SECRET_KEY);

/**
 * ✅ Crée un PaymentIntent (mobile / PaymentSheet) OU une Checkout Session (web).
 * Attend un montant en CENTIMES (integer) côté client.
 */
export const createPaymentIntent = onCall(
  { region: "europe-west1" },
  async (request) => {
    try {
      const {
        amount,               // int en centimes
        currency = "eur",
        from,
        to,
        vehicle,
        distance,
        baseUrl,              // présent uniquement sur web
        timestamp,            // ISO string (heure de départ prévue) – envoyé par le client web
      } = request.data ?? {};

      if (!request.auth) throw new Error("User must be authenticated.");

      const amountCents = Number(amount);
      if (!Number.isInteger(amountCents) || amountCents <= 0) {
        throw new Error(
          "Invalid 'amount': expected a positive integer in cents."
        );
      }

      const isWeb = typeof baseUrl === "string" && baseUrl.length > 0;

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
      const finalBaseUrl =
        typeof baseUrl === "string" && baseUrl.length > 0
          ? baseUrl
          : "https://ride-my-way.com";

      const clientTimestamp =
        typeof timestamp === "string" && timestamp.length > 0
          ? timestamp
          : new Date().toISOString(); // fallback (dev)

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
  }
);

/**
 * ✅ Vérifie l'état d'un PaymentIntent
 * GET /verifyPaymentIntent?pi=pi_xxx
 * OU  /verifyPaymentIntent?session_id=cs_xxx
 */
export const verifyPaymentIntent = onRequest(
  { region: "europe-west1" },
  async (req, res): Promise<void> => {
    // CORS simple
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "GET, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }

    try {
      if (req.method !== "GET") {
        res.status(405).json({ error: "Method not allowed" });
        return;
      }

      const pi = (req.query.pi as string | undefined) ?? undefined;
      const sessionId =
        (req.query.session_id as string | undefined) ?? undefined;

      if (!pi && !sessionId) {
        res
          .status(400)
          .json({ error: "Missing 'pi' or 'session_id' query parameter" });
        return;
      }

      let paymentIntent: Stripe.PaymentIntent;
      if (pi) {
        paymentIntent = await stripe.paymentIntents.retrieve(pi);
      } else {
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
        paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId);
      }

      res.json({
        id: paymentIntent.id,
        status: paymentIntent.status, // ex: 'requires_capture' après autorisation
        amount: paymentIntent.amount,
        currency: paymentIntent.currency,
        capture_method: paymentIntent.capture_method,
        metadata: paymentIntent.metadata,
      });
      return;
    } catch (err: any) {
      console.error("❌ verifyPaymentIntent error:", err);
      res.status(500).json({ error: err?.message ?? "Internal error" });
      return;
    }
  }
);

/**
 * ✅ Capture un paiement autorisé (requires_capture)
 * GET /capturePaymentIntent?pi=pi_xxx
 */
export const capturePaymentIntent = onRequest(
  { region: "europe-west1" },
  async (req, res): Promise<void> => {
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "GET, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }

    try {
      const pi = req.query.pi as string | undefined;
      if (!pi) {
        res.status(400).json({ error: "Missing 'pi' query parameter" });
        return;
      }

      const paymentIntent = await stripe.paymentIntents.retrieve(pi);
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
        status: captured.status, // 'succeeded'
        amount: captured.amount,
        currency: captured.currency,
      });
      return;
    } catch (err: any) {
      console.error("❌ capturePaymentIntent error:", err);
      res
        .status(500)
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
  { region: "europe-west1" },
  async (req, res): Promise<void> => {
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "GET, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }

    try {
      const pi = req.query.pi as string | undefined;
      if (!pi) {
        res.status(400).json({ error: "Missing 'pi' query parameter" });
        return;
      }

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
        status: canceled.status, // 'canceled'
        amount: canceled.amount,
        currency: canceled.currency,
      });
      return;
    } catch (err: any) {
      console.error("❌ cancelPaymentIntent error:", err);
      res
        .status(500)
        .json({ error: err?.message ?? "Internal error canceling PaymentIntent" });
      return;
    }
  }
);
