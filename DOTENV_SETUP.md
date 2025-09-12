# Clonar App - Environment Variables Setup

This guide explains how to set up environment variables for the Clonar app using dotenv.

## Overview

The Python backend now automatically loads environment variables from a `.env` file, making it easy to configure API keys and other settings without hardcoding them in the source code.

## Setup Instructions

### 1. Install Dependencies

```bash
cd python
pip install -r requirements.txt
```

### 2. Create Environment File

Run the setup script to create a `.env` file:

```bash
python setup_env.py
```

This will create a `.env` file with placeholder values.

### 3. Configure Your API Keys

Edit the `.env` file and replace the placeholder values:

```env
# SerpAPI Configuration
SERPAPI_KEY=your_actual_serpapi_key_here
SERPAPI_ENDPOINT=https://serpapi.com/search.json

# Database Configuration (for Node.js)
DB_USER=postgres
DB_HOST=postgres
DB_NAME=clonar_db
DB_PASSWORD=password
DB_PORT=5432
```

### 4. Test the Setup

Run the test script to verify everything is working:

```bash
python test_dotenv.py
```

### 5. Start the Server

```bash
uvicorn app:app --reload --port 8000
```

### 6. Test the API

Test with a hotel query:

```bash
curl -X POST http://127.0.0.1:8000/search \
  -H "Content-Type: application/json" \
  -d '{"query":"hotels in Salt Lake City"}'
```

Test with a shopping query:

```bash
curl -X POST http://127.0.0.1:8000/search \
  -H "Content-Type: application/json" \
  -d '{"query":"sneakers under $100"}'
```

## What's Changed

### 1. Updated `app.py`

```python
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()
```

### 2. Updated `requirements.txt`

Added `python-dotenv` dependency.

### 3. Created Setup Scripts

- `setup_env.py` - Creates .env file with placeholders
- `test_dotenv.py` - Tests dotenv functionality

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `SERPAPI_KEY` | Your SerpAPI key for search functionality | Required |
| `SERPAPI_ENDPOINT` | SerpAPI endpoint URL | `https://serpapi.com/search.json` |
| `DB_USER` | PostgreSQL username | `postgres` |
| `DB_HOST` | PostgreSQL host | `postgres` |
| `DB_NAME` | Database name | `clonar_db` |
| `DB_PASSWORD` | Database password | `password` |
| `DB_PORT` | Database port | `5432` |

## Troubleshooting

### Issue: "SerpAPI key not configured"

**Solution**: Make sure you've:
1. Created a `.env` file in the `python/` directory
2. Added your real SerpAPI key to the file
3. Restarted the server after making changes

### Issue: "ModuleNotFoundError: No module named 'dotenv'"

**Solution**: Install the required dependency:
```bash
pip install python-dotenv
```

### Issue: UnicodeDecodeError when loading .env

**Solution**: Make sure the `.env` file is saved with UTF-8 encoding.

## Security Notes

- Never commit your `.env` file to version control
- The `.env` file is already in `.gitignore`
- Use `.env.example` for sharing configuration templates
- Keep your API keys secure and rotate them regularly

## Next Steps

1. Get your SerpAPI key from [serpapi.com](https://serpapi.com)
2. Add it to your `.env` file
3. Start the server and test the API
4. The app will now automatically detect hotel vs shopping queries and return appropriate results!
