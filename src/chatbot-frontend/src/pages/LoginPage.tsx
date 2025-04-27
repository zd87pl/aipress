import React, { useState } from 'react'; // Import useState
import { useAuth } from '../contexts/AuthContext'; // Import useAuth hook
import Button from '../components/Button'; // Use the Button component
import TextInput from '../components/TextInput'; // Import TextInput
import LoadingSpinner from '../components/LoadingSpinner'; // Import LoadingSpinner

const LoginPage: React.FC = () => {
  const { 
    signInWithGoogle, 
    signInWithGithub, 
    signInWithApple, 
    signUpWithEmail, // Destructure email functions
    signInWithEmail 
  } = useAuth(); 

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null); // State for displaying errors
  const [isSubmitting, setIsSubmitting] = useState(false); // State to disable buttons during auth

  // --- Social Sign-In Handlers ---
  const handleGoogleSignIn = async () => {
    try {
      await signInWithGoogle();
      // No need to navigate here, AuthContext listener in App.tsx will handle re-render
    } catch (error) {
      console.error("Google Sign-In failed in component:", error);
      // Optionally show an error message to the user
    }
  };
  const handleGithubSignIn = async () => {
    try {
      await signInWithGithub();
    } catch (error) {
      console.error("GitHub Sign-In failed in component:", error);
    }
  };
  const handleAppleSignIn = async () => {
    try {
      await signInWithApple();
    } catch (error) {
       console.error("Apple Sign-In failed in component:", error);
       // Optionally show an error message to the user
    }
  };

  // --- Email/Password Handlers ---
   const handleEmailSignIn = async (e: React.FormEvent) => {
    e.preventDefault(); // Prevent default form submission
    setError(null);
    setIsSubmitting(true);
    try {
      await signInWithEmail(email, password);
      // Auth state change will handle redirect/UI update
    } catch (err: any) {
      console.error("Email Sign-In failed:", err);
      setError(err.message || "Failed to sign in. Please check your credentials.");
      setIsSubmitting(false);
    }
     // isSubmitting will be reset by auth state change on success
  };

   const handleEmailSignUp = async (e: React.FormEvent) => {
     e.preventDefault(); 
     setError(null);
     setIsSubmitting(true);
     try {
       await signUpWithEmail(email, password);
       // Auth state change will handle redirect/UI update
     } catch (err: any) {
       console.error("Email Sign-Up failed:", err);
       setError(err.message || "Failed to sign up.");
       setIsSubmitting(false);
     }
      // isSubmitting will be reset by auth state change on success
   };


  return (
    <div className="flex items-center justify-center min-h-screen bg-gray-100">
      <div className="p-8 bg-white rounded-lg shadow-md w-full max-w-sm">
        <h1 className="text-2xl font-semibold text-center text-gray-800 mb-6">
          Welcome to AIPress
        </h1>
        <div className="space-y-4">
          <Button 
            variant="secondary" 
            onClick={handleGoogleSignIn}
            className="w-full flex items-center justify-center" // Basic styling for icon + text
          >
            {/* Placeholder for Google Icon */}
            <span className="mr-2">G</span> 
            Sign in with Google
          </Button>
          <Button 
            variant="secondary" 
            onClick={handleGithubSignIn}
            className="w-full flex items-center justify-center bg-gray-800 text-white hover:bg-gray-900" // GitHub styling
          >
            {/* Placeholder for GitHub Icon */}
            <span className="mr-2">GH</span>
            Sign in with GitHub
          </Button>
           <Button 
            variant="secondary" 
            onClick={handleAppleSignIn}
            className="w-full flex items-center justify-center bg-black text-white hover:bg-gray-800" // Apple styling
          >
            {/* Placeholder for Apple Icon */}
            <span className="mr-2"></span> 
                Sign in with Apple
          </Button>
        </div>

        {/* Separator */}
        <div className="my-6 flex items-center justify-center">
          <span className="px-2 text-sm text-gray-500">Or</span>
        </div>

        {/* Email/Password Form */}
        <form onSubmit={handleEmailSignIn} className="space-y-4">
           {error && (
            <p className="text-red-500 text-sm text-center">{error}</p>
          )}
          <TextInput
            label="Email"
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="you@example.com"
            required
            disabled={isSubmitting}
            aria-label="Email address"
          />
          <TextInput
            label="Password"
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="••••••••"
            required
            disabled={isSubmitting}
            aria-label="Password"
          />
          <div className="flex flex-col sm:flex-row sm:space-x-2 space-y-2 sm:space-y-0 pt-2">
             <Button 
              type="submit" // Sign in by default
              variant="primary"
              disabled={isSubmitting || !email || !password}
              className="w-full"
            >
              {/* LoadingSpinner will be added later */}
              {isSubmitting ? 'Signing In...' : 'Sign In'} 
            </Button>
            <Button 
              type="button" // Use type="button" to prevent form submission
              variant="secondary"
              onClick={handleEmailSignUp} // Call sign up handler
              disabled={isSubmitting || !email || !password}
              className="w-full"
            >
               {/* LoadingSpinner will be added later */}
              {isSubmitting ? 'Signing Up...' : 'Sign Up'}
            </Button>
          </div>
        </form>

        {/* Separator */}
        <div className="my-6 flex items-center justify-center">
          <span className="px-2 text-sm text-gray-500">Or</span>
        </div>

        {/* Email/Password Form */}
        <form onSubmit={handleEmailSignIn} className="space-y-4">
           {error && (
            <p className="text-red-500 text-sm text-center">{error}</p>
          )}
          <TextInput
            label="Email"
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="you@example.com"
            required
            disabled={isSubmitting}
            aria-label="Email address"
          />
          <TextInput
            label="Password"
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="••••••••"
            required
            disabled={isSubmitting}
            aria-label="Password"
          />
          <div className="flex flex-col sm:flex-row sm:space-x-2 space-y-2 sm:space-y-0 pt-2">
             <Button 
              type="submit" // Sign in by default
              variant="primary"
              disabled={isSubmitting || !email || !password}
              className="w-full"
            >
              {/* LoadingSpinner will be added in next step */}
              {isSubmitting ? 'Signing In...' : 'Sign In'} 
            </Button>
            <Button 
              type="button" // Use type="button" to prevent form submission
              variant="secondary"
              onClick={handleEmailSignUp} // Call sign up handler
              disabled={isSubmitting || !email || !password}
              className="w-full"
            >
               {/* LoadingSpinner will be added in next step */}
              {isSubmitting ? 'Signing Up...' : 'Sign Up'}
            </Button>
          </div>
        </form>

        {/* Separator */}
        <div className="my-6 flex items-center justify-center">
          <span className="px-2 text-sm text-gray-500">Or</span>
        </div>

        {/* Email/Password Form */}
        <form onSubmit={handleEmailSignIn} className="space-y-4">
           {error && (
            <p className="text-red-500 text-sm text-center">{error}</p>
          )}
          <TextInput
            label="Email"
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="you@example.com"
            required
            disabled={isSubmitting}
            aria-label="Email address"
          />
          <TextInput
            label="Password"
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="••••••••"
            required
            disabled={isSubmitting}
            aria-label="Password"
          />
          <div className="flex flex-col sm:flex-row sm:space-x-2 space-y-2 sm:space-y-0 pt-2">
             <Button 
              type="submit" // Sign in by default
              variant="primary"
              disabled={isSubmitting || !email || !password}
              className="w-full"
            >
              {/* LoadingSpinner will be added in next step */}
              {isSubmitting ? 'Signing In...' : 'Sign In'} 
            </Button>
            <Button 
              type="button" // Use type="button" to prevent form submission
              variant="secondary"
              onClick={handleEmailSignUp} // Call sign up handler
              disabled={isSubmitting || !email || !password}
              className="w-full"
            >
               {/* LoadingSpinner will be added in next step */}
              {isSubmitting ? 'Signing Up...' : 'Sign Up'}
            </Button>
          </div>
        </form>

        {/* Separator */}
        <div className="my-6 flex items-center justify-center">
          <span className="px-2 text-sm text-gray-500">Or</span>
        </div>

        {/* Email/Password Form */}
        <form onSubmit={handleEmailSignIn} className="space-y-4">
           {error && (
            <p className="text-red-500 text-sm text-center">{error}</p>
          )}
          <TextInput
            label="Email"
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="you@example.com"
            required
            disabled={isSubmitting}
            aria-label="Email address"
          />
          <TextInput
            label="Password"
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="••••••••"
            required
            disabled={isSubmitting}
            aria-label="Password"
          />
          <div className="flex flex-col sm:flex-row sm:space-x-2 space-y-2 sm:space-y-0 pt-2">
             <Button 
              type="submit" // Sign in by default
              variant="primary"
              disabled={isSubmitting || !email || !password}
              className="w-full"
            >
              {isSubmitting ? <LoadingSpinner size="sm" color="text-white" /> : 'Sign In'}
            </Button>
            <Button 
              type="button" // Use type="button" to prevent form submission
              variant="secondary"
              onClick={handleEmailSignUp} // Call sign up handler
              disabled={isSubmitting || !email || !password}
              className="w-full"
            >
              {isSubmitting ? <LoadingSpinner size="sm" /> : 'Sign Up'}
            </Button>
          </div>
        </form>
      </div>
    </div>
  );
};

export default LoginPage;
