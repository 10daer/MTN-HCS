# Module Deployment: RDS (Relational Database Service)
## `modules/rds`

> **Prerequisites**: [00-SETUP.md](00-SETUP.md) complete, [01-MODULE-NETWORK.md](01-MODULE-NETWORK.md) applied, [02-MODULE-SECURITY.md](02-MODULE-SECURITY.md) applied.
> **Deploy order**: After network and security. RDS needs a VPC, subnet, and security group.
> **Estimated apply time**: 20–40 minutes per instance

---

## What This Module Creates

| Resource | HCS Type | Description |
|---|---|---|
| RDS Instances | `hcs_rds_instance` | MySQL or PostgreSQL managed instance |
| MySQL databases | `hcs_rds_mysql_database` | Databases inside a MySQL instance |
| MySQL accounts | `hcs_rds_mysql_account` | MySQL user accounts |
| MySQL privileges | `hcs_rds_mysql_database_privilege` | Per-database read/write grants |
| PostgreSQL databases | `hcs_rds_pg_database` | Databases inside a PostgreSQL instance |
| PostgreSQL accounts | `hcs_rds_pg_account` | PostgreSQL user accounts |
| PostgreSQL privileges | `hcs_rds_pg_database_privilege` | Per-schema read/write grants |
| PostgreSQL plugins | `hcs_rds_pg_plugin` | Extensions (pgaudit, pg_stat_statements, etc.) |
| SQL Audit | `hcs_rds_sql_audit` | Audit logging configuration |

---

## Step 1 — Collect Network IDs

Like GaussDB, RDS takes VPC/subnet/SG IDs directly in tfvars:

```bash
cd environments/dev

# VPC ID
terraform state show module.network.hcs_vpc.this | grep '^ id '

# Private subnet ID
terraform state show 'module.network.hcs_vpc_subnet.private["private-1"]' | grep '^ id '

# Database security group ID
terraform state show 'module.security.hcs_networking_secgroup.groups["db"]' | grep '^ id '
```

---

## Step 2 — Set Passwords Safely

Never put database passwords in `terraform.tfvars`. Use environment variable overrides:

```bash
# PostgreSQL instance password
export TF_VAR_rds_instances='{
  pg_primary = {
    name              = "dev-rds-pg"
    flavor            = "rds.pg.n1.large.2.ha"
    vpc_id            = "<vpc-id>"
    subnet_id         = "<private-subnet-id>"
    security_group_id = "<db-sg-id>"
    availability_zone = ["az1.dc0", "az1.dc0"]
    db_type           = "PostgreSQL"
    db_version        = "14"
    db_password       = "MySecureP@ss123!"
    volume_type       = "ULTRAHIGH"
    volume_size       = 100
    ha_replication_mode = "sync"
    backup_start_time = "02:00-03:00"
    backup_keep_days  = 7
    ssl_enable        = true
    time_zone         = "UTC+01:00"
    tags              = { Tier = "database" }
  }
}'

# PostgreSQL account passwords
export TF_VAR_rds_pg_accounts='{
  app_user = {
    instance_key = "pg_primary"
    name         = "app_user"
    password     = "AppUserP@ss456!"
  }
}'
```

---

## Step 3 — Add RDS Values to `terraform.tfvars`

```hcl
# ── RDS — Instances ───────────────────────────────────────────────────────────
rds_instances = {
  pg_primary = {
    name              = "dev-rds-pg"
    flavor            = "rds.pg.n1.large.2.ha"   # see flavor table below
    vpc_id            = "<vpc-id>"
    subnet_id         = "<private-subnet-id>"
    security_group_id = "<db-sg-id>"

    # AZ list: first = primary AZ, second = standby AZ
    availability_zone = ["az1.dc0", "az1.dc0"]   # same AZ for dev; different for prod

    db_type     = "PostgreSQL"    # PostgreSQL | MySQL
    db_version  = "14"            # check available versions in HCS Console
    db_password = ""              # override with TF_VAR_rds_instances env var

    volume_type = "ULTRAHIGH"     # ULTRAHIGH (SSD) | HIGH (SAS) | COMMON (SATA)
    volume_size = 100             # GB — minimum 40, increments of 10

    # HA replication
    ha_replication_mode = "sync"  # sync | async (sync = no data loss, slightly slower)

    # Backup
    backup_start_time = "02:00-03:00"
    backup_keep_days  = 7

    # Security
    ssl_enable = true             # recommended for all environments

    # Timezone
    time_zone = "UTC+01:00"

    tags = { Tier = "database" }
  }
}

# ── PostgreSQL Databases ──────────────────────────────────────────────────────
rds_pg_databases = {
  app_db = {
    instance_key = "pg_primary"
    name         = "app_db"
    owner        = "rdsAdmin"     # default admin account created with the instance
  }
  analytics_db = {
    instance_key = "pg_primary"
    name         = "analytics_db"
    owner        = "rdsAdmin"
  }
}

# ── PostgreSQL Accounts ───────────────────────────────────────────────────────
rds_pg_accounts = {
  app_user = {
    instance_key = "pg_primary"
    name         = "app_user"
    password     = ""    # override with TF_VAR_rds_pg_accounts env var
  }
  readonly_user = {
    instance_key = "pg_primary"
    name         = "readonly_user"
    password     = ""
  }
}

# ── PostgreSQL Privileges ─────────────────────────────────────────────────────
rds_pg_privileges = {
  app_user_readwrite = {
    instance_key = "pg_primary"
    db_key       = "app_db"        # key from rds_pg_databases
    users = [
      { account_key = "app_user", schema_name = "public", readonly = false }
    ]
  }
  readonly_access = {
    instance_key = "pg_primary"
    db_key       = "analytics_db"
    users = [
      { account_key = "readonly_user", schema_name = "public", readonly = true }
    ]
  }
}

# ── PostgreSQL Plugins ────────────────────────────────────────────────────────
rds_pg_plugins = {
  pgaudit = {
    instance_key = "pg_primary"
    db_key       = "app_db"
    name         = "pgaudit"
  }
  pg_stat = {
    instance_key = "pg_primary"
    db_key       = "app_db"
    name         = "pg_stat_statements"
  }
}

# ── SQL Audit ─────────────────────────────────────────────────────────────────
rds_sql_audits = {
  pg_audit = {
    instance_key = "pg_primary"
    keep_days    = 30
    audit_types  = ["CREATE_USER", "DROP_USER", "INSERT", "DELETE", "UPDATE", "SELECT"]
  }
}
```

### MySQL instance example

```hcl
rds_instances = {
  mysql_app = {
    name              = "dev-rds-mysql"
    flavor            = "rds.mysql.n1.large.2.ha"
    vpc_id            = "<vpc-id>"
    subnet_id         = "<private-subnet-id>"
    security_group_id = "<db-sg-id>"
    availability_zone = ["az1.dc0", "az1.dc0"]
    db_type           = "MySQL"
    db_version        = "8.0"
    db_password       = ""           # set via TF_VAR_rds_instances
    volume_type       = "ULTRAHIGH"
    volume_size       = 100
    ha_replication_mode = "semisync"  # MySQL: semisync | async
    backup_start_time = "03:00-04:00"
    backup_keep_days  = 7
    lower_case_table_names = "1"     # 0 = case-sensitive, 1 = case-insensitive
    tags = { Tier = "database" }
  }
}

rds_mysql_databases = {
  app_db = {
    instance_key  = "mysql_app"
    name          = "app_db"
    character_set = "utf8mb4"
    description   = "Application database"
  }
}

rds_mysql_accounts = {
  app_user = {
    instance_key = "mysql_app"
    name         = "app_user"
    password     = ""     # set via TF_VAR_rds_mysql_accounts
    hosts        = ["%"]  # allow connection from any IP; restrict to subnet for prod
  }
}

rds_mysql_privileges = {
  app_access = {
    instance_key = "mysql_app"
    db_key       = "app_db"
    users = [
      { account_key = "app_user", readonly = false }
    ]
  }
}
```

### Flavor reference

| Flavor pattern | Engine | vCPU | RAM | Notes |
|---|---|---|---|---|
| `rds.pg.n1.large.2.ha` | PostgreSQL | 2 | 4 GB | HA, dev |
| `rds.pg.n1.xlarge.4.ha` | PostgreSQL | 4 | 16 GB | HA, standard prod |
| `rds.mysql.n1.large.2.ha` | MySQL | 2 | 4 GB | HA, dev |
| `rds.mysql.n1.xlarge.4.ha` | MySQL | 4 | 16 GB | HA, standard prod |

Check available flavors: HCS Console → RDS → Create DB Instance → Instance Specifications.

---

## Step 4 — Plan

```bash
source ~/.hcs-credentials.sh

cd environments/dev
terraform plan \
  -var-file="terraform.tfvars" \
  -target=module.rds \
  -out=rds.tfplan
```

### What to verify

```
# module.rds.hcs_rds_instance.instances["pg_primary"] will be created
  + name              = "dev-rds-pg"
  + flavor            = "rds.pg.n1.large.2.ha"
  + vpc_id            = "<vpc-id>"

  + db {
      + type     = "PostgreSQL"
      + version  = "14"
      + password = (sensitive value)
    }

  + volume {
      + type = "ULTRAHIGH"
      + size = 100
    }

# module.rds.hcs_rds_pg_database.pg_databases["app_db"] will be created
  + name         = "app_db"
  + instance_id  = (known after apply)

# module.rds.hcs_rds_pg_account.pg_accounts["app_user"] will be created
  + name        = "app_user"
  + instance_id = (known after apply)
```

Confirm VPC/subnet/SG IDs, flavor, DB type and version are correct.

---

## Step 5 — Apply

```bash
terraform apply rds.tfplan
```

> ⏱ RDS instance creation takes **20–40 minutes**. Databases, accounts, and privileges are created after the instance is available.

```
module.rds.hcs_rds_instance.instances["pg_primary"]: Creating...
module.rds.hcs_rds_instance.instances["pg_primary"]: Still creating... [5m0s elapsed]
...
module.rds.hcs_rds_instance.instances["pg_primary"]: Creation complete after 28m42s

module.rds.hcs_rds_pg_database.pg_databases["app_db"]: Creating...
module.rds.hcs_rds_pg_account.pg_accounts["app_user"]: Creating...
...

Apply complete! Resources: 7 added, 0 changed, 0 destroyed.
```

---

## Step 6 — Verify

### View instance details

```bash
terraform state show 'module.rds.hcs_rds_instance.instances["pg_primary"]' \
  | grep -E 'id|private_ips|status|db_port'
```

Key outputs:
- `resolved_instance_ids` — map of all instance IDs
- `instance_endpoints` — private connection endpoints
- `instance_statuses` — current status (should be `ACTIVE`)

### Verify in HCS Console

1. HCS Console → RDS → Instances
2. Find `dev-rds-pg` → status **Available**
3. Click instance → **Databases** tab → `app_db`, `analytics_db` listed
4. Click **Accounts** tab → `app_user`, `readonly_user` listed

### Test connection from app tier

```bash
# From an app server (via bastion or VPN)
# PostgreSQL:
psql -h <rds-private-ip> -p 5432 -U app_user -d app_db
# Enter password when prompted

# MySQL:
mysql -h <rds-private-ip> -P 3306 -u app_user -p app_db
```

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `flavor not found` | Flavor string not available | Check HCS Console → RDS → Create → Specifications |
| `DB version not supported` | `db_version` not available | Check HCS Console for supported versions (e.g. PostgreSQL 12, 13, 14) |
| `ha_replication_mode invalid` | Wrong value for engine | PostgreSQL: `sync`/`async`; MySQL: `semisync`/`async` |
| `password does not meet requirements` | Weak password | Must have uppercase, lowercase, number, special char, min 8 chars |
| `subnet not in VPC` | Subnet ID not in the VPC | Re-check both IDs from network module state |
| `account creation failed` | Instance not yet in ACTIVE state | Wait for instance to stabilize, then apply again |
| `plugin not available` | Extension not supported in DB version | Check HCS docs for available extensions per PostgreSQL version |
