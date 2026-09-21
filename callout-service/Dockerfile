FROM python:3.12-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends curl unzip && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Download Envoy data-plane-api protos
RUN curl -fsSL https://github.com/envoyproxy/data-plane-api/archive/refs/heads/main.zip -o dpa.zip \
    && unzip -q dpa.zip && mv data-plane-api-main envoy-api && rm dpa.zip

# Download googleapis protos (needed by Envoy protos)
RUN curl -fsSL https://github.com/googleapis/googleapis/archive/refs/heads/master.zip -o goog.zip \
    && unzip -q goog.zip && mv googleapis-master googleapis && rm goog.zip

# Download xDS API protos (udpa / xds)
RUN curl -fsSL https://github.com/cncf/xds/archive/refs/heads/main.zip -o xds.zip \
    && unzip -q xds.zip && mv xds-main xds && rm xds.zip

# Generate Python stubs for ext_proc + dependencies
RUN python -m grpc_tools.protoc \
    -I envoy-api \
    -I googleapis \
    -I xds \
    --python_out=proto_out \
    --grpc_python_out=proto_out \
    envoy-api/envoy/service/ext_proc/v3/external_processor.proto \
    envoy-api/envoy/config/core/v3/base.proto \
    envoy-api/envoy/type/v3/http_status.proto \
    envoy-api/envoy/extensions/filters/http/ext_proc/v3/processing_mode.proto

COPY main.py .

# ── Runtime ──────────────────────────────────────────────────────────────────
FROM python:3.12-slim

WORKDIR /app

COPY --from=builder /app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY --from=builder /app/proto_out ./proto_out
COPY --from=builder /app/main.py .

ENV PORT=8080 PYTHONPATH=/app/proto_out

EXPOSE 8080

ENTRYPOINT ["python", "main.py"]
