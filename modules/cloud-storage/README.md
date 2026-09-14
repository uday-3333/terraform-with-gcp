# Cloud Storage Module

This Terraform module creates and manages multiple Google Cloud Storage buckets with comprehensive security and lifecycle configurations.

## Features

- **Multiple Buckets**: Create and manage multiple buckets with different configurations
- **Security Controls**:
  - Uniform bucket-level access (IAM only)
  - Public access prevention
  - Customer-managed encryption keys (CMEK)
  - Object versioning
  - Retention policies
- **Lifecycle Management**:
  - Custom lifecycle rules
  - Automatic object deletion
  - Version lifecycle management
- **Additional Features**:
  - CORS configuration
  - Access logging
  - Custom labels
  - IAM policy management

## Usage

### Multiple Buckets

```hcl
module "cloud_storage" {
  source     = "./modules/cloudstorage"
  project_id = "your-project-id"

  buckets = {
    "production-data" = {
      name                     = "my-company-prod-data"
      location                 = "US"
      storage_class            = "STANDARD"
      enable_object_versioning = true
      
      labels = {
        environment = "production"
        team        = "data-engineering"
      }
    }
    
    "dev-temp" = {
      name                 = "my-company-dev-temp"
      location             = "US-CENTRAL1"
      storage_class        = "STANDARD"
      force_destroy        = true
      enable_auto_deletion = true
      auto_delete_age_days = 30
      
      labels = {
        environment = "development"
      }
    }
  }
}
```

### Advanced Configuration

```hcl
module "cloud_storage" {
  source     = "./modules/cloudstorage"
  project_id = "your-project-id"

  buckets = {
    "secure-data" = {
      name                        = "my-company-secure-data"
      location                    = "US"
      storage_class               = "STANDARD"
      uniform_bucket_level_access = true
      public_access_prevention    = "enforced"
      enable_object_versioning    = true
      
      # Customer-managed encryption
      kms_key_name = "projects/your-project/locations/us/keyRings/my-keyring/cryptoKeys/my-key"
      
      # Retention policy for compliance
      retention_policy = {
        retention_period = 2592000  # 30 days in seconds
        is_locked        = false
      }
      
      # Lifecycle rules
      lifecycle_rules = [
        {
          action = {
            type          = "SetStorageClass"
            storage_class = "NEARLINE"
          }
          condition = {
            age = 90
          }
        }
      ]
      
      # Version lifecycle
      enable_versioning_lifecycle    = true
      noncurrent_version_delete_days = 30
      
      # Logging
      logging_config = {
        log_bucket        = "my-company-logs"
        log_object_prefix = "storage-logs/"
      }
      
      labels = {
        environment = "production"
        compliance  = "required"
      }
    }
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| project_id | The ID of the project in which the buckets will be created | `string` | n/a | yes |
| buckets | Map of bucket configurations | `map(object)` | `{}` | yes |

### Bucket Configuration Object

Each bucket in the `buckets` map supports the following attributes:

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | The name of the bucket | `string` | n/a | yes |
| location | The location of the bucket | `string` | `"US"` | no |
| storage_class | The storage class (STANDARD, NEARLINE, COLDLINE, ARCHIVE) | `string` | `"STANDARD"` | no |
| force_destroy | Delete all objects when deleting the bucket | `bool` | `false` | no |
| uniform_bucket_level_access | Enable uniform bucket-level access | `bool` | `true` | no |
| public_access_prevention | Prevent public access (enforced/inherited) | `string` | `"enforced"` | no |
| enable_object_versioning | Enable object versioning | `bool` | `false` | no |
| retention_policy | Retention policy configuration | `object` | `null` | no |
| lifecycle_rules | List of lifecycle rules | `list(object)` | `[]` | no |
| kms_key_name | Cloud KMS key for CMEK | `string` | `null` | no |
| encryption_key | Alternative Cloud KMS key | `string` | `null` | no |
| logging_config | Bucket logging configuration | `object` | `null` | no |
| cors_config | CORS configuration | `list(object)` | `[]` | no |
| labels | Labels to apply to the bucket | `map(string)` | `{}` | no |
| use_authoritative_policy | Use authoritative IAM policy | `bool` | `false` | no |
| authoritative_policy_bindings | IAM policy bindings | `list(object)` | `[]` | no |
| enable_auto_deletion | Enable automatic deletion | `bool` | `false` | no |
| auto_delete_age_days | Days before auto-deletion | `number` | `90` | no |
| enable_versioning_lifecycle | Enable version lifecycle | `bool` | `false` | no |
| noncurrent_version_delete_days | Days before deleting old versions | `number` | `30` | no |

## Outputs

| Name | Description |
|------|-------------|
| buckets | Map of all created buckets with their details |
| bucket_names | Map of bucket keys to bucket names |
| bucket_urls | Map of bucket keys to bucket URLs |
| bucket_self_links | Map of bucket keys to bucket self links |
| bucket_ids | Map of bucket keys to bucket IDs |
| buckets_with_public_access_prevention | Map of buckets with public access prevention enforced |
| buckets_with_kms_encryption | Map of buckets with KMS encryption enabled |
| buckets_with_versioning | Map of buckets with object versioning enabled |

## Examples

See the [examples](./examples) directory for more detailed examples:

- [multiple-buckets.tf](./examples/multiple-buckets.tf) - Multiple buckets with different configurations

## Security Best Practices

1. **Enable uniform bucket-level access** - Use IAM only, disable ACLs
2. **Enforce public access prevention** - Prevent accidental public exposure
3. **Enable object versioning** - Protect against accidental deletion/modification
4. **Use customer-managed encryption keys (CMEK)** - For sensitive data
5. **Configure retention policies** - For compliance requirements
6. **Implement lifecycle rules** - Optimize storage costs
7. **Enable access logging** - For audit trails

## Migration from Single Bucket

If you're migrating from the previous single-bucket version:

**Before:**
```hcl
module "cloud_storage" {
  source                      = "./modules/cloudstorage"
  project_id                  = "your-project-id"
  bucket_name                 = "my-bucket"
  location                    = "US"
  storage_class               = "STANDARD"
  enable_object_versioning    = true
}
```

**After:**
```hcl
module "cloud_storage" {
  source     = "./modules/cloudstorage"
  project_id = "your-project-id"
  
  buckets = {
    "my-bucket" = {
      name                     = "my-bucket"
      location                 = "US"
      storage_class            = "STANDARD"
      enable_object_versioning = true
    }
  }
}
```

**Note:** You'll also need to update output references from `module.cloud_storage.bucket_name` to `module.cloud_storage.bucket_names["my-bucket"]`.