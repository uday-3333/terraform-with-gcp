variable "name" {
  description = "Name for the LB traffic extension resource"
  type        = string
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "forwarding_rule_id" {
  description = "Full ID of the HTTPS global forwarding rule to attach the extension to"
  type        = string
}

variable "backend_service_id" {
  description = "Self-link of the decision Cloud Run backend service used as the callout target"
  type        = string
}

variable "timeout" {
  description = "Callout timeout (e.g. '5s'). Requests fall through when fail_open = true and this is exceeded."
  type        = string
  default     = "5s"
}

variable "fail_open" {
  description = "When true, requests continue to origin if the callout fails or times out (recommended for availability)"
  type        = bool
  default     = true
}

variable "cel_expression" {
  description = "CEL match condition applied to every request. Defaults to 'true' (intercept all requests)."
  type        = string
  default     = "true"
}

variable "supported_events" {
  description = "Extension event hooks. REQUEST_HEADERS intercepts before the request reaches the backend."
  type        = list(string)
  default     = ["REQUEST_HEADERS"]
}
