import React from 'react';
import SidebarNav, { NavItem } from './SidebarNav'; // Assuming SidebarNav is in the same directory

interface AdminLayoutProps {
  children: React.ReactNode;
  navItems: NavItem[]; // Pass nav items down to SidebarNav
  currentPath: string; // Pass current path down
}

const AdminLayout: React.FC<AdminLayoutProps> = ({ 
    children, 
    navItems, 
    currentPath 
}) => {
  return (
    <div className="flex h-screen bg-gray-100">
      {/* Sidebar */}
      <SidebarNav navItems={navItems} currentPath={currentPath} className="flex-shrink-0" />

      {/* Main Content Area */}
      <main className="flex-1 overflow-y-auto p-6">
        {children}
      </main>
    </div>
  );
};

export default AdminLayout;
