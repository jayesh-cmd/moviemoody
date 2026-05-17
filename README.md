# Movie Moody (Film Oracle)

A smart, minimalist movie and TV show recommendation engine. It uses Anthropic's Claude to analyze your current mood and suggests the perfect titles to match, enriched with real-time data (posters, genres, IMDB ratings) from TMDB and OMDb.

## Architecture
- **Backend:** FastAPI (Python) handles the API integrations (`/recommend` endpoint)
- **Frontend:** SwiftUI (iOS/macOS) featuring dynamic spring animations, 3D carousel UI, and native glassmorphism.
- **AI/Data Sources:** Claude 3.5 Sonnet (for reasoning), TMDB API (for posters and metadata), OMDb API (for IMDB ratings).

## Setup & Running

### 1. Backend (Python)
Ensure you have Python 3.11+ installed.

```bash
# Install dependencies
pip install -r requirements.txt

# Create your .env file
cp .env.example .env

# Add your API keys to .env
CLAUDE_KEY="your_anthropic_key"
OMDB_KEY="your_omdb_key"
TMDB_KEY="your_tmdb_key"

# Run the server on your local network
uvicorn main:app --reload --host 0.0.0.0
```

### 2. Frontend (iOS)
- Open `mood.swift` in your Xcode project.
- Ensure the `SERVER_URL` at the top of the file points to your Mac's local network IP address (e.g., `http://192.168.1.5:8000`).
- Build and run on your iPhone or iOS Simulator.
