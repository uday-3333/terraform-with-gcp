# Cloud Run Service Module (v2)

Deploys **one or more Google Cloud Run services** from a single map-based `for_each` call using the `google_cloud_run_v2_service` resource (Cloud Run Admin API v2). Supports scaling, VPC connectivity, Secret Manager, health probes, custom domains, and gen1/gen2 execution environments. Works unchanged across `dev`, `stage`, `prelive`, and `prod`.

## Features

- Multiple services from a single module call (`services` map)
- Native v2 scaling (`min_instance_count` / `max_instance_count`)
- Startup, liveness, and readiness HTTP probes (per-service)
- Optional unauthenticated public access via `allow_public_access` (per-service)
- Disable default public URI endpoints via `default_uri_disabled` (per-service)
- VPC Access Connector with configurable egress
- Secret Manager env-vars and file-mounted volumes
- HTTP/2, gRPC (h2c), session affinity, ingress modes
- `deletion_protection` toggle (per-service)
- Extensive plan-time validations (env var names, port ranges, timeouts, probe timing)

## Usage

```hcl
module "cloud_run" {
  source     = "../../modules/cloud-run"
  project_id = "prj-nrg-dev-cni-digital"

  services = {
    frontend = {
      service_name          = "smb-cni-dev-frontend"
      region                = "us-central1"
      container_image       = "gcr.io/my-project/frontend:v1.0.0"
      service_account_email = "frontend-sa@prj-nrg-dev-cni-digital.iam.gserviceaccount.com"

      min_instances = 0
      max_instances = 5

      ingress_type = "INGRESS_TRAFFIC_ALL"

      environment_variables = {
        LOG_LEVEL = "info"
        ENV       = "dev"
      }

      startup_probe_enabled  = true
      liveness_probe_enabled = true
      liveness_probe_path    = "/healthz"

      labels = { app = "frontend", env = "dev" }
    }

    backend = {
      service_name          = "smb-cni-dev-backend"
      region                = "us-central1"
      container_image       = "gcr.io/my-project/backend:v1.0.0"
      service_account_email = "backend-sa@prj-nrg-dev-cni-digital.iam.gserviceaccount.com"

      ingress_type = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
      default_uri_disabled = true

      environment_variables_secret = {
        DB_PASSWORD = { secret_name = "smb-cni-dev-db-password", secret_key = "latest" }
      }

      labels = { app = "backend", env = "dev" }
    }
  }
}
```

## Usage in dev — readiness probe + public access

Reference the module the same way as any other environment; the two new inputs are per-service opt-ins:

```hcl
module "cloud_run" {
  source     = "git::https://dev.azure.com/digital-it-apps/NRG-Terraform-Modules/_git/terraform-gcp-digital-cloud-run-service?ref=v<TAG>"
  project_id = "prj-nrg-dev-cni-digital"

  services = {
    frontend = {
      service_name          = "smb-cni-dev-frontend"
      region                = "us-central1"
      container_image       = "gcr.io/my-project/frontend:v1.0.0"
      service_account_email = "frontend-sa@prj-nrg-dev-cni-digital.iam.gserviceaccount.com"

      ingress_type        = "INGRESS_TRAFFIC_ALL"
      allow_public_access = true   # opt-in: grants allUsers roles/run.invoker

      readiness_probe_enabled           = true
      readiness_probe_path              = "/api/ready"
      readiness_probe_period            = 10
      readiness_probe_timeout           = 1
      readiness_probe_failure_threshold = 3
    }
  }
}
```

Notes:

- `allow_public_access` defaults to `false`. Leave it off unless the service is genuinely internet-facing; internal services should stay on `INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER` and go through the LB.
- Setting `allow_public_access = true` requires the pipeline's deployer SA to hold `roles/run.admin` (or the narrower `run.services.setIamPolicy` permission) on the target project. Request this via your platform IAM channel before enabling.
- `default_uri_disabled` defaults to `true`. This disables the auto-generated default public URI endpoint, preventing unauthenticated access through the service's automatic Cloud Run URL. Set to `false` only if you need direct access to the auto-generated URI.
- `readiness_probe_*` is disabled by default. Cloud Run's `startup_probe` already gates traffic to a new revision until it passes, so `readiness_probe` is only needed when you want an ongoing readiness signal separate from liveness.
- Cloud Run's readiness probe block does **not** accept `initial_delay_seconds` (unlike startup/liveness); the module intentionally omits that field.

## Module Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| project_id | The GCP project ID | `string` | n/a | yes |
| services | Map of Cloud Run v2 services to deploy | `map(object)` | `{}` | no |
| host_project_id | Host project ID for the shared VPC that has SAP connectivity | `string` | `null` | no |
| vpc_network | VPC network name used for SAP connectivity | `string` | `null` | no |

## Service Configuration (per-service inputs)

Every service in the `services` map object supports (all `optional()` unless marked required):

| Field | Type | Default | Notes |
|---|---|---|---|
| `service_name` | string | — | **required** Cloud Run service names: max 50 chars, lowercase letters/digits/hyphens only, must start with letter, cannot end with hyphen. Module auto-truncates to 50 chars. |
| `region` | string | — | **required** |
| `container_image` | string | — | **required** |
| `service_account_email` | string | — | **required by validation** (no default-SA fallback) |
| `cpu_limit` / `memory_limit` | string | `"1"` / `"1Gi"` | |
| `min_instances` / `max_instances` | number | 0 / 10 | maps to `template.scaling.min/max_instance_count` |
| `max_instance_request_concurrency` | number | 80 | maps to v2 `template.max_instance_request_concurrency` |
| `timeout_seconds` | number | 300 | max 3600; module converts to v2 string duration `"${n}s"` |
| `container_port` | number | 8080 | validated 1-65535 |
| `cpu_throttling` | bool | true | maps to v2 `resources.cpu_idle` (same semantics) |
| `startup_cpu_boost` | bool | false | maps to v2 `resources.startup_cpu_boost` |
| `execution_environment` | string | `"EXECUTION_ENVIRONMENT_GEN2"` | `"EXECUTION_ENVIRONMENT_GEN1"` or `"EXECUTION_ENVIRONMENT_GEN2"` |
| `grpc_enabled` | bool | false | `true` sets port name to `h2c` for gRPC |
| `session_affinity` | bool | false | |
| `enable_vpc_egress` / `vpc_egress_type` | bool / string | true / `"ALL_TRAFFIC"` | `vpc_egress_type` must be `"ALL_TRAFFIC"` or `"PRIVATE_RANGES_ONLY"` |
| `ingress_type` | string | `"INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"` | `"INGRESS_TRAFFIC_ALL"`, `"INGRESS_TRAFFIC_INTERNAL_ONLY"`, `"INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"` |
| `default_uri_disabled` | bool | true | when `true`, disables the default public URI endpoint for the service; provides security by preventing access via auto-generated URL |
| `deletion_protection` | bool | false | v2 API default is `true`; set `true` per-env for prod safety |
| `environment_variables` | map(string) | `{}` | keys validated: `[A-Z_][A-Z0-9_]*`, no `X_GOOGLE_` prefix |
| `environment_variables_secret` | map(object({secret_name, secret_key})) | `{}` | `secret_key` = version (e.g. `"latest"` or `"3"`) |
| `volume_mounts` / `volumes` | list(object) | `[]` | mounted secret files; `secret_key` = version |
| `startup_probe_*` / `liveness_probe_*` / `readiness_probe_*` | various | — | independent HTTP probes; readiness is disabled by default |
| `allow_public_access` | bool | false | when `true`, module grants `allUsers` the `roles/run.invoker` role on the service (unauthenticated public access). Requires deployer to hold `roles/run.admin` or `run.services.setIamPolicy`. |
| `template_annotations` / `service_annotations` / `labels` | map(string) | `{}` | |
| `tags` | list(string) | `[]` | network tags applied to VPC access |

## Removed from v1

The following v1 fields do not exist in v2 and have been removed from the module:

- `allow_unauthenticated` — IAM is managed externally (e.g. via a separate IAM module or by the LB / Serverless NEG layer).
- `iam_members` — same reason as above.
- `cpu_utilization_target` / `request_rate_target` / `concurrency_utilization_target` — the v2 provider does not expose these knobs. Use `min_instances`/`max_instances` for scale control.
- `max_request_timeout` — merged into `timeout_seconds` (v2 has a single `timeout` field).
- `http2_enabled` — was a documented no-op in v1; use `grpc_enabled` for h2c on the wire.

## Outputs

| Name | Description |
|------|-------------|
| services | Combined map of service key → all attributes (id, name, location, uri, urls, latest_ready_revision, latest_created_revision, generation, observed_generation) |
| service_ids | Map of service key to Cloud Run service ID |
| service_names | Map of service key to Cloud Run service name |
| service_uris | Map of service key to Cloud Run service primary URI (v2 top-level `uri`) |
| service_locations | Map of service key to Cloud Run service location |
| public_access_services | Map of service key to `allUsers` IAM binding etag (only for services with `allow_public_access = true`) |

**Note:** `services[k].uri` is the v2 primary URL (replaces v1's `status[0].url`). On first apply it may resolve to Terraform `unknown` briefly; use `try()` when passing to other modules on first apply.

## Design notes

- Map keys are **stable identifiers**. Renaming a key destroys and recreates the service.
- `traffic { type = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST", percent = 100 }` is hard-coded — no canary support yet.
- Uses `google_cloud_run_v2_service` (Cloud Run Admin API v2). v1 `google_cloud_run_service` is no longer used.
- Default compute SA usage is blocked by validation — create a per-service SA.
- `deletion_protection` defaults to `false` in the module (matches v1 behavior); override to `true` per-env for prod safety.
- `lifecycle.ignore_changes` on `client` / `client_version` prevents plan drift from Google-side client metadata.

## State migration from v1 (`google_cloud_run_service`)

Terraform `moved` blocks do NOT work across different resource types. For an existing v1-managed workspace, migrate per service:

1. Capture the existing v1 resource ID (`region/project/name`).
2. Rewrite HCL to use this v2 module (already done here).
3. `terraform state rm module.cloud_run.google_cloud_run_service.service[<key>]`
4. `terraform import module.cloud_run.google_cloud_run_v2_service.service[<key>] <project>/<region>/<name>` — **note the reordered ID** (v2 API is `project/region/name`, v1 was `region/project/name`).
5. `terraform plan` should be clean.

Both APIs manage the same underlying Cloud Run service, so imports round-trip cleanly.