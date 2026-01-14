import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { assertSuperAdmin } from "./admin_guard";

export const adminGetDashboardStats = onCall(
  { region: "europe-west1" },
  async (request) => {
    assertSuperAdmin(request);

    const db = getFirestore();

    // ⚠️ On fait simple et robuste : compter par requêtes.
    // (Optimisation possible ensuite via collectionGroup / counters)
    const [driversSnap, usersSnap, reservationsSnap, feedbacksSnap] =
      await Promise.all([
        db.collection("drivers").get(),
        db.collection("users").get(),
        db.collection("reservations").get(),
        db.collection("feedbacks").get(),
      ]);

    const drivers = driversSnap.size;
    const users = usersSnap.size;
    const reservations = reservationsSnap.size;
    const feedbacks = feedbacksSnap.size;

    // Statuts (basés sur tes rules actuelles)
    let pending = 0,
      confirmed = 0,
      enRoute = 0,
      pret = 0,
      enCours = 0,
      terminee = 0;

    reservationsSnap.forEach((d) => {
      const s = String(d.get("status") ?? "");
      if (s === "En attente") pending++;
      else if (s === "Confirmée") confirmed++;
      else if (s === "En route") enRoute++;
      else if (s === "Prêt") pret++;
      else if (s === "En cours") enCours++;
      else if (s === "Terminée") terminee++;
    });

    // KYC drivers
    let verified = 0,
      pendingKyc = 0,
      rejected = 0;

    driversSnap.forEach((d) => {
      const vs = String(d.get("verificationStatus") ?? "");
      if (vs === "verified") verified++;
      else if (vs === "pending") pendingKyc++;
      else if (vs === "rejected") rejected++;
    });

    return {
      totals: { drivers, users, reservations, feedbacks },
      reservationsByStatus: {
        pending,
        confirmed,
        enRoute,
        pret,
        enCours,
        terminee,
      },
      driversByVerification: {
        verified,
        pending: pendingKyc,
        rejected,
      },
      generatedAt: Date.now(),
    };
  }
);
