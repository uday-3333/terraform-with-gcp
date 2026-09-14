output "buckets" {
  description = "Map of all created buckets with their details"
  value = {
    for k, bucket in google_storage_bucket.buckets : k => {
      name          = bucket.name
      url           = bucket.url
      self_link     = bucket.self_link
      id            = bucket.id
      location      = bucket.location
      storage_class = bucket.storage_class
    }
  }
}

output "bucket_names" {
  description = "Map of bucket keys to bucket names"
  value       = { for k, bucket in google_storage_bucket.buckets : k => bucket.name }
}

output "bucket_urls" {
  description = "Map of bucket keys to bucket URLs"
  value       = { for k, bucket in google_storage_bucket.buckets : k => bucket.url }
}

output "bucket_self_links" {
  description = "Map of bucket keys to bucket self links"
  value       = { for k, bucket in google_storage_bucket.buckets : k => bucket.self_link }
}

output "bucket_ids" {
  description = "Map of bucket keys to bucket IDs"
  value       = { for k, bucket in google_storage_bucket.buckets : k => bucket.id }
}

# Security Outputs
output "buckets_with_public_access_prevention" {
  description = "Map of buckets with public access prevention enforced"
  value = {
    for k, v in var.buckets : k => v.public_access_prevention == "enforced"
  }
}

output "buckets_with_kms_encryption" {
  description = "Map of buckets with KMS encryption enabled"
  value = {
    for k, v in var.buckets : k => (v.kms_key_name != null || v.encryption_key != null)
  }
}

output "buckets_with_versioning" {
  description = "Map of buckets with object versioning enabled"
  value = {
    for k, v in var.buckets : k => v.enable_object_versioning
  }
}