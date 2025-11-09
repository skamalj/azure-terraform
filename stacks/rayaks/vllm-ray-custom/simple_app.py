"""
Simple Ray Serve App - Minimal Example
Just returns a response to test autoscaling
"""

import time
import logging
from fastapi import FastAPI
from ray import serve
from ray.serve import Application
from typing import Dict 

logger = logging.getLogger("ray.serve")

app = FastAPI()


@serve.deployment(
    autoscaling_config={
        "min_replicas": 0,              # Start with 0 replicas
        "max_replicas": 2,              # Scale up to 2
        "target_ongoing_requests": 50,  # Scale when 50 requests pending
    },
    max_ongoing_requests=100,          # Max 100 concurrent requests
)
@serve.ingress(app)
class SimpleAPI:
    """Simple API endpoint - no ML, just response."""
    def __init__(self, message: str = "No message passed"):
        self.message = message

    @app.get("/health")
    async def health(self):
        """Health check."""
        return {"status": "healthy"}
    
    @app.get("/test")
    async def test(self):
        """Test endpoint."""
        return {"message": "Hello from Ray Serve!"}
    
    @app.post("/slow")
    async def slow_request(self):
        """Simulate slow request to trigger autoscaling."""
        time.sleep(2)  # 2 seconds
        return {"result": "Done after 2 seconds -- " + self.message}

def build_app(message, args: Dict[str, str]) -> Application:
    return SimpleAPI.bind(message=message)

if __name__ == "__main__":
    app = build_app({})
    serve.run(app, blocking=True)
