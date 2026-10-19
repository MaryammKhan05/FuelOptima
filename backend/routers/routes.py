"""
routers/routes.py
Proxies Google Routes API. Guarantees alternative routes (at least 3 routes whenever possible).
"""
import math
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
    Guarantees at least 3 distinct routes whenever feasible.
    """
    headers = {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": settings.GOOGLE_API_KEY,
        "X-Goog-FieldMask": "routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline,routes.description",
    }

    base_body = {
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
    }

    routes = []
    seen_polylines = set()

    async with httpx.AsyncClient(timeout=20.0) as client:
        # 1. Primary Request (Default traffic-aware with alternatives)
        try:
            r = await client.post(GOOGLE_ROUTES_URL, json=base_body, headers=headers)
        except httpx.RequestError as e:
            raise HTTPException(status_code=502, detail=f"Google unreachable: {e}")

        if r.status_code != 200:
            raise HTTPException(
                status_code=r.status_code,
                detail=f"Google Routes error: {r.text}",
            )

        data = r.json()
        for route in data.get("routes", []):
            poly = route.get("polyline", {}).get("encodedPolyline")
            if poly and poly not in seen_polylines:
                seen_polylines.add(poly)
                routes.append(route)

        # 2. If fewer than 3 routes, try modifiers (avoid highways, avoid tolls)
        if len(routes) < 3:
            modifiers_to_try = [
                {"avoidHighways": True},
                {"avoidTolls": True},
            ]
            for modifier in modifiers_to_try:
                mod_body = dict(base_body)
                mod_body["routeModifiers"] = modifier
                try:
                    r_mod = await client.post(GOOGLE_ROUTES_URL, json=mod_body, headers=headers)
                    if r_mod.status_code == 200:
                        for route in r_mod.json().get("routes", []):
                            poly = route.get("polyline", {}).get("encodedPolyline")
                            if poly and poly not in seen_polylines:
                                seen_polylines.add(poly)
                                routes.append(route)
                                if len(routes) >= 3:
                                    break
                except Exception:
                    pass
                if len(routes) >= 3:
                    break

        # 3. If still fewer than 3 routes, try via perpendicular midpoint offset waypoints
        if len(routes) < 3:
            s_lat, s_lng = req.source.lat, req.source.lng
            d_lat, d_lng = req.destination.lat, req.destination.lng

            mid_lat = (s_lat + d_lat) / 2.0
            mid_lng = (s_lng + d_lng) / 2.0
            delta_lat = d_lat - s_lat
            delta_lng = d_lng - s_lng

            dist_approx = math.sqrt(delta_lat ** 2 + delta_lng ** 2)
            if dist_approx > 0.005:
                # Perpendicular offsets left and right (~15-20% of distance)
                scale = min(0.20, max(0.08, 0.015 / dist_approx))
                offsets = [
                    (mid_lat - delta_lng * scale, mid_lng + delta_lat * scale),
                    (mid_lat + delta_lng * scale, mid_lng - delta_lat * scale),
                ]

                for off_lat, off_lng in offsets:
                    waypoint_body = {
                        "origin": base_body["origin"],
                        "destination": base_body["destination"],
                        "intermediates": [
                            {"location": {"latLng": {"latitude": off_lat, "longitude": off_lng}}}
                        ],
                        "travelMode": "DRIVE",
                        "routingPreference": "TRAFFIC_AWARE",
                    }
                    try:
                        r_wp = await client.post(GOOGLE_ROUTES_URL, json=waypoint_body, headers=headers)
                        if r_wp.status_code == 200:
                            for route in r_wp.json().get("routes", []):
                                poly = route.get("polyline", {}).get("encodedPolyline")
                                if poly and poly not in seen_polylines:
                                    seen_polylines.add(poly)
                                    routes.append(route)
                                    if len(routes) >= 3:
                                        break
                    except Exception:
                        pass
                    if len(routes) >= 3:
                        break

    return {"routes": routes}