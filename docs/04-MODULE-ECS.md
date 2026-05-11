# Module Deployment: ECS (Elastic Cloud Server)
## `modules/ecs` — Web Tier (`module.web`) + App Tier (`module.app`)

> **Prerequisites**: [00-SETUP.md](00-SETUP.md) complete, [01-MODULE-NETWORK.md](01-MODULE-NETWORK.md) applied, [02-MODULE-SECURITY.md](02-MODULE-SECURITY.md) applied.
> **Deploy order**: **4th** — ECS depends on VPC subnets and security groups being present.
> **Estimated apply time**: ~5–10 minutes (per tier, depending on image size)

---

## What This Module Creates

The root module instantiates the ECS module **twice** — once for the web tier (public subnets) and once for the app tier (private subnets):

| Module call | Subnet type | Security group | Instance naming |
|---|---|---|---|
| `module.web` | Public subnets (round-robin) | `web-sg` + `default-sg` | `myapp-dev-web-01`, `web-02` |
| `module.app` | Private subnets (round-robin) | `app-sg` + `default-sg` | `myapp-dev-app-01`, `app-02` |

### Resources per tier

| Resource | HCS Type | Description |
|---|---|---|
| Instances | `hcs_ecs_compute_instance` | VMs with system disk, optional data disk, cloud-init |
| Keypairs | `hcs_ecs_compute_keypair` | SSH keypairs (optional — can reference pre-existing) |
| Server groups | `hcs_ecs_compute_server_group` | Anti-affinity groups to spread instances across hosts |
| EIP associations | `hcs_ecs_compute_eip_associate` | If `assign_eip = true` on an instance |
| Volume attachments | `hcs_ecs_compute_volume_attach` | EVS volumes managed outside the module |
| Snapshots | `hcs_ecs_compute_snapshot` | Instance snapshots |

---

## Step 1 — Pre-check: SSH Key Pair Must Exist in HCS

The `key_pair_name` value must reference a key pair that **already exists** in HCS. Terraform will not create it unless you use the `keypairs` input variable.

**Check existing key pairs**:
1. HCS Console → ECS → Key Pairs
2. Confirm the name you plan to use is listed

**Or let Terraform create and export a new key pair** (optional):

```hcl
# Add to terraform.tfvars — Terraform creates the key and saves the .pem locally
ecs_web_keypairs = {
  web_key = {
    name     = "myapp-dev-web-key"
    key_file = "myapp-dev-web-key.pem"    # saved to environments/dev/
  }
}
```

> **Important**: If Terraform creates the key, the `.pem` file is written to `environments/dev/`. This file is gitignored. Back it up immediately.

---

## Step 2 — Check Available Images and Flavors

### Find image name

```bash
# After network is deployed, run in the Terraform console:
cd environments/dev
terraform console -var-file="terraform.tfvars"
> data.hcs_ims_images.this.images[*].name
```

Or check in HCS Console → ECS → Create ECS → Image tab.

Common names:
- `Ubuntu 20.04 server 64bit`
- `Ubuntu 22.04 server 64bit`
- `CentOS 7.9 64bit`

### Find available flavors

HCS Console → ECS → Create ECS → Instance Type dropdown.

Common flavors:

| Flavor | vCPU | RAM | Use case |
|---|---|---|---|
| `c6.large.2` | 2 | 4 GB | Web tier dev |
| `c6.xlarge.2` | 4 | 8 GB | App tier dev |
| `c6.xlarge.4` | 4 | 16 GB | App tier prod |
| `c6.2xlarge.4` | 8 | 32 GB | Heavy compute |
| `s3.large.4` | 2 | 8 GB | General purpose |

---

## Step 3 — Add ECS Values to `terraform.tfvars`

```hcl
# ── ECS — Common ─────────────────────────────────────────────────────────────
key_pair_name = "my-keypair"                    # must exist in HCS
image_name    = "Ubuntu 20.04 server 64bit"    # must match exact image name in HCS

# ── ECS — Web Tier (public subnets) ──────────────────────────────────────────
web_instance_count   = 2                        # number of web servers to create
web_flavor_id        = "c6.large.2"            # 2 vCPU / 4 GB
web_system_disk_type = "business_type_01"      # check HCS for available disk types
web_system_disk_size = 50                       # GB

# ── ECS — App Tier (private subnets) ─────────────────────────────────────────
app_instance_count   = 2                        # number of app servers to create
app_flavor_id        = "c6.xlarge.2"           # 4 vCPU / 8 GB
app_system_disk_type = "business_type_01"
app_system_disk_size = 50                       # GB
app_data_disk_size   = 100                      # GB — extra data disk per app server
```

### Anti-affinity server groups (optional but recommended for production)

Anti-affinity ensures instances are placed on different physical hosts. If one host fails, not all servers go down:

```hcl
# Web tier anti-affinity group
ecs_web_server_groups = {
  web_anti_affinity = {
    name     = "web-anti-affinity"
    policies = ["anti-affinity"]
  }
}

# App tier anti-affinity group
ecs_app_server_groups = {
  app_anti_affinity = {
    name     = "app-anti-affinity"
    policies = ["anti-affinity"]
  }
}
```

> **Note**: For dev environments with small HCS clusters, anti-affinity may fail if there are fewer physical hosts than instances. Set to `{}` for dev if you encounter placement errors.

### Advanced: User data (cloud-init)

To run a startup script on every instance, add `user_data` — but this requires modifying `environments/dev/main.tf` since the instance definitions are inline:

```hcl
# In environments/dev/main.tf, inside the web module instances map:
instances = {
  for i in range(var.web_instance_count) :
  format("web-%02d", i + 1) => {
    flavor_id        = var.web_flavor_id
    subnet_id        = module.network.public_subnet_id_list[i % length(module.network.public_subnet_id_list)]
    system_disk_type = var.web_system_disk_type
    system_disk_size = var.web_system_disk_size
    user_data        = base64encode(file("${path.module}/user-data/web-init.sh"))
  }
}
```

> The `user_data` field accepts plain text or base64. Changes to `user_data` are **ignored after first apply** (see `lifecycle { ignore_changes = [user_data] }` in the ECS module) — this is intentional to prevent instance recreation on config drift.

---

## Step 4 — Plan the ECS Modules

Plan web and app tiers together (they share the same dependencies):

```bash
source ~/.hcs-credentials.sh

cd environments/dev
terraform plan \
  -var-file="terraform.tfvars" \
  -target=module.web \
  -target=module.app \
  -out=ecs.tfplan
```

### What to verify in the plan output

**Web tier:**
```
# module.web.hcs_ecs_compute_instance.instances["web-01"] will be created
  + name              = "myapp-dev-web-web-01"
  + flavor_id         = "c6.large.2"
  + availability_zone = "az1.dc0"
  + security_group_ids = [
      "<web-sg-id>",
      "<default-sg-id>",
    ]
  + network {
      + uuid = "<public-subnet-id>"    ← public subnet
    }
  + system_disk_type = "business_type_01"
  + system_disk_size = 50

# module.web.hcs_ecs_compute_instance.instances["web-02"] will be created
  + name = "myapp-dev-web-web-02"
  + network {
      + uuid = "<public-subnet-id-2>"  ← different subnet (round-robin)
    }
```

**App tier:**
```
# module.app.hcs_ecs_compute_instance.instances["app-01"] will be created
  + name     = "myapp-dev-app-app-01"
  + flavor_id = "c6.xlarge.2"
  + network {
      + uuid = "<private-subnet-id>"   ← private subnet
    }
  + data_disk {
      + type = "business_type_01"
      + size = 100
    }
```

Confirm:
- ✅ Web instances are on **public** subnets
- ✅ App instances are on **private** subnets
- ✅ Web instances use the `web-sg`, app instances use the `app-sg`
- ✅ App instances have a data disk
- ✅ All instances use the correct flavor IDs
- ✅ AZ matches your `availability_zones` setting

---

## Step 5 — Apply

```bash
terraform apply ecs.tfplan
```

Expected output:
```
module.web.hcs_ecs_compute_instance.instances["web-01"]: Creating...
module.web.hcs_ecs_compute_instance.instances["web-02"]: Creating...
module.app.hcs_ecs_compute_instance.instances["app-01"]: Creating...
module.app.hcs_ecs_compute_instance.instances["app-02"]: Creating...
...
module.web.hcs_ecs_compute_instance.instances["web-01"]: Creation complete after 3m20s
...

Apply complete! Resources: 8 added, 0 changed, 0 destroyed.
```

---

## Step 6 — Verify

### View instance details

```bash
cd environments/dev

# List all managed instances
terraform state list | grep hcs_ecs_compute_instance

# Get web-01 details
terraform state show 'module.web.hcs_ecs_compute_instance.instances["web-01"]'
# Shows: id, name, access_ip_v4, status, flavor_id, availability_zone, etc.
```

### View module outputs

The ECS module exposes these per tier (prefixed with `web_` or `app_` in root outputs):

| Output | Description |
|---|---|
| `instance_ids` | Map of `{ "web-01" = "<id>", ... }` |
| `instance_names` | Map of instance names |
| `instance_ips` | Map of private IPs |
| `instance_statuses` | Map of current power states |

### Verify in HCS Console

1. Go to **ECS** → **Instances**
2. You should see all instances listed:
   - `myapp-dev-web-web-01`, `myapp-dev-web-web-02` → status **Running**
   - `myapp-dev-app-app-01`, `myapp-dev-app-app-02` → status **Running**
3. Click an instance → **Security Groups** tab → confirm correct SG is attached
4. Check **Disks** tab on app instances → system disk + data disk should both be listed

### Test SSH access (if bastion is deployed)

```bash
# Get web-01 private IP
terraform state show 'module.web.hcs_ecs_compute_instance.instances["web-01"]' \
  | grep access_ip_v4

# SSH via bastion
ssh -i my-keypair.pem ubuntu@<bastion-public-ip>
# From bastion:
ssh -i my-keypair.pem ubuntu@<web-01-private-ip>
```

---

## Scaling Instances

### Scale up

Change `web_instance_count` or `app_instance_count` in `terraform.tfvars` and re-apply:

```hcl
web_instance_count = 4   # was 2
```

```bash
terraform plan -var-file="terraform.tfvars" -target=module.web -out=ecs.tfplan
terraform apply ecs.tfplan
```

Terraform will **add** two new instances (`web-03`, `web-04`) without touching the existing ones.

### Scale down

> ⚠️ **Warning**: Reducing `web_instance_count` from 4 to 2 will **destroy** `web-03` and `web-04`. Always run plan first and review what will be destroyed.

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `image not found` | `image_name` doesn't match exactly | Check exact name in HCS Console → IMS |
| `flavor not found` | `flavor_id` not available in your region/AZ | Pick from available flavors in HCS Console → ECS |
| `key pair not found` | `key_pair_name` doesn't exist in HCS | Create it in HCS Console → ECS → Key Pairs, or use `ecs_web_keypairs` to create via Terraform |
| `disk type not available` | `system_disk_type` unsupported | Check available types: `SATA`, `SSD`, `SAS`, `business_type_01` |
| `anti-affinity group placement failed` | Not enough physical hosts | Remove anti-affinity for dev, or reduce instance count |
| `quota exceeded` | ECS quota reached | Request quota increase from HCS admin |
| Instance stays in `BUILD` state | HCS issue / resource shortage | Check HCS Console for error details on the instance |
