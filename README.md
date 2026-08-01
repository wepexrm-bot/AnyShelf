# AnyShelf

A cloud-native PDF reading app — upload once, read anywhere, with Wattpad-style font/theme customization and full reading-progress sync across devices.

The web client and API are branded **AnyShelf**; the Flutter client is still internally named *CloudRead*.

## Features

- **PDF-only uploads** with optional cover art; scanned/image PDFs handled via OCR fallback.
- **Layout-aware extraction pipeline** — text reflow, column/reading-order detection, paragraph/heading reconstruction with a confidence score (`reflow_confidence`).
- **Two reading modes** — scroll mode and paginate mode, with single-page and two-page (book flip) layouts.
- **Reader customization** — 9 bundled fonts and multiple themes (sepia, dark, light, etc.), persisted per user.
- **Resume anywhere** — reading position syncs to the backend; Continue Reading surfaces in-progress books, with a circular arrow to cycle through them.
- **Library** — Recently Added, search, shelves (with share/follow), stats (reading sessions, monthly activity).
- **Annotations** — highlights, notes, and bookmarks synced per book.
- **Accounts** — email verification, forgot/reset password, profile banner.

## Structure

```
cloudread/
├── docs/                     feature spec and product docs
│   └── feature-spec.md
├── backend/                  FastAPI service — API, cloud sync, PDF extraction pipeline
│   ├── app/
│   │   ├── main.py           app entrypoint
│   │   ├── config.py         settings (DB, S3/MinIO, JWT, SMTP, OCR)
│   │   ├── db/               SQLAlchemy engine/session
│   │   ├── core/             models, object storage, mail, extraction pipeline
│   │   │   ├── extraction/   extractor / ocr / reading_order / structure
│   │   └── api/
│   │       ├── deps.py       auth + DB dependencies
│   │       └── routes/       auth, books, settings, shelves, social, stats, sync
│   ├── tests/                pytest suite (extraction, stats)
│   ├── requirements.txt
│   ├── Dockerfile
│   └── .env.example
├── web/                      React web client
│   ├── public/               index.html, icons, Google Fonts
│   ├── src/
│   │   ├── App.jsx           routes + shell
│   │   ├── api.js            API base (REACT_APP_API_BASE)
│   │   ├── auth.jsx          auth context (token/user in localStorage)
│   │   ├── uiMode.js         read vs library mode persistence
│   │   └── components/       Library, Reader, BookPaginate, BooksPage,
│   │                         ShelvesPage, SettingsPage, ProfilePage,
│   │                         ThemeControls, UploadModal, Sidebar, AppHeader,
│   │                         auth pages, and more
│   ├── package.json
│   └── serve.js              static server for the production build (port 3000)
└── mobile/                   Flutter mobile client (iOS + Android)
    └── lib/                  main.dart, screens (library, reader), models
```

## Stack

- **Backend:** Python 3.11+, FastAPI, SQLAlchemy, PostgreSQL (metadata), S3-compatible object storage (MinIO, bucket `cloudread-books`), PyMuPDF (PDF parsing), Tesseract (OCR fallback)
- **Web:** React 18, react-router-dom, pdfjs-dist (PDF rendering), react-pageflip (two-page flip), Material Symbols icons
- **Mobile:** Flutter

## Getting started

Prerequisites: Python 3.11+, Node 18+, PostgreSQL running, and an S3-compatible store (MinIO).

### Backend

```bash
cd backend
cp .env.example .env        # configure DB URL + MinIO endpoint/keys
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

The API runs on `http://localhost:8000`.

### Web

```bash
cd web
npm install
npm start                    # CRA dev server (uses REACT_APP_API_BASE, defaults to :8000)
```

For a production build served statically:

```bash
npm run build
npm run serve                # serves build/ on :3000 with SPA fallback + Cache-Control: no-store
```

### Mobile

```bash
cd mobile
flutter pub get
flutter run
```

## Running the full app

Run these from `D:\cloudread-project\cloudread`:

1. **MinIO (object storage):**

```bash
Start-Process "C:\Users\tirth\cloudread-minio\minio.exe" -ArgumentList 'server "C:\Users\tirth\cloudread-minio\data" --console-address :9001'
```

2. **Backend (API on :8000):**

```bash
cd backend
venv\Scripts\activate
uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload
```

3. **Web (static build on :3000):**

```bash
cd web
npm run build
npm run serve
```

Then open http://localhost:3000.

Note: `npm run serve` must run in a separate terminal from the backend. If you already have an old web server running on :3000, kill it first (`Get-Process node | Stop-Process`), else you'll get `EADDRINUSE`.

Dev-mode alternative for the web (hot reload, instead of step 3): `cd web; npm start`.

## Core pipeline

PDF text extraction and reflow reconstruction live in `backend/app/core/extraction/`:

- `extractor.py` — layout-aware text/glyph extraction (PyMuPDF)
- `ocr.py` — OCR fallback for scanned/image-based PDFs
- `reading_order.py` — column/block detection and ordering
- `structure.py` — paragraph/heading reconstruction and confidence scoring

Uploads return immediately with `extraction_status: pending`; extraction runs in the background and produces a reflow-ready structured JSON (stored in object storage). The reader enables reflow when `reflow_confidence >= 0.5`, otherwise falls back to fixed-layout page rendering.

## API overview

| Area | Routes |
| --- | --- |
| Auth | `register`, `login`, `verify-email`, `resend-verification`, `forgot-password`, `reset-password`, `change-password`, `me`, `me/banner` |
| Books | `upload` (PDF only), list, get, `progress`, delete |
| Reading | `sync/progress`, `sync/annotations` (highlights, notes, bookmarks) |
| Settings | reading prefs — theme, font family, mode (scroll/paginate), layout (single/spread) |
| Shelves | CRUD, banner, add/remove books, `shared/all`, follow/unfollow |
| Social | follow/unfollow, following, activity feed |
| Stats | reading sessions, totals, monthly activity |

See `docs/feature-spec.md` for the full product spec and roadmap.
