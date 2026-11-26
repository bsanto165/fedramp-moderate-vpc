# FedRAMP Moderate VPC for AWS GovCloud (US)

Terraform that builds a workload VPC in AWS GovCloud with the network-layer technical controls a FedRAMP Moderate (NIST SP 800-53 Rev 5) system needs.

> **Scope:** Code doesn't make a system compliant on its own. Compliance comes from an authorized boundary, an SSP, an assessment and continuous monitoring. This repo covers the VPC's share of the SC, AC, AU and CM controls and gives you evidence for the SSP. Org-level controls (CloudTrail org trail, Config, Security Hub, GuardDuty, SCPs, IAM Identity Center) belong in your landing zone. See [What this does not cover](#what-this-does-not-cover).

## Architecture

```
                 Agency network                       Internet
                       |  DX / VPN                        ^
                       v                                  |
              +-----------------+   east-west/egress   +---------------------------+
              | Transit Gateway |<------------------->| Inspection & egress VPC   |
              | (network acct)  |                      | Network Firewall, NAT     |
              +-----------------+                      +---------------------------+
                       |
        +--------------+-----------------------------  this repo  ----+
        |  Workload VPC (per environment)                              |
        |   tgw subnets  /28 x AZ   -> TGW attachment                  |
        |   app subnets  private    -> 0.0.0.0/0 via TGW               |
        |                              interface endpoints (AWS APIs)  |
        |   data subnets isolated   -> local + gateway endpoints only  |
        |   Flow Logs + DNS query logs -> CloudWatch (KMS CMK, 365 d)  |
        +--------------------------------------------------------------+
```

`egress_mode` picks how private subnets leave the VPC:

| Mode | Use when | What gets built |
| --- | --- | --- |
| `tgw` (default) | Hub-and-spoke with a central inspection VPC | TGW attachment subnets and attachment; default route to the TGW. No IGW. |
| `nat` | Standalone VPC, no central network account | Public subnets, IGW, one NAT gateway per AZ |
| `none` | Fully isolated workloads | No egress; AWS APIs reachable only through endpoints |

## Subnet plan

The VPC CIDR (/16 to /20) is split into 16 equal blocks:

| Blocks | Tier | Example for 10.40.0.0/16 |
| --- | --- | --- |
| 0-3 | Public (nat mode only) | 10.40.0.0/20, 10.40.16.0/20, 10.40.32.0/20 |
| 4-7 | App (private) | 10.40.64.0/20 ... |
| 8-11 | Data (isolated) | 10.40.128.0/20 ... |
| 12-14 | Reserved for growth | |
| 15 | TGW attachment /28s | 10.40.240.0/28, .16/28, .32/28 |

## Control mapping

| Control | How this code implements it |
| --- | --- |
| AC-4 Information flow enforcement | Tiered subnets; data-tier NACL allows only app CIDRs on `data_ports`; no default route for data tier |
| SC-7 Boundary protection | No IGW in `tgw`/`none` modes; all egress forced to the inspection VPC; default SG, NACL and route table locked down |
| SC-7(4)/(5) Deny by default | Default NACL denies all; custom NACLs allow only listed traffic; endpoint SG has no egress |
| SC-7(7) Split tunneling / SC-8 | AWS API calls stay on the AWS network through VPC endpoints |
| SC-8, SC-13 Transmission confidentiality, FIPS crypto | Provider uses FIPS endpoints; endpoints accept HTTPS only |
| SC-12, SC-28 Key management, data at rest | Customer-managed KMS key with rotation encrypts all log groups |
| AU-2, AU-3, AU-12 Event logging | VPC Flow Logs (ALL traffic, extended v5 fields, 60-second aggregation) and Route 53 Resolver query logs |
| AU-9 Protection of audit information | Logs encrypted with a CMK; IAM role scoped to the flow log group; confused-deputy conditions |
| AU-11 Audit record retention | 365-day minimum retention, enforced by variable validation |
| SI-4 System monitoring | Flow and DNS logs ready for GuardDuty, Security Hub or your SIEM |
| CM-2, CM-3, CM-6 Baseline and change control | Everything in code; CI runs fmt, validate, tflint and Checkov on every pull request |
| CM-7 Least functionality | Default SG stripped; no public IPs auto-assigned on any subnet |
| CM-8 Component inventory | `default_tags` stamp Project, Environment, Compliance and your SystemId on every resource |
| CP-7, SC-5 Availability | Spans 2-3 AZs; one NAT gateway per AZ in `nat` mode |

## Usage

Each environment is a pair of committed files in `env/`: `<name>.tfvars` and `<name>.s3.tfbackend`. Copy the `prod` examples and edit them. The pipeline finds every pair automatically.

Through the pipeline (normal path): open a PR to get a plan comment, merge, approve in the `production` environment, and it applies. See [CI/CD and drift](#cicd-and-drift).

Locally (first bootstrap or break-glass):

```bash
terraform init -backend-config=env/prod.s3.tfbackend
terraform plan -var-file=env/prod.tfvars -out tfplan
terraform apply tfplan
```

Requirements: Terraform 1.9+ (1.10+ for the S3-native state lock in `env/*.s3.tfbackend`), AWS provider 6.x, and credentials for a GovCloud account.

### Notes for GovCloud

- ARNs use the `aws-us-gov` partition; the code reads it from `aws_partition` and never hard-codes it.
- Endpoint service names are `com.amazonaws.<region>.<service>`. Check each one in `interface_endpoints` exists in your region before applying. If you need FIPS-specific endpoint services (for example `kms-fips`) where available, add them to the list.
- A **RAM-shared Transit Gateway** from another account may need the attachment accepted in the network account before the TGW routes work. The network account also owns the TGW route tables and the routes back to this VPC.
- **DNS query logging** to CloudWatch needs the deploying role to have `logs:CreateLogDelivery` and `logs:PutResourcePolicy`; AWS adds the log-group resource policy for you.

### Cost

Interface endpoints are billed per endpoint per AZ: 11 endpoints x 3 AZs is 33 ENIs, roughly $240/month before data processing. Remove any you don't use. NAT gateways in `nat` mode add about $33/month each plus data processing.

## What this does not cover

Put these in your landing zone or other repos; your SSP should reference them:

- Organization CloudTrail to a locked log-archive account (AU-6, AU-9), AWS Config with the NIST 800-53 Rev 5 conformance pack, Security Hub, GuardDuty (CA-7, SI-4)
- SCPs that deny `ec2:CreateInternetGateway`, leaving approved regions, or disabling logging in workload accounts
- The inspection VPC itself: AWS Network Firewall policy, TLS inspection decisions, central egress
- Workload security groups, which belong with each application
- IAM, identity federation and MFA (AC-2, IA-2)
- SSP narratives, diagrams, ports/protocols/services list, POA&M, contingency and IR plans

## CI/CD and drift

This repo is one of three:

| Repo | What it builds |
| --- | --- |
| [org-guardrails](https://github.com/bsanto165/org-guardrails) | SCPs and the pipeline roles in every account |
| [security-baseline](https://github.com/bsanto165/security-baseline) | Org CloudTrail, Config, GuardDuty, Security Hub, Inspector, alerting |
| fedramp-moderate-vpc (this repo) | Workload VPCs |

Workflows:

- `deploy.yml`: on a PR, runs a read-only plan per environment and comments it on the PR. On merge, it waits for approval in the `production` environment, then applies.
- `drift-detection.yml`: runs `terraform plan -detailed-exitcode` nightly. If live infrastructure differs from code, it opens a `drift` issue, and it closes the issue once the environment is back in sync.

Setup: create the `production` environment with required reviewers. Then set the repository variables `PLAN_ROLE_ARN` and `APPLY_ROLE_ARN` (outputs of org-guardrails) and, optionally, `AWS_REGION`.

### Static checks

`.github/workflows/terraform-ci.yml` runs on every pull request and on pushes to `main`:

1. `terraform fmt -check`, `init -backend=false`, `validate`
2. `tflint` with the AWS ruleset
3. Checkov, with results uploaded to GitHub code scanning

Checkov starts with `soft_fail: true`. After the first run, record any accepted risks as inline `#checkov:skip=<ID>:<reason>` comments (the NACL ephemeral-port skips are already documented), then set it to `false` so new findings block merges.
