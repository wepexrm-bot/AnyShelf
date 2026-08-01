# CloudRead

A cloud-native PDF reading app — upload once, read anywhere, with Wattpad-style font/theme customization.

## Structure

```
cloudread/
├── docs/           feature spec and product docs
├── backend/        FastAPI service — API, cloud sync, PDF extraction pipeline
├── web/             React web client
└── mobile/          Flutter mobile client (iOS + Android)
```

## Stack

- **Backend:** Python 3.11+, FastAPI, PyMuPDF (PDF parsing), Tesseract/cloud OCR (scanned PDFs), PostgreSQL (metadata), S3-compatible object storage (files)
- **Web:** React
- **Mobile:** Flutter

## Getting started

### Backend
```bash
cd backend
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

### Web
```bash
cd web
npm install
npm start
```

### Mobile
```bash
cd mobile
flutter pub get
flutter run
```

## Core pipeline

PDF text extraction and reflow reconstruction lives in `backend/app/core/extraction/`:
- `extractor.py` — layout-aware text/glyph extraction (PyMuPDF)
- `ocr.py` — OCR fallback for scanned/image-based PDFs
- `reading_order.py` — column/block detection and ordering
- `structure.py` — paragraph/heading reconstruction and confidence scoring

See `docs/feature-spec.md` for the full product spec and roadmap.
