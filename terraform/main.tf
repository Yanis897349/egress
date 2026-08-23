provider "aws" {
  region = var.aws_region
}

locals {
  bootstrap_script_base64 = filebase64("${path.module}/../cloud-init/setup.sh")
  bootstrap_command = format(
    "printf '%%s' '%s' | base64 -d | bash -s -- '%s'",
    local.bootstrap_script_base64,
    var.reality_sni,
  )
}

resource "aws_lightsail_instance" "vpn" {
  name              = var.instance_name
  availability_zone = var.availability_zone
  blueprint_id      = var.blueprint_id
  bundle_id         = var.bundle_id
  key_pair_name     = var.key_pair_name
  ip_address_type   = "ipv4"
  user_data         = local.bootstrap_command

  tags = {
    Role        = "personal-connectivity"
    Environment = "exchange-year"
    ManagedBy   = "terraform"
  }

  lifecycle {
    precondition {
      condition     = startswith(var.availability_zone, var.aws_region)
      error_message = "availability_zone must belong to aws_region."
    }
  }
}

resource "aws_lightsail_instance_public_ports" "vpn" {
  instance_name = aws_lightsail_instance.vpn.name

  port_info {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
    cidrs     = ["0.0.0.0/0"]
  }

  port_info {
    protocol  = "tcp"
    from_port = 443
    to_port   = 443
    cidrs     = ["0.0.0.0/0"]
  }

  port_info {
    protocol  = "udp"
    from_port = 443
    to_port   = 443
    cidrs     = ["0.0.0.0/0"]
  }

  lifecycle {
    replace_triggered_by = [aws_lightsail_instance.vpn]
  }
}
