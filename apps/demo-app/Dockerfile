# syntax=docker/dockerfile:1.7
ARG PYTHON_IMAGE=python:3.12-slim-bookworm@sha256:e697c81897302a4c4333bade000d98038fbb21eb064f8ee1fd42d02ebcd9d337

FROM ${PYTHON_IMAGE} AS builder

WORKDIR /build
COPY app.py .
RUN python -m compileall -q app.py \
    && mkdir -p /out \
    && cp app.py /out/app.py

FROM ${PYTHON_IMAGE}

ARG VERSION=dev
ARG REVISION=unknown
ARG CREATED

LABEL org.opencontainers.image.title="demo-app" \
      org.opencontainers.image.description="Reference application for the deploy-platform blue/green pipeline" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${CREATED}" \
      org.opencontainers.image.licenses="MIT"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONFAULTHANDLER=1 \
    APP_PORT=8080

ARG DEPENDENCY_URL=""
ENV DEPENDENCY_URL=${DEPENDENCY_URL}

RUN groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app --home-dir /app --shell /usr/sbin/nologin app \
    && install -d -o 10001 -g 10001 -m 0755 /app /data

WORKDIR /app
COPY --from=builder --chown=10001:10001 /out/app.py /app/app.py

USER 10001:10001
EXPOSE 8080
STOPSIGNAL SIGTERM

HEALTHCHECK --interval=30s --timeout=15s --start-period=30s --retries=3 \
  CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=12)"]

ENTRYPOINT ["python", "/app/app.py"]
