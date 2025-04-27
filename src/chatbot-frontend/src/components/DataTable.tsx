import React from 'react';

type DataRow = Record<string, React.ReactNode> | Array<React.ReactNode>;

interface DataTableProps {
  headers: string[];
  rows: DataRow[];
  // Example: keys might map object keys to header order if rows are objects
  // keys?: string[]; 
}

const DataTable: React.FC<DataTableProps> = ({ headers, rows }) => {
  return (
    <div className="my-4 overflow-x-auto">
      <div className="inline-block min-w-full align-middle">
        <div className="overflow-hidden shadow ring-1 ring-black ring-opacity-5 sm:rounded-lg">
          <table className="min-w-full divide-y divide-gray-300">
            <thead className="bg-gray-50">
              <tr>
                {headers.map((header, index) => (
                  <th 
                    key={index} 
                    scope="col" 
                    className="py-3.5 pl-4 pr-3 text-left text-sm font-semibold text-gray-900 sm:pl-6"
                  >
                    {header}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-200 bg-white">
              {rows.length > 0 ? (
                rows.map((row, rowIndex) => (
                  <tr key={rowIndex}>
                    {/* Handle both array rows and object rows (using headers as keys) */}
                    {Array.isArray(row) 
                      ? row.map((cell, cellIndex) => (
                          <td 
                            key={cellIndex} 
                            className="whitespace-nowrap py-4 pl-4 pr-3 text-sm text-gray-500 sm:pl-6"
                          >
                            {cell}
                          </td>
                        ))
                      : headers.map((header, cellIndex) => (
                          <td 
                            key={cellIndex} 
                            className="whitespace-nowrap py-4 pl-4 pr-3 text-sm text-gray-500 sm:pl-6"
                          >
                            {/* Attempt to access using header as key, provide fallback */}
                            {(row as Record<string, React.ReactNode>)[header.toLowerCase()] ?? 
                             (row as Record<string, React.ReactNode>)[header] ?? 
                             '-'} 
                          </td>
                        ))
                    }
                  </tr>
                ))
              ) : (
                <tr>
                  <td 
                    colSpan={headers.length} 
                    className="py-4 pl-4 pr-3 text-sm text-center text-gray-500 sm:pl-6"
                  >
                    No data available.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
};

export default DataTable;
