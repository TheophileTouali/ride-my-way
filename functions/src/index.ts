import * as dotenv from "dotenv";
dotenv.config();

export {
  createPaymentIntent,
  verifyPaymentIntent,
  capturePaymentIntent,
  cancelPaymentIntent,
} from "./payments";

export { getRouteInfo } from "./routes";

import { initializeApp } from "firebase-admin/app";
initializeApp();

// ✅ stats admin (une seule fois)
export { adminGetDashboardStats } from "./admin_dashboard";

export { grantSuperAdmin } from "./admin_users";
export { removeSuperAdmin } from "./admin_users";

