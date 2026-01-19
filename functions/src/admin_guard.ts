import { HttpsError, CallableRequest } from "firebase-functions/v2/https";

/**
 * Vérifie que l'utilisateur appelant possède le claim custom:
 *   super_admin === true
 * Fonction compatible avec onCall (Firebase Functions v2)
 */
export function assertSuperAdmin(request: CallableRequest): string {
  const auth = request.auth;

  if (!auth) {
    throw new HttpsError("unauthenticated", "Connexion requise");
  }

  if (auth.token?.super_admin !== true) {
    throw new HttpsError("permission-denied", "Accès Super Admin requis");
  }

  return auth.uid;
}
