import React from 'react';
import DataTable from './DataTable';
import Button from './Button'; // Assuming Button is in the same directory

interface User {
  id: string;
  email: string;
  role: 'Admin' | 'Tenant';
  tenantId?: string; // Optional tenant ID for Tenant users
  // Add other relevant user fields
}

interface UserTableProps {
  users: User[];
  onEdit?: (userId: string) => void;
  onDelete?: (userId: string) => void;
}

const UserTable: React.FC<UserTableProps> = ({ users, onEdit, onDelete }) => {
  const headers = ['Email', 'Role', 'Tenant ID', 'Actions'];

  const rows = users.map((user) => ({
    Email: user.email,
    Role: user.role,
    'Tenant ID': user.tenantId || '-', // Display '-' if no tenant ID
    Actions: (
      <div className="space-x-2">
        {onEdit && (
          <Button 
            variant="secondary" 
            onClick={() => onEdit(user.id)} 
            className="text-xs px-2 py-1" // Smaller button for table actions
            aria-label={`Edit user ${user.email}`}
          >
            Edit
          </Button>
        )}
        {onDelete && (
          <Button 
            variant="destructive" 
            onClick={() => onDelete(user.id)} 
            className="text-xs px-2 py-1" // Smaller button for table actions
            aria-label={`Delete user ${user.email}`}
          >
            Delete
          </Button>
        )}
      </div>
    ),
  }));

  return (
    <div>
      <h3 className="text-lg font-medium leading-6 text-gray-900 mb-4">User Management</h3>
      <DataTable headers={headers} rows={rows} />
    </div>
  );
};

export default UserTable;
