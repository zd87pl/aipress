import React, { useState, useEffect } from 'react';
import TextInput from './TextInput';
import Button from './Button';

interface UserFormData {
  email: string;
  role: 'Admin' | 'Tenant';
  // Add other fields as needed, e.g., tenantId for Tenant role
}

interface UserFormProps {
  initialData?: UserFormData & { id?: string }; // Optional initial data for editing
  onSubmit: (data: UserFormData) => void;
  onCancel: () => void;
  isSubmitting?: boolean; // Optional flag to disable form during submission
}

const UserForm: React.FC<UserFormProps> = ({ 
  initialData, 
  onSubmit, 
  onCancel,
  isSubmitting = false 
}) => {
  const [formData, setFormData] = useState<UserFormData>(
    initialData || { email: '', role: 'Tenant' }
  );

  // Update form if initialData changes (e.g., when opening modal for different user)
  useEffect(() => {
    if (initialData) {
      setFormData(initialData);
    } else {
      setFormData({ email: '', role: 'Tenant' }); // Reset for new user
    }
  }, [initialData]);


  const handleChange = (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => {
    const { name, value } = e.target;
    setFormData(prev => ({ ...prev, [name]: value }));
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    onSubmit(formData);
  };

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <TextInput
        label="Email"
        name="email"
        type="email"
        value={formData.email}
        onChange={handleChange}
        required
        disabled={isSubmitting}
      />
      
      <div>
        <label htmlFor="role" className="block text-sm font-medium text-gray-700 mb-1">
          Role
        </label>
        <select
          id="role"
          name="role"
          value={formData.role}
          onChange={handleChange}
          disabled={isSubmitting}
          className="block w-full px-3 py-2 border border-gray-300 bg-white rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
        >
          <option value="Tenant">Tenant</option>
          <option value="Admin">Admin</option>
        </select>
      </div>

      {/* Add more fields here if needed, e.g., assigning tenantId */}

      <div className="flex justify-end space-x-3 pt-2">
        <Button type="button" variant="secondary" onClick={onCancel} disabled={isSubmitting}>
          Cancel
        </Button>
        <Button type="submit" variant="primary" disabled={isSubmitting}>
          {isSubmitting ? 'Saving...' : (initialData ? 'Update User' : 'Create User')}
        </Button>
      </div>
    </form>
  );
};

export default UserForm;
