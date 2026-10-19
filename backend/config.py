import os
from dotenv import load_dotenv

load_dotenv()

class Settings:
    GOOGLE_API_KEY: str = os.getenv("GOOGLE_API_KEY", "").strip()
    SUPABASE_URL: str = os.getenv("SUPABASE_URL", "").replace("/rest/v1/", "").replace("/rest/v1", "").strip().rstrip("/")
    SUPABASE_KEY: str = os.getenv("SUPABASE_KEY", "").strip()

    if not GOOGLE_API_KEY or not SUPABASE_URL or not SUPABASE_KEY:
        raise ValueError("Missing environment variables. Check your .env file.")

settings = Settings()