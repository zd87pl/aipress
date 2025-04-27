import React from 'react';

export interface NavItem { // Added export here
  label: string;
  path: string; // Used for linking and determining active state
  icon?: React.ReactNode; // Optional icon component
}

interface SidebarNavProps {
  navItems: NavItem[];
  currentPath: string; // Need current path to highlight active item
  className?: string;
}

const SidebarNav: React.FC<SidebarNavProps> = ({ 
    navItems, 
    currentPath, 
    className = '' 
}) => {
  return (
    <nav className={`w-64 h-full bg-gray-50 border-r border-gray-200 p-4 ${className}`}>
      <div className="mb-6">
        {/* Placeholder for Logo or Title */}
        <h2 className="text-lg font-semibold text-gray-800">AIPress Admin</h2>
      </div>
      <ul className="space-y-2">
        {navItems.map((item) => {
          const isActive = currentPath === item.path;
          return (
            <li key={item.path}>
              <a 
                href={item.path} // Replace with React Router Link component later if using router
                className={`flex items-center px-3 py-2 rounded-md text-sm font-medium transition-colors duration-150 ease-in-out
                  ${
                    isActive 
                      ? 'bg-blue-100 text-blue-700' // Active state style
                      : 'text-gray-600 hover:bg-gray-100 hover:text-gray-900' // Default state style
                  }`}
              >
                {item.icon && <span className="mr-3 h-5 w-5">{item.icon}</span>}
                {item.label}
              </a>
            </li>
          );
        })}
      </ul>
    </nav>
  );
};

export default SidebarNav;
