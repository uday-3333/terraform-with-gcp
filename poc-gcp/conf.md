# nrg-digital-cni / dev — Configuration Reference

## Environment Overview

| Setting | Value |
|---|---|
| Environment | `dev` |
| GCP Project | `prj-nrg-dev-cni-digital` |
| Region | `us-central1` |
| Host Project | `prj-nrg-network-shared` |
| Shared VPC | `nrg-net-dev-vpc-sharedvpc-001` |
| TFC Workspace | `gcp-prj-nrg-dev-cni-digital-workspace` |
| TFC Organization | `nrg-digital` |
| TFC Hostname | `app.terraform.io` |

---

## Mandatory Labels (applied to all resources)

| Label | Value |
|---|---|
| `businessapp` | `web-gcp-smb-cni` |
| `costcenter` | `177501` |
| `companycode` | `0121` |
| `region` | `us-central1` |
| `environment` | `dev` |
| `datapriority` | `private` |
| `nrg-terraformworkspace` | *(injected at runtime from `terraform.workspace`)* |

---

## Naming Prefixes

| Resource Type | Prefix Pattern |
|---|---|
| Common | `dev-prj-nrg-dev-cni-digital` |
| Secret Manager | `sms-dev-prj-nrg-dev-cni-digital` |
| Storage Bucket | `gcsbucket-dev-prj-nrg-dev-cni-digital` |
| Cloud Run | `run-dev-prj-nrg-dev-cni-digital` |
| Cloud Armor | `ca-dev-prj-nrg-dev-cni-digital` |
| HTTPS Load Balancer | `elb-dev-prj-nrg-dev-cni-digital` |

---

## Service Account

Resolved at plan time via `data.google_service_account`:

```
svc-cloud-nrg-dgt-dev-cniapp
```

---

## Cloud Run Services

| Key | Service Name | Port | Subnetwork |
|---|---|---|---|
| `smb-oe-app` | `run-dev-prj-nrg-dev-cni-digital-smb-oe-app` | `3000` | `nrg-net-dev-sbn-usce1-cnidigital-002` |

---

## HTTPS Load Balancers

| Key | Domains | Backend Services |
|---|---|---|
| `cni-smb` | `dev-enroll.nrg.com`, `dev-enroll.directenergy.com` | `enroll-nrg` → `smb-oe-app`, `enroll-de` → `smb-oe-app` |

CDN is enabled on all load balancers.

---

## Cloud Armor Policies

| Key | Policy Name | Mode | IP Whitelist Source |
|---|---|---|---|
| `allow_corp_and_partners` | `ca-dev-prj-nrg-dev-cni-digital-allow-corp-and-partners` | `private` | Remote state: `infrastructure-nrg-shared-network-core` + `cloud_armor_additional_nrg_allowed_ip_list` |

Log level: `NORMAL`

To add extra IPs, append CIDRs to `cloud_armor_additional_nrg_allowed_ip_list` in `locals.tf`.

---

## Secret Manager

| Key | Secret ID |
|---|---|
| `smb-oe-app-secrets` | `sms-dev-prj-nrg-dev-cni-digital-smb-oe-app-kv` |

Replication: `us-central1` only.

---

## Storage Buckets

| Key | Bucket Name | Location |
|---|---|---|
| `ops-assets` | `gcsbucket-dev-prj-nrg-dev-cni-digital-ops-assets` | `us-central1` |

---

## Cloud Monitoring

| Setting | Value |
|---|---|
| Alert duration | `180s` |
| Alert auto-close | `86400s` (24 h) |
| Uptime check regions | `USA_OREGON`, `USA_IOWA`, `USA_VIRGINIA` |
| Max Cloud Run instances threshold | `5` |
| LB volume spike threshold | `5000` |
| Cloud Run 5xx threshold | `5` |
| GCS permission-denied threshold | `2` |
| Notification email | `nrgdigitalit-platform@nrg.com` |

### Uptime Checks

| Key | URL | Path | Interval | Timeout | Expected Status |
|---|---|---|---|---|---|
| `api-endpoint` | `dev-enroll.nrg.com` | `/health` | `300s` | `10s` | `200` |
| `website` | `dev-enroll.directenergy.com` | `/health` | `300s` | `10s` | `200` |

---

## Remote State Dependencies

| Workspace | Used For |
|---|---|
| `infrastructure-nrg-shared-network-core` | `waf_nrg_ip_list` → Cloud Armor IP whitelist |

---

## Terraform Provider

```hcl
provider "google" {
  project = "prj-nrg-dev-cni-digital"
  region  = "us-central1"
  # version >= 7.38.0
}
```

---

## Key Outputs

| Output | Description |
|---|---|
| `cloud_run_service_uris` | Public URIs for all Cloud Run services |
| `load_balancer_ip_addresses` | IP per LB key — use for DNS A records |
| `dns_configuration_instructions` | Per-LB DNS setup guidance |
| `cloud_armor_policy_self_links` | Self-links to attach policies to backends |
| `monitoring_dashboard_id` | Cloud Monitoring dashboard ID |
| `monitoring_uptime_check_ids` | Uptime check IDs |
| `secrets` | *(sensitive)* Secret resource details |