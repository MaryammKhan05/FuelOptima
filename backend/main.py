"""
main.py
The entry point for the FuelOptima backend.
Run with:  uvicorn main:app --reload
"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from routers import places, routes, fuel

app = FastAPI(
    title="FuelOptima Backend",
    description="Proxy for Google APIs, OGRA fuel prices, and (later) ML prediction",
    version="0.1.0",
)

# ---------- CORS ----------
# This is THE fix for your Flutter Chrome CORS problem.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],          # during development — lock down later
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------- Routers ----------
app.include_router(places.router, prefix="/places", tags=["Places"])
app.include_router(routes.router, prefix="/routes", tags=["Routes"])
app.include_router(fuel.router, prefix="/fuel", tags=["Fuel"])


@app.get("/")
def root():
    return {"message": "FuelOptima backend is running"}


@app.get("/health")
def health():
    """Quick check that the server is alive."""
    return {"status": "ok"}