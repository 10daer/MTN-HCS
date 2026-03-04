````markdown
# Huawei Cloud Stack (HCS) GaussDB OpenGauss Terraform Context

**Purpose**  
This file is the complete authoritative reference for any LLM (including yourself) when designing or generating Terraform code for GaussDB OpenGauss on Huawei Cloud Stack.  
Use this document to ensure generated configurations strictly follow the official schemas, constraints, supported deployment modes, HA options, volume rules, KMS encryption, parameter templates, and all documented notes.

---

## Supported Resources

### 1. hcs_gaussdb_opengauss_instance (Resource)

**Description:** Manages a GaussDB OpenGauss instance within Huawei Cloud Stack.

**NOTES**

- If the endpoint is manually configured, both `opengauss` and `opengaussv31` must be configured in the provider.
- After creation, internal initialization occurs — wait several minutes before performing other operations.
- While a backup is in progress, you cannot: create backup, stop/restart instance, node stop/start, HashBucket migration, cluster expansion, restore, spec change, CN shrink/expand, node replacement, or modify port.

**Example Usage**

**Distributed HA mode**

```hcl
variable "vpc_id" {}
variable "subnet_network_id" {}
variable "security_group_id" {}
variable "instance_name" {}
variable "instance_password" {}

data "hcs_availability_zones" "test" {}

resource "hcs_gaussdb_opengauss_instance" "distributed" {
  vpc_id            = var.vpc_id
  subnet_id         = var.subnet_network_id
  security_group_id = var.security_group_id

  flavor            = "gaussdb.opengauss.ee.dn.m6.2xlarge.8.in"
  name              = var.instance_name
  password          = var.instance_password
  sharding_num      = 1
  coordinator_num   = 2
  availability_zone = join(",", slice(data.hcs_availability_zones.test.names, 0, 3))

  ha {
    mode             = "centralization_standard"
    replication_mode = "sync"
    consistency      = "strong"
  }

  volume {
    type = "ULTRAHIGH"
    size = 40
  }
}
```
````

**Centralized HA mode**

```hcl
resource "hcs_gaussdb_opengauss_instance" "centralized" {
  vpc_id            = var.vpc_id
  subnet_id         = var.subnet_network_id
  security_group_id = var.security_group_id
  name              = var.instance_name
  password          = var.instance_password
  flavor            = "gaussdb.opengauss.ee.m6.2xlarge.x868.ha"
  availability_zone = join(",", slice(data.hcs_availability_zones.test.names, 0, 3))

  replica_num = 3

  ha {
    mode             = "centralization_standard"
    replication_mode = "sync"
    consistency      = "strong"
  }

  volume {
    type = "ULTRAHIGH"
    size = 40
  }
}
```

**With KMS Transparent Data Encryption**

```hcl
resource "hcs_gaussdb_opengauss_instance" "with_kms" {
  vpc_id            = var.vpc_id
  subnet_id         = var.subnet_network_id
  security_group_id = var.security_group_id
  name              = "terraform-test"
  password          = var.instance_password
  flavor            = "gaussdb.opengauss.ee.m6.2xlarge.x868.ha"
  availability_zone = join(",", slice(data.hcs_availability_zones.test.names, 0, 3))

  sharding_num    = 1
  coordinator_num = 2

  kms_tde_key_id   = "12345678-1234-1234-1234-12345678abcd"
  kms_project_name = var.project_name

  ha {
    mode             = "centralization_standard"
    replication_mode = "sync"
    consistency      = "strong"
  }

  volume {
    type = "ULTRAHIGH"
    size = 480
  }
}
```

**Distributed instance (solution = hcs2)**

```hcl
resource "hcs_gaussdb_opengauss_instance" "distributed_hcs2" {
  vpc_id            = var.vpc_id
  subnet_id         = var.subnet_network_id
  security_group_id = var.security_group_id
  flavor            = var.flavor_id
  name              = var.instance_name
  password          = var.instance_password
  availability_zone = join(",", slice(data.hcs_availability_zones.test.names, 0, 3))

  solution     = "hcs2"
  sharding_num = 0

  ha {
    mode             = "combined"
    replication_mode = "sync"
    consistency      = "strong"
  }

  volume {
    type = "ULTRAHIGH"
    size = 480
  }

  datastore {
    engine  = "GaussDB(for openGauss)"
    version = "8.202"
  }
}
```

**Argument Reference (key fields)**

- `name` – (Required, String) 4-64 chars, starts with letter, letters/digits/-/\_ only.
- `flavor` – (Required, String, ForceNew) Instance specification (see API docs for valid values).
- `password` – (Required, String) 8-32 chars with uppercase, lowercase, digit + special (~!@#%^\*-\_=+?).
- `availability_zone` – (Required, String, ForceNew) Comma-separated AZs (rules depend on `solution` and `ha.mode`).
- `vpc_id`, `subnet_id` – (Required, String, ForceNew).
- `security_group_id` – (Optional, String, ForceNew).
- `port` – (Optional, String, ForceNew) Default 8000. Restricted port ranges only.
- `ha` – (Required, List, ForceNew) Block (see below).
- `volume` – (Required, List) Block (see below).
- `sharding_num` – (Optional, Int) 1-9 (default 3).
- `coordinator_num` – (Optional, Int) 1-9 (default 3, ≤ 2×sharding_num).
- `replica_num` – (Optional, Int, ForceNew) 2 or 3 (default 3).
- `solution` – (Optional, String, ForceNew) Deployment mode (hcs1–hcs7, triset, quadruset, double, single, logger, etc.).
- `kms_tde_key_id` + `kms_project_name` – (Optional) For transparent encryption.
- `datastore` – (Optional, List, ForceNew).
- `backup_strategy` – (Optional, List).
- `enterprise_project_id`, `time_zone`, `os_type`, `configuration_id`, etc. (see full list in original docs).

**Nested blocks**

**ha block**

- `mode` – (Required) `centralization_standard` or `combined`.
- `replication_mode` – (Required) `sync`.
- `consistency` – (Optional) `strong` or `eventual`.
- `consistency_protocol` – (Optional) `quorum`, `paxos`, `syncStorage`.

**volume block**

- `type` – (Required) `ULTRAHIGH`, `LOCALSSD`, `DORADO`.
- `size` – (Required, Int) GB (rules depend on deployment & shards).

**datastore block**

- `engine` – (Required) `GaussDB(for openGauss)`.
- `version` – (Optional) e.g. `8.202`.

**Attributes Reference**

- `id`, `status`, `type`, `private_ips`, `public_ips`, `endpoints`, `db_user_name`, `nodes[]`, `ha`, `volume`, `datastore`, `backup_strategy`, etc.

**Timeouts**

- `create` – 120m (default)
- `update` – 90m
- `delete` – 45m

**Import**

```bash
terraform import hcs_gaussdb_opengauss_instance.test 1f2c4f48adea4ae684c8edd8818fa349in14
```

**Recommended lifecycle block after import**

```hcl
lifecycle {
  ignore_changes = [
    password,
    availability_zone,
  ]
}
```

---

### 2. hcs_gaussdb_opengauss_parameter_template (Resource)

**Description:** Manages a GaussDB OpenGauss parameter template.

**Example Usage**

**Create new template**

```hcl
resource "hcs_gaussdb_opengauss_parameter_template" "test" {
  name           = "test_gaussdb"
  engine_version = "8.202"
  instance_mode  = "combined_hcs6"

  parameters {
    name  = "audit_system_object"
    value = "100"
  }

  parameters {
    name  = "autoanalyze"
    value = "on"
  }
}
```

**Copy from existing**

```hcl
resource "hcs_gaussdb_opengauss_parameter_template" "copy" {
  name                    = "test_copy"
  source_configuration_id = var.source_configuration_id
}
```

**Argument Reference**

- `name` – (Required, String, ForceNew) Unique, 1-64 chars (letters, digits, -\_.).
- `description` – (Optional, String, ForceNew) Max 256 chars (no >!<"&'= or CR).
- `engine_version` – (Optional, String, ForceNew) Required when `instance_mode` is set.
- `instance_mode` – (Optional, String, ForceNew) `ha`, `combined`, `combined_hcs2` … `combined_hcs7`.
- `parameters` – (Optional, List, ForceNew) List of name/value pairs.
- `source_configuration_id` – (Optional, String, ForceNew) Mutually exclusive with the above three.

**Exactly one** of `engine_version`/`instance_mode` or `source_configuration_id` must be provided.

**Attributes Reference**

- `id`, `created_at`, `updated_at`, `parameters[]` (with `need_restart`, `readonly`, `value_range`, `data_type`, `description`, etc.).

**Import**

```bash
terraform import hcs_gaussdb_opengauss_parameter_template.test <id>
```

**Recommended lifecycle**

```hcl
lifecycle {
  ignore_changes = [
    source_configuration_id,
    parameters,
  ]
}
```

---

## Data Sources

### 1. hcs_gaussdb_opengauss_instance (Data Source)

**Single instance lookup**

```hcl
data "hcs_gaussdb_opengauss_instance" "this" {
  name = "gaussdb-instance"
}
```

### 2. hcs_gaussdb_opengauss_instances (Data Source)

**List of instances**

```hcl
data "hcs_gaussdb_opengauss_instances" "all" {
  name = "gaussdb-instance"
}
```

**Common filters:** `name`, `vpc_id`, `subnet_id`.

**Exported attributes** include full instance details: `id`, `status`, `flavor`, `private_ips`, `public_ips`, `nodes[]`, `ha`, `volume`, `datastore`, `backup_strategy`, etc.

### 3. hcs_gaussdb_opengauss_parameter_template (Data Source)

```hcl
data "hcs_gaussdb_opengauss_parameter_template" "test" {
  template_id = var.template_id
}
```

**Exported:** `id`, `name`, `description`, `engine_version`, `instance_mode`, `parameters[]` (with risk flags).

---

## Usage Guidelines for LLM Code Generation

1. Always use `data "hcs_availability_zones"` for `availability_zone`.
2. Choose the correct `ha.mode` + `solution` combination before setting AZs, shards, replicas, or volume size.
3. For KMS TDE: both `kms_tde_key_id` and `kms_project_name` are required together.
4. Volume size rules are strict — respect shard multiplier and min/max per deployment type.
5. Use `lifecycle { ignore_changes = [password, availability_zone] }` after import.
6. For parameter templates: never mix `source_configuration_id` with `engine_version`/`instance_mode`/`parameters`.
7. Wait for instance `status = "available"` before attaching parameter templates or performing backups.
8. Prefer explicit `replica_num`, `sharding_num`, `coordinator_num` for clarity.

You now have the full, clean GaussDB OpenGauss context.  
Generate Terraform code that strictly respects every constraint and note above.

---

Would you like me to also create a ready-to-use `variables.tf` + `main.tf` example module for a production GaussDB OpenGauss deployment (centralized + distributed variants + parameter template + KMS) based on this context?

```

```
