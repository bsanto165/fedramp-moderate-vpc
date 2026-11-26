################################################################################
# VPC endpoints: AWS API traffic stays on the AWS network (SC-7, SC-8, AC-4).
################################################################################

resource "aws_security_group" "endpoints" {
  name_prefix = "${local.name_prefix}-vpce-"
  description = "HTTPS from inside the VPC to interface endpoints"
  vpc_id      = aws_vpc.this.id

  # No egress block: Terraform removes the default allow-all egress rule.

  # Protected = true: the org-guardrails SCP lets only the pipeline change this SG.
  tags = { Name = "${local.name_prefix}-vpce-sg", Protected = "true" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_https" {
  security_group_id = aws_security_group.endpoints.id
  description       = "HTTPS from VPC"
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# Restrict gateway endpoints to principals in your organization (exfiltration control).
data "aws_iam_policy_document" "gateway_endpoint" {
  count = var.organization_id == null ? 0 : 1

  statement {
    sid       = "AllowOrgPrincipalsOnly"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [var.organization_id]
    }
  }
}

resource "aws_vpc_endpoint" "gateway" {
  for_each = toset(var.gateway_endpoints)

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.${each.value}"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat(aws_route_table.app[*].id, aws_route_table.data[*].id)
  policy            = var.organization_id == null ? null : data.aws_iam_policy_document.gateway_endpoint[0].json

  tags = { Name = "${local.name_prefix}-vpce-${each.value}" }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(var.interface_endpoints)

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.app[*].id
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = { Name = "${local.name_prefix}-vpce-${replace(each.value, ".", "-")}" }
}
