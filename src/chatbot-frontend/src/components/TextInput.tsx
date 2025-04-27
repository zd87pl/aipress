import React from 'react';

interface TextInputProps extends React.InputHTMLAttributes<HTMLInputElement> {
  label?: string;
  // Add value and onChange to props if controlling the component externally
  // value?: string; 
  // onChange?: (event: React.ChangeEvent<HTMLInputElement>) => void;
}

const TextInput: React.FC<TextInputProps> = ({ 
  label, 
  id, 
  className = '', 
  ...props 
}) => {
  const inputId = id || label?.toLowerCase().replace(/\s+/g, '-') || undefined;

  return (
    <div className="mb-4"> {/* Add some margin below */}
      {label && (
        <label 
          htmlFor={inputId} 
          className="block text-sm font-medium text-gray-700 mb-1"
        >
          {label}
        </label>
      )}
      <input
        id={inputId}
        type={props.type || 'text'}
        className={`block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm placeholder-gray-400 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm ${className}`}
        {...props}
      />
    </div>
  );
};

export default TextInput;
