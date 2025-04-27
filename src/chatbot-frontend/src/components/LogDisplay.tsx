import React from 'react';

interface LogDisplayProps {
  logs: string;
  title?: string;
}

const LogDisplay: React.FC<LogDisplayProps> = ({ logs, title }) => {
  return (
    <div className="my-4">
      {title && <h4 className="text-sm font-medium text-gray-600 mb-1">{title}</h4>}
      <pre className="bg-gray-900 text-gray-200 text-xs p-4 rounded-md overflow-x-auto font-mono whitespace-pre-wrap break-words">
        {/* Using whitespace-pre-wrap and break-words helps handle long lines without horizontal overflow */}
        {logs || 'No logs to display.'}
      </pre>
    </div>
  );
};

export default LogDisplay;
