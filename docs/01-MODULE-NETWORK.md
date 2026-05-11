# Module Deployment: Network
## `modules/network`

> **Prerequisites**: [00-SETUP.md](00-SETUP.md) complete — `terraform init` and `terraform validate` must have passed.
> **Deploy order**: **1st** — the Network module has no dependencies. It must be deployed before Security, ECS, CCE, GaussDB, and RDS.
> **Estimated apply time**: ~3 minutes

---

## What This Module Creates

| Resource | HCS Type | Description |
|---|---|---|
| VPC | `hcs_vpc` | Single VPC with your chosen CIDR block |
| Public subnets | `hcs_vpc_subnet` | One per CIDR in `public_subnet_cidrs`, spread across AZs |
| Private subnets | `hcs_vpc_subnet` | One per CIDR in `private_subnet_cidrs`, spread across AZs |
| NAT gateway EIP | `hcs_vpc_eip` | Elastic IP attached to the NAT gateway |
| NAT gateway | `hcs_nat_gateway` | Allows private instances to reach the internet outbound |
| SNAT rules | `hcs_nat_snat_rule` | One per private subnet — routes outbound traffic through NAT |
| Default security group | `hcs_networking_secgroup` | Baseline SG: all egress + intra-VPC ingress allowed |

**Resource naming**: All resources are named `<project>-<environment>-<descriptor>`.
For example with `project = "myapp"` and `environment = "dev"`:
- VPC → `myapp-dev-vpc`
- Public subnets → `myapp-dev-public-1`, `myapp-dev-public-2`
- Private subnets → `myapp-dev-private-1`, `myapp-dev-private-2`
- NAT → `myapp-dev-nat`

---

## Step 1 — Add Network Values to `terraform.tfvars`

Open `environments/dev/terraform.tfvars` and add or confirm these values:

```hcl
# ── Network ──────────────────────────────────────────────────────────────────
vpc_cidr             = "10.10.0.0/16"

# One subnet per entry. Each maps to an AZ in round-robin.
# Must not overlap with existing VPCs in your HCS tenant.
public_subnet_cidrs  = ["10.10.1.0/24", "10.10.2.0/24"]
private_subnet_cidrs = ["10.10.10.0/24", "10.10.11.0/24"]

# Check available AZ names: HCS Console → ECS → Create ECS → AZ dropdown
availability_zones   = ["az1.dc0"]            # add more if multi-AZ: ["az1.dc0", "az2.dc0"]

# Internal DNS resolver for HCS
dns_servers          = ["100.125.4.25"]

# Set false to skip NAT gateway (saves cost for isolated networks)
enable_nat_gateway   = true

# EIP type — must match your HCS external network name
# Check: HCS Console → EIP → Create EIP → Line type
eip_type             = "eip_public_Internet_01"

# CIDR allowed to SSH to the bastion host (used by the Security module)
trusted_ssh_cidr     = "10.0.0.0/8"           # corporate network; tighten for prod
```

### Finding your availability zone names

```bash
# After init, query the provider:
cd environments/dev
terraform console -var-file="terraform.tfvars"
> data.hcs_availability_zones.this.names
# This will fail without a data source, but you can check the HCS console:
# ECS → Create ECS → Availability Zone dropdown
# Common formats: az1.dc0, cn-east-3a, us-east-1a
```

### Subnet sizing guidance

| Environment | Subnet Size | Hosts per Subnet |
|---|---|---|
| Dev | `/24` | 254 |
| Staging | `/23` | 510 |
| Prod | `/22` | 1022 |

> **CIDR conflict check**: Before applying, verify your chosen CIDRs don't overlap with any existing VPC in your HCS tenant. HCS Console → VPC → check existing VPCs.

---

## Step 2 — Plan the Network Module

```bash
source ~/.hcs-credentials.sh

cd environments/dev
terraform plan \
  -var-file="terraform.tfvars" \
  -target=module.network \
  -out=network.tfplan
```

Or using the wrapper (note: extra flags pass through):

```bash
./scripts/tf.sh dev plan -target=module.network
# Plan is saved to environments/dev/dev.tfplan
```

### What to verify in the plan output

Look for these resources in the plan — confirm counts and names:

```
# module.network.hcs_vpc.this will be created
  + name = "myapp-dev-vpc"
  + cidr = "10.10.0.0/16"

# module.network.hcs_vpc_subnet.public["public-1"] will be created
  + name = "myapp-dev-public-1"
  + cidr = "10.10.1.0/24"

# module.network.hcs_vpc_subnet.private["private-1"] will be created
  + name = "myapp-dev-private-1"
  + cidr = "10.10.10.0/24"

# module.network.hcs_nat_gateway.this[0] will be created
  + name = "myapp-dev-nat"
  + spec = "1"   (small — dev default)

# module.network.hcs_networking_secgroup.default will be created
  + name = "myapp-dev-default-sg"
```

Confirm:
- ✅ All subnet CIDRs match what you set in tfvars
- ✅ The number of public/private subnets matches the number of CIDRs you provided
- ✅ NAT gateway is planned (if `enable_nat_gateway = true`)
- ✅ No resources are marked for destruction

---

## Step 3 — Apply

```bash
./scripts/tf.sh dev apply
```

If you ran a targeted plan, apply will use the saved plan:
```bash
cd environments/dev
terraform apply network.tfplan
```

Expected output:
```
module.network.hcs_vpc.this: Creating...
module.network.hcs_vpc.this: Creation complete after 5s

module.network.hcs_vpc_subnet.public["public-1"]: Creating...
module.network.hcs_vpc_subnet.public["public-2"]: Creating...
module.network.hcs_vpc_subnet.private["private-1"]: Creating...
module.network.hcs_vpc_subnet.private["private-2"]: Creating...
...
module.network.hcs_nat_gateway.this[0]: Still creating... [30s elapsed]
module.network.hcs_nat_gateway.this[0]: Creation complete after 45s

Apply complete! Resources: 9 added, 0 changed, 0 destroyed.
```

---

## Step 4 — Verify

### View outputs

```bash
cd environments/dev
terraform output -json
```

The network module exposes these outputs (accessible as `module.network.<output>` within the root module):

| Output | What It Contains |
|---|---|
| `vpc_id` | VPC ID — needed by CCE, GaussDB, RDS |
| `vpc_cidr` | VPC CIDR block |
| `public_subnet_ids` | Map of `{ "public-1" = "<id>", "public-2" = "<id>" }` |
| `public_subnet_id_list` | Flat list of public subnet IDs |
| `private_subnet_ids` | Map of private subnet IDs |
| `private_subnet_id_list` | Flat list of private subnet IDs |
| `default_security_group_id` | ID of the baseline security group |
| `nat_gateway_id` | NAT gateway ID |
| `nat_eip_address` | Public IP of the NAT gateway |

View specific values:
```bash
terraform state show module.network.hcs_vpc.this
terraform state show module.network.hcs_nat_gateway.this[0]
```

### Verify in HCS Console

1. **VPC**: Console → VPC → VPCs → find `myapp-dev-vpc`
2. **Subnets**: Inside the VPC detail, check Subnets tab — all 4 should be listed
3. **NAT Gateway**: Console → NAT Gateway → should show `myapp-dev-nat` with status **Running**
4. **EIP**: Console → EIP — the NAT EIP should appear with status **Bound**

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `CIDR block conflicts` | Your VPC CIDR overlaps with an existing VPC | Change `vpc_cidr` to a non-overlapping range |
| `InvalidNetworkID` | Subnet gateway IP calculated incorrectly | Ensure subnets are at least `/29` and CIDRs are valid |
| `EIP type not found` | `eip_type` value doesn't match HCS external network | Check HCS Console → EIP → Create EIP for valid type names |
| `AZ not available` | AZ name in `availability_zones` doesn't exist | Check valid AZ names in HCS Console → ECS |
| `NAT Gateway quota exceeded` | HCS tenant quota for NAT gateways reached | Request quota increase from HCS admin, or set `enable_nat_gateway = false` |

---

## Key Outputs for Other Modules

After the network module is applied, these values are automatically passed to dependent modules via the root `main.tf`. If you need them for manual reference (e.g. for GaussDB or RDS which take VPC/subnet IDs directly in tfvars):

```bash
cd environments/dev

# Get VPC ID
terraform state show module.network.hcs_vpc.this | grep ' id '

# Get first private subnet ID
terraform state show 'module.network.hcs_vpc_subnet.private["private-1"]' | grep ' id '

# Get default security group ID
terraform state show module.network.hcs_networking_secgroup.default | grep ' id '
```
