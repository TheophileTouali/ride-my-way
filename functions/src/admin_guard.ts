import { HttpsError } from "firebase-functions/v2/https";

export function assertSuperAdmin(request: any) {
  const auth = request.auth;
  if (!auth) throw new HttpsError("unauthenticated", "Connexion requise");

  const claims = auth.token || {};
  const isAdmin = claims.super_admin === true;

  if (!isAdmin) {
    throw new HttpsError("permission-denied", "Accès Super Admin requis");
  }

  return auth.uid as string;
}
