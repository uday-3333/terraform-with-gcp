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

_MAINTENANCE_HTML_FALLBACK = (
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

    def _read_json(self, name: str):
        blob = self._gcs.bucket(self._bucket).blob(f"{self._folder}/{name}")
        return json.loads(blob.download_as_bytes())

    def _read_text(self, name: str) -> str:
        blob = self._gcs.bucket(self._bucket).blob(f"{self._folder}/{name}")
        return blob.download_as_text()

    def _fetch(self):
        maintenance = self._read_json("maintenance.json")
        redirects = self._read_json("redirects.json")
        vanities = self._read_json("vanities.json")
        
        try:
            http_headers = self._read_json("http_headers.json")
        except Exception as e:
            log.warning("Failed to read http_headers.json: %s — using empty list", e)
            http_headers = []

        try:
            maintenance_html = self._read_text("maintenance.html").encode()
        except Exception:
            maintenance_html = _MAINTENANCE_HTML_FALLBACK.encode()

        compiled = []
        for r in redirects:
            try:
                compiled.append(re.compile(r["source"]))
            except re.error as e:
                log.warning("Invalid redirect regex %r: %s — skipping", r["source"], e)
                compiled.append(None)

        log.info(
            "config refreshed — maintenance=%s redirects=%d vanities=%d headers=%d",
            maintenance.get("maintenance"), len(redirects), len(vanities), len(http_headers),
        )
        return {
            "maintenance": maintenance,
            "maintenance_html": maintenance_html,
            "redirects": redirects,
            "vanities": vanities,
            "compiled": compiled,
            "http_headers": http_headers,
        }


def _immediate_response(code: int, headers: dict, body: bytes = b"", extra_headers: dict = None):
    merged_headers = dict(headers)
    if extra_headers:
        merged_headers.update(extra_headers)
    set_headers = [
        core_pb2.HeaderValueOption(header=core_pb2.HeaderValue(key=k, value=v))
        for k, v in merged_headers.items()
    ]
    return ext_proc_pb2.ProcessingResponse(
        immediate_response=ext_proc_pb2.ImmediateResponse(
            status=http_status_pb2.HttpStatus(code=code),
            headers=ext_proc_pb2.HeaderMutation(set_headers=set_headers),
            body=body,
        )
    )


def _continue_request():
    return ext_proc_pb2.ProcessingResponse(
        request_headers=ext_proc_pb2.HeadersResponse()
    )


def _continue_response(extra_headers: dict = None):
    if not extra_headers:
        return ext_proc_pb2.ProcessingResponse(
            response_headers=ext_proc_pb2.HeadersResponse()
        )
    set_headers = [
        core_pb2.HeaderValueOption(header=core_pb2.HeaderValue(key=k, value=v))
        for k, v in extra_headers.items()
    ]
    return ext_proc_pb2.ProcessingResponse(
        response_headers=ext_proc_pb2.HeadersResponse(
            response=ext_proc_pb2.CommonResponse(
                header_mutation=ext_proc_pb2.HeaderMutation(set_headers=set_headers)
            )
        )
    )


def _inject_headers_response(http_headers: list) -> ext_proc_pb2.ProcessingResponse:
    set_headers = [
        core_pb2.HeaderValueOption(
            header=core_pb2.HeaderValue(key=h["headerKey"], value=h["headerValue"]),
            append=False,
        )
        for h in http_headers
        if h.get("headerKey") and h.get("headerValue")
    ]
    if not set_headers:
        return _continue_response()
    return ext_proc_pb2.ProcessingResponse(
        response_headers=ext_proc_pb2.HeadersResponse(
            response=ext_proc_pb2.CommonResponse(
                header_mutation=ext_proc_pb2.HeaderMutation(set_headers=set_headers)
            )
        )
    )


class CalloutServicer(ext_proc_grpc.ExternalProcessorServicer):
    def __init__(self, cache: ConfigCache):
        self._cache = cache

    def Process(self, request_iterator, context):
        for req in request_iterator:
            if req.HasField("request_headers"):
                try:
                    yield self._handle_request(req.request_headers)
                except Exception as e:
                    log.error("request handle error: %s", e)
                    yield _continue_request()
            elif req.HasField("response_headers"):
                try:
                    yield self._handle_response(req.response_headers)
                except Exception as e:
                    log.error("response handle error: %s", e)
                    yield _continue_response()
            else:
                yield _continue_request()

    def _handle_request(self, msg):
        cfg = self._cache.get()

        path = "/"
        for h in msg.headers.headers:
            if h.key == ":path":
                path = h.value
                break

        # Build extra headers from http_headers config
        extra_headers = {h["headerKey"]: h["headerValue"] for h in cfg.get("http_headers", []) if h.get("headerKey") and h.get("headerValue")}

        # 1. Maintenance mode
        if cfg["maintenance"].get("maintenance") == "on":
            log.info("maintenance mode active, returning 200 with %d headers", len(extra_headers))
            return _immediate_response(
                200,
                {"content-type": "text/html; charset=utf-8", "cache-control": "no-store"},
                cfg["maintenance_html"],
                extra_headers,
            )

        # 2. Regex redirects
        for rule, rx in zip(cfg["redirects"], cfg["compiled"]):
            if rx and rx.search(path):
                log.info("redirect match for path=%s, returning 301 with %d headers", path, len(extra_headers))
                return _immediate_response(
                    301,
                    {"location": rule["destination"], "cache-control": "no-store"},
                    b"",
                    extra_headers,
                )

        # 3. Vanity exact-path matches
        for v in cfg["vanities"]:
            if path == v["source"]:
                log.info("vanity match for path=%s, returning 301 with %d headers", path, len(extra_headers))
                return _immediate_response(
                    301,
                    {"location": v["destination"], "cache-control": "no-store"},
                    b"",
                    extra_headers,
                )

        # 4. Allow — continue to origin with headers
        log.info("allowing request to origin, will inject %d headers in response phase", len(extra_headers))
        # Store headers in context for response phase
        self._request_headers = extra_headers
        return _continue_request()

    def _handle_response(self, msg):
        cfg = self._cache.get()
        http_headers = cfg.get("http_headers", [])
        extra_headers = {h["headerKey"]: h["headerValue"] for h in http_headers if h.get("headerKey") and h.get("headerValue")}
        
        if extra_headers:
            log.info("response phase: injecting %d http_headers", len(extra_headers))
            return _inject_headers_response(http_headers)
        
        log.debug("response phase: no headers to inject")
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
        log.info("initial config cache warm successful")
    except Exception as e:
        log.warning("Initial cache warm failed: %s — will retry on first request", e)

    executor = futures.ThreadPoolExecutor(max_workers=10)
    try:
        server = grpc.server(executor)
        ext_proc_grpc.add_ExternalProcessorServicer_to_server(CalloutServicer(cache), server)

        health_servicer = health.HealthServicer()
        health_pb2_grpc.add_HealthServicer_to_server(health_servicer, server)
        health_servicer.set("", health_pb2.HealthCheckResponse.SERVING)

        server.add_insecure_port(f"[::]:{port}")
        server.start()
        log.info("callout service listening on :%s (bucket=%s folder=%s ttl=%ss)", port, bucket, folder, ttl)
        try:
            server.wait_for_termination()
        finally:
            server.stop(grace=5)
    finally:
        executor.shutdown(wait=True)


if __name__ == "__main__":
    main()
