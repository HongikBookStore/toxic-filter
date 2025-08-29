FROM python:3.13.7-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl tar \
  && rm -rf /var/lib/apt/lists/*

COPY requirements-server.txt ./
RUN pip install --no-cache-dir -r requirements-server.txt

# Download model tarball from a URL (public or signed URL)
ARG MODEL_TARBALL_URL
ENV MODEL_PATH=./kcbert_slang_filter_model

RUN if [ -z "$MODEL_TARBALL_URL" ]; then \
      echo "ERROR: MODEL_TARBALL_URL build-arg is required" >&2; \
      exit 2; \
    fi; \
    echo "Downloading model from $MODEL_TARBALL_URL"; \
    curl -fSL "$MODEL_TARBALL_URL" -o /tmp/model.tar.gz; \
    mkdir -p "$MODEL_PATH"; \
    tar -xzf /tmp/model.tar.gz -C /app; \
    rm -f /tmp/model.tar.gz; \
    test -f "$MODEL_PATH/config.json"

COPY app.py ./

ENV PORT=9090
EXPOSE 9090

CMD ["gunicorn", "--workers", "1", "--threads", "2", "--timeout", "120", "--preload", "-b", "0.0.0.0:9090", "app:app"]
