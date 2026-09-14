# Cloud Armor Security Policy Module - Multiple Policies Support

This Terraform module creates and manages **multiple** Google Cloud Armor security policies with **IP-based access control**. This module is designed for environments where advanced WAF features (OWASP rules, bot protection, rate limiting) are handled by **Imperva WAF**.

## Features

- **Multiple Policies**: Create and manage multiple Cloud Armor policies with different configurations
- **IP Allowlisting (Whitelisting)**: Explicitly allow traffic from trusted IP ranges
- **IP Denylisting (Blacklisting)**: Block traffic from known malicious IP sources
- **Private/Public Access Modes**: Automatic default rule configuration per policy
- **Advanced Logging**: Configurable log levels for debugging and monitoring
- **Load Balancer Integration**: Easy attachment to backend services and buckets

## Key Simplifications

This module focuses on **IP-based access control only**:

- ✅ **IP Whitelisting/Blacklisting** (CIDR-based access control)
- ✅ **Multiple Policies** (private and public in one module call)
- ✅ **Private/Public Access Modes** (deny-by-default or allow-by-default)
- ✅ **Advanced Logging Options**
- ❌ **OWASP ModSecurity Rules** (handled by Imperva WAF)
- ❌ **Bot Protection/reCAPTCHA** (handled by Imperva WAF)
- ❌ **Rate Limiting** (handled by Imperva WAF or application layer)
- ❌ **Geo-blocking** (handled by Imperva WAF)
- ❌ **Adaptive DDoS Protection** (handled by Imperva WAF)

## Usage

### Multiple Policies - Public and Private

```hcl
module "cloud_armor" {
  source     = "./modules/cloudarmor"
  project_id = "your-project-id"

  policies = {
    # Private policy - Admin/Internal access only
    "private-admin" = {
      name        = "private-admin-policy"
      description = "Private access for admin services - IP whitelist only"
      access_mode = "private"  # Deny all by default

      enable_ip_whitelist = true
      ip_whitelist = [
        "203.0.113.0/24",     # Corporate office
        "198.51.100.0/24",    # VPN network
        "10.0.0.0/8",         # Internal GCP networks
      ]

      log_level = "VERBOSE"

      labels = {
        environment = "production"
        access_type = "private"
      }
    }

    # Public policy - Customer-facing services
    "public-web" = {
      name        = "public-web-policy"
      description = "Public web services - Imperva WAF protection"
      access_mode = "public"  # Allow all by default

      enable_ip_whitelist = false
      enable_ip_blacklist = true
      ip_blacklist = [
        "192.0.2.100/32",     # Known bad actor
      ]

      log_level = "NORMAL"

      labels = {
        environment = "production"
        access_type = "public"
      }
    }
  }
}
```

### Simple Private Policy

```hcl
module "cloud_armor" {
  source     = "./modules/cloudarmor"
  project_id = "your-project-id"

  policies = {
    "admin-only" = {
      name        = "admin-whitelist-policy"
      access_mode = "private"
      
      enable_ip_whitelist = true
      ip_whitelist = [
        "203.0.113.0/24",
        "10.0.0.1/32"
      ]
    }
  }
}
```

### Simple Public Policy

```hcl
module "cloud_armor" {
  source     = "./modules/cloudarmor"
  project_id = "your-project-id"

  policies = {
    "public-api" = {
      name        = "public-api-policy"
      access_mode = "public"
    }
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| project_id | The GCP project ID | `string` | n/a | yes |
| policies | Map of Cloud Armor security policies | `map(object)` | `{}` | yes |

### Policy Configuration Object

Each policy in the `policies` map supports:

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | Name of the security policy | `string` | n/a | yes |
| description | Description of the policy | `string` | `"Cloud Armor IP-based Access Control Policy (WAF via Imperva)"` | no |
| access_mode | Access mode: 'private' or 'public' | `string` | `"public"` | no |
| enable_ip_whitelist | Enable IP whitelist | `bool` | `false` | no |
| ip_whitelist | List of IP ranges to whitelist (CIDR) | `list(string)` | `[]` | no |
| enable_ip_blacklist | Enable IP blacklist | `bool` | `false` | no |
| ip_blacklist | List of IP ranges to blacklist (CIDR) | `list(string)` | `[]` | no |
| default_rule_action_override | Override default rule action | `string` | `null` | no |
| log_level | Log level (NORMAL or VERBOSE) | `string` | `"NORMAL"` | no |
| user_ip_request_headers | Headers for IP extraction | `list(string)` | `null` | no |
| labels | Labels for the policy | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| policies | Map of all created policies with details |
| policy_ids | Map of policy keys to IDs |
| policy_names | Map of policy keys to names |
| policy_self_links | Map of policy keys to self links (for load balancer attachment) |
| policy_fingerprints | Map of policy keys to fingerprints |
| access_modes | Map of policy keys to access modes |
| default_rule_actions | Map of policy keys to default rule actions |
| ip_whitelist_status | Map of policy keys to whitelist enabled status |
| whitelisted_ips | Map of policy keys to whitelisted IPs |
| blacklisted_ips | Map of policy keys to blacklisted IPs |
| rule_counts | Map of policy keys to total rule counts |
| policies_summary | Comprehensive summary of all policies |

## Examples

See the [examples](./examples) directory:

- [public-and-private-policies.tf](./examples/public-and-private-policies.tf) - Complete example with multiple policies

## Attaching to Load Balancers

### Backend Service

```hcl
resource "google_compute_backend_service" "admin" {
  name            = "admin-backend"
  security_policy = module.cloud_armor.policy_self_links["private-admin"]
  # ... other configuration
}

resource "google_compute_backend_service" "web" {
  name            = "web-backend"
  security_policy = module.cloud_armor.policy_self_links["public-web"]
  # ... other configuration
}
```

### Backend Bucket

```hcl
resource "google_compute_backend_bucket" "static" {
  name                 = "static-assets"
  edge_security_policy = module.cloud_armor.policy_self_links["public-web"]
  # ... other configuration
}
```

## Access Modes

### Private Mode (`access_mode = "private"`)

- **Default Action**: `deny(403)` - deny all traffic
- **Use Case**: Admin interfaces, internal APIs, databases
- **Requirements**: Must configure `ip_whitelist` to allow traffic
- **Rule Evaluation**:
  1. Check IP whitelist → Allow if matched
  2. Check IP blacklist → Deny if matched (optional)
  3. **Default → Deny all**

### Public Mode (`access_mode = "public"`)

- **Default Action**: `allow` - allow all traffic
- **Use Case**: Public-facing applications with Imperva WAF
- **Security**: Imperva WAF handles threat protection
- **Rule Evaluation**:
  1. Check IP blacklist → Deny if matched (optional)
  2. **Default → Allow all**

## IP Address Format (CIDR Notation)

```hcl
ip_whitelist = [
  "203.0.113.0/24",      # Entire subnet (256 addresses)
  "198.51.100.50/32",    # Single IP address
  "10.0.0.0/8"           # Large corporate network
]
```

### CIDR Quick Reference

| CIDR | IPs | Use Case |
|------|-----|----------|
| /32 | 1 | Single server/VPN |
| /24 | 256 | Standard subnet |
| /16 | 65,536 | Large corporate network |
| /8 | 16,777,216 | Very large network |

## Best Practices

### Private Mode
- ✅ Always enable IP whitelist
- ✅ Use `/32` for single endpoints
- ✅ Use `/24` for office networks
- ✅ Set `log_level = "VERBOSE"` for troubleshooting
- ✅ Review whitelist quarterly

### Public Mode
- ✅ Rely on Imperva WAF for security
- ✅ Use `log_level = "NORMAL"` for production
- ✅ Use IP blacklist only for active attackers
- ✅ Configure `user_ip_request_headers` if behind proxy/CDN

### General
- ✅ Use descriptive policy names
- ✅ Apply consistent labels
- ✅ Test in non-production first
- ✅ Store sensitive IPs in variables

## IP Extraction Behind Proxy/CDN

```hcl
module "cloud_armor" {
  source     = "./modules/cloudarmor"
  project_id = "your-project-id"

  policies = {
    "my-policy" = {
      name = "my-policy"
      
      # Extract real client IP from headers
      user_ip_request_headers = [
        "X-Forwarded-For",
        "X-Real-IP"
      ]
    }
  }
}
```

## Troubleshooting

### Access denied despite whitelisted IP
1. Verify CIDR format is correct
2. Check `enable_ip_whitelist = true`
3. Set `log_level = "VERBOSE"`
4. Configure `user_ip_request_headers` if behind proxy
5. Verify client's public IP

### Public mode blocking all traffic
1. Verify `access_mode = "public"`
2. Check `default_rule_action_override` is not set to deny
3. Review Cloud Armor logs

## Cost Considerations

- **Cloud Armor**: $5/month per policy + $0.75/million requests
- **Logging**: `VERBOSE` increases Cloud Logging costs
- **Recommendation**: Use `NORMAL` in production

## Security Notes

- ⚠️ This module provides **IP-based access control only**
- ⚠️ **Do not** disable Imperva WAF
- ⚠️ IP whitelisting alone is **not sufficient** for production
- ✅ Always use HTTPS/SSL
- ✅ Combine with IAM for defense-in-depth

## Migration from Single Policy

**Before:**
```hcl
module "cloud_armor" {
  source      = "./modules/cloudarmor"
  project_id  = "your-project-id"
  policy_name = "my-policy"
  access_mode = "private"
  # ... other variables
}
```

**After:**
```hcl
module "cloud_armor" {
  source     = "./modules/cloudarmor"
  project_id = "your-project-id"
  
  policies = {
    "my-policy" = {
      name        = "my-policy"
      access_mode = "private"
      # ... other configuration
    }
  }
}
```

Update output references from `module.cloud_armor.policy_self_link` to `module.cloud_armor.policy_self_links["my-policy"]`.
