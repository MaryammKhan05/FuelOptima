"""
routers/routes.py
Proxies Google Routes API. Returns alternative routes between two points.
"""
import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from config import settings

router = APIRouter()

GOOGLE_ROUTES_URL = "https://routes.googleapis.com/directions/v2:computeRoutes"


class LatLng(BaseModel):
    """A simple lat/lng pair that Flutter sends in JSON."""
    lat: float
    lng: float


class RouteRequest(BaseModel):
    """What Flutter sends to /routes/compute."""
    source: LatLng
    destination: LatLng


@router.post("/compute")
async def compute_routes(req: RouteRequest):
    """
    Ask Google Routes API for routes between two points.

    Flutter calls:
        POST /routes/compute
        { "source": {"lat": 24.86, "lng": 67.00},
          "destination": {"lat": 24.90, "lng": 67.05} }
    """
    body = {
        "origin": {
            "location": {
                "latLng": {
                    "latitude": req.source.lat,
                    "longitude": req.source.lng,
                }
            }
        },
        "destination": {
            "location": {
                "latLng": {
                    "latitude": req.destination.lat,
                    "longitude": req.destination.lng,
                }
            }
        },
        "travelMode": "DRIVE",
        "computeAlternativeRoutes": True,
        "routingPreference": "TRAFFIC_AWARE",
        "fields": "routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline",
    }

    headers = {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": settings.GOOGLE_API_KEY,
    }

    async with httpx.AsyncClient(timeout=15.0) as client:
        try:
            r = await client.post(GOOGLE_ROUTES_URL, json=body, headers=headers)
        except httpx.RequestError as e:
            raise HTTPException(status_code=502, detail=f"Google unreachable: {e}")

    if r.status_code != 200:
        raise HTTPException(
            status_code=r.status_code,
            detail=f"Google Routes error: {r.text}",
        )

    return r.json()