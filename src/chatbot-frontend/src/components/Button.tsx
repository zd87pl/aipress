import React from 'react';

interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'primary' | 'secondary' | 'destructive';
  children: React.ReactNode;
}

const Button: React.FC<ButtonProps> = ({
  variant = 'primary',
  children,
  className = '',
  disabled = false,
  ...props
}) => {
  const baseStyle =
    'px-4 py-2 rounded-md font-medium focus:outline-none focus:ring-2 focus:ring-offset-2 transition ease-in-out duration-150';
  
  // Define styles for each variant and state
  let variantStyle = '';
  switch (variant) {
    case 'secondary':
      variantStyle = `bg-gray-100 text-gray-700 hover:bg-gray-200 focus:ring-gray-500 ${
        disabled ? 'opacity-50 cursor-not-allowed' : ''
      }`;
      break;
    case 'destructive':
      variantStyle = `bg-red-500 text-white hover:bg-red-600 focus:ring-red-500 ${
        disabled ? 'opacity-50 cursor-not-allowed' : ''
      }`;
      break;
    case 'primary':
    default:
      // Using a muted blue as the primary accent color for now
      variantStyle = `bg-blue-600 text-white hover:bg-blue-700 focus:ring-blue-500 ${
        disabled ? 'opacity-50 cursor-not-allowed' : ''
      }`;
      break;
  }

  return (
    <button
      className={`${baseStyle} ${variantStyle} ${className}`}
      disabled={disabled}
      {...props}
    >
      {children}
    </button>
  );
};

export default Button;
