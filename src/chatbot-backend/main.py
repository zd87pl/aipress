import os
import json
from fastapi import FastAPI, HTTPException, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel
import uvicorn
import requests # Import requests

# Firebase Admin
import firebase_admin
from firebase_admin import credentials, auth

# Google Cloud / Vertex AI
import google.auth
import vertexai
from vertexai.generative_models import GenerativeModel, Part

# --- Configuration ---
# Load from environment variables
GCP_PROJECT_ID = os.getenv("GCP_PROJECT_ID")
GCP_LOCATION = os.getenv("GCP_LOCATION", "us-central1") # Default location
GEMINI_MODEL_NAME = os.getenv("GEMINI_MODEL_NAME", "gemini-1.5-flash-001") # Default model
CONTROL_PLANE_URL = os.getenv("CONTROL_PLANE_URL") # URL for the control plane API

# Validate configuration
if not GCP_PROJECT_ID:
    raise ValueError("GCP_PROJECT_ID environment variable not set.")
# Add validation for CONTROL_PLANE_URL if critical for startup
# if not CONTROL_PLANE_URL:
#    raise ValueError("CONTROL_PLANE_URL environment variable not set.")

print(f"Initializing Vertex AI for Project: {GCP_PROJECT_ID}, Location: {GCP_LOCATION}")
try:
    # Initialize Vertex AI SDK
    credentials, project_id = google.auth.default()
    vertexai.init(project=GCP_PROJECT_ID, location=GCP_LOCATION, credentials=credentials)
    print("Vertex AI initialized successfully.")
except Exception as e:
    print(f"Error initializing Vertex AI: {e}")
    # raise

# Initialize Gemini model
try:
    gemini_model = GenerativeModel(GEMINI_MODEL_NAME)
    print(f"Gemini model '{GEMINI_MODEL_NAME}' loaded successfully.")
except Exception as e:
    print(f"Error loading Gemini model '{GEMINI_MODEL_NAME}': {e}")
    # raise

# Initialize Firebase Admin SDK
try:
    firebase_admin.initialize_app()
    print("Firebase Admin SDK initialized successfully.")
except Exception as e:
    print(f"Error initializing Firebase Admin SDK: {e}")
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
# Note: Using Part directly might be complex if not needed; simple dicts might suffice for history if structure is simple
class HistoryPart(BaseModel):
     text: str

class HistoryItem(BaseModel):
    role: str # 'user' or 'model'
    parts: list[HistoryPart]

class ChatMessageInput(BaseModel):
    message: str
    history: list[HistoryItem] = [] # Add conversation history
    tenant_id: str | None = None # Add tenant_id

class ChatMessageOutput(BaseModel):
    response: str
    # Optionally add action details if needed later
    # action_taken: dict | None = None


# --- Gemini Interaction ---
async def get_gemini_response(prompt_parts: list) -> str:
    """Sends structured prompt parts to Gemini and returns the text response."""
    if not gemini_model:
         raise HTTPException(status_code=500, detail="Gemini model not initialized.")
    try:
        print(f"Sending prompt to Gemini (first part): {prompt_parts[0]}...") # Log first part
        # Use generate_content_async with a list of Parts or strings
        response = await gemini_model.generate_content_async(prompt_parts) 
        print("Received response from Gemini.")
        
        if response.candidates and response.candidates[0].content.parts:
             # Assuming the response is primarily text
             full_response_text = "".join(part.text for part in response.candidates[0].content.parts if hasattr(part, 'text'))
             return full_response_text
        else:
             print("Gemini response was empty or blocked.")
             # Check for finish_reason if available: response.candidates[0].finish_reason
             # Check for safety_ratings: response.candidates[0].safety_ratings
             return "I'm sorry, I couldn't generate a response for that."
    except Exception as e:
        print(f"Error interacting with Gemini: {e}")
        raise HTTPException(status_code=500, detail=f"Error communicating with AI model: {e}")


# --- Authentication Dependency ---
auth_scheme = HTTPBearer()

async def verify_token(credentials: HTTPAuthorizationCredentials = Depends(auth_scheme)):
    """Dependency function to verify Firebase ID token."""
    token = credentials.credentials
    try:
        decoded_token = auth.verify_id_token(token, check_revoked=True)
        print(f"Token verified for UID: {decoded_token.get('uid')}")
        return decoded_token 
    except auth.RevokedIdTokenError:
        raise HTTPException(status_code=401, detail="Token has been revoked.")
    except auth.InvalidIdTokenError:
        raise HTTPException(status_code=401, detail="Invalid ID token.")
    except Exception as e:
        print(f"Error verifying token: {e}")
        raise HTTPException(status_code=401, detail="Could not verify token.")


# --- API Endpoints ---
@app.post("/chat", response_model=ChatMessageOutput)
async def handle_chat_message(
    chat_input: ChatMessageInput, 
    # user: dict = Depends(verify_token) # Temporarily disabled auth dependency for testing
):
    """
    Handles incoming chat messages (authentication temporarily disabled), 
    gets response from Gemini, and potentially interprets actions.
    """
    # Mock user ID for testing when auth is disabled
    user_uid = "mock-user-for-testing" 
    tenant_id = chat_input.tenant_id # Get tenant_id from input
    print(f"Handling chat for user: {user_uid}, tenant: {tenant_id}")

    # --- Build Prompt for Gemini ---
    system_prompt = """You are AIPress Bot, a helpful assistant for managing WordPress sites hosted on the AIPress platform. 
You can help users create sites, check logs, view billing, and delete sites.
Your user ID is {user_uid}. The current site context (tenant ID) is {tenant_id}.

Available Actions (respond ONLY with a single JSON object containing 'action' and 'params' if an action is required, otherwise respond conversationally):
- Create Site: {{"action": "CREATE_SITE", "params": {{"name": "<site_name>"}}}} (Ask for name if not provided)
- Get Logs: {{"action": "GET_LOGS", "params": {{"filter": "<optional_filter>", "time_range": "<optional_time>"}}}} (Requires tenant_id context)
- Get Billing: {{"action": "GET_BILLING", "params": {{}}}} (Requires tenant_id context)
- Delete Site: {{"action": "DELETE_SITE", "params": {{"confirm": true}}}} (Requires tenant_id context and explicit confirmation)

If the user asks to perform an action but is missing information (like site name or confirmation), ask for the missing information.
If the user context (tenant_id) is required for an action but not provided in the current context, state that you need the site context first (do not invent a tenant_id).
Do not perform actions without necessary information or confirmation.
---
"""
    formatted_system_prompt = system_prompt.format(
        user_uid=user_uid, 
        tenant_id=tenant_id or "None"
    )

    # Prepare history in the format expected by Gemini SDK (list of Parts or structured content)
    # Assuming simple text parts for now
    prompt_history = []
    for item in chat_input.history:
        if item.parts and item.parts[0].text:
            prompt_history.append(Part.from_text(f"{item.role.capitalize()}: {item.parts[0].text}"))
            
    # Combine system prompt, history, and new user message
    prompt_parts = [Part.from_text(formatted_system_prompt)] + prompt_history + [Part.from_text(f"User: {chat_input.message}")]

    try:
        ai_response_text = await get_gemini_response(prompt_parts)
        
        action_data = None
        processed_response = ai_response_text # Default to AI's text response

        # --- Basic Action Parsing Placeholder ---
        try:
            # Attempt to parse if response looks like JSON action
            if ai_response_text.strip().startswith("{") and ai_response_text.strip().endswith("}"):
                 parsed_json = json.loads(ai_response_text)
                 if isinstance(parsed_json, dict) and "action" in parsed_json:
                      action_data = parsed_json
                      print(f"Detected action: {action_data}")
                      
                      # Placeholder: Validate action and params
                      action_name = action_data.get("action")
                      action_params = action_data.get("params", {})

                      # Example check: Actions requiring tenant_id
                      if action_name in ["GET_LOGS", "GET_BILLING", "DELETE_SITE"] and not tenant_id:
                           processed_response = "I need to know which site you're referring to. Please provide the site context or ID."
                           action_data = None # Prevent execution
                      # Example check: Delete confirmation
                      elif action_name == "DELETE_SITE" and not action_params.get("confirm"):
                           processed_response = "Are you absolutely sure you want to delete this site? This cannot be undone. Please confirm."
                           action_data = None # Prevent execution
                      else:
                           # TODO: Call Control Plane API (requires CONTROL_PLANE_URL and auth strategy for CP)
                           # if CONTROL_PLANE_URL and action_name == "CREATE_SITE": ...
                           # elif CONTROL_PLANE_URL and action_name == "GET_LOGS": ... etc.
                           print(f"TODO: Execute action '{action_name}' via Control Plane API with params: {action_params}")
                           processed_response = f"Okay, proceeding with action '{action_name}'. (Execution simulation)" # Simulate success for now
                           # Handle actual CP response later

        except json.JSONDecodeError:
             # Not a JSON action, treat as regular text
             pass 
        except Exception as e:
             print(f"Error during action processing: {e}")
             processed_response = "An error occurred while trying to process the requested action."
        # --- End Action Parsing Placeholder ---

        return ChatMessageOutput(response=processed_response)

    except HTTPException as http_exc:
        # Re-raise HTTPExceptions from get_gemini_response or verify_token
        raise http_exc
    except Exception as e:
        print(f"Error in /chat endpoint: {e}")
        raise HTTPException(status_code=500, detail="An internal error occurred processing the chat message.")


if __name__ == "__main__":
    # Note: Use 'uvicorn main:app --reload' for development
    uvicorn.run(app, host="0.0.0.0", port=8080)
