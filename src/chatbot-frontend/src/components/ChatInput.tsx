import React, { useState } from 'react';
import TextInput from './TextInput'; // Assuming in the same directory
import Button from './Button'; // Assuming in the same directory

interface ChatInputProps {
  onSendMessage: (message: string) => void;
  disabled?: boolean;
}

const ChatInput: React.FC<ChatInputProps> = ({ onSendMessage, disabled = false }) => {
  const [message, setMessage] = useState('');

  const handleSend = () => {
    const trimmedMessage = message.trim();
    if (trimmedMessage && !disabled) {
      onSendMessage(trimmedMessage);
      setMessage(''); // Clear input after sending
    }
  };

  const handleKeyPress = (event: React.KeyboardEvent<HTMLInputElement>) => {
    if (event.key === 'Enter' && !event.shiftKey) { // Send on Enter, allow Shift+Enter for newline
      event.preventDefault(); // Prevent default form submission/newline
      handleSend();
    }
  };

  return (
    <div className="flex items-center space-x-2">
      <TextInput
        value={message}
        onChange={(e) => setMessage(e.target.value)}
        onKeyPress={handleKeyPress}
        placeholder="Type your message..."
        disabled={disabled}
        className="flex-grow" // Make input take available space
        aria-label="Chat message input"
      />
      <Button 
        onClick={handleSend} 
        disabled={disabled || message.trim().length === 0}
        aria-label="Send message"
      >
        Send
      </Button>
    </div>
  );
};

export default ChatInput;
