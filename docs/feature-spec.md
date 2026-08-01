# CloudRead — Feature Specification
### A cloud-native PDF reading app with immersive customization (mobile + web)

---

## 1. Core Concept

A reading platform where users upload PDFs once, then access them from any device — phone, tablet, or browser — without needing the physical file stored locally. The reading experience is fully customizable (fonts, themes, backgrounds), closer to Wattpad/Kindle than a plain PDF viewer.

**One-line pitch:** "Upload once, read anywhere, make every book feel like yours."

---

## 2. Core Feature Pillars

### 2.1 Cloud Library & Sync
- Upload PDFs from device, Google Drive, Dropbox, or a URL
- Files stored in cloud object storage (e.g., S3/GCS), streamed on demand — no full local copy required
- Reading position, bookmarks, highlights, and notes sync in real time across devices
- Offline mode: user can explicitly "download for offline" a book; auto-cleans cache based on storage limits
- Library organization: folders/shelves, tags, custom covers, recently read, favorites

### 2.2 Reading Experience Customization
- **Font control:** swap typeface (serif/sans/dyslexia-friendly), adjust size, line spacing, letter spacing, justification
- **Theme engine:** solid color backgrounds (light, dark, sepia, night, custom hex) + designed "theme packs" (paper texture, gradient, seasonal)
- **Layout modes:** scroll vs. paginated, single vs. double page (tablet/web), margins
- **Re-flow engine:** since source is PDF (fixed layout), this needs either:
  - A **text-reflow mode** that extracts text/structure from the PDF and re-renders it in the chosen font/theme (like an EPUB), OR
  - A **fixed-layout mode** with only theme/background/brightness changes (page image/vector untouched)
  - Recommend supporting both, with automatic detection of whether a PDF is "reflowable" (text-based) or must stay fixed (scanned/image-based)

### 2.3 Reading Tools
- In-line highlighting (multi-color) and sticky notes
- Bookmarks and "continue reading" per book
- Full-text search within a book and across library
- Table of contents auto-detected from PDF outline/bookmarks
- Reading progress bar + estimated time remaining
- Text-to-speech (accessibility + commute use case)
- Dictionary/definition lookup on word tap

### 2.4 Social / Wattpad-like Layer (optional differentiator)
- Public/private shelves users can share
- Reading stats & streaks (gamification: days read, books finished)
- Reviews/ratings, comments per book or per chapter
- Book clubs / group reading with shared annotations
- Follow other readers, see their shelves

### 2.5 Account & Access
- Cross-platform auth (email, Google, Apple)
- Storage tiers (free with cap, paid for more storage/offline books)
- Device management (see/revoke logged-in devices)

---

## 3. Suggested Phases (MVP → Full Vision)

| Phase | Focus | Key Deliverables |
|---|---|---|
| **MVP** | Core cloud reading | Upload, cloud sync, basic reader (theme/background/font size), progress sync |
| **Phase 2** | Personalization | Full font engine, reflow mode, highlights/notes, TTS |
| **Phase 3** | Social layer | Public shelves, reviews, streaks, book clubs |
| **Phase 4** | Monetization & scale | Storage tiers, offline optimization, publisher/author tools |

---

## 4. Technical Considerations

- **PDF rendering:** PDF.js (web) works well; mobile needs a native renderer (PDFKit on iOS, PdfRenderer/MuPDF on Android) or a shared cross-platform engine (e.g., PSPDFKit, or open-source MuPDF via a Flutter/React Native bridge)
- **Reflow challenge:** true text-reflow from PDF is non-trivial — PDFs don't have semantic structure like EPUB. Options:
  - Extract text via layout-aware parsing (e.g., PyMuPDF, pdf.js text layer) and rebuild paragraphs heuristically
  - Offer reflow only for "clean" text PDFs, gracefully fall back to fixed-layout+theme-only for scanned/complex PDFs
- **Sync backend:** WebSocket or periodic sync for reading position/annotations; conflict resolution needed if user reads offline on two devices
- **Storage costs:** PDFs can be large — consider compression, tiered storage (hot/cold), and CDN delivery for fast opens

---

## 5. Open Questions to Resolve Next
- Is the social/Wattpad layer core to the vision, or a later add-on?
- Should this support formats beyond PDF (EPUB, MOBI) for a "one library" experience?
- Free tier storage limit — what's sustainable given PDF file sizes?
- Native apps (Swift/Kotlin) vs. cross-platform (React Native/Flutter) for mobile, given PDF rendering complexity?

---

*Next steps: once these are settled, this doc can evolve into user flow diagrams, wireframes, and a technical architecture doc.*
