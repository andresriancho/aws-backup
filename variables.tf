variable "mail_from" {
  description = "The 'from' email address to use when sending notifications"
  default     = "it@ggvc.com"
}

variable "mail_to" {
  description = "The 'to' email address where notifications are sent"
  default     = "it@ggvc.com"
}

variable "profile" {
  default = "terraform"
}

variable "region" {
  default = "us-east-1"
}