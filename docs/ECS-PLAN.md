````markdown
# Huawei Cloud Stack (HCS) ECS Terraform Context

**Purpose**  
This file is the complete authoritative reference for any LLM (including yourself) when designing or generating Terraform configurations for Elastic Cloud Server (ECS) resources in Huawei Cloud Stack.

Use this document to ensure all generated code follows the official schemas, disk encryption rules, attachment behaviors, cloning limitations, snapshot/rollback constraints, and best practices.

---

## Supported Resources

### 1. hcs_ecs_compute_instance (Resource)

**Description:** Manages an ECS virtual machine instance.

**Recommended Data Sources (used in all examples)**

```hcl
data "hcs_availability_zones" "az" {}
data "hcs_ecs_compute_flavors" "flavor" { ... }
data "hcs_ims_images" "image" { ... }
data "hcs_vpc_subnets" "subnet" { ... }
data "hcs_networking_secgroups" "sg" { ... }
```
````

**Example Usage**

**Basic Instance**

```hcl
resource "hcs_ecs_compute_instance" "basic" {
  name               = "tf-ecs-basic"
  image_id           = data.hcs_ims_images.image.images[0].id
  flavor_id          = data.hcs_ecs_compute_flavors.flavor.ids[0]
  security_group_ids = [data.hcs_networking_secgroups.sg.security_groups[0].id]
  availability_zone  = data.hcs_availability_zones.az.names[0]

  network {
    uuid              = data.hcs_vpc_subnets.subnet.subnets[0].id
    source_dest_check = false
  }

  system_disk_type = "business_type_01"
  system_disk_size = 40

  data_disks {
    type = "business_type_01"
    size = 100
  }

  delete_disks_on_termination = true
  delete_eip_on_termination   = true
}
```

**With EIP**

```hcl
resource "hcs_vpc_eip" "eip" { ... }

resource "hcs_ecs_compute_eip_associate" "assoc" {
  public_ip   = hcs_vpc_eip.eip.address
  instance_id = hcs_ecs_compute_instance.basic.id
}
```

**With Attached Volume (recommended for multiple disks)**

```hcl
resource "hcs_evs_volume" "data" { ... }

resource "hcs_ecs_compute_volume_attach" "attach" {
  instance_id = hcs_ecs_compute_instance.basic.id
  volume_id   = hcs_evs_volume.data.id
  device      = "/dev/vdb"
}
```

**Multiple Data Disks (order not guaranteed)**

```hcl
data_disks {
  type = "business_type_01"
  size = 100
}
data_disks {
  type = "business_type_01"
  size = 200
}
```

**Multiple Networks**

```hcl
network { uuid = "net1" }
network { uuid = "net2" }
```

**User Data (cloud-init)**

```hcl
user_data = base64encode(file("cloud-init.yaml"))
```

**Encrypted Volumes**

```hcl
system_disk_type = "business_type_01"
kms_key_id       = "ce488d6a-..."
encrypt_cipher   = "AES256-XTS"

data_disks {
  kms_key_id     = "ce488d6a-..."
  encrypt_cipher = "AES256-XTS"
  type           = "business_type_01"
  size           = 100
}
```

**Power Action**

```hcl
power_action = "OFF"   # ON, OFF, REBOOT, FORCE-OFF, FORCE-REBOOT
```

**Tags**

```hcl
tags = {
  env  = "prod"
  team = "backend"
}
```

**Argument Reference (key fields)**

- `name` – (Required) 1-64 chars.
- `image_id` or `image_name` – (Required, ForceNew).
- `flavor_id` – (Required).
- `availability_zone` – (Optional, ForceNew).
- `security_group_ids` – (Optional).
- `network` – (Required, ForceNew) – supports `uuid`, `fixed_ip_v4`, `ipv6_enable`, `source_dest_check`.
- `system_disk_type/size` – (Optional, ForceNew).
- `data_disks` – (Optional, ForceNew) – `type`, `size`, `snapshot_id`, `kms_key_id`, `encrypt_cipher`.
- `user_data` – (Optional, ForceNew).
- `key_pair` / `admin_pass` – (Optional).
- `eip_type` / `bandwidth` / `eip_id` – for auto EIP.
- `delete_disks_on_termination`, `delete_eip_on_termination`.
- `power_action`, `tags`, `enterprise_project_id`, `scheduler_hints`.

**Attributes Reference**

- `id`, `status`, `public_ip`, `access_ip_v4/v6`, `system_disk_id`, `network[]`, `volume_attached[]`.

**Import**

```bash
terraform import hcs_ecs_compute_instance.example <instance_id>
```

**Recommended lifecycle**

```hcl
lifecycle {
  ignore_changes = [user_data, data_disks]
}
```

**Timeouts**

- `create` – 30m
- `update` – 30m
- `delete` – 30m

---

### 2. hcs_ecs_compute_snapshot (Resource)

**Description:** Creates a snapshot of an ECS instance.

```hcl
resource "hcs_ecs_compute_snapshot" "snap" {
  instance_id = hcs_ecs_compute_instance.basic.id
  name        = "daily-snap"
}
```

**Import:** `<instance_id>/<snapshot_id>`

**Timeouts:** `create` – 14h

---

### 3. hcs_ecs_compute_eip_associate (Resource)

**Description:** Associates IPv4 EIP or IPv6 to Shared Bandwidth on an ECS.

**Examples:** auto-detect network, explicit fixed_ip, IPv6 + shared bandwidth.

**Argument Reference**

- `instance_id` – (Required, ForceNew)
- `public_ip` – (Optional) for IPv4 EIP
- `bandwidth_id` – (Optional) for IPv6 shared bandwidth
- `fixed_ip` – (Optional) IPv4 or IPv6 address

**Import:** `<eip_or_bandwidth>/<instance_id>/<fixed_ip>`

---

### 4. hcs_ecs_compute_instance_clone (Resource)

**Description:** Clones an existing ECS instance.

**NOTE:** Clone resources can only be created — they cannot be updated or deleted locally.

**Examples:** basic clone, modify network(s), change password, change keypair.

**Argument Reference**

- `instance_id` – (Required, ForceNew)
- `name` – (Required, ForceNew)
- `power_on` – (Required)
- `retain_passwd`, `admin_pass`, `key_pair`
- `vpc_id`, `network[]` blocks for custom networking

---

### 5. hcs_ecs_compute_interface_attach (Resource)

**Description:** Attaches additional network interface (port) to an ECS.

**Examples:** auto port, custom fixed_ip, custom port_id.

**Argument Reference**

- `instance_id` – (Required, ForceNew)
- `network_id` or `port_id` (mutually exclusive)
- `fixed_ip`, `source_dest_check`

**Import:** `<instance_id>/<port_id>`

**Timeouts:** create/delete 10m

---

### 6. hcs_ecs_compute_keypair (Resource)

**Description:** Manages SSH keypair.

**Examples:** create new (with private key export), import existing public key.

```hcl
resource "hcs_ecs_compute_keypair" "kp" {
  name     = "my-key"
  key_file = "private_key.pem"   # optional
}
```

**Import:** by name

---

### 7. hcs_ecs_compute_snapshot_rollback (Resource)

**Description:** Rolls back an ECS to a snapshot.

**NOTE:** Only rollback supported — no local update/delete.

```hcl
resource "hcs_ecs_compute_snapshot_rollback" "rb" {
  instance_id = "..."
  snapshot_id = "..."
}
```

**Timeouts:** create 30m

---

### 8. hcs_ecs_compute_server_group (Resource)

**Description:** Manages anti-affinity / affinity server group.

```hcl
resource "hcs_ecs_compute_server_group" "sg" {
  name     = "anti-affinity-group"
  policies = ["anti-affinity"]
  members  = [hcs_ecs_compute_instance.basic.id]
}
```

**Import:** by id

---

### 9. hcs_ecs_compute_volume_attach (Resource)

**Description:** Attaches EVS volume to ECS.

```hcl
resource "hcs_ecs_compute_volume_attach" "attach" {
  instance_id = hcs_ecs_compute_instance.basic.id
  volume_id   = hcs_evs_volume.data.id
  device      = "/dev/vdb"
}
```

**Import:** `<instance_id>/<volume_id>`

**Timeouts:** create/delete 10m

---

## Data Sources

### hcs_ecs_compute_flavors

```hcl
data "hcs_ecs_compute_flavors" "flavors" {
  availability_zone = "az1.dc1"
  cpu_core_count    = 2
  memory_size       = 4
}
```

### hcs_ecs_compute_instance / hcs_ecs_compute_instances

Single or list lookup by name, id, ip, flavor, etc.

### hcs_ecs_compute_servergroups

List server groups by name.

---

## Usage Guidelines for LLM Code Generation

1. Always use data sources for AZ, flavor, image, subnet, secgroup.
2. Prefer separate `hcs_ecs_compute_volume_attach` for multiple data disks (order control).
3. For encryption: set `kms_key_id` + `encrypt_cipher = "AES256-XTS"` on system + data disks.
4. Use `delete_disks_on_termination = true` and `delete_eip_on_termination = true` in production.
5. For cloning: only create – never update/delete the clone resource.
6. For keypair: use `key_file` to export private key automatically.
7. After import of instance: ignore `user_data`, `data_disks`.
8. Use `power_action` for start/stop/reboot inside Terraform.
9. Server groups: `anti-affinity` is most common for HA.

You now have the complete, clean ECS context.

Would you like a full production-ready module (`main.tf` + `variables.tf` + `outputs.tf`) that includes:

- ECS with encrypted disks
- Multiple networks
- EIP association
- Extra volume attachment
- Keypair
- Snapshot + rollback example
- Server group

Just say the word and I’ll generate it!

```

```
