````markdown
# Huawei Cloud Stack (HCS) RDS Terraform Context

**Purpose**  
This file is the complete authoritative reference for any LLM (including yourself) when designing or generating Terraform configurations for Relational Database Service (RDS) resources in Huawei Cloud Stack.

Use this document to ensure all generated code follows the official schemas, engine-specific behaviors (MySQL vs PostgreSQL), HA configuration, parameter groups, privilege management, plugins, and SQL audit settings.

---

## Supported Resources

### 1. hcs_rds_instance (Resource)

**Description:** Manages an RDS instance (MySQL or PostgreSQL).

**Example Usage**

**Single Instance**

```hcl
resource "hcs_rds_instance" "single" {
  name              = "tf-rds-single"
  flavor            = "rds.pg.n1.large.2"
  vpc_id            = var.vpc_id
  subnet_id         = var.subnet_id
  security_group_id = var.secgroup_id
  availability_zone = [var.az1]

  db {
    type     = "PostgreSQL"
    version  = "12"
    password = var.password
  }

  volume {
    type = "ULTRAHIGH"
    size = 100
  }

  backup_strategy {
    start_time = "08:00-09:00"
    keep_days  = 7
  }
}
```
````

**Primary/Standby (HA)**

```hcl
resource "hcs_rds_instance" "ha" {
  name                = "tf-rds-ha"
  flavor              = "rds.pg.n1.large.2.ha"
  ha_replication_mode = "async"
  vpc_id              = var.vpc_id
  subnet_id           = var.subnet_id
  security_group_id   = var.secgroup_id
  availability_zone   = [var.az1, var.az2]

  db {
    type     = "PostgreSQL"
    version  = "12"
    password = var.password
  }

  volume {
    type = "ULTRAHIGH"
    size = 100
  }
}
```

**With Custom Parameters**

```hcl
  parameters {
    name  = "div_precision_increment"
    value = "12"
  }
```

**MySQL Example**

```hcl
resource "hcs_rds_instance" "mysql" {
  name              = "tf-mysql"
  flavor            = "rds.mysql.xlarge.arm4.single"
  availability_zone = [var.az1]
  vpc_id            = var.vpc_id
  subnet_id         = var.subnet_id
  security_group_id = var.secgroup_id

  db {
    type     = "MySQL"
    version  = "5.7"
    password = var.mysql_password
  }

  volume {
    type = "ULTRAHIGH"
    size = 100
  }
}
```

**Argument Reference (key fields)**

- `name` – (Required) 4-64 chars.
- `flavor` – (Required) e.g. `rds.pg.n1.large.2` or `.ha` suffix.
- `availability_zone` – (Required, List, ForceNew) 1 or 2 AZs.
- `vpc_id`, `subnet_id`, `security_group_id` – (Required, ForceNew where noted).
- `db` – (Required, ForceNew) `type` (`MySQL`/`PostgreSQL`), `version`, `password`, `port`.
- `volume` – (Required) `type` (`ULTRAHIGH`, `LOCALSSD`, `CLOUDSSD`, `ESSD`), `size`, auto-expand options.
- `backup_strategy` – `start_time`, `keep_days`, `period`.
- `ha_replication_mode` – `async`/`semisync` (MySQL), `async`/`sync` (PostgreSQL).
- `parameters[]` – custom DB parameters.
- `lower_case_table_names`, `time_zone`, `ssl_enable`, `description`, `tags`, `enterprise_project_id`.
- `restore` – for point-in-time restore (postpaid only).

**Attributes Reference**

- `id`, `status`, `private_ips`, `public_ips`, `nodes[]`, `db.user_name`.

**Import**

```bash
terraform import hcs_rds_instance.example <instance_id>
```

**Recommended lifecycle**

```hcl
lifecycle {
  ignore_changes = [db, restore, param_group_id, availability_zone]
}
```

**Timeouts**

- `create/update/delete` – 30m default.

---

### 2–4. MySQL-specific Resources

**hcs_rds_mysql_account**

```hcl
resource "hcs_rds_mysql_account" "acct" {
  instance_id = hcs_rds_instance.mysql.id
  name        = "app_user"
  password    = var.password
  hosts       = ["%"]
}
```

**hcs_rds_mysql_database**

```hcl
resource "hcs_rds_mysql_database" "db" {
  instance_id   = hcs_rds_instance.mysql.id
  name          = "app_db"
  character_set = "utf8mb4"
  description   = "Application database"
}
```

**hcs_rds_mysql_database_privilege**

```hcl
resource "hcs_rds_mysql_database_privilege" "priv" {
  instance_id = hcs_rds_instance.mysql.id
  db_name     = hcs_rds_mysql_database.db.name

  users {
    name     = hcs_rds_mysql_account.acct.name
    readonly = false
  }
}
```

---

### 5–8. PostgreSQL-specific Resources (HCS 8.5.0+)

**hcs_rds_pg_account**

```hcl
resource "hcs_rds_pg_account" "pg_acct" {
  instance_id = hcs_rds_instance.pg.id
  name        = "pg_user"
  password    = var.password
}
```

**hcs_rds_pg_database**

```hcl
resource "hcs_rds_pg_database" "pg_db" {
  instance_id = hcs_rds_instance.pg.id
  name        = "pg_app_db"
  owner       = "rdsAdmin"
}
```

**hcs_rds_pg_database_privilege**

```hcl
resource "hcs_rds_pg_database_privilege" "pg_priv" {
  instance_id = hcs_rds_instance.pg.id
  db_name     = hcs_rds_pg_database.pg_db.name

  users {
    name        = hcs_rds_pg_account.pg_acct.name
    schema_name = "public"
    readonly    = false
  }
}
```

**hcs_rds_pg_plugin**

```hcl
resource "hcs_rds_pg_plugin" "pgaudit" {
  instance_id   = hcs_rds_instance.pg.id
  database_name = hcs_rds_pg_database.pg_db.name
  name          = "pgaudit"
}
```

---

### 9. hcs_rds_sql_audit (Resource)

**Description:** Enables SQL audit (MySQL & PostgreSQL).

```hcl
resource "hcs_rds_sql_audit" "audit" {
  instance_id = hcs_rds_instance.mysql.id
  keep_days   = 30

  audit_types = [
    "CREATE_USER", "DROP_USER", "INSERT", "DELETE", "UPDATE"
  ]
}
```

---

## Data Sources

### hcs_rds_pg_plugins (PostgreSQL only)

```hcl
data "hcs_rds_pg_plugins" "all" {
  instance_id   = var.instance_id
  database_name = var.db_name
}
```

---

## Usage Guidelines for LLM Code Generation

1. **Engine Choice** – MySQL vs PostgreSQL changes flavor suffix, replication mode, and available sub-resources.
2. **HA Setup** – Use two AZs + `.ha` flavor + `ha_replication_mode`.
3. **MySQL Workflow** – Instance → Database → Account → Privilege.
4. **PostgreSQL Workflow** – Instance → Database → Account → Privilege → Plugin.
5. **Parameters** – Use `parameters` block for runtime tuning (some require restart).
6. **Backup** – Always define `backup_strategy` for production.
7. **Import** – Ignore `db`, `password`, `availability_zone` after import.
8. **SQL Audit** – Only for MySQL/PostgreSQL; set `keep_days` and `audit_types`.
9. **Versioning** – PostgreSQL resources require HCS 8.5.0+.

You now have the complete, clean RDS context.

Would you like a full production-ready module that includes:

- MySQL primary/standby with encryption
- PostgreSQL with plugins + audit
- Database + account + privilege setup
- Parameter tuning
- Backup strategy
- Tags + enterprise project

Just say the word and I’ll generate it right away!

```

```
