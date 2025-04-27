import React, { createContext, useState, useEffect, useContext, ReactNode } from 'react';
import { 
  onAuthStateChanged, 
  User, 
  signOut as firebaseSignOut, 
  GoogleAuthProvider, 
  GithubAuthProvider, 
  OAuthProvider, // Import OAuthProvider for Apple
  signInWithPopup,
  createUserWithEmailAndPassword, // Added for email signup
  signInWithEmailAndPassword // Added for email signin
} from 'firebase/auth';
import { auth } from '../firebaseConfig'; // Import the initialized auth instance

interface AuthContextType {
  currentUser: User | null;
  loading: boolean;
  signInWithGoogle: () => Promise<void>; 
  signInWithGithub: () => Promise<void>; 
  signInWithApple: () => Promise<void>; 
  signUpWithEmail: (email: string, password: string) => Promise<void>; // Added Email Sign-Up
  signInWithEmail: (email: string, password: string) => Promise<void>; // Added Email Sign-In
  logout: () => Promise<void>;
}

// Create the context with a default value (or undefined and check in useAuth)
const AuthContext = createContext<AuthContextType | undefined>(undefined);

// Custom hook to use the auth context
export function useAuth() {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}

interface AuthProviderProps {
  children: ReactNode;
}

// Provider component
export const AuthProvider: React.FC<AuthProviderProps> = ({ children }) => {
  const [currentUser, setCurrentUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true); // Start loading until auth state is determined

  useEffect(() => {
    // Subscribe to user authentication state changes
    const unsubscribe = onAuthStateChanged(auth, (user) => {
      setCurrentUser(user);
      setLoading(false); // Auth state determined, stop loading
      console.log("Auth state changed, current user:", user?.email); // For debugging
    });

    // Unsubscribe on unmount
    return unsubscribe;
  }, []);

  // --- Placeholder Sign Out Function ---
  const logout = async () => {
    setLoading(true);
    try {
      await firebaseSignOut(auth);
      // currentUser state will be updated by onAuthStateChanged listener
      console.log("User signed out successfully");
    } catch (error) {
      console.error("Error signing out:", error);
      setLoading(false); // Stop loading on error
    }
    // setLoading(false) is handled by onAuthStateChanged
  };

  // --- Sign In Functions ---
  const signInWithGoogle = async () => {
    setLoading(true); // Indicate loading during sign-in attempt
    const provider = new GoogleAuthProvider();
    try {
      // Use signInWithPopup for web environments
      const result = await signInWithPopup(auth, provider);
      // User state will be updated by onAuthStateChanged, no need to setCurrentUser here
      console.log("Google Sign-In successful:", result.user.email);
    } catch (error) {
      console.error("Error during Google Sign-In:", error);
      // Handle specific errors if needed (e.g., popup closed, network error)
      setLoading(false); // Stop loading on error
    }
    // setLoading(false) is handled by onAuthStateChanged on success
  };

  const signInWithGithub = async () => {
    setLoading(true);
    const provider = new GithubAuthProvider();
    try {
      const result = await signInWithPopup(auth, provider);
      console.log("GitHub Sign-In successful:", result.user.email);
    } catch (error) {
      console.error("Error during GitHub Sign-In:", error);
      setLoading(false);
    }
    // setLoading(false) handled by onAuthStateChanged
  };

  const signInWithApple = async () => {
    setLoading(true);
    const provider = new OAuthProvider('apple.com');
    // You might need to add custom parameters or scopes depending on your setup
    // provider.addScope('email');
    // provider.addScope('name');
    try {
      const result = await signInWithPopup(auth, provider);
      // Apple sign-in might require additional steps to get email/name depending on first login
      console.log("Apple Sign-In successful:", result.user.email); 
    } catch (error: any) {
      console.error("Error during Apple Sign-In:", error);
       // Handle specific Apple errors (e.g., account linking)
      // if (error.code === 'auth/account-exists-with-different-credential') {
      //   // Handle account linking prompt
      // }
      setLoading(false);
    }
     // setLoading(false) handled by onAuthStateChanged
  };

  const signUpWithEmail = async (email: string, password: string) => {
    setLoading(true);
    try {
      const userCredential = await createUserWithEmailAndPassword(auth, email, password);
      // User signed up and signed in. State updated via onAuthStateChanged.
      console.log("Email Sign-Up successful:", userCredential.user.email);
       // TODO: Potentially call backend here to create user profile in platform DB
    } catch (error: any) {
      console.error("Error during Email Sign-Up:", error);
      // Handle specific errors like 'auth/email-already-in-use'
      setLoading(false);
      throw error; // Re-throw error to be caught in component for UI feedback
    }
     // setLoading(false) handled by onAuthStateChanged
  };

  const signInWithEmail = async (email: string, password: string) => {
     setLoading(true);
     try {
      const userCredential = await signInWithEmailAndPassword(auth, email, password);
      // User signed in. State updated via onAuthStateChanged.
      console.log("Email Sign-In successful:", userCredential.user.email);
    } catch (error: any) {
      console.error("Error during Email Sign-In:", error);
      // Handle specific errors like 'auth/wrong-password' or 'auth/user-not-found'
      setLoading(false);
      throw error; // Re-throw error to be caught in component for UI feedback
    }
    // setLoading(false) handled by onAuthStateChanged
  };


  const value = {
    currentUser,
    loading,
    signInWithGoogle,
    signInWithGithub,
    signInWithApple,
    signUpWithEmail, // Expose the function
    signInWithEmail, // Expose the function
    logout,
  };

  // Don't render children until loading is false to prevent rendering protected routes prematurely
  return (
    <AuthContext.Provider value={value}>
      {!loading && children} 
    </AuthContext.Provider>
  );
};
