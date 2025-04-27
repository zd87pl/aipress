from fastapi import FastAPI
import uvicorn

app = FastAPI(
    title="AIPress Chatbot Backend",
    description="Handles user chat interactions, AI integration, and communication with the Control Plane.",
    version="0.1.0",
)

@app.get("/")
async def read_root():
    """Root endpoint for health check."""
    return {"message": "AIPress Chatbot Backend is running."}

# Placeholder for future endpoints
# @app.post("/chat")
# async def handle_chat_message(message: dict):
#     # TODO: Implement message handling, AI interaction, Control Plane communication
#     return {"response": "Message received (not processed yet)"}

if __name__ == "__main__":
    # Note: Use 'uvicorn main:app --reload' for development
    uvicorn.run(app, host="0.0.0.0", port=8080)
