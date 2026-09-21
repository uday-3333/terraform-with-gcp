import json
import logging
import os
import re
import threading
import time
from concurrent import futures

import grpc
from google.cloud import storage
from grpc_health.v1 import health, health_pb2, health_pb2_grpc

from envoy.service.ext_proc.v3 import external_processor_pb2 as ext_proc_pb2
from envoy.service.ext_proc.v3 import external_processor_pb2_grpc as ext_proc_grpc
from envoy.config.core.v3 import base_pb2 as core_pb2
from envoy.type.v3 import http_status_pb2

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
log = logging.getLogger(__name__)

MAINTENANCE_HTML = (
    '<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>Maintenance</title>'
    '<style>body{font-family:sans-serif;text-align:center;padding:80px;background:#f5f5f5}'
    'h1{color:#333}p{color:#666}</style></head>'
    '<body><h1>Scheduled Maintenance</h1>'
    '<p>We are currently performing scheduled maintenance. Please check back shortly.</p>'
    '</body></html>'
)


class ConfigCache:
    def __init__(self, gcs: storage.Client, bucket: str, folder: str, ttl: float):
        self._gcs = gcs
        self._bucket = bucket
        self._folder = folder
        self._ttl = ttl
        self._lock = threading.Lock()
        self._data = None
        self._fetched_at = 0.0

    def get(self):
        with self._lock:
            if self._data and (time.monotonic() - self._fetched_at) < self._ttl:
                return self._data
            try:
                self._data = self._fetch()
                self._fetched_at = time.monotonic()
            except Exception as e:
                if self._data:
                    log.warning("GCS fetch failed (%s), using stale config", e)
                else:
                    raise
            return self._data

    def _read(self, name: str):
        blob = self._gcs.bucket(self._bucket).blob(f"{self._folder}/{name}")
        return json.loads(blob.download_as_bytes())

    def _fetch(self):
        maintenance = self._read("maintenance.json")
        redirects = self._read("redirects.json")
        vanities = self._read("vanities.json")

        compiled = []
        for r in redirects:
            try:
                compiled.append(re.compile(r["source"]))
            except re.error as e:
                log.warning("Invalid redirect regex %r: %s — skipping", r["source"], e)
                compiled.append(None)

        log.info(
            "config refreshed — maintenance=%s redirects=%d vanities=%d",
            maintenance.get("maintenance"), len(redirects), len(vanities),
        )
        return {
            "maintenance": maintenance,
            "redirects": redirects,
            "vanities": vanities,
            "compiled": compiled,
        }


def _immediate_response(code: int, headers: dict, body: bytes = b""):
    set_headers = [
        core_pb2.HeaderValueOption(header=core_pb2.HeaderValue(key=k, value=v))
        for k, v in headers.items()
    ]
    return ext_proc_pb2.ProcessingResponse(
        immediate_response=ext_proc_pb2.ImmediateResponse(
            status=http_status_pb2.HttpStatus(code=code),
            headers=ext_proc_pb2.HeaderMutation(set_headers=set_headers),
            body=body,
        )
    )


def _continue_response():
    return ext_proc_pb2.ProcessingResponse(
        request_headers=ext_proc_pb2.HeadersResponse()
    )


class CalloutServicer(ext_proc_grpc.ExternalProcessorServicer):
    def __init__(self, cache: ConfigCache):
        self._cache = cache

    def Process(self, request_iterator, context):
        for req in request_iterator:
            if not req.HasField("request_headers"):
                yield _continue_response()
                continue
            try:
                yield self._handle(req.request_headers)
            except Exception as e:
                log.error("handle error: %s", e)
                yield _continue_response()

    def _handle(self, msg):
        cfg = self._cache.get()

        path = "/"
        for h in msg.headers.headers:
            if h.key == ":path":
                path = h.value
                break

        # 1. Maintenance mode
        if cfg["maintenance"].get("maintenance") == "on":
            return _immediate_response(
                200,
                {"content-type": "text/html; charset=utf-8", "cache-control": "no-store"},
                MAINTENANCE_HTML.encode(),
            )

        # 2. Regex redirects
        for rule, rx in zip(cfg["redirects"], cfg["compiled"]):
            if rx and rx.search(path):
                return _immediate_response(
                    301,
                    {"location": rule["destination"], "cache-control": "no-store"},
                )

        # 3. Vanity exact-path matches
        for v in cfg["vanities"]:
            if path == v["source"]:
                return _immediate_response(
                    301,
                    {"location": v["destination"], "cache-control": "no-store"},
                )

        # 4. Allow — continue to origin
        return _continue_response()


def main():
    port = os.environ.get("PORT", "8080")
    bucket = os.environ["GCS_BUCKET"]
    folder = os.environ.get("GCS_FOLDER_PREFIX", "maintenance")
    ttl = float(os.environ.get("CONFIG_TTL_SECONDS", "5"))

    gcs = storage.Client()
    cache = ConfigCache(gcs, bucket, folder, ttl)

    try:
        cache.get()
    except Exception as e:
        log.warning("Initial cache warm failed: %s — will retry on first request", e)

    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    ext_proc_grpc.add_ExternalProcessorServicer_to_server(CalloutServicer(cache), server)

    health_servicer = health.HealthServicer()
    health_pb2_grpc.add_HealthServicer_to_server(health_servicer, server)
    health_servicer.set("", health_pb2.HealthCheckResponse.SERVING)

    server.add_insecure_port(f"[::]:{port}")
    server.start()
    log.info("callout service listening on :%s (bucket=%s folder=%s ttl=%ss)", port, bucket, folder, ttl)
    server.wait_for_termination()


if __name__ == "__main__":
    main()
