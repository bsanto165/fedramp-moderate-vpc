output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC CIDR."
  value       = aws_vpc.this.cidr_block
}

output "availability_zones" {
  description = "AZs used."
  value       = local.azs
}

output "public_subnet_ids" {
  description = "Public subnet IDs (empty unless egress_mode = nat)."
  value       = aws_subnet.public[*].id
}

output "app_subnet_ids" {
  description = "App-tier private subnet IDs."
  value       = aws_subnet.app[*].id
}

output "data_subnet_ids" {
  description = "Data-tier private subnet IDs."
  value       = aws_subnet.data[*].id
}

output "tgw_subnet_ids" {
  description = "TGW attachment subnet IDs (empty unless egress_mode = tgw)."
  value       = aws_subnet.tgw[*].id
}

output "app_route_table_ids" {
  description = "App-tier route table IDs."
  value       = aws_route_table.app[*].id
}

output "data_route_table_ids" {
  description = "Data-tier route table IDs."
  value       = aws_route_table.data[*].id
}

output "transit_gateway_attachment_id" {
  description = "TGW attachment ID (null unless egress_mode = tgw)."
  value       = try(aws_ec2_transit_gateway_vpc_attachment.this[0].id, null)
}

output "nat_gateway_public_ips" {
  description = "NAT public IPs, for agency allow lists (empty unless egress_mode = nat)."
  value       = aws_eip.nat[*].public_ip
}

output "endpoint_security_group_id" {
  description = "Security group on interface endpoints."
  value       = aws_security_group.endpoints.id
}

output "interface_endpoint_ids" {
  description = "Interface endpoint IDs by service."
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.id }
}

output "gateway_endpoint_ids" {
  description = "Gateway endpoint IDs by service."
  value       = { for k, v in aws_vpc_endpoint.gateway : k => v.id }
}

output "flow_log_group_name" {
  description = "CloudWatch log group for VPC Flow Logs."
  value       = aws_cloudwatch_log_group.flow_logs.name
}

output "dns_query_log_group_name" {
  description = "CloudWatch log group for DNS query logs."
  value       = try(aws_cloudwatch_log_group.dns_query[0].name, null)
}

output "logs_kms_key_arn" {
  description = "KMS key encrypting VPC logs."
  value       = aws_kms_key.logs.arn
}
