import { initializeApp } from "firebase/app";
import { getAuth } from "firebase/auth";
// Import other Firebase services as needed, e.g., getFirestore, getAnalytics

// Your web app's Firebase configuration
// IMPORTANT: Load these values from environment variables, do NOT hardcode them here.
// Vite exposes env variables prefixed with VITE_
const firebaseConfig = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY,
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN,
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID,
  storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID,
  appId: import.meta.env.VITE_FIREBASE_APP_ID,
  measurementId: import.meta.env.VITE_FIREBASE_MEASUREMENT_ID // Optional: for Analytics
};

// Validate that environment variables are loaded
if (!firebaseConfig.apiKey || !firebaseConfig.authDomain || !firebaseConfig.projectId) {
    console.error("Firebase configuration environment variables are missing!");
    // Consider throwing an error or displaying a message to the user
}

// Initialize Firebase
const app = initializeApp(firebaseConfig);

// Initialize Firebase Authentication and get a reference to the service
const auth = getAuth(app);

// Initialize other services like Firestore, Analytics if needed
// const db = getFirestore(app);
// const analytics = getAnalytics(app);


export { app, auth }; // Export auth instance for use in components
// Export other services as needed
