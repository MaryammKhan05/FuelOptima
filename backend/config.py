"""
config.py
Loads environment variables from the .env file.
Other files import from here to get their settings.
"""
import os
from dotenv import load_dotenv

# Read the .env file into the environment
load_dotenv()


class Settings:
    """All app settings in one place."""
    GOOGLE_API_KEY: str = os.getenv("GOOGLE_API_KEY", "")

    # Sanity check — if the key is missing, fail immediately
    if not GOOGLE_API_KEY:
        raise ValueError(
            "GOOGLE_API_KEY is not set. Did you create a .env file in backend/?"
        )


# A single instance other modules can import
settings = Settings()