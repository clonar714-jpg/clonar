import os
from dotenv import load_dotenv

# Force load the .env from project root
dotenv_path = os.path.join(os.path.dirname(__file__), "..", ".env")
load_dotenv(dotenv_path=dotenv_path)

print("SERPAPI_KEY =", os.getenv("SERPAPI_KEY"))
print("SERPAPI_ENDPOINT =", os.getenv("SERPAPI_ENDPOINT"))
