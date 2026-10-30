# CareerPath Production Dockerfile for Google Cloud Run / Render
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Install build essentials for PyMuPDF and Pillow
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application source and data files
COPY . .

# Google Cloud Run injects the PORT environment variable
ENV PORT=8080
ENV ENVIRONMENT=production
EXPOSE 8080

CMD exec uvicorn main:app --host 0.0.0.0 --port ${PORT}
