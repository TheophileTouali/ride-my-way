import * as admin from "firebase-admin";
import { onDocumentUpdated } from "firebase-functions/v2/firestore";

// ─────────────────────────────────────────────────────────────
// Business constants
// ─────────────────────────────────────────────────────────────
const PLATFORM_COMMISSION_RATE = 0.40;
const DRIVER_NET_RATE = 1.0 - PLATFORM_COMMISSION_RATE; // 0.60
const TIMEZONE = "Europe/Paris";
const REGION = "europe-west1";

// ─────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────
function toCents(value: unknown): number {
  const n = Number(value ?? 0);
  if (!Number.isFinite(n)) return 0;
  return Math.round(n * 100);
}

function pickGrossField(data: Record<string, any>): number {
  if (data.price != null) return Number(data.price) || 0;
  if (data.amount != null) return Number(data.amount) || 0;
  if (data.fare != null) return Number(data.fare) || 0;
  return 0;
}

function isJustCompleted(before: Record<string, any>, after: Record<string, any>) {
  const b = String(before.status ?? "");
  const a = String(after.status ?? "");
  return b !== "Terminée" && a === "Terminée";
}

function timeKeysFromDate(date: Date) {
  const fmt = (opt: Intl.DateTimeFormatOptions) =>
    new Intl.DateTimeFormat("fr-FR", { timeZone: TIMEZONE, ...opt }).format(date);

  const yyyy = fmt({ year: "numeric" });
  const mm = fmt({ month: "2-digit" });
  const dd = fmt({ day: "2-digit" });
  const HH = fmt({ hour: "2-digit", hourCycle: "h23" });

  const dayKey = `${yyyy}-${mm}-${dd}`;        // 2026-01-16
  const monthKey = `${yyyy}-${mm}`;            // 2026-01
  const hourKey = `${yyyy}-${mm}-${dd} ${HH}`; // 2026-01-16 13

  const dayNum = Number(dd);
  const half = dayNum <= 15 ? "H1" : "H2";
  const payoutKey = `${yyyy}-${mm}-${half}`;   // 2026-01-H2

  return { dayKey, monthKey, hourKey, payoutKey };
}

// ─────────────────────────────────────────────────────────────
// TRIGGER: reservations/{id} -> status Terminée + completedAt
// ─────────────────────────────────────────────────────────────
export const onReservationCompleted = onDocumentUpdated(
  {
    document: "reservations/{reservationId}",
    region: REGION,
  },
  async (event) => {
    const before = (event.data?.before.data() as Record<string, any>) ?? {};
    const after = (event.data?.after.data() as Record<string, any>) ?? {};
    const reservationId = event.params.reservationId;

    // 1) uniquement transition vers Terminée
    if (!isJustCompleted(before, after)) return;

    // 2) guard driverId + completedAt
    const driverId = String(after.driverId ?? "").trim();
    if (!driverId) {
      console.warn(`[${reservationId}] Terminée mais driverId manquant -> skip.`);
      return;
    }

    const completedAt = after.completedAt;
    if (!completedAt || typeof completedAt.toDate !== "function") {
      console.warn(`[${reservationId}] Terminée mais completedAt absent/invalide -> skip.`);
      return;
    }

    // 3) idempotence
    if (after.statsApplied === true) {
      console.log(`[${reservationId}] stats déjà appliquées -> skip.`);
      return;
    }

    const completedDate = completedAt.toDate() as Date;
    const { dayKey, monthKey, hourKey, payoutKey } = timeKeysFromDate(completedDate);

    // 4) Montants (cents)
    const gross = pickGrossField(after);
    const grossCents = toCents(gross);

    const driverNetCents = Math.round(grossCents * DRIVER_NET_RATE);
    const platformCents = grossCents - driverNetCents;

    const db = admin.firestore();
    const inc = admin.firestore.FieldValue.increment;
    const serverTs = admin.firestore.FieldValue.serverTimestamp;

    const reservationRef = event.data!.after.ref;

    const driverStatsRef = db.collection("driver_stats").doc(driverId);
    const byHourRef = driverStatsRef.collection("byHour").doc(hourKey);
    const byDayRef = driverStatsRef.collection("byDay").doc(dayKey);
    const byMonthRef = driverStatsRef.collection("byMonth").doc(monthKey);

    const payoutRef = db
      .collection("driver_payouts")
      .doc(driverId)
      .collection("periods")
      .doc(payoutKey);

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(reservationRef);
      const fresh = (snap.data() as Record<string, any>) ?? {};

      if (fresh.statsApplied === true) return;

      // enrich reservation
      tx.set(
        reservationRef,
        {
          grossCents,
          driverNetCents,
          platformCents,
          timeKeys: { dayKey, monthKey, hourKey, payoutKey },
          statsApplied: true,
          statsAppliedAt: serverTs(),
        },
        { merge: true }
      );

      // global driver stats
      tx.set(
        driverStatsRef,
        {
          driverId,
          totalGrossCents: inc(grossCents),
          totalDriverNetCents: inc(driverNetCents),
          totalPlatformCents: inc(platformCents),
          ridesCompleted: inc(1),
          updatedAt: serverTs(),
        },
        { merge: true }
      );

      // by hour
      tx.set(
        byHourRef,
        {
          driverId,
          key: hourKey,
          grossCents: inc(grossCents),
          driverNetCents: inc(driverNetCents),
          platformCents: inc(platformCents),
          ridesCompleted: inc(1),
          updatedAt: serverTs(),
        },
        { merge: true }
      );

      // by day
      tx.set(
        byDayRef,
        {
          driverId,
          key: dayKey,
          grossCents: inc(grossCents),
          driverNetCents: inc(driverNetCents),
          platformCents: inc(platformCents),
          ridesCompleted: inc(1),
          updatedAt: serverTs(),
        },
        { merge: true }
      );

      // by month
      tx.set(
        byMonthRef,
        {
          driverId,
          key: monthKey,
          grossCents: inc(grossCents),
          driverNetCents: inc(driverNetCents),
          platformCents: inc(platformCents),
          ridesCompleted: inc(1),
          updatedAt: serverTs(),
        },
        { merge: true }
      );

      // payout quinzaine
      tx.set(
        payoutRef,
        {
          driverId,
          key: payoutKey,
          monthKey,
          grossCents: inc(grossCents),
          driverNetCents: inc(driverNetCents),
          platformCents: inc(platformCents),
          ridesCompleted: inc(1),
          status: fresh.payoutStatus ?? "pending",
          updatedAt: serverTs(),
        },
        { merge: true }
      );
    });

    console.log(
      `[${reservationId}] ✅ stats appliquées | gross=${grossCents}c net=${driverNetCents}c platform=${platformCents}c keys=${dayKey}/${hourKey}/${monthKey}/${payoutKey}`
    );
  }
);
