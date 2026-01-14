require("dotenv").config();
const admin = require("firebase-admin");
const path = require("path");

const serviceAccount = require(path.join(__dirname, "serviceAccountKey.json"));

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

async function run() {
  const uid = process.env.UID;

  if (!uid) {
    throw new Error("❌ UID manquant dans le fichier .env");
  }

  await admin.auth().setCustomUserClaims(uid, {
    super_admin: true,
  });

  const user = await admin.auth().getUser(uid);

  console.log("✅ super_admin activé pour:", uid);
  console.log("🔎 Claims actuels:", user.customClaims);

  process.exit(0);
}

run().catch((e) => {
  console.error("❌ Erreur:", e);
  process.exit(1);
});
