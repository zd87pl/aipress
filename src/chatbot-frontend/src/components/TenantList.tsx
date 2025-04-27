import React from 'react';
import DataTable from './DataTable';
import Button from './Button'; // For potential actions like viewing details

interface Tenant {
  id: string;
  name: string; // Tenant name or site identifier
  status: 'Active' | 'Creating' | 'Deleting' | 'Error' | string; // Example statuses
  // Add other relevant tenant fields, e.g., creation date, URL
  url?: string; 
}

interface TenantListProps {
  tenants: Tenant[];
  onViewDetails?: (tenantId: string) => void; 
  // Add other action handlers if needed, e.g., onDeleteTenant
}

const TenantList: React.FC<TenantListProps> = ({ tenants, onViewDetails }) => {
  const headers = ['Tenant ID', 'Name', 'Status', 'URL', 'Actions'];

  const rows = tenants.map((tenant) => ({
    'Tenant ID': tenant.id,
    'Name': tenant.name,
    'Status': tenant.status,
    'URL': tenant.url ? <a href={tenant.url} target="_blank" rel="noopener noreferrer" className="text-blue-600 hover:underline">{tenant.url}</a> : '-',
    'Actions': (
      <div className="space-x-2">
        {onViewDetails && (
          <Button 
            variant="secondary" 
            onClick={() => onViewDetails(tenant.id)} 
            className="text-xs px-2 py-1"
            aria-label={`View details for tenant ${tenant.name}`}
          >
            Details
          </Button>
        )}
        {/* Add other buttons like Delete if needed */}
      </div>
    ),
  }));

  return (
    <div>
      <h3 className="text-lg font-medium leading-6 text-gray-900 mb-4">Tenant Sites</h3>
      <DataTable headers={headers} rows={rows} />
    </div>
  );
};

export default TenantList;
