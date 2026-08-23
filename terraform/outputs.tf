output "vpn_ip" {
  description = "Current public IPv4 address of the VPS."
  value       = aws_lightsail_instance.vpn.public_ip_address
}

output "instance_name" {
  description = "Lightsail instance name."
  value       = aws_lightsail_instance.vpn.name
}
