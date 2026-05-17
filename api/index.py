import json
import httpx
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional
from dotenv import load_dotenv
import os

# Shared session — HTTP/2 enabled, browser UA to pass TMDB's WAF
_session = httpx.Client(http2=True, timeout=15.0)
_session.headers.update({
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                  "AppleWebKit/537.36 (KHTML, like Gecko) "
                  "Chrome/124.0.0.0 Safari/537.36",
    "Accept"    : "application/json",
})

load_dotenv()

CLAUDE_KEY = os.getenv("CLAUDE_KEY")
OMDB_KEY   = os.getenv("OMDB_KEY")
TMDB_KEY   = os.getenv("TMDB_KEY")

TMDB_BASE  = "https://api.tmdb.org/3"
TMDB_IMG   = "https://image.tmdb.org/t/p/w500"

app = FastAPI(title="Film Oracle API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── models ──

class MoodRequest(BaseModel):
    mood: str
    content_type: str = "movie"  # "movie" or "show"

class Movie(BaseModel):
    title:       str
    year:        Optional[str]
    poster:      Optional[str]   # from TMDB
    genres:      list[str]       # from TMDB
    overview:    Optional[str]   # from TMDB
    imdb_rating: Optional[str]   # from OMDb
    why:         Optional[str]   # from Claude


# ── helpers ──

def get_movies_from_claude(mood: str, content_type: str = "movie") -> list[dict]:
    """Ask Claude for 6 titles that match the mood."""
    if content_type == "show":
        kind        = "TV series or shows"
        kind_single = "TV series"
        note        = 'Use the exact show title as listed on streaming platforms (e.g. "Severance", "The Bear").'
    else:
        kind        = "movies"
        kind_single = "movie"
        note        = 'Use the exact theatrical title (e.g. "The Godfather", "Dune: Part Two").'

    try:
        response = _session.post(
            "https://api.anthropic.com/v1/messages",
            headers={
                "x-api-key": CLAUDE_KEY,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            },
            json={
                "model": "claude-sonnet-4-5",
                "max_tokens": 400,
                "messages": [{
                    "role": "user",
                    "content": (
                        f'You are a {kind_single} recommendation engine. The user mood: "{mood}"\n\n'
                        f"Return exactly 6 {kind} as a JSON array.\n"
                        "Platform preference: prefer Netflix originals or titles on Netflix "
                        "(aim for 3-4 out of 6); include 2-3 from other platforms (HBO, A24, Prime, Apple TV+) "
                        "for variety. Never mention platforms in the response.\n\n"
                        "Each item must have:\n"
                        '- "title": exact title as it appears in databases\n'
                        f"  {note}\n"
                        '- "year": release year as string\n'
                        '- "why": one punchy sentence (max 10 words) why it fits this mood\n\n'
                        "Return ONLY the JSON array, no markdown, no explanation."
                    ),
                }],
            },
            timeout=30.0,
        )
    except httpx.RequestError as e:
        raise HTTPException(status_code=502, detail=f"Cannot reach Claude API: {e}")

    if not response.is_success:
        raise HTTPException(status_code=502, detail=f"Claude error: {response.text}")

    text = response.json()["content"][0]["text"].strip()
    text = text.replace("```json", "").replace("```", "").strip()

    try:
        return json.loads(text)
    except json.JSONDecodeError:
        raise HTTPException(status_code=502, detail="Claude returned invalid JSON")


def fetch_tmdb(title: str, year: Optional[str]) -> Optional[dict]:
    """Search TMDB by title — returns poster, genres, overview, exact title."""
    params = {
        "api_key": TMDB_KEY,
        "query": title,
        "language": "en-US",
        "page": 1,
    }
    if year:
        params["year"] = year

    try:
        response = _session.get(f"{TMDB_BASE}/search/multi", params=params)
    except httpx.RequestError as e:
        raise HTTPException(status_code=502, detail=f"Cannot reach TMDB: {e}")
    data = response.json()

    results = data.get("results", [])
    if not results:
        return None

    # pick the first movie or tv result
    item = next(
        (r for r in results if r.get("media_type") in ("movie", "tv")),
        results[0]
    )

    poster_path = item.get("poster_path")

    return {
        "title":     item.get("title") or item.get("name"),
        "year":      (item.get("release_date") or item.get("first_air_date") or "")[:4],
        "poster":    f"{TMDB_IMG}{poster_path}" if poster_path else None,
        "overview":  item.get("overview"),
        "genre_ids": item.get("genre_ids", []),
    }


def fetch_tmdb_genres() -> dict:
    """Returns {genre_id: genre_name} for movies."""
    try:
        res = _session.get(
            f"{TMDB_BASE}/genre/movie/list",
            params={"api_key": TMDB_KEY, "language": "en-US"}
        )
    except httpx.RequestError as e:
        raise HTTPException(status_code=502, detail=f"Cannot reach TMDB: {e}")
    genres = res.json().get("genres", [])
    return {g["id"]: g["name"] for g in genres}


def fetch_omdb_rating(title: str) -> Optional[str]:
    """Fetch only the IMDB rating from OMDb by title."""
    try:
        response = _session.get(
            "https://www.omdbapi.com/",
            params={"t": title, "apikey": OMDB_KEY}
        )
    except httpx.RequestError:
        return None
    data = response.json()

    if data.get("Response") == "False":
        return None

    rating = data.get("imdbRating")
    return rating if rating and rating != "N/A" else None


def build_movie(claude_item: dict, genre_map: dict) -> Optional[dict]:
    """Combine Claude + TMDB + OMDb data into one movie object."""
    title = claude_item.get("title", "")
    year  = claude_item.get("year")
    why   = claude_item.get("why")

    tmdb = fetch_tmdb(title, year)
    if not tmdb:
        return None

    exact_title = tmdb["title"]
    imdb_rating = fetch_omdb_rating(exact_title)
    genres      = [genre_map.get(gid, "") for gid in tmdb["genre_ids"] if gid in genre_map]

    return {
        "title":       exact_title,
        "year":        tmdb["year"],
        "poster":      tmdb["poster"],       # TMDB
        "genres":      genres,               # TMDB
        "overview":    tmdb["overview"],     # TMDB
        "imdb_rating": imdb_rating,          # OMDb
        "why":         why,                  # Claude
    }


# ── endpoints ──

@app.get("/api")
def root():
    return {"status": "ok", "message": "Film Oracle API is running"}


@app.post("/api/recommend", response_model=list[Movie])
def recommend(body: MoodRequest):
    """
    Takes a mood string, returns 6 enriched movie recommendations.

    Sources:
        Claude → titles + why
        TMDB   → poster, genres, overview
        OMDb   → IMDB rating

    Body:
        { "mood": "something that feels like a rainy sunday afternoon" }
    """
    if not body.mood.strip():
        raise HTTPException(status_code=400, detail="mood cannot be empty")

    claude_titles = get_movies_from_claude(body.mood, body.content_type)
    genre_map     = fetch_tmdb_genres()

    movies = []
    for item in claude_titles:
        movie = build_movie(item, genre_map)
        if movie:
            movies.append(movie)

    if not movies:
        raise HTTPException(status_code=404, detail="No movies found")

    return movies


@app.get("/movie/{title}", response_model=Movie)
def get_movie(title: str):
    """
    Fetch a single movie by title.

    Sources:
        TMDB → poster, genres, overview
        OMDb → IMDB rating

    Params:
        title: movie name (e.g. "Inception", "Parasite")
    """
    genre_map = fetch_tmdb_genres()
    tmdb = fetch_tmdb(title, year=None)

    if not tmdb:
        raise HTTPException(status_code=404, detail=f"'{title}' not found on TMDB")

    exact_title = tmdb["title"]
    imdb_rating = fetch_omdb_rating(exact_title)
    genres      = [genre_map.get(gid, "") for gid in tmdb["genre_ids"] if gid in genre_map]

    return {
        "title":       exact_title,
        "year":        tmdb["year"],
        "poster":      tmdb["poster"],
        "genres":      genres,
        "overview":    tmdb["overview"],
        "imdb_rating": imdb_rating,
        "why":         None,
    }