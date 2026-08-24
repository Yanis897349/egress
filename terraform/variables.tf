variable "aws_region" {
  description = "AWS region in which to create the Lightsail instance."
  type        = string
  default     = "ap-northeast-1"

  validation {
    condition     = can(regex("^[a-z]{2}(?:-gov)?-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "aws_region must be a valid AWS region name."
  }
}

variable "availability_zone" {
  description = "Lightsail availability zone. It must belong to aws_region."
  type        = string
  default     = "ap-northeast-1a"

  validation {
    condition     = can(regex("^[a-z]{2}(?:-gov)?-[a-z]+-[0-9]+[a-z]$", var.availability_zone))
    error_message = "availability_zone must be a valid AWS availability zone name."
  }
}

variable "instance_name" {
  description = "Name of the disposable Lightsail instance."
  type        = string
  default     = "beijing-vpn"

  validation {
    condition = (
      length(var.instance_name) >= 2 &&
      length(var.instance_name) <= 255 &&
      can(regex("^[A-Za-z0-9][A-Za-z0-9._-]*[A-Za-z0-9]$", var.instance_name))
    )
    error_message = "instance_name must be 2-255 characters, start and end with an alphanumeric character, and contain only letters, numbers, periods, underscores, or hyphens."
  }
}

variable "blueprint_id" {
  description = "Active Lightsail OS blueprint ID."
  type        = string
  default     = "ubuntu_24_04"

  validation {
    condition     = length(trimspace(var.blueprint_id)) > 0
    error_message = "blueprint_id must not be empty."
  }
}

variable "bundle_id" {
  description = "Active Lightsail bundle ID."
  type        = string

  validation {
    condition     = length(trimspace(var.bundle_id)) > 0
    error_message = "bundle_id must not be empty."
  }
}

variable "key_pair_name" {
  description = "Name of an existing Lightsail key pair in aws_region."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]*[A-Za-z0-9]$", var.key_pair_name))
    error_message = "key_pair_name must be at least two characters and contain only letters, numbers, underscores, or hyphens."
  }
}

variable "reality_sni" {
  description = "TLS 1.3-capable hostname used as the REALITY handshake target."
  type        = string
  default     = "www.cloudflare.com"

  validation {
    condition = (
      length(var.reality_sni) <= 253 &&
      can(regex("^(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\\.)+[A-Za-z]{2,63}$", var.reality_sni))
    )
    error_message = "reality_sni must be a valid DNS hostname."
  }
}
