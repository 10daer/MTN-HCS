# Module Deployment: Security
## `modules/security`

> **Prerequisites**: [00-SETUP.md](00-SETUP.md) complete, [01-MODULE-NETWORK.md](01-MODULE-NETWORK.md) applied.
> **Deploy order**: **2nd** — must come after Network. ECS, CCE, GaussDB, and RDS all depend on security groups being present.
> **Estimated apply time**: ~1 minute

---

## What This Module Creates

The security module is a **security group factory** — it takes a declarative map of groups and rules and creates all the corresponding HCS resources.

| Resource | HCS Type | Description |
|---|---|---|
| Security groups | `hcs_networking_secgroup` | One group per key in the `security_groups` map |
| Default egress rule | `hcs_networking_secgroup_rule` | Allow-all egress created automatically per group |
| Ingress rules | `hcs_networking_secgroup_rule` | One rule per entry in each group's `ingress_rules` list |

### Default security group architecture (as defined in `environments/dev/main.tf`)

The root module pre-defines four security groups in the `module "security"` call. These are not driven by `terraform.tfvars` — they are hardcoded in `main.tf` because the tier structure is architectural:

| Group Key | Name | Purpose |
|---|---|---|
| `bastion` | `<prefix>-bastion-sg` | Allows SSH from `trusted_ssh_cidr` — jump host access |
| `web` | `<prefix>-web-sg` | Allows HTTP (80) and HTTPS (443) from internet (`0.0.0.0/0`) |
| `app` | `<prefix>-app-sg` | Allows traffic from the web tier only (remote_sg reference) |
| `database` | `<prefix>-database-sg` | Allows DB port traffic from the app tier only |

This is a **zero-trust tiered architecture** — each tier only accepts traffic from the tier directly above it.

```
Internet → web-sg (80/443)
           web-sg → app-sg (8080)
                    app-sg → database-sg (5432 / 3306)
```

---

## Step 1 — Review the Security Group Definition in `main.tf`

The security module is called in `environments/dev/main.tf`. Unlike other modules, its input is defined inline rather than via `terraform.tfvars`. Open the file and find the `module "security"` block.

The definition looks like this (already in the repo):

```hcl
module "security" {
  source      = "../../modules/security"
  name_prefix = local.name_prefix
  vpc_id      = module.network.vpc_id

  security_groups = {
    bastion = {
      description = "Bastion host — SSH from trusted network"
      ingress_rules = [
        {
          protocol         = "tcp"
          port_range_min   = 22
          port_range_max   = 22
          remote_ip_prefix = var.trusted_ssh_cidr    # from terraform.tfvars
        }
      ]
    }

    web = {
      description = "Web tier — HTTP/HTTPS from internet"
      ingress_rules = [
        {
          protocol         = "tcp"
          port_range_min   = 80
          port_range_max   = 80
          remote_ip_prefix = "0.0.0.0/0"
        },
        {
          protocol         = "tcp"
          port_range_min   = 443
          port_range_max   = 443
          remote_ip_prefix = "0.0.0.0/0"
        }
      ]
    }

    app = {
      description = "App tier — traffic from web tier only"
      ingress_rules = [
        {
          protocol       = "tcp"
          port_range_min = 8080
          port_range_max = 8080
          remote_sg_key  = "web"     # references the web group above
        }
      ]
    }

    database = {
      description = "Database tier — traffic from app tier only"
      ingress_rules = [
        {
          protocol       = "tcp"
          port_range_min = 5432
          port_range_max = 5432
          remote_sg_key  = "app"     # references the app group above
        },
        {
          protocol       = "tcp"
          port_range_min = 3306
          port_range_max = 3306
          remote_sg_key  = "app"
        }
      ]
    }
  }

  depends_on = [module.network]
}
```

### Adding custom security groups

To add a new group (e.g. for a monitoring stack), add a new key to the `security_groups` map in `main.tf`:

```hcl
monitoring = {
  description = "Monitoring stack — Prometheus scrape from app tier"
  ingress_rules = [
    {
      protocol       = "tcp"
      port_range_min = 9090
      port_range_max = 9090
      remote_sg_key  = "app"
    }
  ]
}
```

---

## Step 2 — Confirm the `trusted_ssh_cidr` in `terraform.tfvars`

The bastion security group uses `var.trusted_ssh_cidr` for the SSH ingress CIDR. Make sure it is set correctly:

```hcl
# In terraform.tfvars
trusted_ssh_cidr = "10.0.0.0/8"    # your corporate network range; tighten for prod
```

> **Security note**: Never set this to `0.0.0.0/0` in staging or prod. SSH should only be allowed from your VPN CIDR or bastion host IP.

---

## Step 3 — Plan the Security Module

```bash
source ~/.hcs-credentials.sh

cd environments/dev
terraform plan \
  -var-file="terraform.tfvars" \
  -target=module.security \
  -out=security.tfplan
```

### What to verify in the plan output

```
# module.security.hcs_networking_secgroup.groups["bastion"] will be created
  + name        = "myapp-dev-bastion-sg"
  + description = "Bastion host — SSH from trusted network"

# module.security.hcs_networking_secgroup.groups["web"] will be created
  + name        = "myapp-dev-web-sg"

# module.security.hcs_networking_secgroup.groups["app"] will be created
  + name        = "myapp-dev-app-sg"

# module.security.hcs_networking_secgroup.groups["database"] will be created
  + name        = "myapp-dev-database-sg"

# module.security.hcs_networking_secgroup_rule.egress_all["bastion"] will be created
  + direction         = "egress"
  + remote_ip_prefix  = "0.0.0.0/0"

# module.security.hcs_networking_secgroup_rule.ingress["bastion-ingress-0"] will be created
  + direction        = "ingress"
  + protocol         = "tcp"
  + port_range_min   = 22
  + port_range_max   = 22
  + remote_ip_prefix = "10.0.0.0/8"

# module.security.hcs_networking_secgroup_rule.ingress["app-ingress-0"] will be created
  + direction              = "ingress"
  + remote_group_id        = (known after apply)   ← ID of the web-sg
```

Confirm:
- ✅ Four security groups are being created
- ✅ `bastion` ingress shows your `trusted_ssh_cidr`, not `0.0.0.0/0`
- ✅ `app` ingress rule shows `remote_group_id` (references `web` group) — not a raw CIDR
- ✅ `database` ingress rule shows `remote_group_id` (references `app` group)
- ✅ Each group has an egress-allow-all rule

---

## Step 4 — Apply

```bash
terraform apply security.tfplan
```

Or if applying via the wrapper:

```bash
./scripts/tf.sh dev apply
```

Expected output:
```
module.security.hcs_networking_secgroup.groups["bastion"]: Creating...
module.security.hcs_networking_secgroup.groups["web"]: Creating...
module.security.hcs_networking_secgroup.groups["app"]: Creating...
module.security.hcs_networking_secgroup.groups["database"]: Creating...
...
module.security.hcs_networking_secgroup_rule.ingress["bastion-ingress-0"]: Creating...
...

Apply complete! Resources: 12 added, 0 changed, 0 destroyed.
```

---

## Step 5 — Verify

### View security group IDs

```bash
cd environments/dev
terraform output -json
```

The security module outputs:
- `security_group_ids` — map of `{ "bastion" = "<id>", "web" = "<id>", "app" = "<id>", "database" = "<id>" }`

Get specific IDs:

```bash
terraform state show 'module.security.hcs_networking_secgroup.groups["web"]' | grep ' id '
terraform state show 'module.security.hcs_networking_secgroup.groups["app"]' | grep ' id '
```

### Verify in HCS Console

1. Go to **VPC** → **Security Groups**
2. You should see four new groups prefixed with your project name:
   - `myapp-dev-bastion-sg`
   - `myapp-dev-web-sg`
   - `myapp-dev-app-sg`
   - `myapp-dev-database-sg`
3. Click each group and inspect the **Inbound Rules** tab:
   - `bastion-sg`: port 22, source = your trusted CIDR
   - `web-sg`: ports 80 and 443, source = `0.0.0.0/0`
   - `app-sg`: port 8080, source = `web-sg` (shown as security group reference)
   - `database-sg`: ports 5432 and 3306, source = `app-sg`

---

## Modifying Security Groups After Deployment

### Adding a new ingress rule to an existing group

Edit the corresponding group's `ingress_rules` list in `environments/dev/main.tf`:

```hcl
web = {
  description = "Web tier"
  ingress_rules = [
    { protocol = "tcp", port_range_min = 80, port_range_max = 80, remote_ip_prefix = "0.0.0.0/0" },
    { protocol = "tcp", port_range_min = 443, port_range_max = 443, remote_ip_prefix = "0.0.0.0/0" },
    # Add new rule:
    { protocol = "tcp", port_range_min = 8443, port_range_max = 8443, remote_ip_prefix = "0.0.0.0/0" }
  ]
}
```

Then plan and apply, targeting only security:

```bash
terraform plan -var-file="terraform.tfvars" -target=module.security -out=security.tfplan
terraform apply security.tfplan
```

> Adding a new rule is an **in-place update** — no downtime to existing rules or instances using the SG.

### Important: Rule ordering

Rules in the `ingress_rules` list are keyed by index (`sg_key-ingress-0`, `sg_key-ingress-1`, etc.). **Do not reorder or remove rules from the middle of the list** — Terraform will destroy and recreate rules at shifted indices. Always append new rules at the end.

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `remote group not found` | `remote_sg_key` references a group that doesn't exist in the same map | Check the key spelling matches exactly |
| `Security group quota exceeded` | HCS tenant SG quota reached | Delete unused SGs or request quota increase |
| `Rule already exists` | Duplicate ingress rule with same port+protocol+source | Remove the duplicate from the list |
| `depends on module.network` error | Network not deployed yet | Apply `module.network` first |
