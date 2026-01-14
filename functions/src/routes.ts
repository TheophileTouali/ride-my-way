import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as functions from "firebase-functions";

type LatLng = { lat: number; lng: number };

export const getRouteInfo = onCall(
  { region: "europe-west1" },
  async (request) => {
    const { origin, destination } = request.data as {
      origin?: LatLng;
      destination?: LatLng;
    };

    if (!origin || !destination) {
      throw new HttpsError("invalid-argument", "origin et destination requis");
    }

    const apiKey =
      process.env.GOOGLE_MAPS_KEY || functions.config().google?.maps_key;

    if (!apiKey) {
      throw new HttpsError(
        "failed-precondition",
        "Clé Google Maps manquante côté serveur"
      );
    }

    // ✅ “Réel” = trafic maintenant + modèle best_guess
    // ✅ alternatives=true -> on récupère plusieurs routes comme Maps
    const url =
      "https://maps.googleapis.com/maps/api/directions/json" +
      `?origin=${origin.lat},${origin.lng}` +
      `&destination=${destination.lat},${destination.lng}` +
      `&mode=driving` +
      `&departure_time=now` +
      `&traffic_model=best_guess` +
      `&alternatives=true` +
      `&key=${apiKey}`;

    const res = await fetch(url);
    const json: any = await res.json();

    if (json.status !== "OK") {
      throw new HttpsError(
        "failed-precondition",
        `Directions error: ${json.status} - ${json.error_message || ""}`
      );
    }

    const routes = json.routes as any[];
    if (!routes?.length) {
      throw new HttpsError("failed-precondition", "Aucune route retournée");
    }

    // ✅ Choix de l’itinéraire “le plus rapide en trafic”
    // (comme fait souvent Maps quand trafic activé)
    let best = routes[0];
    let bestSeconds =
      Number(best.legs?.[0]?.duration_in_traffic?.value) ||
      Number(best.legs?.[0]?.duration?.value) ||
      Number.MAX_SAFE_INTEGER;

    for (const r of routes) {
      const leg = r.legs?.[0];
      const s =
        Number(leg?.duration_in_traffic?.value) ||
        Number(leg?.duration?.value) ||
        Number.MAX_SAFE_INTEGER;

      if (s < bestSeconds) {
        best = r;
        bestSeconds = s;
      }
    }

    const leg = best.legs[0];

    const meters = Number(leg.distance.value);
    const durationTraffic =
      Number(leg.duration_in_traffic?.value) || Number(leg.duration.value);

    return {
      distanceKm: Math.round((meters / 1000) * 100) / 100,
      durationSeconds: durationTraffic,
      // debug utile si tu veux afficher/sonder
      routeSummary: best.summary || "",
    };
  }
);
