# Maintenance Callout Service

gRPC service that implements the [Envoy External Processing API](https://www.envoyproxy.io/docs/envoy/latest/api-v3/service/ext_proc/v3/external_processor.proto).  
Called by GCP Service Extensions on every request to evaluate maintenance mode, regex redirects, and vanity URL rules stored in GCS.

## How it works

```
Request → LB → Service Extension → gRPC callout (this service)
                                         ↓
                              Read GCS maintenance/ folder (5s TTL cache)
                                         ↓
                    ┌────────────────────┴────────────────────┐
                    │  maintenance.json  maintenance = "on"?  │ → 200 + HTML page
                    │  redirects.json    regex match?         │ → 301 redirect
                    │  vanities.json     exact path match?    │ → 301 redirect
                    │  (no match)                             │ → continue to origin
                    └─────────────────────────────────────────┘
```

## GCS config files (updated by app teams — no Terraform needed)

| File | Purpose | Example |
|------|---------|---------|
| `maintenance/maintenance.json` | Toggle maintenance mode | `{"maintenance":"on"}` |
| `maintenance/redirects.json` | Regex-based redirects | `[{"source":"^/files.*$","destination":"https://example.com"}]` |
| `maintenance/vanities.json` | Exact-path vanity URLs | `[{"source":"/PROMO2026","destination":"https://example.com/promo"}]` |

## Build & push with Cloud Build

Run from the **repo root**:

```bash
gcloud builds submit \
  --config callout-service/cloudbuild.yaml \
  --substitutions _REGION=us-central1 \
  callout-service/
```

The build prints the pushed image URI at the end:
```
gcr.io/PROJECT_ID/maintenance-callout:SHORT_SHA
```

### Pin to immutable digest (recommended for prod)

After the build, get the digest:
```bash
gcloud container images describe gcr.io/PROJECT_ID/maintenance-callout:latest \
  --format='get(image_summary.digest)'
```

Then update `locals.tf`:
```hcl
container_image = "gcr.io/PROJECT_ID/maintenance-callout@sha256:<digest>"
```

## Enable the Service Extension

In `poc-gcp/sites.tf`, flip the flag for your site:
```hcl
enable_extension = true
```

Then run:
```bash
terraform apply
```

## Toggle maintenance mode (no Terraform needed)

```bash
# Enable
echo '{"maintenance":"on"}' | gsutil cp - gs://BUCKET_NAME/maintenance/maintenance.json

# Disable
echo '{"maintenance":"off"}' | gsutil cp - gs://BUCKET_NAME/maintenance/maintenance.json
```

Changes take effect within 5 seconds (CONFIG_TTL_SECONDS).

## Local development

```bash
export GCS_BUCKET=your-bucket-name
export GCS_FOLDER_PREFIX=maintenance
export CONFIG_TTL_SECONDS=5
export PORT=8080

pip install -r requirements.txt
python main.py
```

Test with grpcurl:
```bash
grpcurl -plaintext localhost:8080 grpc.health.v1.Health/Check
```
