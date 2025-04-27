import React, { createContext, useState, useEffect, useContext, ReactNode } from 'react';
import { onAuthStateChanged, User, signOut as firebaseSignOut } from 'firebase/auth';
import { auth } from '../firebaseConfig'; // Import the initialized auth instance

interface AuthContextType {
  currentUser: User | null;
  loading: boolean;
  // Add login functions later, e.g., signInWithGoogle, signInWithGithub etc.
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

  // --- Placeholder Sign In Functions (to be implemented) ---
  // const signInWithGoogle = async () => { ... };
  // const signInWithGithub = async () => { ... };
  // etc.

  const value = {
    currentUser,
    loading,
    logout,
    // Add signIn functions here once implemented
  };

  // Don't render children until loading is false to prevent rendering protected routes prematurely
  return (
    <AuthContext.Provider value={value}>
      {!loading && children} 
    </AuthContext.Provider>
  );
};
