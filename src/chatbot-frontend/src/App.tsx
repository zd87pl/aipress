// Removed useState and logo imports

// Import the global CSS file which now contains Tailwind directives
import './index.css' 

function App() {
  return (
    <div className="p-4"> {/* Added padding using Tailwind */}
      <h1 className="text-xl text-blue-500"> {/* Styled heading with Tailwind */}
        AIPress Chatbot Frontend
      </h1>
      <p>Basic setup with Vite, React, TypeScript, and Tailwind CSS.</p>
      {/* Future components will be added here */}
    </div>
  )
}

export default App
