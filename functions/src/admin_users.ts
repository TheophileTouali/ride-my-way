import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getAuth } from "firebase-admin/auth";
import { assertSuperAdmin } from "./admin_guard";

export const grantSuperAdmin = onCall(
  { region: "europe-west1" },
  async (request) => {
    // ✅ Seuls les super admins peuvent attribuer
    assertSuperAdmin(request);

    const uid = String(request.data?.uid ?? "").trim();
    if (!uid) {
      throw new HttpsError("invalid-argument", "uid manquant");
    }

    await getAuth().setCustomUserClaims(uid, { super_admin: true });

    return { success: true, uid };
  }
);


export const removeSuperAdmin = onCall(
  { region: "europe-west1" },
  async (request) => {
    // Seuls les super admins peuvent retirer le rôle
    const callerUid = assertSuperAdmin(request);

    const uid = String(request.data?.uid ?? "").trim();
    if (!uid) {
      throw new HttpsError("invalid-argument", "uid manquant");
    }

    // Sécurité : éviter qu’un super admin se retire lui-même par erreur
    if (uid === callerUid) {
      throw new HttpsError(
        "failed-precondition",
        "Impossible de retirer votre propre rôle super admin"
      );
    }

    // Supprime uniquement le claim super_admin
    await getAuth().setCustomUserClaims(uid, {
      super_admin: false,
    });

    return {
      success: true,
      uid,
      removed: true,
    };
  }
);
