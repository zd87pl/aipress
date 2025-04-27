import React from 'react';

interface LoadingSpinnerProps {
  size?: 'sm' | 'md' | 'lg'; // Optional size prop
  color?: string; // Optional color override (Tailwind class e.g., 'text-blue-600')
  className?: string; // Allow additional classes
}

const LoadingSpinner: React.FC<LoadingSpinnerProps> = ({ 
  size = 'md', 
  color = 'text-blue-600', // Default to primary color
  className = '' 
}) => {
  let sizeClasses = '';
  switch (size) {
    case 'sm':
      sizeClasses = 'h-4 w-4';
      break;
    case 'lg':
      sizeClasses = 'h-8 w-8';
      break;
    case 'md':
    default:
      sizeClasses = 'h-6 w-6';
      break;
  }

  return (
    <div className={`flex justify-center items-center ${className}`}>
      <div 
        className={`animate-spin rounded-full border-t-2 border-b-2 border-transparent ${sizeClasses} ${color}`}
        style={{ borderTopColor: 'currentColor', borderBottomColor: 'currentColor' }} // Use currentColor for spinner segments
        role="status" 
        aria-live="polite"
      >
        <span className="sr-only">Loading...</span> {/* Accessibility */}
      </div>
    </div>
  );
};

export default LoadingSpinner;
