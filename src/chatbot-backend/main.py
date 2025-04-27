import os
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import uvicorn
import google.auth
import vertexai
from vertexai.generative_models import GenerativeModel, Part

# --- Configuration ---
# Load from environment variables
GCP_PROJECT_ID = os.getenv("GCP_PROJECT_ID")
GCP_LOCATION = os.getenv("GCP_LOCATION", "us-central1") # Default location
GEMINI_MODEL_NAME = os.getenv("GEMINI_MODEL_NAME", "gemini-1.5-flash-001") # Default model

# Validate configuration
if not GCP_PROJECT_ID:
    raise ValueError("GCP_PROJECT_ID environment variable not set.")

print(f"Initializing Vertex AI for Project: {GCP_PROJECT_ID}, Location: {GCP_LOCATION}")
try:
    # Initialize Vertex AI SDK
    credentials, project_id = google.auth.default()
    vertexai.init(project=GCP_PROJECT_ID, location=GCP_LOCATION, credentials=credentials)
    print("Vertex AI initialized successfully.")
except Exception as e:
    print(f"Error initializing Vertex AI: {e}")
    # Depending on deployment strategy, might want to raise error or just log
    # raise

# Initialize Gemini model
try:
    gemini_model = GenerativeModel(GEMINI_MODEL_NAME)
    print(f"Gemini model '{GEMINI_MODEL_NAME}' loaded successfully.")
except Exception as e:
    print(f"Error loading Gemini model '{GEMINI_MODEL_NAME}': {e}")
    # raise

app = FastAPI(
    title="AIPress Chatbot Backend",
    description="Handles user chat interactions, AI integration, and communication with the Control Plane.",
    version="0.1.0",
)

@app.get("/")
async def read_root():
    """Root endpoint for health check."""
    return {"message": "AIPress Chatbot Backend is running."}


# --- Pydantic Models ---
class ChatMessageInput(BaseModel):
    message: str
    # Add conversation history, user info, tenant_id etc. later
    # history: list[dict] = [] 
    # user_id: str
    # tenant_id: str | None = None 

class ChatMessageOutput(BaseModel):
    response: str
    # Add action details if needed later
    # action: dict | None = None


# --- Gemini Interaction (Basic Example) ---
async def get_gemini_response(prompt: str) -> str:
    """Sends a prompt to Gemini and returns the text response."""
    if not gemini_model:
         raise HTTPException(status_code=500, detail="Gemini model not initialized.")
    try:
        print(f"Sending prompt to Gemini: {prompt[:200]}...") # Log truncated prompt
        response = await gemini_model.generate_content_async(prompt)
        print("Received response from Gemini.")
        # Handle potential lack of content or safety blocks later
        if response.candidates and response.candidates[0].content.parts:
             return response.candidates[0].content.parts[0].text
        else:
             print("Gemini response was empty or blocked.")
             return "I'm sorry, I couldn't generate a response for that."
    except Exception as e:
        print(f"Error interacting with Gemini: {e}")
        raise HTTPException(status_code=500, detail=f"Error communicating with AI model: {e}")


# --- API Endpoints ---
@app.post("/chat", response_model=ChatMessageOutput)
async def handle_chat_message(chat_input: ChatMessageInput):
    """
    Handles incoming chat messages, gets response from Gemini, 
    and (later) interprets actions.
    """
    # TODO: Build a more sophisticated prompt including history, user context, 
    #       defined actions Gemini can take, tenant_id etc.
    prompt = f"User message: {chat_input.message}\n\nRespond conversationally." 

    try:
        ai_response = await get_gemini_response(prompt)
        
        # TODO: Implement Action parsing here
        # If ai_response contains an action command:
        #   - Validate action and parameters
        #   - Call Control Plane API
        #   - Format Control Plane result for user (or send back to Gemini)
        #   - Return action details in output if needed
        # Else (just text response):
        return ChatMessageOutput(response=ai_response)

    except HTTPException as http_exc:
        # Re-raise HTTPExceptions from get_gemini_response
        raise http_exc
    except Exception as e:
        print(f"Error in /chat endpoint: {e}")
        raise HTTPException(status_code=500, detail="An internal error occurred processing the chat message.")


if __name__ == "__main__":
    # Note: Use 'uvicorn main:app --reload' for development
    uvicorn.run(app, host="0.0.0.0", port=8080)
