// Service worker för FCM web push (La Familia).
// Tar emot push när webbappen är stängd/i bakgrunden. Notification-meddelanden
// visas automatiskt av SDK:n; klick fokuserar/öppnar appen.
importScripts("https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "AIzaSyBjHA2kJQIt8sxtVUJAOzMXIgz0FDQp1lw",
  authDomain: "la-familia-5d9f5.firebaseapp.com",
  projectId: "la-familia-5d9f5",
  storageBucket: "la-familia-5d9f5.firebasestorage.app",
  messagingSenderId: "1062436758460",
  appId: "1:1062436758460:web:4c46764483a57ab7bb81b9",
});

const messaging = firebase.messaging();

// Klick på notisen: fokusera öppet fönster, annars öppna appen.
self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true }).then((list) => {
      for (const client of list) {
        if ("focus" in client) return client.focus();
      }
      return clients.openWindow("/");
    })
  );
});
