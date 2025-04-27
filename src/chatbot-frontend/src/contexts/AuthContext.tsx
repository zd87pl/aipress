import React, { createContext, useState, /* useEffect, */ useContext, ReactNode } from 'react';
// Comment out Firebase imports for mock implementation
// import { 
//   onAuthStateChanged, 
//   User, 
//   signOut as firebaseSignOut, 
//   GoogleAuthProvider, 
//   GithubAuthProvider, 
//   OAuthProvider, 
//   signInWithPopup,
//   createUserWithEmailAndPassword, 
//   signInWithEmailAndPassword 
// } from 'firebase/auth';
// import { auth } from '../firebaseConfig'; 

// Define a mock User type shape 
interface MockUser {
  uid: string;
  email: string | null;
}

interface AuthContextType {
  currentUser: MockUser | null; // Use MockUser type
  loading: boolean;
  signInWithGoogle: () => Promise<void>; 
  signInWithGithub: () => Promise<void>; 
  signInWithApple: () => Promise<void>; 
  signUpWithEmail: (email: string, password: string) => Promise<void>; 
  signInWithEmail: (email: string, password: string) => Promise<void>; 
  logout: () => Promise<void>;
  getIdToken: () => Promise<string | null>; // Function to get ID token
}

// Create the context with a default value
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
  // --- Mock Authentication ---
  const mockUser: MockUser = { uid: "mock-user-123", email: "test@example.com" };
  // Set mock user by default for testing, or null to test login page
  const [currentUser, setCurrentUser] = useState<MockUser | null>(mockUser); 
  const [loading, setLoading] = useState(false); // No loading needed for mock

  // --- Mock Sign Out Function ---
  const logout = async () => {
    console.log("Mock Logout called");
    setCurrentUser(null); // Set user to null to show login page
    setLoading(false); // Ensure loading is false after logout
  };

  // --- Mock Sign In Functions ---
  // These just set the mock user 
  const mockSignIn = async () => {
    console.log("Mock Sign In called");
    if (!currentUser) {
        setLoading(true); // Simulate loading briefly
        await new Promise(res => setTimeout(res, 300)); // Short delay
        setCurrentUser(mockUser);
        setLoading(false);
    }
  }
  const signInWithGoogle = mockSignIn;
  const signInWithGithub = mockSignIn;
  const signInWithApple = mockSignIn;
  // Simulate signup also logs in
  const signUpWithEmail = async (_email: string, _password: string) => { await mockSignIn(); }; 
  const signInWithEmail = async (_email: string, _password: string) => { await mockSignIn(); };

  // --- Mock Get ID Token ---
  const getIdToken = async (): Promise<string | null> => {
    // Return a placeholder token string for backend testing
    // IMPORTANT: This is NOT a real secure token!
    if (currentUser) {
        console.log("Returning mock ID token");
        return "mock-firebase-id-token"; 
    }
    console.log("No mock user, returning null token");
    return null;
  };

  const value = {
    currentUser,
    loading,
    signInWithGoogle,
    signInWithGithub,
    signInWithApple,
    signUpWithEmail, 
    signInWithEmail, 
    logout,
    getIdToken,
  };

  // Render children immediately for mock setup, or use !loading if needed
  return (
    <AuthContext.Provider value={value}>
      {children} 
    </AuthContext.Provider>
  );
};
