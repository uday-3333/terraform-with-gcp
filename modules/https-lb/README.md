# GCP External HTTPS Cloud Load Balancer for Cloud Run Module

A production-ready Terraform module that provisions a global External HTTPS Cloud Load Balancer for Google Cloud Run applications using serverless Network Endpoint Groups (NEGs). This module supports custom domains, Google-managed SSL certificates, Cloud Armor security policies (external and user-managed), and Cloud CDN.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Module Usage](#module-usage)
- [Architecture](#architecture)
- [Important Notes](#important-notes)
- [SSL Certificate Provisioning](#ssl-certificate-provisioning)
- [DNS Configuration](#dns-configuration)
- [Security Best Practices](#security-best-practices)
- [Troubleshooting](#troubleshooting)
- [Variables](#variables)
- [Outputs](#outputs)

## Overview

This Terraform module creates a complete External HTTPS load balancing solution for multiple Cloud Run applications. Unlike traditional load balancers, serverless NEGs eliminate the need for:

- Custom VPC networking
- Network configuration
- Instance groups
- Manual traffic routing

The module now supports flexible routing to **multiple Cloud Run services** on a single load balancer, enabling:

1. **Host-based Routing** - Route api.example.com to one service, web.example.com to another
2. **Path-based Routing** - Route /api/* paths to API service, /web/* paths to web service
3. **Combined Routing** - Use both host and path rules simultaneously for complex architectures
4. **Per-service Security Policies** - Attach external Cloud Armor policies per backend service
5. **Single Global Entry Point** - One static IP and SSL certificate for all services

The module handles:

1. **Global External HTTPS Load Balancer** with automatic HTTP to HTTPS redirect
2. **Dynamic Serverless NEGs** - One per Cloud Run service for direct integration
3. **Google-Managed SSL Certificates** for custom domains
4. **Default SSL Policy** with `min_tls_version = "TLS_1_2"` and `profile = "MODERN"` (override supported)
5. **Mandatory Logging** - Request logging for all backend services with configurable sample rate
6. **Cloud CDN** for content acceleration (global defaults with optional per-service overrides)
7. **Cloud Armor Policy Attachment** per backend service using external user-managed policies
8. **Advanced Multi-Service Routing** with host rules and path-based routing

## Features

✅ **Multi-Service Support** - Route multiple Cloud Run services on a single load balancer  
✅ **Flexible Routing** - Host-based and path-based routing to different services  
✅ **Global Serverless Load Balancing** - Route traffic to Cloud Run services  
✅ **Custom Domain Support** - Use custom domains with external DNS providers  
✅ **Google-Managed Certificates** - Automatic SSL/TLS certificate provisioning  
✅ **Secure TLS Defaults** - Module-managed SSL policy (`TLS_1_2` + `MODERN`) with external override support  
✅ **Logging** - Mandatory request logging for load balancer traffic monitoring  
✅ **Cloud CDN Integration** - Configurable caching policies  
✅ **Cloud Armor Security** - External Cloud Armor policy attachment per backend service  
✅ **Per-Service Security Policies** - Independent Cloud Armor policy attachment per service  
✅ **Terraform Best Practices** - Comprehensive validation and naming conventions  

## Prerequisites

1. **GCP Project** - Active GCP project with billing enabled
2. **Cloud Run Service** - Deployed Cloud Run service (module does not create this)
3. **Terraform** - v1.0 or later
4. **Google Terraform Provider** - v5.0 or later
5. **External DNS** - DNS hosting with a provider outside of Google Cloud DNS
6. **Service Account Permissions** - Service account must have the following roles:
   - `compute.admin` - To manage load balancing resources
   - `compute.securityAdmin` - To manage Cloud Armor policies
   - `compute.networkAdmin` - To manage network resources
   - `compute.addresses.create` - To reserve static IP addresses

### Required IAM Permissions

```yaml
permissions:
  - compute.globalAddresses.create
  - compute.globalAddresses.delete
  - compute.globalAddresses.get
  - compute.globalForwardingRules.create
  - compute.globalForwardingRules.delete
  - compute.targetHttpsProxies.create
  - compute.targetHttpsProxies.delete
  - compute.urlMaps.create
  - compute.urlMaps.delete
  - compute.sslCertificates.create
  - compute.sslCertificates.delete
  - compute.backendServices.create
  - compute.backendServices.delete
  - compute.healthChecks.create
  - compute.healthChecks.delete
  - compute.networkEndpointGroups.get
  - compute.securityPolicies.create
  - compute.securityPolicies.delete
```

## Module Usage

### Minimal Example (Moved from examples/minimal_example.tf)

```hcl
terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }
}

provider "google" {
  project = "your-gcp-project-id"
  region  = "us-central1"
}

module "cloud_https_lb_neg" {
  source = "../"

  project_id     = "your-gcp-project-id"
  region         = "us-central1"
  lb_name_prefix = "webapps-prod"

  # Two custom domains (one per web app)
  domain_names = [
    "app1.example.com",
    "app2.example.com"
  ]

  # Two Cloud Run services with host + path based routing
  cloud_run_services = [
    {
      name                     = "app1"
      cloud_run_service_name   = "app1-cloud-run-service"
      cloud_run_service_region = "us-central1"
      security_policy          = "projects/your-gcp-project-id/global/securityPolicies/app1-policy"
      path_rules = [
        { paths = ["/", "/app1/*", "/shared/*"] }
      ]
      host_rules = [
        { hosts = ["app1.example.com"] }
      ]
    },
    {
      name                     = "app2"
      cloud_run_service_name   = "app2-cloud-run-service"
      cloud_run_service_region = "us-central1"
      security_policy          = "projects/your-gcp-project-id/global/securityPolicies/app2-policy"
      path_rules = [
        { paths = ["/app2/*"] }
      ]
      host_rules = [
        { hosts = ["app2.example.com"] }
      ]
    }
  ]

  enable_cdn = true

  labels = {
    managed_by  = "terraform"
    environment = "prod"
    app_group   = "webapps"
  }
}

output "load_balancer_ip" {
  value = module.cloud_https_lb_neg.load_balancer_ip_address
}
```

### Basic Configuration (Single Service)

```hcl
module "https_cloud_run_lb" {
  source = "./gcp-https-lb-cloud-run"

  project_id           = "my-project"
  lb_name_prefix       = "my-app-lb"
  domain_names         = ["app.example.com"]
  enable_cdn           = true

  # Single Cloud Run service with path-based routing
  cloud_run_services = [
    {
      name                     = "main"
      cloud_run_service_name   = "my-cloud-run-service"
      cloud_run_service_region = "us-central1"
      security_policy          = "projects/my-project/global/securityPolicies/main-policy"
      path_rules = [
        { paths = ["/*"] }  # Routes all traffic to this service
      ]
    }
  ]

  labels = {
    managed_by   = "terraform"
    team         = "platform"
    cost_center  = "engineering"
  }
}
```

### Multi-Service with Host-Based Routing

```hcl
module "https_cloud_run_lb" {
  source = "./gcp-https-lb-cloud-run"

  project_id           = "my-project"
  lb_name_prefix       = "multi-app-lb"
  domain_names         = ["api.example.com", "web.example.com"]
  enable_cdn           = true

  # Multiple services with host-based routing
  cloud_run_services = [
    {
      name                     = "api"
      cloud_run_service_name   = "api-service"
      cloud_run_service_region = "us-central1"
      security_policy          = "projects/my-project/global/securityPolicies/api-policy"
      host_rules = [
        { hosts = ["api.example.com"] }
      ]
    },
    {
      name                     = "web"
      cloud_run_service_name   = "web-service"
      cloud_run_service_region = "us-central1"
      security_policy          = "projects/my-project/global/securityPolicies/web-policy"
      host_rules = [
        { hosts = ["web.example.com"] }
      ]
    }
  ]

  labels = {
    managed_by = "terraform"
  }
}

# Optional: use an external SSL policy instead of module-managed default
module "https_cloud_run_lb_with_external_policy" {
  source = "./gcp-https-lb-cloud-run"

  project_id           = "my-project"
  lb_name_prefix       = "multi-app-lb"
  domain_names         = ["api.example.com", "web.example.com"]
  ssl_policy_self_link = "projects/my-project/global/sslPolicies/my-external-policy"

  cloud_run_services = [
    {
      name                     = "api"
      cloud_run_service_name   = "api-service"
      cloud_run_service_region = "us-central1"
      security_policy          = "projects/my-project/global/securityPolicies/api-policy"
      host_rules = [{ hosts = ["api.example.com"] }]
      path_rules = [{ paths = ["/api/*"] }]
    },
    {
      name                     = "web"
      cloud_run_service_name   = "web-service"
      cloud_run_service_region = "us-central1"
      security_policy          = "projects/my-project/global/securityPolicies/web-policy"
      host_rules = [{ hosts = ["web.example.com"] }]
      path_rules = [{ paths = ["/*"] }]
    }
  ]
}
```

### Multi-Service with Path-Based Routing

```hcl
module "https_cloud_run_lb" {
  source = "./gcp-https-lb-cloud-run"

  project_id           = "my-project"
  lb_name_prefix       = "app-lb"
  domain_names         = ["example.com", "www.example.com"]
  enable_cdn           = true

  # Multiple services with path-based routing
  cloud_run_services = [
    {
      name                     = "api"
      cloud_run_service_name   = "api-service"
      cloud_run_service_region = "us-central1"
      security_policy          = "projects/my-project/global/securityPolicies/api-policy"
      path_rules = [
        { paths = ["/api/v1/*", "/api/v2/*"] }
      ]
    },
    {
      name                     = "web"
      cloud_run_service_name   = "web-service"
      cloud_run_service_region = "us-central1"
      security_policy          = "projects/my-project/global/securityPolicies/web-policy"
      path_rules = [
        { paths = ["/", "/about/*", "/contact/*"] }
      ]
    },
    {
      name                     = "admin"
      cloud_run_service_name   = "admin-service"
      cloud_run_service_region = "us-central1"
      security_policy          = "projects/my-project/global/securityPolicies/admin-policy"
      path_rules = [
        { paths = ["/admin/*"] }
      ]
    }
  ]

  labels = {
    managed_by = "terraform"
    team       = "platform"
  }
}

output "load_balancer_ip" {
  value = module.https_cloud_run_lb.load_balancer_ip_address
}

output "certificate_status" {
  value = module.https_cloud_run_lb.managed_certificate_status
}

output "services_summary" {
  value = module.https_cloud_run_lb.cloud_run_services_summary
}
```

### Complex Multi-Service with Combined Routing

```hcl
module "https_cloud_run_lb" {
  source = "./gcp-https-lb-cloud-run"

  project_id           = "my-project"
  lb_name_prefix       = "enterprise-lb"
  domain_names         = ["api.example.com", "cdn.example.com", "admin.example.com"]
  enable_cdn           = true
  global_default_cdn_policy = {
    cache_mode          = "CACHE_ALL_STATIC"
    default_ttl_seconds = 3600
    max_ttl_seconds     = 86400
    client_ttl_seconds  = 3600
    negative_caching    = true
    negative_caching_policies = [
      { code = 410, ttl = 120 },
      { code = 404, ttl = 120 }
    ]
  }

  cloud_run_services = [
    {
      name                     = "api-v1"
      cloud_run_service_name   = "api-service-v1"
      cloud_run_service_region = "us-central1"
      security_policy          = "projects/my-project/global/securityPolicies/api-v1-policy"
      path_rules = [
        { paths = ["/api/v1/*"] }
      ]
    },
    {
      name                     = "api-v2"
      cloud_run_service_name   = "api-service-v2"
      cloud_run_service_region = "us-east1"
      security_policy          = "projects/my-project/global/securityPolicies/api-v2-policy"
      path_rules = [
        { paths = ["/api/v2/*"] }
      ]
    },
    {
      name                     = "cdn"
      cloud_run_service_name   = "cdn-service"
      cloud_run_service_region = "us-central1"
      security_policy          = "projects/my-project/global/securityPolicies/cdn-policy"
      host_rules = [
        { hosts = ["cdn.example.com"] }
      ]
      path_rules = [
        { paths = ["/static/*", "/media/*"] }
      ]
    },
    {
      name                     = "admin"
      cloud_run_service_name   = "admin-service"
      cloud_run_service_region = "us-central1"
      security_policy          = "projects/my-project/global/securityPolicies/admin-policy"
      host_rules = [
        { hosts = ["admin.example.com"] }
      ]
    }
  ]

  labels = {
    managed_by = "terraform"
    team       = "platform"
    environment = "production"
  }
}
```

## Architecture

The module creates a multi-service load balancing architecture:

```
┌─────────────────────────────────────────────────────────────┐
│   Global Static IP Address + Google-Managed SSL Certificate  │
│   (Single entry point for all services)                      │
└──────────────────────────────────┬──────────────────────────┘
                                   │
                    ┌──────────────┴──────────────┐
                    │                             │
          ┌─────────▼──────────┐        ┌────────▼────────┐
          │  HTTPS Proxy       │        │  HTTP Proxy     │
          │  (443)             │        │  (80->301 HTTPS)│
          └─────────┬──────────┘        └─────────────────┘
                    │
              ┌─────▼──────┐
              │  URL Map   │
              │  Routing   │  ←── Host-based rules
              │  Logic     │  ←── Path-based rules
              └─────┬──────┘
                    │
        ┌───────────┴───────────┬──────────────┐
        │                       │              │
   ┌────▼─────┐         ┌───────▼──┐    ┌─────▼────┐
   │ Backend   │         │ Backend  │    │ Backend  │
   │ Service 1 │         │ Service 2│    │ Service 3│
   │ ---------│         │ ---------|    │ ---------|
     │ Cloud CDN │         │ Cloud CDN│    │ Cloud CDN│
     │ (global + │         │ (global +│    │ (global +│
     │ per-svc)  │         │ per-svc) │    │ per-svc) │
   └─────┬─────┘         └────┬─────┘    └────┬─────┘
         │                    │               │
     ┌─────▼────┐         ┌─────▼────┐     ┌─────▼────┐
     │ Cloud    │         │ Cloud    │     │ Cloud    │
     │ Armor    │         │ Armor    │     │ Armor    │
     │ Policy 1 │         │ Policy 2 │     │ Policy 3 │
     └─────┬────┘         └─────┬────┘     └─────┬────┘
         │                    │               │
        ┌────▼────┐         ┌─────▼──┐     ┌────▼────┐
    │  NEG 1  │         │  NEG 2 │     │  NEG 3  │
    │ Cloud   │         │ Cloud  │     │ Cloud   │
    │  Run 1  │         │  Run 2 │     │  Run 3  │
    └─────────┘         └────────┘     └─────────┘
```

### Resource Hierarchy (Dependency Order)

1. **Static IP Address** - Global, reserved IP for DNS delegation
2. **Forwarding Rules** - Routes 443 (HTTPS) and 80 (HTTP->redirect)
3. **HTTPS Proxy** - Terminates TLS, references SSL certificate and URL map
4. **HTTP Proxy** - Redirects HTTP to HTTPS
5. **SSL Certificate** - Google-managed with automatic renewal
6. **URL Map** - Routes traffic to backend services based on host/path rules
7. **Backend Services** - One per Cloud Run service
  - References the service NEG
  - Applies Cloud CDN (global defaults with optional per-service override)
  - Attaches one external Cloud Armor security policy per service (`cloud_run_services[].security_policy`)
8. **Serverless NEGs** - One per service, references specific Cloud Run service
9. **External Cloud Armor Policies** - Created/managed outside module and attached to each backend service

### Routing Flow

```
Client Request
    ↓
Static IP + SSL Certificate
    ↓
HTTPS Proxy (TLS Termination)
    ↓
URL Map (Route Decision)
    ├─→ Host: api.example.com → Backend Service 1 → NEG 1 → Cloud Run Service 1
    ├─→ Host: web.example.com → Backend Service 2 → NEG 2 → Cloud Run Service 2
    └─→ Paths: /admin/* → Backend Service 3 → NEG 3 → Cloud Run Service 3
    ↓
Cloud Armor (Security Check, per service)
  ├─→ Policy rules from externally managed security policies
  └─→ DDoS/WAF controls based on attached policy
    ↓
Cloud CDN (Cache Check)
    ├─→ Return cached response if available
    └─→ Forward to backend if cache miss
    ↓
Cloud Run Service
    ↓
Response
```

## Logging

### Logging (Mandatory)

Request logging is **mandatory** for all backend services. Logs are sent to Cloud Logging:

```hcl
# Default logging configuration
enable_logging    = true              # Enable logging
logging_sample_rate = 1.0             # Log all requests (0.0 to 1.0)
```

**Custom Logging Configuration:**

```hcl
module "https_cloud_run_lb" {
  source = "./gcp-https-lb-cloud-run"
  
  # ... other configuration ...
  
  # Override logging defaults
  enable_logging      = true
  logging_sample_rate = 0.5            # Log 50% of requests (for high traffic)
}
```

**Accessing Logs:**

Logs are available in Cloud Logging:

```bash
gcloud logging read "resource.type=http_load_balancer" \
  --project=<project_id> \
  --limit 50
```

Or view in Cloud Console: **Logging > Log Explorer > Resource = HTTP Load Balancer**

**Log Contents:**
- HTTP method, URL, and status code
- Client IP address and user agent
- Request/response size
- Latency information
- Backend service name
- Cache status (if CDN enabled)

## Important Notes

### Multi-Service Configuration

1. **Service Naming**: Each service in `cloud_run_services` requires a unique `name` field (e.g., "api", "web", "admin") used for resource naming and identification.

2. **Routing Rules**: Each service can have:
   - `path_rules`: List of URL paths to route to this service (e.g., ["/api/*"])
   - `host_rules`: List of hostnames to route to this service (e.g., ["api.example.com"])
   - **At least one must be specified** for each service
  - **Wildcard matching behavior**: Services with `host_rules` are excluded from wildcard (`*`) global path matching by design. Only path-only services (services without `host_rules`) participate in wildcard global path matching, and those path patterns must be unique across path-only services. When path-only services are present, do not define `*` in `host_rules`; wildcard matching is reserved for the module-managed global matcher.

3. **Default Service**: The first service in `cloud_run_services` is treated as the default. Traffic matching no other rules goes to this service.

4. **Backend Services**: One backend service created per Cloud Run service, linked to its NEG.

5. **Policy Scope**:
  - `security_policy` is required per service and may differ across services.
  - Cloud CDN uses `global_default_cdn_policy` and can be overridden per service with `cloud_run_services[].cdn_policy`.

### Google-Managed Certificate Provisioning

1. **Automatic DNS Validation Required**: Google-managed certificates require DNS validation. The certificate will remain in PROVISIONING state until DNS records are properly configured.

2. **DNS Record Creation**: You must create A records pointing your domain names to the load balancer's static IP address in your external DNS provider.

3. **Certificate Status Monitoring**: Use the following command to check certificate status:
   ```bash
   gcloud compute ssl-certificates describe <certificate_name> \
     --project=<project_id>
   ```

4. **Provisioning Time**: Typically takes 5-15 minutes but can take up to 24 hours.

5. **Certificate Renewal**: Google automatically renews managed certificates before expiry. No action required.

### SSL Policy Behavior

1. **Default (module-managed)**: If `ssl_policy_self_link` is `null`, the module creates a global SSL policy with:
  - `min_tls_version = "TLS_1_2"`
  - `profile = "MODERN"`
2. **External override**: If `ssl_policy_self_link` is provided, the module uses that policy and does not create a default SSL policy.

### Serverless NEGs and Cloud Run

1. **Single Region NEG**: The serverless NEG is created in the Cloud Run service's region. Cross-region traffic is handled by the global load balancer.

2. **Service Automatic Discovery**: The NEG automatically discovers all Cloud Run service instances and revisions.

3. **No VPC Peering Required**: Serverless NEGs don't require VPC peering or network configuration.

### Cloud CDN Considerations

- **Default Cache Mode**: `global_default_cdn_policy.cache_mode` defaults to `CACHE_ALL_STATIC`.
- **Default Negative Caching**: If not overridden, negative caching is enabled with 404/410 = 120 seconds.
- **Complete Object Required**: `global_default_cdn_policy` and `cloud_run_services[].cdn_policy` must be provided as complete objects when set.
- **Cache Invalidation**: Use `gcloud compute backend-services update` to purge cache.
- **Precedence**: CDN settings resolve in this order: `cloud_run_services[].cdn_policy` (service override) -> top-level `global_default_cdn_policy` (global default) -> module built-in defaults.

Custom `global_default_cdn_policy` example:

```hcl
module "https_cloud_run_lb" {
  # ... existing required module inputs

  enable_cdn = true
  global_default_cdn_policy = {
    cache_mode          = "CACHE_ALL_STATIC"
    default_ttl_seconds = 1800
    max_ttl_seconds     = 7200
    client_ttl_seconds  = 600
    negative_caching    = true
    negative_caching_policies = [
      { code = 404, ttl = 60 },
      { code = 410, ttl = 300 },
      { code = 500, ttl = 30 }
    ]
  }
}
```

### Security Policy Assignment

1. **Per-Service Policy Required**: Every entry in `cloud_run_services` must include `security_policy`.

2. **Policy Ownership**: Security policies are managed outside this module and attached per backend service.

3. **Policy Flexibility**: Different services can use different security policies in the same load balancer.

### Multi-Environment Support

Use separate module instantiations per environment by varying `lb_name_prefix`, `domain_names`, labels, and Cloud Run service identities.

Example:
```hcl
module "lb_prod" {
  # ... configuration
  lb_name_prefix = "myapp-prod"
}

module "lb_dev" {
  # ... configuration
  lb_name_prefix = "myapp-dev"
}
```

## SSL Certificate Provisioning

### Step 1: Deploy Module

```bash
terraform apply
```

### Step 2: Get Load Balancer IP

```bash
terraform output load_balancer_ip_address
```

Output: `203.0.113.45`

### Step 3: Create DNS A Records

In your DNS provider (AWS Route 53, Cloudflare, GoDaddy, etc.):

```
Domain: app.example.com
Type: A
Value: 203.0.113.45
TTL: 300

Domain: www.app.example.com
Type: A
Value: 203.0.113.45
TTL: 300
```

### Step 4: Wait for Certificate Provisioning

Monitor certificate status:

```bash
gcloud compute ssl-certificates describe my-app-lb-prod-ssl-cert \
  --project=my-project
```

Look for `status: ACTIVE` or `managedStatus: MANAGED` (depending on provider version).

### Step 5: Verify HTTPS Access

```bash
curl -vI https://app.example.com
```

Should return a valid SSL certificate without warnings.

## DNS Configuration

### For External DNS Providers

The module outputs DNS configuration instructions. Once resources are created:

1. **Retrieve Load Balancer IP**:
   ```bash
   terraform output load_balancer_ip_address
   ```

2. **Create A Records** in your DNS provider for all domains listed in `domain_names`.

3. **Verify DNS Propagation**:
   ```bash
   nslookup app.example.com
   ```

4. **Test HTTPS Connection**:
   ```bash
   curl https://app.example.com
   ```

## Security Best Practices

### 1. Per-Service Security Policy

Assign explicit security policies per backend service:

```hcl
cloud_run_services = [
  {
    name                     = "api"
    cloud_run_service_name   = "api-service"
    cloud_run_service_region = "us-central1"
    security_policy          = "projects/my-project/global/securityPolicies/api-policy"
    path_rules               = [{ paths = ["/api/*"] }]
  }
]
```

### 2. HTTPS Enforcement

The module automatically redirects HTTP to HTTPS. Never allow unencrypted traffic:

```
HTTP (80) → 301 Redirect → HTTPS (443)
```

### 3. Backend Reachability

Ensure your Cloud Run service is reachable by the load balancer:

- Service is deployed in the configured region
- URL map rules send traffic to the intended backend
- Service responds successfully to real client requests

### 4. CDN Security

When CDN is enabled:

- Cache headers are respected from Cloud Run responses
- Private/sensitive data should not be cached
- Use `Cache-Control: private` in response headers

### 5. Monitoring and Alerting

Set up monitoring for:

```bash
# Certificate expiration (auto-renewed, but monitor anyway)
gcloud compute ssl-certificates list --project=<project_id>

# Backend health
gcloud compute backend-services get-health <backend_service_name> \
  --global --project=<project_id>

# Cloud Armor metrics
# Monitor in Cloud Console > Cloud Armor > Policies
```

## Troubleshooting

### SSL Certificate Stuck in PROVISIONING

**Symptom**: Certificate remains in PROVISIONING state

**Solution**:
1. Verify DNS A records are created and propagated
2. Check certificate details:
   ```bash
   gcloud compute ssl-certificates describe <cert_name> --project=<project_id>
   ```
3. Ensure domain names exactly match DNS records
4. Wait up to 24 hours for provisioning

### Backend Service Returns Errors

**Symptom**: Requests fail or return 5xx responses

**Solution**:
1. Verify Cloud Run service is deployed and running
2. Check service is in the correct region
3. Test service endpoint manually:
   ```bash
  curl -v https://<cloud_run_url>
   ```
4. Ensure Cloud Run service responds with 200-399 status codes for expected paths

### 502 Bad Gateway Errors

**Symptom**: HTTPS requests return 502 errors

**Solution**:
1. Check Cloud Run service readiness and logs
2. Verify URL map routing rules are correct
3. Ensure path matchers have valid service references
4. Check Cloud Armor policies are not blocking traffic

### Certificate Status Shows PROVISIONING but DNS is Correct

**Symptom**: Certificate won't transition to ACTIVE

**Solution**:
1. Recreate the certificate:
   ```hcl
   lifecycle {
     create_before_destroy = true
   }
   ```
2. Delete and reapply:
   ```bash
   terraform destroy -target=google_compute_managed_ssl_certificate.https
   terraform apply
   ```
3. Contact Google Cloud Support if issue persists

### Cloud Armor Blocking Legitimate Traffic

**Symptom**: Valid requests return 403 Forbidden

**Solution**:
1. Check Cloud Armor policies are correctly configured
2. Verify the correct policy is attached in `cloud_run_services[].security_policy`
3. Test with `--noproxy` to bypass local proxies:
   ```bash
   curl --noproxy "*" https://app.example.com
   ```
4. Review Cloud Armor logs in Cloud Console

## Variables

### Core Variables

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project_id` | string | **Required** | GCP Project ID |
| `lb_name_prefix` | string | **Required** | Prefix for all resource names |
| `domain_names` | list(string) | **Required** | Domain names for SSL certificate (multi-SAN) |
| `ssl_policy_self_link` | string | `null` | Optional external SSL policy self_link; when null the module creates TLS 1.2 + MODERN policy |

### Multi-Service Configuration

| Name | Type | Description |
|------|------|-------------|
| `cloud_run_services` | list(object) | **Required** - Non-empty list of Cloud Run services with routing configuration |

**cloud_run_services object structure:**

```hcl
{
  name                     = string           # Unique service identifier (e.g., "api", "web")
  cloud_run_service_name   = string           # Cloud Run service name
  cloud_run_service_region = optional(string) # Cloud Run service region (defaults to module `region`)
  security_policy          = string           # Required security policy self_link/id for this backend service
  cdn_policy = optional(object({              # Optional per-service CDN override (all fields required when set)
    cache_mode                = string
    default_ttl_seconds       = number
    max_ttl_seconds           = number
    client_ttl_seconds        = number
    negative_caching          = bool
    negative_caching_policies = list(object({
      code = number
      ttl  = number
    }))
  }))
  path_rules = optional(list(object({
    paths = list(string)  # URL paths for this service (e.g., ["/api/*", "/api/v1"])
  })), [])
  host_rules = optional(list(object({
    hosts = list(string)  # Hostnames for this service (e.g., ["api.example.com"])
  })), [])
  # Note: At least one of path_rules or host_rules must be specified
}
```

### Security & CDN Configuration

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `enable_cdn` | bool | `true` | Enable Cloud CDN for all services |
| `global_default_cdn_policy` | object | predefined defaults | Global default CDN policy object; when set, all attributes are required. Can be overridden per service by `cloud_run_services[].cdn_policy`. |

### Connection Configuration

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `session_affinity` | string | `NONE` | Session affinity mode (NONE, CLIENT_IP, CLIENT_IP_PROTO, CLIENT_IP_PORT) |
| `connection_draining_timeout_seconds` | number | `300` | Connection draining timeout (1-3600) |
| `request_timeout_seconds` | number | `30` | Request timeout (1-3600) |
| `region` | string | `us-central1` | Default region used when a service omits `cloud_run_service_region` |

### Logging Configuration

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `enable_logging` | bool | `true` | Enable request logging for backend services |
| `logging_sample_rate` | number | `1.0` | Logging sample rate (0.0 to 1.0) |

### Labeling & Organization

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `labels` | map(string) | `{managed_by: "terraform"}` | Labels applied to all resources |

## Outputs

### Load Balancer Infrastructure

| Name | Description |
|------|-------------|
| `load_balancer_ip_address` | External static IP address of the load balancer |
| `load_balancer_ip_address_name` | Name of the static IP resource |
| `https_forwarding_rule_name` | Name of the HTTPS forwarding rule |
| `https_forwarding_rule_id` | ID of the HTTPS forwarding rule |
| `http_forwarding_rule_name` | Name of the HTTP forwarding rule |

### SSL Certificate

| Name | Description |
|------|-------------|
| `managed_certificate_name` | Name of the Google-managed SSL certificate |
| `managed_certificate_id` | ID of the SSL certificate |
| `managed_certificate_status` | Status of the Certificate Manager certificate (reads from `.managed[0].state`, defaults to `PROVISIONING`) |
| `managed_certificate_domains` | List of domains covered by the certificate |
| `certificate_dns_authorization_records` | DNS authorization CNAME records required for certificate validation (keyed by domain) |
| `ssl_policy_self_link` | Effective SSL policy self_link attached to HTTPS proxy |
| `module_managed_ssl_policy_name` | Name of module-managed SSL policy (null when external policy is provided) |

### Multi-Service Backend Resources

| Name | Description |
|------|-------------|
| `backend_services` | Map of all backend services by service name with IDs and self links |
| `backend_service_ids` | List of all backend service IDs |
| `cloud_run_negs` | Map of all serverless NEGs by service name with IDs |
| `cloud_run_neg_ids` | List of all serverless NEG IDs |

### Logging

| Name | Description |
|------|-------------|
| `logging_enabled` | Whether logging is enabled for backend services |
| `logging_sample_rate` | Logging sample rate (0.0 to 1.0) |

### Routing & Security

| Name | Description |
|------|-------------|
| `url_map_name` | Name of the URL map |
| `url_map_id` | ID of the URL map |
| `https_proxy_name` | Name of the HTTPS proxy |
| `https_proxy_id` | ID of the HTTPS proxy |
| `cloud_armor_policy_name` | Map of service name => attached Cloud Armor policy identifier |
| `cloud_armor_policy_id` | Map of service name => attached Cloud Armor policy identifier |
| `cloud_armor_enabled` | Whether every configured service has a non-empty Cloud Armor policy assignment |
| `cdn_enabled` | Whether Cloud CDN is enabled |
| `cdn_effective_cache_mode` | Map of service name => effective Cloud CDN cache mode (service override or global default) |

### Service Configuration Summary

| Name | Description |
|------|-------------|
| `cloud_run_services_summary` | Detailed summary of all configured services with routing rules |
| `routing_configuration` | Summary of routing configuration (default service, total services, services with host/path rules) |
| `project_id` | GCP Project ID |
| `region` | Primary region for the load balancer |
| `all_resource_labels` | Labels applied to all resources |
| `lb_name_prefix` | Name prefix used for all resources |
| `dns_configuration_instructions` | Instructions for configuring DNS records |

## License

This module is provided as-is for educational and production use.

## Support

For issues or questions:

1. Check the [Troubleshooting](#troubleshooting) section
2. Review GCP documentation for [Cloud Load Balancing](https://cloud.google.com/load-balancing/docs)
3. Consult [Cloud Run documentation](https://cloud.google.com/run/docs)
4. Contact your cloud platform team or GCP support