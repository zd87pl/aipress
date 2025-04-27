import React from 'react';
// Import useAuth hook to access login functions later
// import { useAuth } from '../contexts/AuthContext'; 
import Button from '../components/Button'; // Use the Button component

const LoginPage: React.FC = () => {
  // const { signInWithGoogle, signInWithGithub, /* ... other methods */ } = useAuth();

  // Placeholder handlers - replace with actual calls to useAuth functions
  const handleGoogleSignIn = () => console.log('TODO: Sign in with Google');
  const handleGithubSignIn = () => console.log('TODO: Sign in with GitHub');
  const handleAppleSignIn = () => console.log('TODO: Sign in with Apple');
  const handleEmailSignIn = () => console.log('TODO: Sign in with Email');


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
           <Button 
            variant="secondary" 
            onClick={handleEmailSignIn}
            className="w-full"
          >
            Sign in with Email
          </Button>
        </div>
      </div>
    </div>
  );
};

export default LoginPage;
