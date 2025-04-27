import React, { useState } from 'react';
import TextInput from './TextInput'; // Re-use TextInput for base styling

interface SecretInputProps extends React.InputHTMLAttributes<HTMLInputElement> {
  label?: string;
  // Add value and onChange if controlling externally
  // value?: string;
  // onChange?: (event: React.ChangeEvent<HTMLInputElement>) => void;
}

const SecretInput: React.FC<SecretInputProps> = ({ 
  label, 
  id, 
  className = '', 
  ...props 
}) => {
  const [showPassword, setShowPassword] = useState(false);
  const inputId = id || label?.toLowerCase().replace(/\s+/g, '-') || undefined;

  return (
    <div className="mb-4 relative"> {/* Added relative positioning for the button */}
      <TextInput
        label={label}
        id={inputId}
        type={showPassword ? 'text' : 'password'} // Toggle type based on state
        className={`pr-10 ${className}`} // Add padding for the button
        {...props}
      />
      <button
        type="button"
        onClick={() => setShowPassword(!showPassword)}
        className="absolute inset-y-0 right-0 top-5 flex items-center px-3 text-gray-500 hover:text-gray-700 focus:outline-none" // Position button inside input area (adjust top-5 based on label presence/styling)
        aria-label={showPassword ? 'Hide secret' : 'Show secret'}
      >
        {/* Basic Show/Hide text, could replace with icons */}
        {showPassword ? 'Hide' : 'Show'} 
      </button>
    </div>
  );
};

export default SecretInput;
