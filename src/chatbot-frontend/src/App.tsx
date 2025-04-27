import React, { useState } from 'react'; // Correctly import React and useState
// Import the global CSS file which now contains Tailwind directives
import './index.css'; 
import { useAuth } from './contexts/AuthContext'; // Import the auth hook
import LoginPage from './pages/LoginPage'; // Import the LoginPage
import LoadingSpinner from './components/LoadingSpinner'; // Import LoadingSpinner
import Button from './components/Button'; // Import Button for logout example
import ChatLog from './components/ChatLog'; // Import ChatLog
import ChatInput from './components/ChatInput'; // Import ChatInput

// Define message structure (can be moved to a types file later)
interface Message {
  sender: 'user' | 'system';
  content: string;
}

function App() {
  const { currentUser, loading, logout } = useAuth();
  const [messages, setMessages] = useState<Message[]>([
    // Initial welcome message
    { sender: 'system', content: 'Welcome to AIPress! How can I help you today?' } 
  ]);
  const [isChatDisabled, setIsChatDisabled] = useState(false); // To disable input while processing

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

  // --- Chat Handling Logic ---
  const handleSendMessage = async (messageContent: string) => {
    // Add user message to the log
    const userMessage: Message = { sender: 'user', content: messageContent };
    setMessages(prev => [...prev, userMessage]);
    setIsChatDisabled(true); // Disable input

    // TODO: Send message to backend API
    console.log('Sending to backend:', messageContent); 
    
    // --- Placeholder for backend response ---
    // Simulate backend processing and response
    await new Promise(resolve => setTimeout(resolve, 1000)); // Wait 1 second
    const systemResponse: Message = { 
      sender: 'system', 
      content: `Received: "${messageContent}". (Backend processing not implemented yet)` 
    };
    setMessages(prev => [...prev, systemResponse]);
    // --- End Placeholder ---

    setIsChatDisabled(false); // Re-enable input
  };


  // If user is logged in, show the main application interface
  return (
    <div className="flex flex-col h-screen max-w-3xl mx-auto p-4"> 
      {/* Header */}
      <div className="flex justify-between items-center mb-4 border-b pb-2">
        <h1 className="text-xl font-semibold text-gray-800">
          AIPress Chat
        </h1>
        <div className='flex items-center space-x-2'>
           <span className="text-sm text-gray-600 truncate max-w-xs">{currentUser.email || 'User'}</span>
           {/* Removed size="sm" prop as it's not defined; styling is handled by className */}
           <Button onClick={logout} variant="secondary" className="px-3 py-1 text-sm">Logout</Button> 
        </div>
      </div>

      {/* Chat Area */}
      <div className="flex-grow mb-4 overflow-hidden"> {/* Allow ChatLog to take space */}
        <ChatLog messages={messages} />
      </div>
      
      {/* Input Area */}
      <ChatInput onSendMessage={handleSendMessage} disabled={isChatDisabled} />
    </div>
  );
}

export default App;
