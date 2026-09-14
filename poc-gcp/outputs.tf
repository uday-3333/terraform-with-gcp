output "storage_buckets" {
  description = "Map of all created storage buckets with their details"
  value       = module.storage_buckets.buckets
}

output "bucket_names" {
  description = "Map of all bucket names"
  value       = module.storage_buckets.bucket_names
}

output "bucket_urls" {
  description = "Map of all bucket URLs"
  value       = module.storage_buckets.bucket_urls
}

output "bucket_self_links" {
  description = "Map of bucket self links"
  value       = module.storage_buckets.bucket_self_links
}
#
# output "secrets" {
#   description = "Map of all created secrets with their details"
#   value       = module.secrets.secrets
#   sensitive   = true
# }
#
# output "secret_ids" {
#   description = "Map of secret key to short secret ID"
#   value       = module.secrets.secret_ids
# }
#
# output "secret_names" {
#   description = "Map of secret key to full resource name"
#   value       = module.secrets.secret_names
# }
#
# output "security_summary" {
#   description = "Security features enabled on all buckets"
#   value = {
#     public_access_prevention = module.storage_buckets.buckets_with_public_access_prevention
#     kms_encryption           = module.storage_buckets.buckets_with_kms_encryption
#     versioning               = module.storage_buckets.buckets_with_versioning
#   }
# }

output "cloud_run_services" {
  description = "Map of all created Cloud Run services with their details"
  value       = module.cloud_run.services
}

output "cloud_run_service_names" {
  description = "Map of all Cloud Run service names"
  value       = module.cloud_run.service_names
}

output "cloud_run_service_uris" {
  description = "Map of all Cloud Run service URIs (v2 top-level `uri`)"
  value       = module.cloud_run.service_uris
}

output "cloud_run_service_locations" {
  description = "Map of all Cloud Run service locations"
  value       = module.cloud_run.service_locations
}

output "cloud_armor_policy_ids" {
  description = "Map of Cloud Armor policy keys to policy IDs"
  value       = module.cloud_armor.policy_ids
}

output "cloud_armor_policy_names" {
  description = "Map of Cloud Armor policy keys to policy names"
  value       = module.cloud_armor.policy_names
}

output "cloud_armor_policy_self_links" {
  description = "Map of Cloud Armor policy keys to policy self links (use these to attach to load balancers)"
  value       = module.cloud_armor.policy_self_links
}

output "load_balancer_ip_addresses" {
  description = "Map of load balancer keys to their IP addresses"
  value = {
    for lb_key, lb in module.cloud_https_lbs :
    lb_key => lb.load_balancer_ip_address
  }
}

output "dns_configuration_instructions" {
  description = "Map of load balancer keys to DNS configuration instructions"
  value = {
    for lb_key, lb in module.cloud_https_lbs :
    lb_key => lb.dns_configuration_instructions
  }
}