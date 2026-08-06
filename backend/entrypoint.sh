#!/bin/sh
set -e

echo "Initializing database schema..."
python -c "from app.db.database import Base, engine; import app.core.models; Base.metadata.create_all(engine)"
echo "Applying schema migrations..."
python -c "from app.db.database import run_migrations; run_migrations()"

echo "Starting API on port ${PORT:-8000}..."
exec uvicorn app.main:app --host 0.0.0.0 --port "${PORT:-8000}" --workers 1
