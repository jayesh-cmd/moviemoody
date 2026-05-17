# Movie Moody (Film Oracle)

A smart, minimalist movie and TV show recommendation engine. It uses Anthropic's Claude to analyze your current mood and suggests the perfect titles to match, enriched with real-time data (posters, genres, IMDB ratings) from TMDB and OMDb.

## Architecture
- **Backend:** FastAPI (Python) handles the API integrations (`/api/recommend` endpoint) and is structured to be deployed serverlessly on Vercel.
- **Web App:** A responsive, native-feeling WebUI (`index.html`) using HTML/CSS/JS. It mimics the beautiful iOS glassmorphism and carousel animations.
- **iOS App:** SwiftUI frontend (`mood.swift`) featuring dynamic spring animations and native 3D carousels.
- **AI/Data Sources:** Claude 3.5 Sonnet (for reasoning), TMDB API (for posters and metadata), OMDb API (for IMDB ratings).

---

## 🚀 How to Run & Deploy

### 1. Backend & Web App (Vercel Deployment)
The easiest way to host both the backend API and the web app is via Vercel.

1. Ensure all files (`api/index.py`, `index.html`, `requirements.txt`, `vercel.json`) are pushed to your GitHub repository.
2. In your Vercel Dashboard, import the repository.
3. In the Vercel **Environment Variables** settings during setup, add:
   - `CLAUDE_KEY`="your_anthropic_key"
   - `OMDB_KEY`="your_omdb_key"
   - `TMDB_KEY`="your_tmdb_key"
4. Click **Deploy**. Vercel will host `index.html` as your web frontend and run `api/index.py` as your serverless backend.
5. **Web Analytics:** Once deployed, go to your Vercel project's **Analytics** tab and enable Web Analytics. Vercel will track visitor metrics automatically (the script is already included in `index.html`).

*To use the Web App, just visit your new Vercel domain (e.g., `https://your-project.vercel.app`) from any desktop or mobile browser!*

### 2. iOS App (SwiftUI)
To run the native iOS app:

1. Open `mood.swift` in your Xcode project.
2. Locate `private let SERVER_URL` at the top of the file.
3. **If testing locally with a local server:** Set it to your Mac's IP (e.g., `http://192.168.1.5:8000`).
4. **If using your Vercel production server:** Set it to your Vercel domain (e.g., `https://your-project.vercel.app`).
5. Build and run on your iPhone or iOS Simulator.

### Local Development Server (Optional)
If you wish to test the backend/web app locally without deploying:

```bash
# Install dependencies
pip install -r requirements.txt

# Create your .env file
cp .env.example .env # (and fill in your API keys)

# Run the server locally pointing to the new Vercel-ready path
uvicorn api.index:app --reload --host 0.0.0.0
```
Then, you can open `index.html` in your browser. It is programmed to detect that it's running locally and will automatically connect to `http://localhost:8000/api/recommend`.
