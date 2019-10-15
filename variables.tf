variable "mail_from" {
  description = "The 'from' email address to use when sending notifications"
  default     = "ops-team@example.com"
}

variable "mail_to" {
  description = "The 'to' email address where notifications are sent"
  default     = "ops-team@example.com"
}

variable "profile" {
  default = "terraform"
}