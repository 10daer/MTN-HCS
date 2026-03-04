````markdown
# Huawei Cloud Stack (HCS) EIP & Bandwidth Terraform Context

**Purpose**  
This file is the complete authoritative reference for any LLM (including yourself) when designing or generating Terraform configurations for Elastic IP (EIP), Dedicated Bandwidth, and Shared Bandwidth resources in Huawei Cloud Stack.

Use this document to ensure all generated code follows the official schemas, bandwidth rules, association behaviors, and best practices.

---

## Supported Resources

### 1. hcs_vpc_bandwidth (Resource)

**Description:** Manages a Shared Bandwidth resource within Huawei Cloud Stack.

**Example Usage**

```hcl
resource "hcs_vpc_bandwidth" "shared" {
  name = "bandwidth-prod"
  size = 100
}
```
````

**Argument Reference**

- `name` – (Required, String) 1-64 characters (letters, digits, `_`, `-`, `.`).
- `size` – (Required, Int) 5–2000 Mbit/s.
- `enterprise_project_id` – (Optional, String, ForceNew).
- `region` – (Optional, String, ForceNew).

**Attributes Reference**

- `id`
- `share_type`
- `bandwidth_type`
- `status`
- `publicips[]` (list of attached EIPs with `id`, `type`, `ip_address`).

**Timeouts**

- `create` – 10m
- `update` – 10m
- `delete` – 10m

**Import**

```bash
terraform import hcs_vpc_bandwidth.example 7117d38e-4c8f-4624-a505-bd96b97d024c
```

---

### 2. hcs_vpc_bandwidth_associate (Resource)

**Description:** Associates an EIP to a Shared Bandwidth.

**Important Note**

- Yearly/monthly EIPs cannot be added to a shared bandwidth.
- When an EIP is removed from a shared bandwidth, a dedicated bandwidth (5 Mbit/s by default, billed by bandwidth) is automatically allocated. You can resize it afterward.

**Example Usage**

**Single EIP**

```hcl
resource "hcs_vpc_bandwidth_associate" "example" {
  bandwidth_id = hcs_vpc_bandwidth.shared.id
  eip_id       = hcs_vpc_eip.my_eip.id
}
```

**Multiple EIPs (count)**

```hcl
variable "eip_ids" {
  type = list(string)
}

resource "hcs_vpc_bandwidth_associate" "multiple" {
  count = length(var.eip_ids)

  bandwidth_id = hcs_vpc_bandwidth.shared.id
  eip_id       = var.eip_ids[count.index]
}
```

**Associating Terraform-managed dedicated EIP**

```hcl
resource "hcs_vpc_eip" "dedicated" {
  publicip {
    type = "eip"
  }
  bandwidth {
    share_type = "PER"
    name       = "dedicated"
    size       = 10
  }
  lifecycle {
    ignore_changes = [bandwidth]
  }
}

resource "hcs_vpc_bandwidth_associate" "attach" {
  bandwidth_id = hcs_vpc_bandwidth.shared.id
  eip_id       = hcs_vpc_eip.dedicated.id
}
```

**Argument Reference**

- `bandwidth_id` – (Required, String, ForceNew) Shared bandwidth ID.
- `eip_id` – (Required, String) EIP ID.
- `bandwidth_size` – (Optional, Int) Dedicated bandwidth size after removal from shared (default 5).
- `region` – (Optional, String, ForceNew).

**Attributes Reference**

- `id` – `<bandwidth_id>/<eip_id>`
- `public_ip`
- `bandwidth_name`

**Import**

```bash
terraform import hcs_vpc_bandwidth_associate.example <bandwidth_id>/<eip_id>
```

---

### 3. hcs_vpc_eip (Resource)

**Description:** Manages an Elastic IP (EIP) resource.

**Example Usage**

**Dedicated Bandwidth (PER)**

```hcl
resource "hcs_vpc_eip" "dedicated" {
  publicip {
    type = "eip"
  }

  bandwidth {
    share_type = "PER"
    name       = "my-dedicated-bandwidth"
    size       = 10
  }
}
```

**Shared Bandwidth (WHOLE)**

```hcl
resource "hcs_vpc_bandwidth" "shared" {
  name = "shared-bandwidth"
  size = 100
}

resource "hcs_vpc_eip" "shared" {
  publicip {
    type = "eip"
  }

  bandwidth {
    share_type = "WHOLE"
    id         = hcs_vpc_bandwidth.shared.id
  }
}
```

**Argument Reference**

- `publicip` – (Required, List) Block:
  - `type` – (Optional, String, ForceNew) Usually `"eip"`.
  - `ip_address` – (Optional, String, ForceNew) Specific IPv4 to assign.
- `bandwidth` – (Required, List) Block:
  - `share_type` – (Required, String, ForceNew) `PER` or `WHOLE`.
  - `name` – (Optional) Required when `PER`.
  - `size` – (Optional) 1–300, required when `PER`.
  - `id` – (Optional, String, ForceNew) Required when `WHOLE`.
- `name` – (Optional, String) 1-64 chars.
- `enterprise_project_id` – (Optional, String, ForceNew).

**Attributes Reference**

- `id`
- `address` (IPv4)
- `private_ip`
- `port_id`
- `status`

**Timeouts**

- `create` – 10m
- `update` – 5m
- `delete` – 5m

**Import**

```bash
terraform import hcs_vpc_eip.example 2c7f39f3-702b-48d1-940c-b50384177ee1
```

---

### 4. hcs_vpc_eip_associate (Resource)

**Description:** Associates an EIP to a private IP address or port (NAT, ELB, ECS, VIP, etc.).

**Example Usage**

**Associate to fixed private IP**

```hcl
resource "hcs_vpc_eip_associate" "fixed_ip" {
  public_ip  = hcs_vpc_eip.my_eip.address
  network_id = var.network_id
  fixed_ip   = "192.168.10.50"
}
```

**Associate to existing port (recommended)**

```hcl
resource "hcs_vpc_eip_associate" "port" {
  public_ip = hcs_vpc_eip.my_eip.address
  port_id   = hcs_networking_vip.my_vip.id
}
```

**Argument Reference**

- `public_ip` – (Required, String, ForceNew) EIP address.
- `fixed_ip` – (Optional, String, ForceNew) Private IP to bind.
- `network_id` – (Optional, String, ForceNew) Required when `fixed_ip` is used.
- `port_id` – (Optional, String, ForceNew) Alternative to `fixed_ip` + `network_id`.
- `region` – (Optional, String, ForceNew).

**Attributes Reference**

- `id`
- `mac_address`
- `status` (should be `BOUND`)

**Timeouts**

- `create` – 5m
- `delete` – 5m

**Import**

```bash
terraform import hcs_vpc_eip_associate.example <eip_id>
```

---

## Usage Guidelines for LLM Code Generation

1. **Bandwidth Strategy**
   - Use `PER` for dedicated bandwidth on a single EIP.
   - Use `WHOLE` + `hcs_vpc_bandwidth` for multiple EIPs sharing bandwidth.

2. **Association Order**
   - Always create EIP first, then associate (or use `hcs_vpc_bandwidth_associate` for shared).
   - For Terraform-managed dedicated EIPs, add `lifecycle { ignore_changes = [bandwidth] }`.

3. **Best Practice for Binding**
   - Prefer `port_id` over `fixed_ip` + `network_id` when possible (more reliable).
   - Use `hcs_networking_vip` for ELB/VIP scenarios.

4. **Import Recommendations**

   ```hcl
   lifecycle {
     ignore_changes = [bandwidth]   # for hcs_vpc_eip
   }
   ```

5. **Common Patterns**
   - One shared bandwidth + multiple `hcs_vpc_bandwidth_associate` resources (use `count` or `for_each`).
   - Dedicated EIP + direct `bandwidth { share_type = "PER" }` block inside `hcs_vpc_eip`.

You now have the complete, clean EIP & Bandwidth context.

Would you like me to create a ready-to-use example module (`main.tf` + `variables.tf` + `outputs.tf`) that demonstrates all four resources together (dedicated + shared scenarios, multiple EIPs, associations, and imports)? Just say the word!

```

```
