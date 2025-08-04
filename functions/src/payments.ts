import { onCall } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import Stripe from "stripe";

const stripeSecret = defineSecret("STRIPE_SECRET_KEY");

export const createPaymentIntent = onCall(
  { secrets: [stripeSecret] },
  async (request) => {
    const {
      amount,
      currency = "eur",
      from,
      to,
      vehicle,
      distance,
      baseUrl,
    } = request.data;
    const context = request.auth;

    console.log("🔎 App Check Info:", request.app); // indique mobile vs web si activé

    if (!context) throw new Error("User must be authenticated.");
    if (!amount) throw new Error("Amount is required.");

    const stripe = new Stripe(stripeSecret.value(), {
      apiVersion: "2025-06-30.basil" as Stripe.LatestApiVersion,
    });

    const stripeAmount = Math.round(amount * 100);

    // ✅ Détection automatique
    const isWeb = !request.app; // App Check manquant → souvent web
    console.log("🌐 Détection plateforme :", isWeb ? "WEB" : "MOBILE");

    if (!isWeb) {
      console.log("🚀 Création PaymentIntent (Mobile)");
      const paymentIntent = await stripe.paymentIntents.create({
        amount: stripeAmount,
        currency,
        payment_method_types: ["card"],
        capture_method: "manual",
        metadata: { userId: context.uid, from, to, vehicle, distance: distance.toString() },
      });
      return { clientSecret: paymentIntent.client_secret, paymentIntentId: paymentIntent.id };
    }

    console.log("🌐 Création Session Checkout (Web)");
    const finalBaseUrl = baseUrl || "https://ride-my-way.com";

    const session = await stripe.checkout.sessions.create({
      mode: "payment",
      payment_method_types: ["card"],
      line_items: [{
        price_data: { currency, product_data: { name: "Réservation Ride My Way" }, unit_amount: stripeAmount },
        quantity: 1,
      }],
      success_url: `${finalBaseUrl}/#/payment-success`,
      cancel_url: `${finalBaseUrl}/#/payment-cancel`,
      metadata: { userId: context.uid },
    });

    console.log("✅ Session Checkout créée:", session.id);
    return { checkoutUrl: session.url };
  }
);
