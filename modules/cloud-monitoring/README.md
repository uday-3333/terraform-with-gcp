# Cloud Monitoring Module

Creates Cloud Monitoring resources for GCP infrastructure across multiple services and components:
- **Cloud Run**: request count, error rate, latency (p95), active instances
- **Cloud SQL**: CPU, memory, connections
- **HTTPS Load Balancer**: request count, error rate, latency (p95)
- **Cloud Storage**: bucket errors and access
- **Pub/Sub**: backlog depth, delivery latency
- **Uptime Checks**: monitor customer-facing URLs
- **Dashboards**: unified environment overview
- **Alerts**: configurable email/Slack notifications

## Features

- Simple flat configuration with maps for each component
- Per-component alert policies with configurable thresholds
- Environment-wide unified dashboard
- Optional uptime checks for customer URLs
- Centralized notification channels
- No complex nesting — straightforward metric filters

## Usage

```hcl
module "monitoring" {
  source      = "../../modules/cloud-monitoring"
  project_id  = "prj-nrg-dev-cni-digital"
  environment = "dev"

  notification_channels = [
    "projects/prj-nrg-dev-cni-digital/notificationChannels/1234567890"
  ]

  monitoring = {
    enable_dashboard = true
    enable_alerts    = true
    cloud_run_alerts = true
    cloud_sql_alerts = true
    lb_alerts        = true
    uptime_checks    = [
      "https://enroll.nrg.com",
      "https://api.nrg.com"
    ]
  }

  cloud_run = {
    frontend = {
      service_name         = "smb-cni-dev-frontend"
      service_url          = "https://frontend-abc123.run.app"
      error_rate_threshold = 5
      latency_threshold    = 1000
    }
  }

  cloud_sql = {
    primary = {
      instance_name        = "prj-nrg-dev-cni-digital:us-central1:primary"
      cpu_threshold        = 80
      memory_threshold     = 85
      connection_threshold = 80
    }
  }

  load_balancer = {
    main = {
      resource_name        = "lb-dev-main"
      error_rate_threshold = 5
      latency_threshold    = 1000
    }
  }

  cloud_storage = {
    logs = {
      bucket_name = "prj-nrg-dev-cni-digital-logs"
    }
  }

  pubsub = {
    events = {
      resource_name     = "projects/prj-nrg-dev-cni-digital/subscriptions/events-sub"
      backlog_threshold = 100
    }
  }
}
```

## Inputs

### Global

| Input | Type | Default | Notes |
|---|---|---|---|
| `project_id` | string | — | GCP project ID |
| `environment` | string | — | Environment name (dev, staging, prod) |
| `notification_channels` | list(string) | `[]` | Full paths: `projects/PROJECT/notificationChannels/ID` |
| `monitoring` | object | — | Feature flags and uptime URLs (see below) |

### monitoring object

| Field | Type | Default |
|---|---|---|
| `enable_dashboard` | bool | true |
| `enable_alerts` | bool | true |
| `cloud_run_alerts` | bool | true |
| `cloud_sql_alerts` | bool | true |
| `lb_alerts` | bool | true |
| `uptime_checks` | list(string) | [] |

### cloud_run map

| Field | Type | Default | Notes |
|---|---|---|---|
| `service_name` | string | — | Required. Cloud Run service name |
| `service_url` | string | — | Optional. Service URL for dashboard reference |
| `error_rate_threshold` | number | 5 | Non-2xx req/s threshold |
| `latency_threshold` | number | 1000 | 95th percentile latency in ms |

### cloud_sql map

| Field | Type | Default |
|---|---|---|
| `instance_name` | string | Required. GCP instance ID |
| `cpu_threshold` | number | 80 |
| `memory_threshold` | number | 85 |
| `connection_threshold` | number | 80 |

### load_balancer map

| Field | Type | Default |
|---|---|---|
| `resource_name` | string | Required. Forwarding rule name |
| `error_rate_threshold` | number | 5 |
| `latency_threshold` | number | 1000 |

### cloud_storage map

| Field | Type | Default |
|---|---|---|
| `bucket_name` | string | Required. Bucket name |

### pubsub map

| Field | Type | Default |
|---|---|---|
| `resource_name` | string | Required. Subscription ID |
| `backlog_threshold` | number | 100 |

## Outputs

- `dashboard_id` — environment monitoring dashboard ID
- `cloud_run_alerts` — error_rate and latency alert IDs
- `cloud_sql_alerts` — cpu, memory, connections alert IDs
- `lb_alerts` — error_rate and latency alert IDs
- `uptime_check_ids` — uptime check resource IDs

## Design notes

- **Simple flat maps**: No deeply nested objects. Each component has its own map with only relevant fields.
- **Optional fields**: Thresholds use sensible defaults; omit if standard values work.
- **Centralized notifications**: All alerts use the same notification channels for consistency.
- **Feature flags**: Independently toggle each alert type and the dashboard via the `monitoring` object.
- **Uptime checks**: Pass customer URLs directly in `monitoring.uptime_checks` — no need to manage service_url coupling.
