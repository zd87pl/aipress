import React from 'react';
// Import the global CSS file which now contains Tailwind directives
import './index.css'; 
import { useAuth } from './contexts/AuthContext'; // Import the auth hook
import LoginPage from './pages/LoginPage'; // Import the LoginPage
import LoadingSpinner from './components/LoadingSpinner'; // Import LoadingSpinner
import Button from './components/Button'; // Import Button for logout example

function App() {
  const { currentUser, loading, logout } = useAuth();

  // Show loading indicator while checking auth state
  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <LoadingSpinner size="lg" />
      </div>
    );
  }

  // If user is not logged in, show LoginPage
  if (!currentUser) {
    return <LoginPage />;
  }

  // If user is logged in, show the main application interface
  // (Placeholder for now, will be replaced with chat UI, routing, etc.)
  return (
    <div className="p-4"> 
      <div className="flex justify-between items-center mb-4">
        <h1 className="text-xl text-blue-500">
          AIPress Chatbot Frontend (Logged In)
        </h1>
        <Button onClick={logout} variant="secondary">Logout</Button>
      </div>
      <p>Welcome, {currentUser.email || 'User'}!</p>
      <p>Basic setup with Vite, React, TypeScript, and Tailwind CSS.</p>
      {/* TODO: Replace with actual Chat UI or Router */}
    </div>
  );
}

export default App;
