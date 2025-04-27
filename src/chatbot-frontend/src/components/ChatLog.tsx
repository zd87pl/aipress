import React, { useEffect, useRef } from 'react';
import ChatMessage from './ChatMessage'; // Assuming it's in the same directory

interface Message {
  sender: 'user' | 'system';
  content: string;
  // Add a unique key if possible, e.g., id: string | number;
}

interface ChatLogProps {
  messages: Message[];
}

const ChatLog: React.FC<ChatLogProps> = ({ messages }) => {
  const chatEndRef = useRef<HTMLDivElement>(null);

  // Automatically scroll to the bottom when new messages are added
  useEffect(() => {
    chatEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  return (
    <div className="h-96 overflow-y-auto border border-gray-300 rounded-md p-4 bg-white flex flex-col space-y-2 mb-4">
      {messages.map((msg, index) => (
        // Use a more stable key if available, otherwise index is fallback
        <ChatMessage key={index} sender={msg.sender} content={msg.content} />
      ))}
      {/* Empty div to target for scrolling */}
      <div ref={chatEndRef} />
    </div>
  );
};

export default ChatLog;
