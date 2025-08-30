FROM python:3.13.7-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates tar \
    && rm -rf /var/lib/apt/lists/*

COPY requirements-server.txt ./
RUN pip install --no-cache-dir -r requirements-server.txt

ENV MODEL_PATH=./kcbert_model
COPY kcbert_model.tar.gz /tmp/model.tar.gz
RUN mkdir -p "$MODEL_PATH" \
    && tar -xzf /tmp/model.tar.gz -C /app \
    && rm -f /tmp/model.tar.gz \
    && test -f "$MODEL_PATH/config.json"

COPY app.py ./

ENV PORT=9090
EXPOSE 9090

CMD ["gunicorn", "--workers", "1", "--threads", "2", "--timeout", "120", "--preload", "-b", "0.0.0.0:9090", "app:app"]
