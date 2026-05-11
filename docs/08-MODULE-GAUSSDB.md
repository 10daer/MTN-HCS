# Module Deployment: GaussDB OpenGauss
## `modules/gaussdb`

> **Prerequisites**: [00-SETUP.md](00-SETUP.md) complete, [01-MODULE-NETWORK.md](01-MODULE-NETWORK.md) applied, [02-MODULE-SECURITY.md](02-MODULE-SECURITY.md) applied.
> **Deploy order**: After network and security. GaussDB needs a VPC, subnet, and security group ID.
> **Estimated apply time**: 45–90 minutes (GaussDB instances are slow to provision)

---

## What This Module Creates

| Resource | HCS Type | Description |
|---|---|---|
| Parameter templates | `hcs_gaussdb_opengauss_parameter_template` | Reusable DB configuration templates |
| Instances | `hcs_gaussdb_opengauss_instance` | GaussDB OpenGauss cluster (HA-capable) |

GaussDB OpenGauss is HCS's enterprise PostgreSQL-compatible database. It supports:
- **Centralized HA** — primary + standby nodes, sync/async replication
- **Distributed** — sharded architecture for very large datasets

---

## Step 1 — Collect Network IDs

GaussDB requires VPC ID, subnet ID, and security group ID passed explicitly in tfvars (unlike ECS, which gets them from module outputs automatically).

```bash
cd environments/dev

# VPC ID
terraform state show module.network.hcs_vpc.this | grep '^ id '

# First private subnet ID (recommended for DB placement)
terraform state show 'module.network.hcs_vpc_subnet.private["private-1"]' | grep '^ id '

# Database security group ID
terraform state show 'module.security.hcs_networking_secgroup.groups["db"]' | grep '^ id '
```

Note these three values — you'll use them in Step 2.

---

## Step 2 — Add GaussDB Values to `terraform.tfvars`

### Setting passwords safely

```bash
# Set before running plan/apply — never put passwords in terraform.tfvars
export TF_VAR_gaussdb_instances='{
  primary = {
    name              = "dev-gaussdb-primary"
    flavor            = "gaussdb.opengauss.ee.m6.2xlarge.x868.ha"
    password          = "MySecureP@ss123!"
    vpc_id            = "<vpc-id-from-step-1>"
    subnet_id         = "<private-subnet-id-from-step-1>"
    security_group_id = "<db-sg-id-from-step-1>"
    ha_mode                 = "centralization_standard"
    ha_replication_mode     = "sync"
    ha_consistency          = "strong"
    volume_type             = "ULTRAHIGH"
    volume_size             = 100
    replica_num             = 3
    az_count                = 3
    configuration_key       = "dev_tuned"
    backup_start_time       = "02:00-03:00"
    backup_keep_days        = 7
    time_zone               = "UTC+01:00"
  }
}'
```

Or add to `terraform.tfvars` with empty password and override via env var:

```hcl
# ── GaussDB — Parameter Templates ────────────────────────────────────────────
gaussdb_parameter_templates = {
  dev_tuned = {
    name           = "dev-tuned-template"
    description    = "Tuned parameters for dev OpenGauss workloads"
    engine_version = "8.202"
    instance_mode  = "combined"      # combined | primary | standby
    parameters = [
      { name = "audit_system_object", value = "100" },
      { name = "autoanalyze",         value = "on" },
      { name = "enable_alarm",        value = "on" }
    ]
  }
}

# ── GaussDB — Instances ───────────────────────────────────────────────────────
gaussdb_instances = {
  primary = {
    name              = "dev-gaussdb-primary"
    flavor            = "gaussdb.opengauss.ee.m6.2xlarge.x868.ha"
    password          = ""           # override with TF_VAR_gaussdb_instances env var
    vpc_id            = "<vpc-id>"
    subnet_id         = "<private-subnet-id>"
    security_group_id = "<db-sg-id>"

    # HA configuration
    ha_mode             = "centralization_standard"  # or "independent"
    ha_replication_mode = "sync"    # sync | async
    ha_consistency      = "strong"  # strong | eventual

    # Storage
    volume_type = "ULTRAHIGH"   # ULTRAHIGH (SSD) | HIGH (SAS)
    volume_size = 100           # GB — minimum 40, must be multiple of 40

    # Cluster sizing
    replica_num = 3    # 3 = primary + 2 standbys (HA)
    az_count    = 3    # must match or be <= number of available AZs in your region

    # Parameter template (must match a key from gaussdb_parameter_templates)
    configuration_key = "dev_tuned"

    # Backup
    backup_start_time = "02:00-03:00"
    backup_keep_days  = 7

    # Timezone
    time_zone = "UTC+01:00"
  }
}
```

### HA mode reference

| `ha_mode` | Nodes | Use case |
|---|---|---|
| `centralization_standard` | 1 primary + 2 standbys | Standard HA — most common |
| `independent` | Single node | Dev/test only — no HA |

### Flavor naming convention

GaussDB flavors follow this pattern: `gaussdb.opengauss.ee.<series>.<size>.x868.<type>`
- `m6.2xlarge` = 8 vCPU / 64 GB RAM
- `m6.xlarge` = 4 vCPU / 32 GB RAM
- `.ha` suffix = high-availability flavor
- Check available flavors: HCS Console → GaussDB → Create Instance → Instance Specifications

---

## Step 3 — Plan

```bash
source ~/.hcs-credentials.sh

cd environments/dev
terraform plan \
  -var-file="terraform.tfvars" \
  -target=module.gaussdb \
  -out=gaussdb.tfplan
```

### What to verify

```
# module.gaussdb.hcs_gaussdb_opengauss_parameter_template.templates["dev_tuned"] will be created
  + name           = "dev-tuned-template"
  + engine_version = "8.202"
  + instance_mode  = "combined"

# module.gaussdb.hcs_gaussdb_opengauss_instance.instances["primary"] will be created
  + name              = "dev-gaussdb-primary"
  + flavor            = "gaussdb.opengauss.ee.m6.2xlarge.x868.ha"
  + vpc_id            = "<your-vpc-id>"
  + subnet_id         = "<private-subnet-id>"
  + security_group_id = "<db-sg-id>"

  + ha {
      + mode             = "centralization_standard"
      + replication_mode = "sync"
      + consistency      = "strong"
    }

  + volume {
      + type = "ULTRAHIGH"
      + size = 100
    }
```

Confirm VPC ID, subnet ID, and SG ID match your network outputs.

---

## Step 4 — Apply

```bash
terraform apply gaussdb.tfplan
```

> ⏱ GaussDB instance creation takes **45–90 minutes**. The process polls every 10 seconds.

```
module.gaussdb.hcs_gaussdb_opengauss_instance.instances["primary"]: Creating...
module.gaussdb.hcs_gaussdb_opengauss_instance.instances["primary"]: Still creating... [10m0s elapsed]
...
module.gaussdb.hcs_gaussdb_opengauss_instance.instances["primary"]: Creation complete after 1h2m14s

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.
```

---

## Step 5 — Verify

```bash
terraform state show 'module.gaussdb.hcs_gaussdb_opengauss_instance.instances["primary"]' \
  | grep -E 'id|endpoint|status|private_ips'
```

Key outputs from the module:
- `instance_ids` — map of instance IDs
- `instance_endpoints` — connection endpoint (host:port)
- `instance_statuses` — current status (should be `available`)

### Verify in HCS Console

1. HCS Console → GaussDB → Instances
2. Find `dev-gaussdb-primary` → status **Available**
3. Click instance → **Connections** tab → note the private endpoint (e.g. `10.10.10.x:8000`)
4. Check **HA** tab → primary + 2 standby nodes listed

### Test connection from app tier

```bash
# From an app server (via bastion or VPN)
psql -h <gaussdb-private-ip> -p 8000 -U root -d postgres
# Enter your password when prompted
```

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `flavor not found` | Flavor string not available in your region | Check HCS Console → GaussDB → Create Instance |
| `az_count exceeds available AZs` | `az_count = 3` but region has fewer AZs | Set `az_count` to the number of AZs in your region |
| `volume_size must be multiple of 40` | e.g. `volume_size = 80` is fine, `90` is not | Use multiples: 40, 80, 120, 160... |
| `security group not found` | Wrong SG ID in tfvars | Re-check ID from state output |
| Instance stuck in `BUILD` for >2 hours | HCS resource issue | Check HCS Console events; contact HCS admin |
| `password does not meet complexity requirements` | HCS enforces strong passwords for GaussDB | Min 8 chars, uppercase, lowercase, number, special char (`@!%^*`) |
