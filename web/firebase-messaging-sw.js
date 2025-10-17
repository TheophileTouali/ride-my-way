/* web/firebase-messaging-sw.js */

// IMPORTANT : on utilise les "compat" pour rester simple avec FlutterFire
importScripts(
  "https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js"
);
importScripts(
  "https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js"
);

// == Ta config Firebase (copie EXACTE de celle utilisée dans ton app) ==
firebase.initializeApp({
  apiKey: "AI...tonApiKey...",
  authDomain: "ride-my-way-7f258.firebaseapp.com",
  projectId: "ride-my-way-7f258",
  storageBucket: "ride-my-way-7f258.appspot.com",
  messagingSenderId: "XXXXXXXXXXXX",
  appId: "1:XXXXXXXXXXXX:web:YYYYYYYYYYYYYYYY",
});

// Initialiser Messaging pour le SW
const messaging = firebase.messaging();

// Optionnel : réponse aux clicks de notif
self.addEventListener("notificationclick", function (event) {
  event.notification.close();
  event.waitUntil(
    clients.openWindow("/") // ouvre ton app
  );
});
