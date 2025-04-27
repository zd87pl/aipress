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
  // Optional: Add unique ID for keys later
  id?: string | number; 
}

// Define the HistoryItem structure expected by the backend
interface HistoryPart {
  text: string;
}
interface HistoryItem {
  role: 'user' | 'model'; // Match backend roles
  parts: HistoryPart[];
}


function App() {
  // Get getIdToken from useAuth
  const { currentUser, loading, logout, getIdToken } = useAuth(); 
  const [messages, setMessages] = useState<Message[]>([
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
    setIsChatDisabled(true);

    let systemResponse: Message;
    try {
      const token = await getIdToken(); // Get the auth token
      if (!token) {
        throw new Error("User not authenticated.");
      }

      console.log('Sending message to backend:', messageContent);
      const backendUrl = import.meta.env.VITE_CHATBOT_BACKEND_URL || 'http://localhost:8080'; // Use env var or default

      const response = await fetch(`${backendUrl}/chat`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`, // Send the token
        },
        // Format history for the backend
        body: JSON.stringify({ 
            message: messageContent,
            history: messages.map(msg => ({ // Map current messages state to history format
                role: msg.sender === 'user' ? 'user' : 'model', // Convert 'system' to 'model' for backend
                parts: [{ text: msg.content }]
            })),
            tenant_id: null // TODO: Add actual tenant_id later
        }), 
      });

      if (!response.ok) {
        // Try to get error detail from backend response
        let errorDetail = `HTTP error! status: ${response.status}`;
        try {
            const errorData = await response.json();
            errorDetail = errorData.detail || errorDetail;
        } catch (jsonError) {
            // Ignore if response is not JSON
        }
        throw new Error(errorDetail);
      }

      const data = await response.json();
      systemResponse = { sender: 'system', content: data.response };

    } catch (error: any) {
      console.error("Error sending message to backend:", error);
      systemResponse = { 
        sender: 'system', 
        content: `Error: ${error.message || 'Could not connect to the backend.'}` 
      };
    } finally {
      setMessages(prev => [...prev, systemResponse]);
      setIsChatDisabled(false); // Re-enable input regardless of success/failure
    }
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
