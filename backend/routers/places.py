"""
routers/places.py
Proxies Google Places API (New) calls so the Flutter app never sees the API key.

New API docs: https://developers.google.com/maps/documentation/places/web-service/op-overview
"""
import httpx
from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel

from config import settings

router = APIRouter()

# Google Places API (New) uses a single base and different endpoints
PLACES_BASE = "https://places.googleapis.com/v1"


# ---------- Autocomplete ----------
class AutocompleteRequest(BaseModel):
    """What Flutter sends to /places/autocomplete."""
    input: str


@router.post("/autocomplete")
async def places_autocomplete(req: AutocompleteRequest):
    """
    Forward a Places Autocomplete request to Google (New API).

    Flutter calls:
        POST /places/autocomplete
        { "input": "Karachi" }
    """
    url = f"{PLACES_BASE}/places:autocomplete"

    body = {
        "input": req.input,
        # Restrict search to Pakistan
        "includedRegionCodes": ["pk"],
    }

    headers = {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": settings.GOOGLE_API_KEY,
        # FieldMask: which fields we want back. Narrower = cheaper.
        "X-Goog-FieldMask": "suggestions.placePrediction.placeId,"
                            "suggestions.placePrediction.text,"
                            "suggestions.placePrediction.structuredFormat",
    }

    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            r = await client.post(url, json=body, headers=headers)
        except httpx.RequestError as e:
            raise HTTPException(status_code=502, detail=f"Google unreachable: {e}")

    if r.status_code != 200:
        raise HTTPException(
            status_code=r.status_code,
            detail=f"Google Places error: {r.text}",
        )

    return r.json()


# ---------- Details ----------
class DetailsRequest(BaseModel):
    place_id: str


@router.post("/details")
async def places_details(req: DetailsRequest):
    """
    Get details (including lat/lng) for a place by its place_id.

    Flutter calls:
        POST /places/details
        { "place_id": "ChIJ..." }
    """
    url = f"{PLACES_BASE}/places/{req.place_id}"

    headers = {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": settings.GOOGLE_API_KEY,
        # Only fetch geometry + display name — keeps billing low
        "X-Goog-FieldMask": "id,displayName,formattedAddress,location",
    }

    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            r = await client.get(url, headers=headers)
        except httpx.RequestError as e:
            raise HTTPException(status_code=502, detail=f"Google unreachable: {e}")

    if r.status_code != 200:
        raise HTTPException(
            status_code=r.status_code,
            detail=f"Google Places error: {r.text}",
        )

    return r.json()


# ---------- Text Search ----------
class TextSearchRequest(BaseModel):
    text_query: str


@router.post("/textsearch")
async def places_textsearch(req: TextSearchRequest):
    """
    Free-text place search — used as fallback when autocomplete wasn't tapped.

    Flutter calls:
        POST /places/textsearch
        { "text_query": "Karachi Airport" }
    """
    url = f"{PLACES_BASE}/places:searchText"

    body = {
        "textQuery": req.text_query,
    }

    headers = {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": settings.GOOGLE_API_KEY,
        "X-Goog-FieldMask": "places.id,places.displayName,places.location",
    }

    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            r = await client.post(url, json=body, headers=headers)
        except httpx.RequestError as e:
            raise HTTPException(status_code=502, detail=f"Google unreachable: {e}")

    if r.status_code != 200:
        raise HTTPException(
            status_code=r.status_code,
            detail=f"Google Places error: {r.text}",
        )

    return r.json()