# GCP Implementation Guide: Maintenance Pages, Redirects, and Vanity Domains

**Date**: 2026-09-17  
**Project**: nrg-gcp-infra/dev  
**Migration From**: AWS Lambda@Edge (nrg-aws-infra)

---

## 🎯 Executive Summary

This guide provides a comprehensive analysis and implementation plan for migrating maintenance page, redirects, and vanity domain functionality from AWS Lambda@Edge to GCP.

### Quick Decision Guide

**Do you need Cloud Run callout service?**

| Your Requirement | Cloud Run Needed? | Recommended Approach | Monthly Cost |
|------------------|-------------------|---------------------|--------------|
| **Static maintenance page** (toggle via Terraform) | ❌ No | Cloud Armor redirect | ~$5 |
| **Static URL redirects** (< 10 fixed paths) | ❌ No | URL Maps | ~$5 |
| **Dynamic maintenance toggle** (app team controlled) | ✅ Yes | Service Extensions + Cloud Run | ~$40-50 |
| **Regex-based redirects** (`^/files.*$`) | ✅ Yes | Service Extensions + Cloud Run | ~$40-50 |
| **AWS Lambda@Edge parity** | ✅ Yes | Service Extensions + Cloud Run | ~$40-50 |

### Recommended Architecture for Your Use Case

Based on your AWS Lambda@Edge implementation (with S3 config files, regex redirects, and app-team controlled maintenance mode):

**✅ Use: Service Extensions + Cloud Run Callout Service**

- App teams update GCS bucket files (no Terraform)
- Changes take effect in 5-10 seconds
- Supports regex redirects
- 99.95% uptime with min instances = 2
- ~$40-50/month total cost
- 75% cheaper than AWS Lambda@Edge

---

## 📊 AWS Lambda@Edge Current Implementation

### Architecture Overview

The AWS implementation uses **Lambda@Edge** functions triggered at the **viewer-request** stage of CloudFront distributions. The implementation follows a modular pattern using the `digital-lae-ops` Terraform module.

```
Client Request
     ↓
CloudFront Distribution
     ↓
viewer-request (Lambda@Edge: maintenance-and-redirects)
     ├─→ Maintenance Mode? → Return 200 + maintenance.html
     ├─→ Redirect Match? → Return 301 + Location header
     ├─→ Vanity Match? → Return 301 + Location header
     └─→ No Match → Continue to origin
     ↓
origin-request (Lambda@Edge: index-rewrite)
     ↓
Origin (ALB/S3)
     ↓
origin-response (Lambda@Edge: add-security-headers)
     ↓
Return to Client
```

### Key Terraform Resources

**File**: `nrg-aws-infra/nrg-aws-automation/terraform/cirro/dev/lambda_at_edge.tf`

**Module Invocation**:
```hcl
module "lae_maintenance_and_redirects" {
  source   = "app.terraform.io/nrg-digital/digital-lae-ops/aws"
  for_each = local.additional_lae_map
  
  template_filename = "lae-maintenance-and-redirects"
  template_file_map = {
    TTLInMilliSecs      = 5000,
    OpsBucketPath       = "${each.value.OpsBucketName}",
    MaintenanceJsonFile = "${each.value.OpsBucketPath}/maintenance.conf",
    MaintenanceHtmlFile = "${each.value.OpsBucketPath}/maintenance.html",
    RedirectsJsonFile   = "${each.value.OpsBucketPath}/redirects.conf",
    VanitiesJsonFile    = "${each.value.OpsBucketPath}/vanities.conf"
  }
  function_name          = "${local.common_name_prefix}-${each.key}-lae-maintenance-and-redirects-function"
  lae_execution_role_arn = module.lambda_at_edge_execution_role.role_arn
  function_handler_name  = "${local.zone_prefix}-${each.key}-lae-maintenance-and-redirects"
}
```

**CloudFront Integration**:
```hcl
lambda_function_association = {
  viewer-request = {
    lambda_arn   = module.lae_maintenance_and_redirects["shop_aocb"].qualified_arn
    include_body = false
  }
}
```

### Lambda Function Logic Summary

**File**: `nrg-aws-infra/nrg-aws-automation/terraform/nrg-digital-commons/lambdas/source/lae-maintenance-and-redirects.js.tftpl`

**Key Features**:
1. **Runtime**: Node.js 22.x (AWS SDK v3)
2. **S3 Integration**: Reads configuration files from S3 bucket
3. **Caching**: 5-second TTL for all config files (in-memory cache)
4. **Processing Order**:
   - Check maintenance mode first
   - Then check redirects (regex-based)
   - Then check vanities (exact path match)
   - Finally return original request

### Maintenance Mode Control

- **Configuration File**: `maintenance.conf` stored in S3
- **Format**: JSON array with key-value pairs
- **Example**:
```json
[   
    {     
        "key": "maintenance" ,
        "value": "off"  // Change to "on" to enable
    }
]
```
- **Behavior**: When `value === "on"`, returns 200 status with `maintenance.html` content from S3

### Redirects Configuration

- **Configuration File**: `redirects.conf` stored in S3
- **Format**: JSON array with regex source and destination
- **Example**:
```json
[
    {     
        "source": "^/files.*$" ,
        "destination": "https://dev-my.reliant.com"
    },
    {        
        "source": ".+.(htm?)$" ,
        "destination": "https://dev-my.reliant.com"
    }
]
```
- **Behavior**: Returns 301 redirect, preserves query strings

### Vanities Configuration

- **Configuration File**: `vanities.conf` stored in S3
- **Format**: JSON array with exact path matches
- **Example**:
```json
[
    {
        "destination": "https://dev1-www.reliant.com/en/public/reliant_care.jsp",
        "source": "/ABOUTCARE"
    },
    {
        "destination": "https://dev1-www.reliant.com/en/residential/customer-care/index.jsp",
        "source": "/ACCOUNTTOOLS"
    }
]
```
- **Behavior**: Returns 301 redirect for exact path matches, preserves query strings

### IAM Permissions

**Lambda@Edge Execution Role**:
- **Trusted Entities**: `lambda.amazonaws.com`, `edgelambda.amazonaws.com`
- **Inline Policies**:
  - CloudWatch Logs write access (for logging)
  - S3 GetObject access to ops bucket (for reading config files)

### Application Team Control

**How Maintenance Mode is Toggled**:
1. Application teams access the S3 bucket: `${site}-s3-${environment}-${brand}-digital-ops-assets`
2. Navigate to the ops config folder (e.g., `cirro/shop/`)
3. Update `maintenance.conf` and change `"value": "off"` to `"value": "on"`
4. Lambda@Edge functions cache config for 5 seconds (TTL), so change takes effect within 5 seconds globally
5. **No infrastructure changes required** - pure operational toggle

---

## 🏗️ GCP Options Comparison

| Approach | Pros | Cons | Maturity | Migration Effort |
|----------|------|------|----------|------------------|
| **Service Extensions (Plugins)** | - Native GCP edge computing<br>- WebAssembly for performance<br>- Integrates with Cloud CDN/LB<br>- Pre-cache (edge) and post-cache (traffic) extension points<br>- Official GCP solution | - WebAssembly learning curve (Rust/C++/Go)<br>- Limited to header manipulation<br>- Cannot directly read GCS in plugins<br>- Relatively new (Preview for Media CDN)<br>- No direct S3-like config file pattern | GA for Cloud CDN<br>Preview for Media CDN<br>Active development (2026 updates) | **High**<br>- Rewrite Lambda code in Rust/C++<br>- Different configuration model<br>- Need callout service for GCS access |
| **Service Extensions (Callouts)** | - Can call external services via gRPC<br>- More flexibility than plugins<br>- Can run on Cloud Run/GKE<br>- Can access GCS, databases, APIs<br>- Full programming language support | - Higher latency (gRPC call overhead)<br>- More complex architecture<br>- Need to manage callout backend service<br>- Additional cost for backend service | GA for Application LB<br>Preview for Secure Web Proxy | **Medium-High**<br>- Build gRPC service<br>- Deploy/manage Cloud Run service<br>- Rewrite Lambda logic in Go/Python/etc. |
| **Cloud Run + URL Maps** | - Simple redirect logic<br>- No code deployment for basic redirects<br>- Native Terraform support<br>- Well-documented | - Not true edge computing (regional)<br>- All-or-nothing maintenance mode<br>- Limited dynamic behavior<br>- No request-level logic | GA<br>Mature, production-ready | **Low-Medium**<br>- Configure URL maps in Terraform<br>- Backend bucket for maintenance page<br>- Manual redirect rules |
| **Cloud Armor Custom Rules** | - Can redirect with 302 status<br>- Rule-based approach<br>- No code deployment<br>- Security-focused integration | - Limited to simple conditions<br>- Cannot read external config<br>- Rule limit (10,000 per policy)<br>- Not designed for this use case | GA<br>Production-ready | **Low**<br>- Configure Cloud Armor rules<br>- Limited to static redirects<br>- No dynamic maintenance mode |
| **Cloud Functions + Cloud CDN** | - Familiar serverless model<br>- Multiple language support<br>- Similar to Lambda concept | - Regional deployment only<br>- Not true edge execution<br>- Higher cold start latency<br>- Not integrated with CDN edge | GA<br>Production-ready | **Medium**<br>- Port Lambda code to Cloud Functions<br>- Different event model<br>- Regional vs edge execution |

---

## ✅ Recommended GCP Architecture

### UPDATED RECOMMENDATION: Service Extensions Callouts ONLY (Simpler!)

After analyzing complexity vs. benefits, the **recommended approach is Service Extensions Callouts directly** (skip the WebAssembly plugin layer).

**Why This Simpler Approach**:
1. ✅ **No WebAssembly complexity** - no Rust/C++ learning curve
2. ✅ **Easier to implement** - just write Go/Python/Node.js Cloud Run service
3. ✅ **Easier to debug** - standard application code, not WebAssembly
4. ✅ **Still edge-executed** - Service Extensions call Cloud Run from edge locations
5. ✅ **Application team control** - still use GCS bucket for config
6. ✅ **Lower operational complexity** - one less layer to manage
7. ⚠️ **Trade-off**: Every request makes gRPC call (~10-30ms latency), but Cloud Run caching makes this acceptable

**Original Recommendation (More Complex)**:
- Service Extensions Plugins (WebAssembly) + Callout Service
- **Pros**: Lowest latency, plugin can cache callout responses
- **Cons**: WebAssembly learning curve, two layers to maintain

**New Recommendation (Simpler, Production-Ready)**:
- Service Extensions Callouts directly to Cloud Run
- **Pros**: Much simpler, easier to maintain, production-ready
- **Cons**: Slightly higher latency per request (~10-30ms)

### Architecture Diagram

```
┌───────────────────────────────────────────────────────────────────┐
│                         Client Request                            │
│                    (https://your-domain.com)                      │
└───────────────────────┬───────────────────────────────────────────┘
                        ↓
┌───────────────────────────────────────────────────────────────────┐
│              Global External Application Load Balancer            │
│              (HTTPS proxy → URL map → Cloud Armor)                │
└───────────────────────┬───────────────────────────────────────────┘
                        ↓
┌───────────────────────────────────────────────────────────────────┐
│         Service Extensions Plugin (WebAssembly at Edge)           │
│  ⚠️  Cannot directly access GCS - must use gRPC callout          │
└─────┬─────────────────────────────────────────────────────────────┘
      │
      │ gRPC Callout (Envoy External Processing API)
      ↓
┌───────────────────────────────────────────────────────────────────┐
│           Cloud Run Callout Service (Middleware/Bridge)           │
│  • Implements gRPC server                                         │
│  • Has GCS client library access                                  │
│  • Reads from CONFIG bucket (not application bucket)              │
│  • Caches configs for 5 seconds                                   │
│  • Returns decision: maintenance/redirect/allow                   │
└─────┬─────────────────────────────────────────────────────────────┘
      │
      │ Reads configuration files
      ↓
┌───────────────────────────────────────────────────────────────────┐
│      GCS Bucket: CONFIGURATION STORAGE (ops-config bucket)        │
│  • maintenance.json  ← App team updates this                      │
│  • redirects.json                                                 │
│  • vanities.json                                                  │
│  • maintenance.html                                               │
│  ⚠️  Separate from your application content bucket                │
└───────────────────────────────────────────────────────────────────┘

      ↓ (After Service Extensions processes the request)
      
      Decision:
      ├─→ Maintenance ON? → Return 200 + maintenance.html content
      ├─→ Redirect Match? → Return 301 + Location header
      ├─→ Vanity Match?   → Return 301 + Location header
      └─→ Allow Request   → Continue to Application Backend
                                    ↓
            ┌───────────────────────────────────────────────────┐
            │      APPLICATION BACKEND (Your Website/App)       │
            │  Options:                                         │
            │  • GCS bucket (static site)  ← Could be this      │
            │  • Cloud Run service #2 (your app) ← Or this      │
            │  • GKE cluster                                    │
            │  • Compute Engine                                 │
            │  ⚠️  If Cloud Run: SEPARATE from callout service  │
            │  ⚠️  Different from ops-config bucket             │
            └───────────────────────┬───────────────────────────┘
                                    ↓
                            Return to Client

═══════════════════════════════════════════════════════════════════
IMPORTANT: Cloud Run Callout Service ≠ Application Cloud Run Service
═══════════════════════════════════════════════════════════════════
If your app runs on Cloud Run, you will have TWO Cloud Run services:
  1. Callout Service (gRPC) - reads GCS configs
  2. Application Service (HTTP) - serves your app
```

### Implementation Details

**1. Service Extensions Edge Plugin (WebAssembly)**
- **Language**: Rust (recommended by Google) or C++
- **Location**: Edge of Google's network
- **Function**: Makes gRPC callout to Cloud Run service
- **Caching**: Can cache callout responses in Wasm module
- **Repository**: Use samples from https://github.com/GoogleCloudPlatform/service-extensions

**2. Callout Backend Service (Cloud Run)**
- **Language**: Go, Python, or Node.js
- **Runtime**: Implements Envoy External Processing gRPC API
- **Purpose**: Acts as middleware between Service Extensions and GCS(WebAssembly cannot directly access GCS)
- **Function**:
  - Read GCS bucket for `maintenance.json`, `redirects.json`, `vanities.json`
  - Cache configs in-memory with 5-second TTL
  - Return maintenance/redirect decisions to edge plugin
- **Scaling**: Auto-scales, can handle global edge traffic
- **Permissions**: Service account with `roles/storage.objectViewer` on ops config bucket
- **Why Required**: Service Extensions WebAssembly plugins cannot directly access GCS - they can only make gRPC callouts

**3. Cloud Storage Configuration Bucket** (Separate from Application Backend)
- **Bucket**: `${project}-gcs-${environment}-${brand}-ops-config`
- **Purpose**: Stores maintenance mode configuration (NOT your application content)
- **Files**:
  - `maintenance.json` - maintenance mode flag
  - `redirects.json` - redirect rules
  - `vanities.json` - vanity URL mappings
  - `maintenance.html` - maintenance page content
- **Access**: Application teams granted `roles/storage.objectAdmin` on specific prefix
- **Note**: This is separate from your application backend bucket

**4. Application Backend** (Your Actual Website/App)
- **Options**: GCS bucket (static site), Cloud Run, GKE, Compute Engine, etc.
- **Purpose**: Hosts your actual application/website
- **Example**: If static site → separate GCS bucket like `${project}-website-assets`
- **Note**: This is where normal requests go AFTER passing through maintenance/redirect checks

**4. Terraform Resources**
```hcl
# Service Extensions Edge Extension
resource "google_network_services_lb_traffic_extension" "maintenance_redirects" {
  name        = "${var.project}-edge-maintenance-redirects"
  location    = "global"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  
  extension_chains {
    name = "maintenance-check"
    match_condition {
      cel_expression = "true"  # Apply to all requests
    }
    extensions {
      name = "callout-maintenance"
      service = google_cloud_run_service.maintenance_callout.status[0].url
      timeout = "0.5s"
    }
  }
}

# Cloud Run Callout Service
resource "google_cloud_run_service" "maintenance_callout" {
  name     = "${var.project}-maintenance-callout"
  location = var.region
  
  template {
    spec {
      service_account_name = google_service_account.maintenance_callout.email
      containers {
        image = "gcr.io/${var.project}/maintenance-callout:latest"
        env {
          name  = "GCS_BUCKET"
          value = google_storage_bucket.ops_config.name
        }
        env {
          name  = "CONFIG_TTL_SECONDS"
          value = "5"
        }
      }
    }
  }
}

# GCS Bucket for Configuration
resource "google_storage_bucket" "ops_config" {
  name     = "${var.project}-ops-config"
  location = "US"
  
  uniform_bucket_level_access = true
}
```

---

## 💰 Cost Comparison

### AWS Lambda@Edge (100M requests/month):
- Lambda@Edge: $0.60 per 1M requests
- Lambda@Edge compute: $0.00005001 per GB-second
- **Total**: ~$60-80/month

### GCP Service Extensions (100M requests/month):
- Service Extensions: **Free** (no additional charge for plugins)
- Cloud Run callout: $0.40 per 1M requests (first 2M free)
- Cloud Run CPU/Memory: ~$0.00002400 per GB-second
- Example: 100M requests/month with 10% callout rate (90% cached at edge)
- **Total**: ~$15-25/month

**💵 Cost Savings**: ~75% cheaper on GCP

---

## 📝 Application-Managed Maintenance Mode Options

### Option 1: Cloud Storage Bucket with Flag File (RECOMMENDED) ⭐

**How It Works**:
1. Create GCS bucket: `${project}-ops-config`
2. Store `maintenance.json` in bucket
3. Cloud Run callout service reads file with 5-second cache
4. Service Extensions edge plugin queries callout service

**Application Team Workflow**:
```bash
# Enable maintenance mode
echo '{"maintenance": "on"}' | gsutil cp - gs://my-app-ops-config/maintenance.json

# Disable maintenance mode
echo '{"maintenance": "off"}' | gsutil cp - gs://my-app-ops-config/maintenance.json
```

**Metrics**:
- **Latency Impact**: 
  - First request: ~50-100ms (GCS read + gRPC callout)
  - Subsequent requests: ~5-10ms (cached in Cloud Run for 5s, then edge cache)
- **Ease of Use**: ⭐⭐⭐⭐⭐
  - Simple JSON file update
  - Can use gsutil, Cloud Console, or API
  - Can grant granular IAM permissions
- **Cost**: Minimal
  - GCS storage: ~$0.02/month for 1MB
  - GCS operations: ~$0.004 per 10,000 reads
  - Cloud Run: First 2M requests free

### Option 2: Secret Manager

**How It Works**:
1. Store maintenance flag as secret
2. Cloud Run callout service reads secret with caching
3. Update secret to toggle maintenance mode

**Application Team Workflow**:
```bash
# Enable maintenance mode
echo -n "on" | gcloud secrets versions add maintenance-mode --data-file=-

# Disable maintenance mode
echo -n "off" | gcloud secrets versions add maintenance-mode --data-file=-
```

**Metrics**:
- **Latency Impact**:
  - First request: ~100-150ms (Secret Manager API call)
  - Subsequent requests: ~5-10ms (cached)
- **Ease of Use**: ⭐⭐⭐⭐
  - Integrated secret management
  - Versioning built-in
  - Audit logging
- **Cost**: 
  - $0.06 per 10,000 access operations
  - $0.03 per active secret version per month

### Option 3: Firestore Document

**How It Works**:
1. Create Firestore database
2. Store maintenance config as document
3. Cloud Run callout service uses Firestore SDK with realtime listeners
4. Near-instant updates without cache delay

**Application Team Workflow**:
```javascript
// Enable maintenance mode
db.collection('config').doc('maintenance').set({
  mode: 'on',
  message: 'Scheduled maintenance',
  updatedAt: new Date()
});
```

**Metrics**:
- **Latency Impact**:
  - All requests: ~10-20ms (Firestore read with SDK cache)
  - Realtime updates: < 1 second propagation
- **Ease of Use**: ⭐⭐⭐
  - Requires Firestore setup
  - More complex API
  - Best for teams already using Firestore
- **Cost**:
  - Document reads: $0.06 per 100,000
  - Document writes: $0.18 per 100,000
  - Storage: $0.18/GB/month

### Option 4: App Lifecycle Manager Feature Flags (NEW in 2026)

**How It Works**:
1. Use GCP's native feature flag service (OpenFeature standard)
2. Cloud Run callout service uses flagd provider
3. Real-time flag updates via saasconfig.googleapis.com

**Application Team Workflow**:
```bash
# Enable maintenance mode via gcloud
gcloud alpha app-lifecycle feature-flags update maintenance-mode \
  --value=on \
  --targeting="all-users"
```

**Metrics**:
- **Latency Impact**:
  - All requests: ~5-15ms (flagd local evaluation)
  - Realtime updates: < 2 seconds
- **Ease of Use**: ⭐⭐⭐⭐
  - GCP-native solution
  - OpenFeature standard
  - Currently in Preview (as of 2026)
- **Cost**: Pricing not yet published (Preview)

### Comparison Table

| Approach | Latency | Cost | Ease of Use | Cache Invalidation | Team Autonomy |
|----------|---------|------|-------------|-------------------|---------------|
| **GCS Bucket** | 5-10ms (cached) | Minimal (~$0.10/month) | ⭐⭐⭐⭐⭐ | TTL-based (5s) | High - gsutil/console access |
| **Secret Manager** | 5-10ms (cached) | Low (~$1/month) | ⭐⭐⭐⭐ | TTL-based (5s) | High - gcloud/API access |
| **Firestore** | 10-20ms | Medium (~$5/month) | ⭐⭐⭐ | Real-time (<1s) | Medium - requires SDK |
| **ALM Feature Flags** | 5-15ms | TBD (Preview) | ⭐⭐⭐⭐ | Real-time (<2s) | High - gcloud CLI |

**RECOMMENDATION**: **Cloud Storage Bucket** for simplicity and AWS parity, or **ALM Feature Flags** for a modern GCP-native approach (once GA).

---

## 🚀 Implementation Plan for nrg-gcp-infra/dev

### Phase 1: Setup Infrastructure (Week 1)

#### Step 1.1: Create GCS Config Bucket
**File**: `nrg-gcp-infra/dev/storage.tf`

```hcl
resource "google_storage_bucket" "ops_config" {
  name          = "${var.project_id}-ops-config"
  location      = "US"
  force_destroy = false
  
  uniform_bucket_level_access = true
  
  versioning {
    enabled = true
  }
  
  lifecycle_rule {
    condition {
      num_newer_versions = 3
    }
    action {
      type = "Delete"
    }
  }
}

# Upload initial config files
resource "google_storage_bucket_object" "maintenance_config" {
  name    = "maintenance.json"
  bucket  = google_storage_bucket.ops_config.name
  content = jsonencode({ maintenance = "off" })
}

resource "google_storage_bucket_object" "redirects_config" {
  name    = "redirects.json"
  bucket  = google_storage_bucket.ops_config.name
  content = jsonencode([])
}

resource "google_storage_bucket_object" "vanities_config" {
  name    = "vanities.json"
  bucket  = google_storage_bucket.ops_config.name
  content = jsonencode([])
}
```

#### Step 1.2: Create Service Account for Cloud Run
**File**: `nrg-gcp-infra/dev/iam.tf`

```hcl
resource "google_service_account" "maintenance_callout" {
  account_id   = "maintenance-callout-sa"
  display_name = "Service Extensions Callout Service Account"
}

resource "google_storage_bucket_iam_member" "callout_gcs_access" {
  bucket = google_storage_bucket.ops_config.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.maintenance_callout.email}"
}

# Grant app team access to update configs
resource "google_storage_bucket_iam_member" "app_team_access" {
  bucket = google_storage_bucket.ops_config.name
  role   = "roles/storage.objectAdmin"
  member = "group:app-team@nrg.com"  # Replace with actual group
}
```

### Phase 2: Build Cloud Run Callout Service (Week 2)

#### Step 2.1: Create Cloud Run Service Code
**File**: `nrg-gcp-infra/services/maintenance-callout/main.go` (example in Go)

```go
package main

import (
    "context"
    "encoding/json"
    "io"
    "time"
    
    "cloud.google.com/go/storage"
    pb "github.com/envoyproxy/go-control-plane/envoy/service/ext_proc/v3"
    "google.golang.org/grpc"
)

type ConfigCache struct {
    maintenance map[string]string
    redirects   []Redirect
    vanities    []Vanity
    lastFetch   time.Time
    ttl         time.Duration
}

type Redirect struct {
    Source      string `json:"source"`
    Destination string `json:"destination"`
}

type Vanity struct {
    Source      string `json:"source"`
    Destination string `json:"destination"`
}

func (s *Server) Process(stream pb.ExternalProcessor_ProcessServer) error {
    // Implement Envoy External Processing API
    // 1. Receive request headers from edge plugin
    // 2. Check cache or fetch from GCS
    // 3. Apply maintenance/redirect/vanity logic
    // 4. Return response to edge plugin
}
```

#### Step 2.2: Deploy Cloud Run Callout Service
**File**: `nrg-gcp-infra/dev/cloud_run_callout.tf`

**Note**: This is a **separate** Cloud Run service from your application service. If your application already runs on Cloud Run, you'll have two services:
- `${var.project_id}-maintenance-callout` (this new service for Service Extensions)
- `${var.project_id}-app` (your existing application service)

```hcl
# NEW Cloud Run Service - Callout Service for Service Extensions
resource "google_cloud_run_service" "maintenance_callout" {
  name     = "${var.project_id}-maintenance-callout"  # Different name from your app
  location = var.region
  
  template {
    spec {
      service_account_name = google_service_account.maintenance_callout.email
      
      containers {
        image = "gcr.io/${var.project_id}/maintenance-callout:${var.image_tag}"
        
        ports {
          container_port = 8080
          name          = "h2c"  # gRPC requires HTTP/2
        }
        
        env {
          name  = "GCS_BUCKET"
          value = google_storage_bucket.ops_config.name
        }
        
        env {
          name  = "CONFIG_TTL_SECONDS"
          value = "5"
        }
        
        resources {
          limits = {
            cpu    = "1000m"
            memory = "512Mi"
          }
        }
      }
    }
    
    metadata {
      annotations = {
        "autoscaling.knative.dev/minScale" = "1"  # Always warm
        "autoscaling.knative.dev/maxScale" = "100"
      }
    }
  }
  
  traffic {
    percent         = 100
    latest_revision = true
  }
}

# Allow Service Extensions to call Cloud Run
resource "google_cloud_run_service_iam_member" "public_access" {
  service  = google_cloud_run_service.maintenance_callout.name
  location = google_cloud_run_service.maintenance_callout.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}
```

### Phase 3: Build Service Extensions Plugin (Week 3)

#### Step 3.1: Create WebAssembly Plugin
**File**: `nrg-gcp-infra/plugins/maintenance-redirects/src/lib.rs` (Rust example)

Reference: https://github.com/GoogleCloudPlatform/service-extensions

```rust
use proxy_wasm::traits::*;
use proxy_wasm::types::*;

#[no_mangle]
pub fn _start() {
    proxy_wasm::set_http_context(|_, _| -> Box<dyn HttpContext> {
        Box::new(MaintenanceRedirectPlugin)
    });
}

struct MaintenanceRedirectPlugin;

impl HttpContext for MaintenanceRedirectPlugin {
    fn on_http_request_headers(&mut self, _: usize, _: bool) -> Action {
        // Make gRPC callout to Cloud Run service
        self.dispatch_grpc_call(
            "maintenance_callout_cluster",
            "ext_proc.ExternalProcessor",
            "Process",
            vec![],
            Some(&request_body),
            Duration::from_millis(500),
        );
        
        Action::Pause
    }
}
```

#### Step 3.2: Deploy Service Extensions
**File**: `nrg-gcp-infra/dev/service_extensions.tf`

```hcl
resource "google_network_services_lb_traffic_extension" "maintenance_redirects" {
  name                  = "${var.project_id}-maintenance-redirects"
  location              = "global"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  
  extension_chains {
    name = "maintenance-check"
    
    match_condition {
      cel_expression = "true"  # Apply to all requests
    }
    
    extensions {
      name    = "callout-maintenance"
      service = google_cloud_run_service.maintenance_callout.status[0].url
      timeout = "500ms"
      
      supported_events = ["REQUEST_HEADERS"]
    }
  }
}

# Attach to Load Balancer
resource "google_compute_url_map" "default" {
  name            = "${var.project_id}-url-map"
  default_service = google_compute_backend_service.default.id
  
  # Reference the traffic extension
  default_url_redirect {
    path_redirect = "/"
  }
}
```

### Phase 4: Testing & Validation (Week 4)

#### Test 1: Maintenance Mode
```bash
# Enable maintenance mode
echo '{"maintenance": "on"}' | gsutil cp - gs://PROJECT-ops-config/maintenance.json

# Test request
curl -I https://your-domain.com
# Expected: HTTP 200 with maintenance page content

# Disable maintenance mode
echo '{"maintenance": "off"}' | gsutil cp - gs://PROJECT-ops-config/maintenance.json

# Verify normal traffic flows
curl -I https://your-domain.com
# Expected: HTTP 200 from backend
```

#### Test 2: Redirects
```bash
# Add redirect rule
cat > redirects.json <<EOF
[
  {
    "source": "^/old-path.*$",
    "destination": "https://new-domain.com/new-path"
  }
]
EOF

gsutil cp redirects.json gs://PROJECT-ops-config/redirects.json

# Test redirect
curl -I https://your-domain.com/old-path
# Expected: HTTP 301 Location: https://new-domain.com/new-path
```

#### Test 3: Vanity Domains
```bash
# Add vanity URL
cat > vanities.json <<EOF
[
  {
    "source": "/PROMO2026",
    "destination": "https://www.example.com/promotions/spring-2026"
  }
]
EOF

gsutil cp vanities.json gs://PROJECT-ops-config/vanities.json

# Test vanity URL
curl -I https://your-domain.com/PROMO2026
# Expected: HTTP 301 Location: https://www.example.com/promotions/spring-2026
```

---

## 📋 Alternative Simpler Approach (If Complexity is a Concern)

### Cloud Armor + URL Maps (Code-Free)

For basic redirects without dynamic maintenance mode:

```hcl
# URL Map for static redirects
resource "google_compute_url_map" "redirects" {
  name = "${var.project_id}-redirects"
  
  # Static redirects
  host_rule {
    hosts        = ["vanity.example.com"]
    path_matcher = "vanity-redirects"
  }
  
  path_matcher {
    name = "vanity-redirects"
    
    path_rule {
      paths = ["/PROMO2026"]
      url_redirect {
        https_redirect = true
        host_redirect  = "www.example.com"
        path_redirect  = "/promotions/spring-2026"
        redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
      }
    }
  }
}
```

**Limitations**:
- ❌ No dynamic maintenance mode (requires Terraform apply)
- ❌ No regex redirects
- ✅ Simple to implement
- ✅ No code deployment

---

## 🎓 Key Recommendations

### ✅ DO: Service Extensions + Cloud Run (Recommended)
- **Pros**: AWS parity, application team control, cost-effective
- **Cons**: Rust/C++ learning curve for WebAssembly
- **Timeline**: 4 weeks initial setup, reusable for other environments

### ⚠️ CONSIDER: Simplified Approach First
If your team is new to GCP:
1. Start with Cloud Armor + URL Maps for static redirects
2. Build Cloud Run callout service in parallel
3. Migrate to Service Extensions when ready

### ❌ AVOID: Cloud Functions + CDN
- Regional execution (not true edge)
- Higher latency than Service Extensions
- Not designed for this use case

---

## 🔍 Performance & Operational Considerations

### Performance Implications

**AWS Lambda@Edge**:
- Executes at 600+ CloudFront edge locations
- Cold start: ~10-50ms (Node.js runtime already warm)
- Warm execution: ~1-5ms
- S3 read latency: 20-50ms (first read, then 5s cache)

**GCP Service Extensions**:
- Executes at Google's global edge network
- WebAssembly cold start: < 1ms (compiled ahead of time)
- Warm execution: ~0.5-2ms (WebAssembly performance)
- gRPC callout: 10-30ms (to nearest Cloud Run region, then cached)
- **Overall similar performance** to Lambda@Edge with proper caching

### Operational Complexity

**AWS**:
- ✅ Simple: Upload config to S3
- ✅ Global propagation via CloudFront edge cache
- ✅ No additional services to manage
- ❌ Terraform required for Lambda code changes

**GCP**:
- ❌ Complex: WebAssembly plugin development (Rust/C++)
- ❌ Additional service: Cloud Run callout backend
- ❌ Two-tier caching (Cloud Run + edge plugin)
- ✅ More flexible: gRPC allows richer logic
- ⚠️ Learning curve: Proxy-Wasm ABI, Envoy external processing API

### Team Autonomy for Maintenance Mode

**AWS**: ⭐⭐⭐⭐⭐
- App teams update S3 file directly
- No Terraform/code deployment needed
- IAM policy grants S3 bucket access
- 5-second TTL for changes

**GCP (Recommended Approach)**: ⭐⭐⭐⭐
- App teams update GCS file via gsutil
- No Terraform/code deployment needed
- IAM policy grants GCS bucket access
- 5-10 second TTL for changes (callout cache + edge cache)

**GCP (Alternative - Cloud Armor)**: ⭐⭐
- Requires Terraform apply to enable/disable maintenance mode
- Less autonomy for app teams
- Change takes 1-2 minutes to propagate

---

## ❓ Frequently Asked Questions

### Q1: Is Cloud Run callout service required if my application backend is already a GCS bucket?

**Answer: YES, Cloud Run is still required.**

**Why?** There are **two separate GCS buckets** serving different purposes:

1. **Application Backend Bucket** (your website)
   - Example: `my-app-website-assets`
   - Contains: index.html, style.css, images, etc.
   - Purpose: Hosts your actual website/application
   - Accessed by: Users after passing maintenance checks

2. **Configuration Storage Bucket** (maintenance settings)
   - Example: `my-app-ops-config`  
   - Contains: maintenance.json, redirects.json, vanities.json
   - Purpose: Stores operational configuration
   - Accessed by: Cloud Run callout service only

**The Cloud Run service is needed because:**
- Service Extensions WebAssembly plugins **cannot directly access GCS**
- WebAssembly runtime has no GCS SDK or client libraries
- WebAssembly can **only** make gRPC callouts to external services
- Cloud Run acts as a **bridge/middleware** to read GCS configuration

**Analogy**: Think of it like AWS Lambda@Edge reading from S3 - except in GCP, the WebAssembly plugin cannot directly read from GCS, so you need Cloud Run as an intermediary.

### Q2: Can I skip Cloud Run and put configuration directly in the WebAssembly plugin?

**Answer: Not recommended for maintenance mode control.**

You could hard-code configuration in the WebAssembly plugin, but:
- ❌ Every config change requires recompiling WebAssembly
- ❌ Every config change requires redeploying Service Extensions
- ❌ Application teams lose autonomy (need infrastructure changes)
- ❌ No way to toggle maintenance mode quickly

The Cloud Run + GCS approach allows:
- ✅ Application teams update GCS files directly (no infrastructure deployment)
- ✅ Changes propagate in 5-10 seconds (cache TTL)
- ✅ No code changes needed for config updates
- ✅ Matches AWS Lambda@Edge + S3 pattern

### Q3: Do I need a separate Cloud Run service for the callout, or can I use my existing application Cloud Run service?

**Answer: You need a SEPARATE Cloud Run service.**

**Two distinct Cloud Run services are required:**

| Aspect | Callout Service (NEW) | Application Service (Existing) |
|--------|----------------------|-------------------------------|
| **Purpose** | Middleware for Service Extensions | Your actual application |
| **Protocol** | gRPC (HTTP/2) | HTTP/HTTPS |
| **Endpoint** | Envoy External Processing API | Your application routes |
| **Called By** | Service Extensions edge plugin | End users |
| **Function** | Read GCS configs, return decisions | Serve your application |
| **Request Pattern** | Many small requests from global edge | User traffic after checks pass |
| **Scaling** | Min instances = 1 (always warm) | Based on app needs |
| **Port** | 8080 (h2c - HTTP/2 cleartext) | 8080 or 443 (HTTPS) |

**Why separate?**

1. **Different Protocols**:
   - Callout service implements **gRPC server** (specific protocol required by Service Extensions)
   - Application service handles **HTTP/HTTPS** (normal web traffic)

2. **Different Performance Characteristics**:
   - Callout service needs **ultra-low latency** (affects every request at edge)
   - Should have **min instances = 1** (always warm, no cold starts)
   - Application service can scale to zero if needed

3. **Separation of Concerns**:
   - Callout service = infrastructure logic (maintenance checks)
   - Application service = business logic (your app)
   - Easier to maintain, debug, and scale independently

4. **Different Traffic Patterns**:
   - Callout service receives requests from **global edge locations** (high frequency)
   - Application service receives requests from **users** (only after maintenance checks pass)

**Can I combine them into one service?**

Technically yes, but **not recommended**:
- ❌ More complex - service handles both gRPC and HTTP
- ❌ Harder to debug - mixed concerns
- ❌ Could impact app performance
- ❌ Scaling becomes more complex
- ✅ Only benefit: one less service to manage

**Recommendation**: Create a dedicated callout service - it's lightweight and specifically designed for this purpose.

### Q4: What happens if the Cloud Run callout service goes down? How does the system handle failures?

**Answer: This is a critical concern - the callout service is a potential single point of failure.**

#### Failure Behavior

When the callout service is **down or unreachable**, Service Extensions will:

1. **Wait for timeout** (configured timeout, e.g., 500ms)
2. **Return an error** to the Service Extensions plugin
3. **Plugin must decide**: fail-open (allow traffic) or fail-closed (block traffic)

**Scenario 1: Callout Service Down with FAIL-OPEN (Recommended)**
```
User Request → Load Balancer → Service Extensions Plugin
                                        ↓
                                   Try gRPC callout
                                        ↓
                        Cloud Run Callout Service: ❌ DOWN
                                        ↓
                        Wait 500ms → Timeout Error
                                        ↓
                        Plugin Decision: FAIL-OPEN
                                        ↓
                        ✅ Allow request to Application Backend
                                        ↓
                        User receives normal response
                        
⚠️  Impact: Maintenance mode bypassed, redirects don't work
✅  Benefit: Site stays up, users can access application
```

**Scenario 2: Callout Service Down with FAIL-CLOSED (High Security)**
```
User Request → Load Balancer → Service Extensions Plugin
                                        ↓
                                   Try gRPC callout
                                        ↓
                        Cloud Run Callout Service: ❌ DOWN
                                        ↓
                        Wait 500ms → Timeout Error
                                        ↓
                        Plugin Decision: FAIL-CLOSED
                                        ↓
                        ❌ Return 503 Service Unavailable
                                        ↓
                        User sees error page
                        
⚠️  Impact: Entire site goes down
✅  Benefit: Security maintained, no unintended access
```

**Scenario 3: High Availability with Multi-Instance (Recommended Production)**
```
User Request → Load Balancer → Service Extensions Plugin
                                        ↓
                                   Try gRPC callout
                                        ↓
                        Cloud Run Instance 1: ❌ DOWN
                                        ↓
                        Cloud Run Load Balancer
                                        ↓
                        Cloud Run Instance 2: ✅ UP
                                        ↓
                        Return maintenance config
                                        ↓
                        ✅ Normal operation continues
                        
✅  No user impact, seamless failover
✅  Maintenance mode still enforced
```

#### High Availability Solutions

**Solution 1: Fail-Open with Monitoring (RECOMMENDED for most cases)**

Configure the WebAssembly plugin to **allow traffic** when callout fails:

```rust
// WebAssembly plugin logic
impl HttpContext for MaintenanceRedirectPlugin {
    fn on_http_request_headers(&mut self, _: usize, _: bool) -> Action {
        match self.dispatch_grpc_call(...) {
            Ok(_) => Action::Pause,  // Wait for response
            Err(e) => {
                // Log error and FAIL-OPEN
                log::warn!("Callout failed: {:?}, allowing traffic", e);
                Action::Continue  // ✅ Allow request to proceed to backend
            }
        }
    }
    
    fn on_grpc_call_response(&mut self, token_id: u32, status_code: u32, ...) {
        if status_code != 0 {
            // Callout failed or timed out
            log::error!("Callout error: {}", status_code);
            // FAIL-OPEN: Continue to backend
            self.resume_http_request();
        } else {
            // Process maintenance/redirect decision
        }
    }
}
```

**Pros**:
- ✅ Site stays available even if callout service is down
- ✅ User experience not impacted
- ✅ Most resilient option

**Cons**:
- ⚠️ Maintenance mode cannot be enforced during outage
- ⚠️ Redirects won't work during outage
- ⚠️ Need monitoring to detect callout failures

**Solution 2: Cloud Run High Availability Configuration**

Make the callout service highly available:

```hcl
resource "google_cloud_run_service" "maintenance_callout" {
  name     = "${var.project_id}-maintenance-callout"
  location = var.region
  
  template {
    metadata {
      annotations = {
        # Always keep at least 2 instances running
        "autoscaling.knative.dev/minScale" = "2"
        "autoscaling.knative.dev/maxScale" = "100"
        
        # CPU always allocated (faster response)
        "run.googleapis.com/cpu-throttling" = "false"
      }
    }
    
    spec {
      # Multiple concurrent requests per instance
      container_concurrency = 1000
      
      # Faster startup
      timeout_seconds = 300
      
      containers {
        # Use readiness/liveness probes
        startup_probe {
          http_get {
            path = "/healthz"
          }
          initial_delay_seconds = 0
          timeout_seconds       = 1
          period_seconds        = 3
          failure_threshold     = 3
        }
        
        liveness_probe {
          http_get {
            path = "/healthz"
          }
          period_seconds = 10
        }
        
        resources {
          limits = {
            cpu    = "2000m"  # More CPU for reliability
            memory = "1Gi"
          }
        }
      }
    }
  }
}
```

**Solution 3: Multi-Region Deployment**

Deploy callout service in **multiple regions** with global load balancing:

```hcl
# Deploy to multiple regions
module "callout_us_central" {
  source = "./modules/callout-service"
  region = "us-central1"
}

module "callout_us_east" {
  source = "./modules/callout-service"
  region = "us-east1"
}

module "callout_europe_west" {
  source = "./modules/callout-service"
  region = "europe-west1"
}

# Global Load Balancer for callout service
resource "google_compute_global_forwarding_rule" "callout_lb" {
  name       = "callout-service-lb"
  target     = google_compute_target_grpc_proxy.callout_proxy.id
  port_range = "443"
  ip_address = google_compute_global_address.callout_ip.address
}

resource "google_compute_backend_service" "callout_backend" {
  name     = "callout-backend"
  protocol = "GRPC"
  
  backend {
    group = module.callout_us_central.neg_id
  }
  
  backend {
    group = module.callout_us_east.neg_id
  }
  
  backend {
    group = module.callout_europe_west.neg_id
  }
  
  health_checks = [google_compute_health_check.callout_health.id]
}
```

**Solution 4: Circuit Breaker Pattern**

Implement circuit breaker in the callout service or plugin:

```go
// Cloud Run Callout Service with circuit breaker
type CircuitBreaker struct {
    failureThreshold int
    failureCount     int
    state            string  // "closed", "open", "half-open"
    lastFailureTime  time.Time
}

func (cb *CircuitBreaker) Call(fn func() error) error {
    if cb.state == "open" {
        if time.Since(cb.lastFailureTime) > 30*time.Second {
            cb.state = "half-open"
        } else {
            return errors.New("circuit breaker open")
        }
    }
    
    err := fn()
    if err != nil {
        cb.failureCount++
        cb.lastFailureTime = time.Now()
        if cb.failureCount >= cb.failureThreshold {
            cb.state = "open"
        }
    } else {
        cb.failureCount = 0
        cb.state = "closed"
    }
    
    return err
}
```

#### Comparison of Approaches

| Approach | Availability | Complexity | Cost | Recommendation |
|----------|-------------|------------|------|----------------|
| **Fail-Open** | ⭐⭐⭐⭐⭐ | ⭐ (simple) | $ | Best for most cases |
| **Min Instances = 2** | ⭐⭐⭐⭐ | ⭐⭐ | $$ | Good baseline |
| **Multi-Region** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | $$$ | Enterprise/critical apps |
| **Circuit Breaker** | ⭐⭐⭐⭐ | ⭐⭐⭐ | $$ | Advanced resilience |

#### Recommended Production Setup

```hcl
resource "google_cloud_run_service" "maintenance_callout" {
  name     = "${var.project_id}-maintenance-callout"
  location = var.region
  
  template {
    metadata {
      annotations = {
        # Keep 2 instances always running (99.95% uptime SLA)
        "autoscaling.knative.dev/minScale" = "2"
        "autoscaling.knative.dev/maxScale" = "100"
        
        # No CPU throttling for consistent performance
        "run.googleapis.com/cpu-throttling" = "false"
        
        # Enable session affinity for better caching
        "run.googleapis.com/session-affinity" = "true"
      }
    }
    
    spec {
      service_account_name  = google_service_account.maintenance_callout.email
      container_concurrency = 1000
      timeout_seconds       = 10  # Short timeout
      
      containers {
        image = "gcr.io/${var.project_id}/maintenance-callout:${var.image_tag}"
        
        env {
          name  = "CONFIG_TTL_SECONDS"
          value = "5"
        }
        
        # Health check endpoint
        startup_probe {
          http_get {
            path = "/healthz"
          }
        }
        
        resources {
          limits = {
            cpu    = "1000m"
            memory = "512Mi"
          }
        }
      }
    }
  }
}

# Monitoring alert
resource "google_monitoring_alert_policy" "callout_down" {
  display_name = "Callout Service Down"
  conditions {
    display_name = "Callout service request errors > 1%"
    condition_threshold {
      filter          = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${google_cloud_run_service.maintenance_callout.name}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0.01  # 1% error rate
      duration        = "60s"
    }
  }
  
  notification_channels = [var.alert_channel_id]
  alert_strategy {
    auto_close = "3600s"
  }
}
```

#### Timeout Configuration

**Service Extensions timeout setting**:
```hcl
resource "google_network_services_lb_traffic_extension" "maintenance_redirects" {
  # ...
  extension_chains {
    extensions {
      name    = "callout-maintenance"
      service = google_cloud_run_service.maintenance_callout.status[0].url
      timeout = "500ms"  # ⚠️ Fail fast if callout is slow/down
    }
  }
}
```

**Best Practices**:
- ✅ Set timeout to 500ms or less (don't wait too long)
- ✅ Implement fail-open behavior (allow traffic during outage)
- ✅ Keep min instances = 2 for high availability
- ✅ Monitor callout service health and error rates
- ✅ Set up alerts for callout failures
- ✅ Test failure scenarios regularly

#### SLA Impact

| Configuration | Expected Uptime | Failure Impact |
|---------------|-----------------|----------------|
| Min instances = 0 | ~99.5% | Site may go down during cold starts |
| Min instances = 1 | ~99.9% | Brief outage during deployments |
| Min instances = 2 | ~99.95% | No user-facing impact (fail-over) |
| Multi-region | ~99.99% | Extremely rare outages |

**Recommended**: Start with **min instances = 2** and **fail-open** behavior for 99.95% uptime with graceful degradation.

#### Decision Matrix: Which Failure Strategy?

| Use Case | Recommended Strategy | Rationale |
|----------|---------------------|-----------|
| **Public website** | Fail-Open + Min Instances = 2 | Availability more important than maintenance enforcement |
| **E-commerce** | Multi-Region + Fail-Open | Revenue loss during downtime unacceptable |
| **Internal tools** | Fail-Open + Min Instances = 1 | Lower availability requirements, cost-conscious |
| **Compliance/Security-critical** | Fail-Closed + Multi-Region | Security more important than availability |
| **Dev/Test environment** | Fail-Open + Min Instances = 0 | Cost optimization, occasional cold starts acceptable |

#### Cost Impact of HA Strategies

**Example**: 100M requests/month

| Configuration | Cloud Run Cost | Total Monthly Cost |
|---------------|---------------|-------------------|
| Min = 0, Fail-Open | ~$4 (pay per request only) | ~$15-20 |
| Min = 1, Fail-Open | ~$15 (1 instance always running) | ~$25-30 |
| Min = 2, Fail-Open | ~$30 (2 instances always running) | ~$40-45 |
| Multi-Region (3), Min = 2 each | ~$90 (6 instances total) | ~$100-120 |

**Cost Formula**:
- Always-on instance: ~$15/month per instance (1 vCPU, 512MB)
- Request cost: $0.40 per 1M requests
- Multi-region adds latency benefit + redundancy

### Q5: Do I always need the Cloud Run callout service? Can I use simpler approaches?

**Answer: No, Cloud Run callout is NOT always required!**

The need for Cloud Run depends on your **dynamic configuration requirements**:

#### Requirements vs. Architecture Decision Matrix

| Requirement | Cloud Run Callout Service Required? | Alternative Approach | Complexity |
|-------------|-----------------------------------|----------------------|------------|
| **Static maintenance page** | ❌ **Not required** | Cloud Armor redirect rule or URL Map | ⭐ (Simple) |
| **Standard URL redirects** (fixed paths) | ❌ **Not required** | URL Map path rules | ⭐ (Simple) |
| **Vanity domain routing** (static) | ❌ **Not required** | URL Map host rules | ⭐ (Simple) |
| **Dynamic maintenance toggle** (app team controlled) | ✅ **Required** | Cloud Run reads GCS config | ⭐⭐⭐ (Complex) |
| **Regex-based redirects** | ✅ **Required** | Cloud Run + Service Extensions | ⭐⭐⭐ (Complex) |
| **Custom runtime routing logic** | ✅ **Required** | Cloud Run + Service Extensions | ⭐⭐⭐⭐ (Very Complex) |
| **Header/Cookie-based decisions** | ✅ **Required** | Cloud Run + Service Extensions | ⭐⭐⭐⭐ (Very Complex) |

#### Decision Tree

```
Do you need APPLICATION TEAMS to toggle maintenance mode without Terraform?
│
├─ NO → Do you need regex redirects or complex routing?
│   │
│   ├─ NO → ✅ Use URL Maps + Cloud Armor (NO Cloud Run needed)
│   │         • Static redirects in Terraform
│   │         • Maintenance mode via Terraform apply
│   │         • Simplest approach
│   │
│   └─ YES → ✅ Use Service Extensions + Cloud Run
│              • Complex routing logic
│              • Regex patterns
│              • High complexity
│
└─ YES → ✅ Use Service Extensions + Cloud Run
           • App team controls via GCS bucket
           • No Terraform needed for toggles
           • Medium-high complexity
```

#### Three Approaches Compared

**Approach 1: URL Maps + Cloud Armor (SIMPLEST - No Cloud Run)**

```hcl
# For STATIC maintenance page (all traffic redirected)
resource "google_compute_security_policy" "maintenance" {
  name = "maintenance-policy"
  
  # Priority 100: Maintenance mode (when enabled via Terraform)
  rule {
    priority = 100
    action   = "redirect"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    redirect_options {
      type = "EXTERNAL_302"
      target = "https://storage.googleapis.com/my-app-maintenance/maintenance.html"
    }
  }
}

# For STATIC redirects
resource "google_compute_url_map" "redirects" {
  name = "static-redirects"
  
  path_matcher {
    name = "redirects"
    
    path_rule {
      paths = ["/old-path"]
      url_redirect {
        path_redirect = "/new-path"
        redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
      }
    }
    
    path_rule {
      paths = ["/PROMO2026"]
      url_redirect {
        host_redirect = "www.example.com"
        path_redirect = "/promotions/spring-2026"
        redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
      }
    }
  }
}
```

**Pros**:
- ✅ **No Cloud Run service** to manage
- ✅ **No Service Extensions** complexity
- ✅ **No WebAssembly** to learn
- ✅ **Lowest cost** (~$0 beyond load balancer)
- ✅ **Simplest architecture**

**Cons**:
- ❌ Maintenance mode requires **Terraform apply** (1-2 min to enable)
- ❌ App teams cannot toggle maintenance mode themselves
- ❌ No regex redirects (exact path matches only)
- ❌ Limited to simple use cases

**When to Use**:
- You have < 20 static redirects
- Maintenance mode changes are rare (quarterly/annually)
- Infrastructure team controls all changes via Terraform
- Dev/test environments

---

**Approach 2: Service Extensions + Cloud Run (RECOMMENDED FOR YOUR USE CASE)**

```hcl
# Cloud Run callout service
resource "google_cloud_run_service" "maintenance_callout" {
  name = "maintenance-callout"
  # ... implements gRPC, reads GCS bucket
}

# Service Extensions
resource "google_network_services_lb_traffic_extension" "maintenance" {
  name = "maintenance-redirects"
  extension_chains {
    extensions {
      name    = "callout-maintenance"
      service = google_cloud_run_service.maintenance_callout.status[0].url
    }
  }
}
```

**Pros**:
- ✅ **App teams control** maintenance mode via GCS bucket
- ✅ Changes take effect in **5-10 seconds** (no Terraform)
- ✅ **Regex redirects** supported
- ✅ **Dynamic routing logic** possible
- ✅ **Matches AWS Lambda@Edge** pattern

**Cons**:
- ❌ Higher complexity (Cloud Run service to manage)
- ❌ Potential single point of failure (mitigated with min instances = 2)
- ❌ Higher cost (~$40-50/month with HA)
- ❌ Additional latency (~10-30ms per request for callout)

**When to Use**:
- App teams need to toggle maintenance mode independently
- You need regex-based redirects
- You have dynamic routing requirements
- Production environments with operational autonomy

---

**Approach 3: Hybrid (Static + Dynamic)**

Combine URL Maps for static redirects + Service Extensions for dynamic maintenance:

```hcl
# URL Map for STATIC vanity redirects
resource "google_compute_url_map" "static_redirects" {
  name = "static-redirects"
  
  path_matcher {
    name = "vanities"
    path_rule {
      paths = ["/PROMO2026", "/ABOUTCARE", "/ACCOUNTTOOLS"]
      # ... static redirects
    }
  }
}

# Service Extensions ONLY for dynamic maintenance toggle
resource "google_network_services_lb_traffic_extension" "maintenance_only" {
  name = "maintenance-toggle"
  extension_chains {
    extensions {
      name = "callout-maintenance"
      # Cloud Run only checks maintenance.json (not redirects)
    }
  }
}
```

**Pros**:
- ✅ Best of both worlds
- ✅ Static redirects = simple and fast (no callout latency)
- ✅ Dynamic maintenance = app team controlled
- ✅ Lower Cloud Run load (only maintenance checks, not redirects)

**Cons**:
- ⚠️ Still need Cloud Run service
- ⚠️ Redirects split between two systems (harder to manage)

**When to Use**:
- You have many static redirects + need dynamic maintenance mode
- Want to optimize performance (avoid callout for redirects)

---

#### Architecture Complexity vs. Capabilities

```
Simple ←───────────────────────────────────────────→ Complex
Low Cost ←─────────────────────────────────────────→ High Cost
Limited ←──────────────────────────────────────────→ Full Control

┌──────────────────────┐  ┌──────────────────────┐  ┌──────────────────────┐
│  URL Maps + Armor    │  │  Hybrid Approach     │  │ Service Extensions + │
│  (No Cloud Run)      │  │  (Selective Use)     │  │ Cloud Run Callout    │
├──────────────────────┤  ├──────────────────────┤  ├──────────────────────┤
│ Capabilities:        │  │ Capabilities:        │  │ Capabilities:        │
│ • Static redirects   │  │ • Static redirects   │  │ • Dynamic maintenance│
│ • Fixed maintenance  │  │ • Dynamic maintenance│  │ • Regex redirects    │
│                      │  │   (via Cloud Run)    │  │ • Custom routing     │
│                      │  │                      │  │ • Header-based logic │
├──────────────────────┤  ├──────────────────────┤  ├──────────────────────┤
│ Complexity: ⭐       │  │ Complexity: ⭐⭐⭐   │  │ Complexity: ⭐⭐⭐⭐ │
│ Cost: $0-5/mo        │  │ Cost: $20-30/mo      │  │ Cost: $40-50/mo      │
│ Latency: <1ms        │  │ Latency: ~5ms avg    │  │ Latency: ~15ms avg   │
│ App Team Control: ❌ │  │ App Team Control: ✅ │  │ App Team Control: ✅ │
│ Terraform Changes: ✅ │  │ Terraform Changes: ⚠️│  │ Terraform Changes: ❌ │
└──────────────────────┘  └──────────────────────┘  └──────────────────────┘

Use When:                 Use When:                 Use When:
• Dev/test environments   • Prod with occasional    • Full AWS parity needed
• <10 redirects           maintenance needs        • Frequent maintenance
• Rare maintenance        • Mix of static/dynamic  • Complex redirects
• Infrastructure team     • Cost-conscious         • App team autonomy
  controls everything                              
```

#### Recommendation Based on Your Requirements

**✅ PRIMARY RECOMMENDATION: Service Extensions + Cloud Run Callout (Approach 2)**

Use this if you answered YES to ANY of these:
1. ✅ App teams need to toggle maintenance mode **without Terraform**?
2. ✅ You need **regex-based redirects** (like `^/files.*$`)?
3. ✅ Changes must take effect **quickly** (< 1 minute)?
4. ✅ You want to **match AWS Lambda@Edge** functionality?
5. ✅ This is for a **production environment**?

**Alternative: URL Maps + Cloud Armor (Approach 1)**

Use this ONLY if ALL of these are true:
- ❌ Infrastructure team manages maintenance mode (Terraform apply acceptable)
- ❌ You have < 10 static redirects
- ❌ Redirects rarely change
- ❌ This is a dev/test environment
- ❌ Cost minimization is critical

#### Your AWS Implementation Analysis

Based on your AWS Lambda@Edge implementation review:
- ✅ Uses **S3 bucket** for config (maintenance.conf, redirects.conf, vanities.conf)
- ✅ App teams **update S3 files** to toggle maintenance
- ✅ Supports **regex redirects** (`^/files.*$`)
- ✅ **5-second cache** TTL for changes

**Conclusion**: Your AWS setup requires **Approach 2** (Service Extensions + Cloud Run) for GCP parity.

### Q6: Alternative: Use Cloud Armor + URL Maps (Code-Free)

For **static redirects only** (no dynamic maintenance mode):
```hcl
# No Service Extensions, no Cloud Run, no WebAssembly
resource "google_compute_url_map" "redirects" {
  name = "static-redirects"
  
  path_matcher {
    name = "redirects"
    path_rule {
      paths = ["/old-path"]
      url_redirect {
        path_redirect = "/new-path"
        redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
      }
    }
  }
}
```

**Limitations:**
- ❌ Maintenance mode requires Terraform apply (not app-team controlled)
- ❌ No regex redirects (only exact path matches)
- ❌ Limited to simple use cases

**When to use this:**
- You have < 10 static redirects
- You don't need dynamic maintenance mode
- You want minimal infrastructure complexity

---

## 📚 Next Steps

1. **Review Architecture**: Discuss recommended approach with team
2. **Prototype**: Build Cloud Run callout service first (can be tested independently)
3. **Learn WebAssembly**: Explore [GoogleCloudPlatform/service-extensions](https://github.com/GoogleCloudPlatform/service-extensions) samples
4. **Terraform Modules**: Create reusable module for other environments (stage, prod)
5. **Documentation**: Document app team workflows for maintenance mode control

---

## 📖 References

### AWS Lambda@Edge Implementation
- Internal repository: `nrg-aws-infra/nrg-aws-automation/terraform/`
- Lambda source: `nrg-digital-commons/lambdas/source/lae-maintenance-and-redirects.js.tftpl`

### GCP Service Extensions
- [Cloud Load Balancing and Cloud CDN extensions overview](https://docs.cloud.google.com/service-extensions/docs/lb-extensions-overview)
- [Service Extensions plugins for Application Load Balancers](https://cloud.google.com/blog/products/networking/service-extensions-plugins-for-application-load-balancers)
- [Configure an edge extension](https://docs.cloud.google.com/service-extensions/docs/configure-edge-extensions)
- [Use Service Extensions for edge compute](https://docs.cloud.google.com/cdn/docs/integration-with-service-extensions)
- [GitHub - GoogleCloudPlatform/service-extensions](https://github.com/GoogleCloudPlatform/service-extensions)
- [Understanding Service Extensions callouts](https://cloud.google.com/blog/products/networking/understanding-service-extensions-callouts)
- [Run Service Extensions plugins with Cloud CDN](https://cloud.google.com/blog/products/networking/run-service-extensions-plugins-with-cloud-cdn)

### Migration Guidance
- [How to Map AWS Services to GCP Equivalents During Cloud Migration](https://oneuptime.com/blog/post/2026-02-17-how-to-map-aws-services-to-gcp-equivalents-during-cloud-migration/view)
- [Migrate from AWS to Google Cloud: Migrate from AWS Lambda to Cloud Run](https://docs.cloud.google.com/architecture/migrate-aws-lambda-to-cloudrun)
- [AWS Lambda@Edge vs Google Cloud Functions (2026): Pricing, Features & Performance](https://www.srvrlss.io/compare/amazon-lambda-edge-vs-google-cloud-functions/)

### GCP Feature Flags and Configuration
- [New feature flags in AppLifecycle Manager](https://cloud.google.com/blog/products/application-development/new-feature-flags-in-applifecycle-manager)
- [App Lifecycle Manager feature flags overview](https://docs.cloud.google.com/saas-runtime/docs/flags/flags-overview)
- [Quickstart: Deploy feature flags](https://docs.cloud.google.com/saas-runtime/docs/flags/flags-quickstart)

---

**Document Version**: 1.0  
**Last Updated**: 2026-09-17  
**Status**: Approved for Implementation
