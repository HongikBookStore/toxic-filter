FROM python:3.13.7-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates tar findutils \
  && rm -rf /var/lib/apt/lists/*

COPY requirements-server.txt ./
RUN pip install --no-cache-dir -r requirements-server.txt

ENV MODEL_PATH=./kcbert_model
COPY kcbert_model.tar.gz /tmp/model.tar.gz
RUN set -e; \
    mkdir -p "$MODEL_PATH" /tmp/model_extract; \
    tar --warning=no-unknown-keyword -xzf /tmp/model.tar.gz -C /tmp/model_extract; \
    rm -f /tmp/model.tar.gz; \
    if [ -f "/tmp/model_extract/config.json" ]; then \
      rm -rf "$MODEL_PATH" && mv /tmp/model_extract "$MODEL_PATH"; \
    else \
      CANDIDATE="$(find /tmp/model_extract -maxdepth 3 -type f -name config.json | head -n1)"; \
      if [ -z "$CANDIDATE" ]; then echo 'config.json not found in extracted model'; exit 1; fi; \
      DIR="$(dirname "$CANDIDATE")"; \
      rm -rf "$MODEL_PATH" && mv "$DIR" "$MODEL_PATH"; \
    fi; \
    test -f "$MODEL_PATH/config.json"

COPY app.py ./

ENV PORT=9090
EXPOSE 9090

CMD ["gunicorn", "--workers", "1", "--threads", "2", "--timeout", "120", "--preload", "-b", "0.0.0.0:9090", "app:app"]
