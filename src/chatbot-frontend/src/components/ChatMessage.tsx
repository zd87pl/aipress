import React from 'react';

interface ChatMessageProps {
  sender: 'user' | 'system';
  content: string;
}

const ChatMessage: React.FC<ChatMessageProps> = ({ sender, content }) => {
  const isUser = sender === 'user';

  // Base styles for all messages
  const baseStyle = 'max-w-[80%] rounded-lg px-4 py-2 mb-2 shadow-sm';

  // Styles specific to sender
  const senderStyle = isUser
    ? 'bg-blue-500 text-white self-end' // User messages on the right, blue background
    : 'bg-gray-100 text-gray-800 self-start'; // System messages on the left, light grey background

  return (
    <div className={`flex ${isUser ? 'justify-end' : 'justify-start'}`}>
      <div className={`${baseStyle} ${senderStyle}`}>
        {/* Render content safely, potentially handling markdown or newlines later */}
        {content} 
      </div>
    </div>
  );
};

export default ChatMessage;
