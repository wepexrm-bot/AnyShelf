# AnyShelf

A cloud-native PDF reading app — upload once, read anywhere, on any device. The reading experience is fully customizable (fonts, themes, layout modes) and every position, highlight, and note syncs across devices.

The web client and API are branded **AnyShelf**; the Flutter mobile client is still internally named *CloudRead*.

## Features

### Cloud library & sync
- **Upload PDFs** with optional cover art; scanned/image PDFs are handled via OCR fallback.
- **Edit book details** — change the name, author, genre, and cover image anytime from a 3-dot menu on the cover.
- **Delete books** — removes the PDF, cover, extracted text, and all progress/annotations.
- **Add to shelf** from the same menu; create shelves on the fly.
- **Library organization** — genre filter, sort by newest/oldest, full-text search.
- Reading position, bookmarks, highlights, and notes **sync to the backend** and resume anywhere.

### PDF extraction pipeline
- **Layout-aware extraction** — text reflow, column/reading-order detection, and paragraph/heading reconstruction with a confidence score (`reflow_confidence`).
- **OCR fallback** — scanned/image-only PDFs are recognized with Tesseract.
- **Native PDF annotation import** — highlights and margin notes already in the PDF are imported as text-anchored rows.
- Extraction runs in the background; the reader shows live progress and switches to the reflowed text when it's ready.

### Reader
- **Two reading modes** — scroll and paginate, with single-page and two-page (book flip) layouts.
- **Customizable appearance** — multiple typefaces, size, line spacing, margins, and themes (sepia, dark, night, paper, and more), persisted per user.
- **Smart fallback** — reflow mode when the extracted text is high-confidence, otherwise fixed-layout PDF rendering (PDF.js on web, Syncfusion PDF viewer on mobile).

### Annotations
- Multi-color **highlights**, sticky **notes**, and **bookmarks**, synced per book.
- Works in both scroll and paginated views; imported PDF annotations are reconciled into the reflowed text.

### Continue Reading
- A featured **hero card** for your in-progress book: cover, position, and Resume/Notes actions.
- **Auto-rotates** through the queue in a shuffled order (never repeats back-to-back), pausing on hover or while off-screen.
- Circular arrow for manual cycling with an "X of N" counter; falls back to unstarted books when nothing is in progress.

### Shelves & social
- Create **shelves** with custom colors and banner images; add/remove books.
- **Public shelves** you can share and follow.
- **Follow readers**, see activity (finished a book, highlighted, shared a shelf).

### Stats & streaks
- Books completed, total reading time, current/best streak, monthly activity — driven by logged reading sessions.

### Accounts
- Email **verification**, resend, **forgot/reset/change password**, profile banner, display name.

### Mobile extras
- **Forced updates** — the app compares the installed version against the latest GitHub release and blocks stale APKs with a non-dismissible update dialog.
- **Warm-up ping** on launch so the first request doesn't wait out a cold server start.

## Architecture

```
┌─────────────┐   ┌─────────────┐
│   Flutter   │   │   React     │        Clients (mobile + web)
│   (mobile)  │   │   (web)     │
└──────┬──────┘   └──────┬──────┘
       │                 │  JSON over HTTPS (JWT auth)
       └────────┬────────┘
                ▼
        ┌───────────────┐
        │    FastAPI    │      backend/ — API, auth, cloud sync,
        │  (Python)     │      PDF extraction pipeline, mail
        └──┬───────┬────┘
           │       │
           ▼       ▼
   ┌───────────┐  ┌──────────────────────┐
   │ PostgreSQL│  │ S3-compatible storage │  books/ covers/
   │ (metadata,│  │ (MinIO locally, S3/R2 │  structured/ banners/
   │ progress, │  │  in production)       │
   │ settings…)│  └──────────────────────┘
   └───────────┘
```

### Backend (`backend/`)

| Path | Responsibility |
| --- | --- |
| `app/main.py` | FastAPI app, CORS, router wiring, `/health` (GET + HEAD for uptime monitors) |
| `app/config.py` | Environment-driven settings (DB, S3/MinIO, JWT, SMTP/Brevo, OCR) via pydantic-settings |
| `app/db/database.py` | SQLAlchemy engine/session (pooled, with `pool_pre_ping` + `pool_recycle`) |
| `app/core/models.py` | ORM models (see data model below) |
| `app/core/storage.py` | S3-compatible upload/presign/delete wrapper |
| `app/core/mail.py` | Brevo HTTP API (preferred) with SMTP fallback; verification/reset codes |
| `app/core/extraction/` | `pipeline`, `extractor`, `ocr`, `reading_order`, `structure`, `annotations` |
| `app/api/routes/` | `auth`, `books`, `sync`, `settings`, `shelves`, `stats`, `social` |
| `app/api/deps.py` | Auth + DB dependencies |

### Data model

| Table | Purpose |
| --- | --- |
| `users` | account, email verification + password-reset tokens, profile banner, display name |
| `books` | title/author/genre, object-storage keys (PDF, cover, structured JSON), extraction metadata |
| `reading_progress` | page + reflow offset per user/book |
| `annotations` | highlights / notes / bookmarks, user-created or imported from the PDF |
| `shelves` + `shelf_books` | collections of books with color + banner |
| `shelf_follows` | followed public shelves |
| `user_settings` | per-user reading preferences (theme, font, size, spacing, margins, mode, layout) |
| `user_stats` | books completed, pages, minutes, streaks |
| `reading_sessions` | raw session data behind stats & streaks |
| `follows` | user-to-user follows |
| `activity` | community feed events |

### Extraction pipeline

PDF text extraction and reflow reconstruction live in `backend/app/core/extraction/`:

- `extractor.py` — layout-aware text/glyph extraction (PyMuPDF)
- `ocr.py` — OCR fallback for scanned/image-based PDFs (Tesseract)
- `reading_order.py` — column/block detection and ordering
- `structure.py` — paragraph/heading reconstruction and confidence scoring
- `annotations.py` — import native PDF highlights/notes as text-anchored rows
- `pipeline.py` — orchestrates the above, writes structured JSON to storage

Uploads return immediately with `extraction_status: pending`; extraction runs in the background and produces a reflow-ready structured JSON (stored in object storage). The reader enables reflow when `reflow_confidence >= 0.5`, otherwise falls back to fixed-layout page rendering.

### Web client (`web/`)

React SPA (react-router-dom). `App.jsx` wires routes behind an auth gate. Key components: `Library` (continue reading, shelves, stats, recently added), `BooksPage` (grid + filters + 3-dot book menu), `Reader` + `BookPaginate` (scroll/paginate, PDF.js + react-pageflip), `ShelvesPage`, `ProfilePage`, `SettingsPage`, `UploadModal`, `ThemeControls`, `ContinueReadingCarousel`, `BookActionsMenu`, `ShelfModalContext`. Auth token/user live in `localStorage`; API base is `REACT_APP_API_BASE` (defaults to `http://localhost:8000`).

### Mobile client (`mobile/`)

Flutter app (Provider state). `main.dart` gates on a saved session, warms the API, and checks for forced updates. Screens: `auth_screen`, `library_screen`, `books_screen`, `reader_screen`, `reader_appearance_sheet`, `shelves_screen`, `stats_screen`, `settings_screen`. Services in `services/` wrap the API, auth, books, shelves, stats, settings, UI mode, and update checking. The reader renders reflowed text (scroll/paginated) or fixed-layout PDF via the Syncfusion viewer. API base is `API_BASE` at build time (`--dart-define`).

## Stack

- **Backend:** Python 3.11+, FastAPI, SQLAlchemy, PostgreSQL, boto3 (S3-compatible object storage), PyMuPDF, Tesseract (OCR fallback), python-jose (JWT), pydantic-settings
- **Web:** React 18, react-router-dom, pdfjs-dist (PDF rendering), react-pageflip (two-page flip), Material Symbols icons
- **Mobile:** Flutter (Dart), Syncfusion PDF viewer, Provider, Google Fonts, SharedPreferences
- **Email:** Brevo HTTP API with SMTP fallback

## Getting started

Prerequisites: Python 3.11+, Node 18+, Flutter SDK, PostgreSQL running, and an S3-compatible store (MinIO works great locally).

### 1. Backend

```bash
cd backend
cp .env.example .env        # configure DATABASE_URL + S3_ENDPOINT_URL/keys
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

The API runs on `http://localhost:8000` (`/docs` for the interactive OpenAPI UI, `/health` for health checks).

### 2. Web

```bash
cd web
npm install
npm start                    # CRA dev server, uses REACT_APP_API_BASE (default :8000)
```

Production build served statically (SPA fallback + `Cache-Control: no-store` on :3000):

```bash
npm run build
npm run serve
```

### 3. Mobile

```bash
cd mobile
flutter pub get
flutter run                  # API base: --dart-define=API_BASE=http://<host>:8000
```

On the Android emulator the host machine is reachable at `10.0.2.2`.

### 4. MinIO (local object storage)

Download the MinIO server binary and run it (API on :9000, console on :9001):

```bash
minio server ./minio-data --console-address :9001
```

Point `S3_ENDPOINT_URL` in `.env` at `http://localhost:9000` and create the bucket named in `S3_BUCKET` (`cloudread-books`). Production uses real S3-compatible storage instead.

## API overview

| Area | Routes |
| --- | --- |
| Auth (`/auth`) | `register`, `login`, `verify-email`, `resend-verification`, `forgot-password`, `reset-password`, `change-password`, `me`, `me/banner` (POST/DELETE) |
| Books (`/books`) | `upload` (PDF + optional cover), list, get, `{id}/progress`, `PUT {id}` (edit name/author/genre), `PUT {id}/cover`, delete |
| Reading sync (`/sync`) | `progress` (POST), `progress/{book_id}`, `annotations` (POST), `annotations/{book_id}`, `annotations/{annotation_id}` (DELETE) |
| Settings (`/settings`) | get, update — theme, font, size, spacing, margins, mode, layout |
| Shelves (`/shelves`) | CRUD, `{id}/banner`, `{id}/books/{book_id}` (add/remove), `shared/all`, `{id}/follow` (POST/DELETE) |
| Stats (`/stats`) | `sessions`, totals, `monthly` |
| Social (`/social`) | `follow`, `follow/{target_id}` (DELETE), `following`, `activity` (POST/GET) |
| Health | `/health` (GET + HEAD) |

## Versioning & releases

Mobile versioning follows the convention in `AGENTS.md`:

- Every mobile change bumps **both** the version in `mobile/pubspec.yaml` (e.g. `5.1.0`) **and** the build number after `+` (e.g. `5.1.0+16`).
- Releases are published to GitHub Releases with a tag matching the app version (e.g. `v5.1.0`) plus the signed APK. The mobile app compares its installed version against the latest GitHub release tag; a newer tag triggers the forced-update dialog.

## Deployment

- **Backend & web:** deployed from this repo (e.g. Render). The backend needs `DATABASE_URL`, S3/R2 credentials, and `JWT_SECRET` set in the environment. `/health` is available for uptime monitors.
- **Mobile:** signed APKs are uploaded to GitHub Releases; version tags drive forced updates.
- Uptime monitor targets `https://<api-host>/health`.

## Tests

Backend has a pytest suite covering the extraction pipeline and stats:

```bash
cd backend
pytest
```

## Product spec

See `docs/feature-spec.md` for the full product spec and roadmap.

## License

Released under the [MIT License](LICENSE). Copyright (c) 2026 WepexRM.
