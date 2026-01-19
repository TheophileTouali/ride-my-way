import { HttpsError, onCall } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { assertSuperAdmin } from "./admin_guard";

const kPlatformCommissionRate = 0.40;
const kDriverNetRate = 1.0 - kPlatformCommissionRate; // 0.60
const kTZ = "Europe/Paris";

function toNumber(v: any): number {
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) ? n : 0;
}

function pad2(n: number) {
  return String(n).padStart(2, "0");
}

// force date en timezone Paris
function toParisDate(ts: Timestamp) {
  return new Date(ts.toDate().toLocaleString("en-US", { timeZone: kTZ }));
}

function ymd(d: Date) {
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
}
function ym(d: Date) {
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}`;
}

function fortnightKey(d: Date) {
  const half = d.getDate() <= 15 ? 1 : 2;
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${half}`;
}

function fortnightRangeLabel(d: Date) {
  const y = d.getFullYear();
  const m = d.getMonth();
  const month = pad2(m + 1);

  const lastDay = new Date(y, m + 1, 0).getDate();
  if (d.getDate() <= 15) return `01-${month}-${y} → 15-${month}-${y}`;
  return `16-${month}-${y} → ${pad2(lastDay)}-${month}-${y}`;
}

function startOfDay(date: Date) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate(), 0, 0, 0, 0);
}
function endOfDay(date: Date) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate(), 23, 59, 59, 999);
}

/**
 * ✅ ADMIN DASHBOARD STATS — VERSION PRÊTE À L’EMPLOI
 * Corrections clés:
 * - doneQuery supporte completedAt ET fallback endTime (ton LiveTracking écrit endTime)
 * - completedAt dans l’agrégat = completedAt ?? endTime
 * - gross supporte amountReceived (cents) si price absent
 * - doneReservations cohérent avec doneSnap final (après fallback)
 */
export const adminGetDashboardStats = onCall(
  { region: "europe-west1" },
  async (request) => {
    try {
      assertSuperAdmin(request);

      const db = getFirestore();

      // ─────────────────────────────────────────────────────────────
      // INPUTS
      // ─────────────────────────────────────────────────────────────
      const days = toNumber(request.data?.days ?? 180);
      const now = new Date();

      const driverIdIn = String(request.data?.driverId ?? "").trim();
      const hasDriverFilter = driverIdIn.length > 0;

      let fromDate: Date;
      let toDate: Date;

      const fromIn = request.data?.from;
      const toIn = request.data?.to;

      if (fromIn && toIn) {
        fromDate = new Date(fromIn);
        toDate = new Date(toIn);
      } else {
        toDate = now;
        fromDate = new Date(now);
        fromDate.setDate(fromDate.getDate() - days);
      }

      fromDate = startOfDay(fromDate);
      toDate = endOfDay(toDate);

      const fromTs = Timestamp.fromDate(fromDate);
      const toTs = Timestamp.fromDate(toDate);

      // ─────────────────────────────────────────────────────────────
      // 1) Totaux base
      // ─────────────────────────────────────────────────────────────
      const [driversSnap, usersSnap] = await Promise.all([
        db.collection("drivers").get(),
        db.collection("users").get(),
      ]);

      const feedbacksQuery = hasDriverFilter
        ? db.collection("feedbacks").where("driverId", "==", driverIdIn)
        : db.collection("feedbacks");

      const feedbacksSnap = await feedbacksQuery.get();

      // ─────────────────────────────────────────────────────────────
      // 2) Réservations sur la période (totals.reservations + status + users uniques)
      // ⚠️ createdAt doit être un Timestamp (serverTimestamp) : OK chez toi
      // ─────────────────────────────────────────────────────────────
      let periodReservationsQuery: FirebaseFirestore.Query = db
        .collection("reservations")
        .where("createdAt", ">=", fromTs)
        .where("createdAt", "<=", toTs);

      if (hasDriverFilter) {
        periodReservationsQuery = periodReservationsQuery.where("driverId", "==", driverIdIn);
      }

      const periodReservationsSnap = await periodReservationsQuery.get();

      const statuses: Record<string, string> = {
        pending: "En attente",
        confirmed: "Confirmée",
        enRoute: "En route",
        pret: "Prêt",
        enCours: "En cours",
        terminee: "Terminée",
      };

      const reservationsByStatus: Record<string, number> = Object.fromEntries(
        Object.keys(statuses).map((k) => [k, 0])
      );

      const uniqueUsers = new Set<string>();

      periodReservationsSnap.forEach((doc) => {
        const r = doc.data() as Record<string, any>;
        const st = String(r.status ?? "").trim();

        for (const [k, label] of Object.entries(statuses)) {
          if (st === label) {
            reservationsByStatus[k] = (reservationsByStatus[k] ?? 0) + 1;
            break;
          }
        }

        const uid = String(r.userId ?? r.passengerId ?? r.clientId ?? "").trim();
        if (uid) uniqueUsers.add(uid);
      });

      // ─────────────────────────────────────────────────────────────
      // 3) driversByVerification
      // ─────────────────────────────────────────────────────────────
      const driversByVerification: Record<string, number> = {
        verified: 0,
        pending: 0,
        rejected: 0,
      };

      if (hasDriverFilter) {
        const d = await db.collection("drivers").doc(driverIdIn).get();
        const data = d.exists ? (d.data() as any) : {};
        const v = String(
          data.verificationStatus ??
            data.kycStatus ??
            (data.isVerified === true ? "verified" : "pending") ??
            "pending"
        ).toLowerCase();

        if (v.includes("reject")) driversByVerification.rejected = 1;
        else if (v.includes("verif") || v === "verified") driversByVerification.verified = 1;
        else driversByVerification.pending = 1;
      } else {
        driversSnap.forEach((doc) => {
          const d = doc.data() as any;
          const v = String(
            d.verificationStatus ??
              d.kycStatus ??
              (d.isVerified === true ? "verified" : "pending") ??
              "pending"
          ).toLowerCase();

          if (v.includes("reject")) driversByVerification.rejected += 1;
          else if (v.includes("verif") || v === "verified") driversByVerification.verified += 1;
          else driversByVerification.pending += 1;
        });
      }

      // ─────────────────────────────────────────────────────────────
      // 4) Courses terminées (completedAt OU fallback endTime)
      // ─────────────────────────────────────────────────────────────
      let doneSnap: FirebaseFirestore.QuerySnapshot;

      // Primary: completedAt
      let doneQuery: FirebaseFirestore.Query = db
        .collection("reservations")
        .where("status", "==", "Terminée")
        .where("completedAt", ">=", fromTs)
        .where("completedAt", "<=", toTs);

      if (hasDriverFilter) doneQuery = doneQuery.where("driverId", "==", driverIdIn);
      doneQuery = doneQuery.orderBy("completedAt", "asc");

      doneSnap = await doneQuery.get();

      // Fallback: endTime (car ton LiveTracking écrit endTime)
      if (doneSnap.empty) {
        let doneEndQuery: FirebaseFirestore.Query = db
          .collection("reservations")
          .where("status", "==", "Terminée")
          .where("endTime", ">=", fromTs)
          .where("endTime", "<=", toTs);

        if (hasDriverFilter) doneEndQuery = doneEndQuery.where("driverId", "==", driverIdIn);
        doneEndQuery = doneEndQuery.orderBy("endTime", "asc");

        doneSnap = await doneEndQuery.get();
      }

      // ─────────────────────────────────────────────────────────────
      // 5) Aggregations business (sur courses terminées)
      // ─────────────────────────────────────────────────────────────
      const byHour: Record<string, any> = {};
      const byDay: Record<string, any> = {};
      const byMonth: Record<string, any> = {};
      const byFortnight: Record<string, any> = {};
      const byDriver: Record<string, any> = {};

      for (let h = 0; h < 24; h++) {
        byHour[String(h)] = { rides: 0, gross: 0, driverNet: 0, platform: 0 };
      }

      function ensureDay(key: string) {
        if (!byDay[key]) byDay[key] = { rides: 0, gross: 0, driverNet: 0, platform: 0 };
        return byDay[key];
      }
      function ensureMonth(key: string) {
        if (!byMonth[key]) byMonth[key] = { rides: 0, gross: 0, driverNet: 0, platform: 0 };
        return byMonth[key];
      }
      function ensureFortnight(key: string, label: string) {
        if (!byFortnight[key]) {
          byFortnight[key] = {
            key,
            label,
            rides: 0,
            gross: 0,
            driverNet: 0,
            platform: 0,
            payoutsByDriver: {},
          };
        }
        return byFortnight[key];
      }
      function ensureDriver(driverId: string) {
        if (!byDriver[driverId]) {
          byDriver[driverId] = {
            driverId,
            rides: 0,
            gross: 0,
            driverNet: 0,
            platform: 0,
            byMonth: {},
            byDay: {},
            byHour: {},
            fortnights: {},
          };
        }
        return byDriver[driverId];
      }
      function incBucket(bucket: any, gross: number) {
        const platform = gross * kPlatformCommissionRate;
        const driverNet = gross * kDriverNetRate;
        bucket.rides += 1;
        bucket.gross += gross;
        bucket.platform += platform;
        bucket.driverNet += driverNet;
      }

      doneSnap.forEach((doc) => {
        const data = doc.data() as Record<string, any>;

        // ✅ IMPORTANT : support des deux champs
        const completedAt = (data.completedAt ?? data.endTime) as Timestamp | undefined;
        if (!completedAt) return;

        const dt = toParisDate(completedAt);

        // ✅ prix tolérant
        let gross = toNumber(data.price ?? data.amount ?? data.fare);
        if (!gross && data.amountReceived) {
          const cents = toNumber(data.amountReceived);
          gross = cents > 0 ? cents / 100 : 0;
        }
        if (gross <= 0) return;

        const driverId = String(data.driverId ?? "").trim();
        if (!driverId) return;

        const h = dt.getHours();
        const dayKey = ymd(dt);
        const monthKey = ym(dt);
        const fKey = fortnightKey(dt);
        const fLabel = fortnightRangeLabel(dt);

        incBucket(byHour[String(h)], gross);
        incBucket(ensureDay(dayKey), gross);
        incBucket(ensureMonth(monthKey), gross);

        const f = ensureFortnight(fKey, fLabel);
        incBucket(f, gross);

        if (!f.payoutsByDriver[driverId]) {
          f.payoutsByDriver[driverId] = { rides: 0, gross: 0, driverNet: 0, platform: 0 };
        }
        incBucket(f.payoutsByDriver[driverId], gross);

        const dr = ensureDriver(driverId);
        incBucket(dr, gross);

        if (!dr.byMonth[monthKey]) dr.byMonth[monthKey] = { rides: 0, gross: 0, driverNet: 0, platform: 0 };
        if (!dr.byDay[dayKey]) dr.byDay[dayKey] = { rides: 0, gross: 0, driverNet: 0, platform: 0 };
        if (!dr.byHour[String(h)]) dr.byHour[String(h)] = { rides: 0, gross: 0, driverNet: 0, platform: 0 };
        if (!dr.fortnights[fKey]) dr.fortnights[fKey] = { key: fKey, label: fLabel, rides: 0, gross: 0, driverNet: 0, platform: 0 };

        incBucket(dr.byMonth[monthKey], gross);
        incBucket(dr.byDay[dayKey], gross);
        incBucket(dr.byHour[String(h)], gross);
        incBucket(dr.fortnights[fKey], gross);
      });

      // ─────────────────────────────────────────────────────────────
      // 6) Maps -> Arrays triés
      // ─────────────────────────────────────────────────────────────
      const byDayArr = Object.entries(byDay)
        .map(([key, v]) => ({ key, ...v }))
        .sort((a, b) => a.key.localeCompare(b.key));

      const byMonthArr = Object.entries(byMonth)
        .map(([key, v]) => ({ key, ...v }))
        .sort((a, b) => a.key.localeCompare(b.key));

      const byHourArr = Object.entries(byHour)
        .map(([key, v]) => ({ hour: Number(key), ...v }))
        .sort((a, b) => a.hour - b.hour);

      const fortnightsArr = Object.values(byFortnight)
        .map((f: any) => {
          const payouts = Object.entries(f.payoutsByDriver || {})
            .map(([driverId, pv]: any) => ({ driverId, ...pv }))
            .sort((a, b) => (b.driverNet ?? 0) - (a.driverNet ?? 0));

          return {
            key: f.key,
            label: f.label,
            rides: f.rides,
            gross: f.gross,
            driverNet: f.driverNet,
            platform: f.platform,
            payouts,
          };
        })
        .sort((a: any, b: any) => a.key.localeCompare(b.key));

      const byDriverArr = Object.values(byDriver)
        .map((d: any) => ({
          ...d,
          byMonth: Object.entries(d.byMonth)
            .map(([key, v]: any) => ({ key, ...v }))
            .sort((a, b) => a.key.localeCompare(b.key)),
          byDay: Object.entries(d.byDay)
            .map(([key, v]: any) => ({ key, ...v }))
            .sort((a, b) => a.key.localeCompare(b.key)),
          byHour: Object.entries(d.byHour)
            .map(([k, v]: any) => ({ hour: Number(k), ...v }))
            .sort((a, b) => a.hour - b.hour),
          fortnights: Object.entries(d.fortnights)
            .map(([key, v]: any) => ({ key, ...v }))
            .sort((a, b) => a.key.localeCompare(b.key)),
        }))
        .sort((a: any, b: any) => (b.driverNet ?? 0) - (a.driverNet ?? 0));

      // ─────────────────────────────────────────────────────────────
      // 7) Totaux COHÉRENTS
      // ─────────────────────────────────────────────────────────────
      const totals = {
        drivers: hasDriverFilter ? 1 : driversSnap.size,
        users: hasDriverFilter ? uniqueUsers.size : usersSnap.size,
        reservations: periodReservationsSnap.size,
        feedbacks: feedbacksSnap.size,
        doneReservations: doneSnap.size, // ✅ après fallback
      };

      // ─────────────────────────────────────────────────────────────
      // 8) Retour
      // ─────────────────────────────────────────────────────────────
      return {
        period: {
          from: fromDate.toISOString(),
          to: toDate.toISOString(),
          days,
          timezone: kTZ,
        },
        filter: {
          driverId: hasDriverFilter ? driverIdIn : null,
        },
        totals,
        reservationsByStatus,
        driversByVerification,
        series: {
          byHour: byHourArr,
          byDay: byDayArr,
          byMonth: byMonthArr,
        },
        fortnights: fortnightsArr,
        byDriver: byDriverArr,
        rates: {
          platform: kPlatformCommissionRate,
          driverNet: kDriverNetRate,
        },
        generatedAt: Date.now(),
      };
    } catch (e: any) {
      console.error("adminGetDashboardStats error:", e);

      if (e instanceof HttpsError) throw e;

      const msg = String(e?.message ?? e);

      if (msg.includes("requires an index") || msg.includes("FAILED_PRECONDITION") || e?.code === 9) {
        throw new HttpsError(
          "failed-precondition",
          "Index Firestore manquant pour cette requête. Crée l’index composite demandé (reservations).",
          { raw: msg }
        );
      }

      throw new HttpsError(
        "internal",
        "Erreur interne lors du calcul des statistiques admin.",
        { raw: msg }
      );
    }
  }
);
