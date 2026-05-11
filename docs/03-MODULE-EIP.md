# Module Deployment: EIP (Elastic IPs & Bandwidth)
## `modules/eip`

> **Prerequisites**: [00-SETUP.md](00-SETUP.md) complete, [01-MODULE-NETWORK.md](01-MODULE-NETWORK.md) applied.
> **Deploy order**: **3rd** (after network). Security is not required for EIPs.
> **Estimated apply time**: ~2 minutes

---

## What This Module Creates

The EIP module manages all standalone Elastic IP addresses and bandwidth pools. It is separate from the EIPs created internally by the Network module (for NAT) and the ECS module (for individual instance EIPs).

| Resource | HCS Type | Description |
|---|---|---|
| Shared bandwidth pools | `hcs_vpc_bandwidth` | A pool of bandwidth shared across multiple EIPs |
| Dedicated EIPs | `hcs_vpc_eip` | One EIP with its own bandwidth allocation (`share_type = PER`) |
| Shared EIPs | `hcs_vpc_eip` | EIPs attached to a shared bandwidth pool (`share_type = WHOLE`) |
| Bandwidth associations | `hcs_vpc_bandwidth_associate` | Moves a dedicated EIP into a shared pool |
| EIP associations | `hcs_vpc_eip_associate` | Binds an EIP to a port or fixed private IP |

### Shared vs Dedicated bandwidth explained

| Type | Use when | HCS type |
|---|---|---|
| **Dedicated** (`share_type = PER`) | One EIP needs guaranteed bandwidth (e.g. bastion host) | `hcs_vpc_eip` with `bandwidth.share_type = PER` |
| **Shared** (`share_type = WHOLE`) | Multiple EIPs share a bandwidth cap (e.g. web fleet) | `hcs_vpc_bandwidth` + `hcs_vpc_eip` with `share_type = WHOLE` |

A shared pool of 50 Mbit/s split across 5 web EIPs is much cheaper than 5 × 10 Mbit/s dedicated allocations — and in practice web traffic rarely peaks simultaneously.

---

## Step 1 — Add EIP Values to `terraform.tfvars`

Open `environments/dev/terraform.tfvars` and add the EIP section:

```hcl
# ── EIP — Elastic IPs & Bandwidth ────────────────────────────────────────────

# Shared bandwidth pools
# Key = logical name (used to reference in eip_shared below)
eip_shared_bandwidths = {
  web_pool = {
    name = "web-shared-bw"
    size = 50           # total Mbit/s shared across all attached EIPs
  }
}

# Dedicated EIPs — each has its own bandwidth
eip_dedicated = {
  bastion = {
    name           = "bastion-eip"
    bandwidth_size = 10    # Mbit/s dedicated to this EIP
  }
  vpn = {
    name           = "vpn-eip"
    bandwidth_size = 20
  }
}

# Shared EIPs — attached to a bandwidth pool above
eip_shared = {
  web_01 = {
    bandwidth_key = "web_pool"   # references eip_shared_bandwidths key above
    name          = "web-eip-01"
  }
  web_02 = {
    bandwidth_key = "web_pool"
    name          = "web-eip-02"
  }
}

# Bandwidth associations — move dedicated EIPs into a shared pool (optional)
# Uncomment if you want to move an existing dedicated EIP into a shared pool
# eip_bandwidth_associations = {
#   bastion_to_pool = {
#     bandwidth_key = "web_pool"
#     eip_key       = "bastion"
#   }
# }

# EIP associations — bind EIPs to ports or private IPs (optional)
# Use after ECS instances are deployed to get their port IDs
# eip_associations = {
#   bastion_bind = {
#     eip_key = "bastion"
#     port_id = "<bastion-instance-port-id>"    # from ECS module outputs
#   }
# }
```

### Minimal configuration (just one bastion EIP)

If you only need one EIP for a bastion host and don't need a shared pool:

```hcl
eip_shared_bandwidths      = {}
eip_bandwidth_associations = {}
eip_associations           = {}
eip_shared                 = {}

eip_dedicated = {
  bastion = {
    name           = "bastion-eip"
    bandwidth_size = 10
  }
}
```

---

## Step 2 — Plan the EIP Module

```bash
source ~/.hcs-credentials.sh

cd environments/dev
terraform plan \
  -var-file="terraform.tfvars" \
  -target=module.eip \
  -out=eip.tfplan
```

### What to verify in the plan output

```
# module.eip.hcs_vpc_bandwidth.shared["web_pool"] will be created
  + name       = "myapp-dev-web-shared-bw"
  + size        = 50

# module.eip.hcs_vpc_eip.dedicated["bastion"] will be created
  + publicip.type      = "eip_public_Internet_01"
  + bandwidth.share_type = "PER"
  + bandwidth.size       = 10
  + bandwidth.name       = "myapp-dev-bastion-eip-bw"

# module.eip.hcs_vpc_eip.shared["web_01"] will be created
  + publicip.type      = "eip_public_Internet_01"
  + bandwidth.share_type = "WHOLE"
  + bandwidth.id         = (known after apply)  ← ID of web_pool
```

Confirm:
- ✅ All shared bandwidths show correct sizes
- ✅ Dedicated EIPs show `share_type = PER` with correct bandwidth sizes
- ✅ Shared EIPs show `share_type = WHOLE` with a bandwidth reference

---

## Step 3 — Apply

```bash
terraform apply eip.tfplan
```

Expected output:
```
module.eip.hcs_vpc_bandwidth.shared["web_pool"]: Creating...
module.eip.hcs_vpc_bandwidth.shared["web_pool"]: Creation complete after 3s

module.eip.hcs_vpc_eip.dedicated["bastion"]: Creating...
module.eip.hcs_vpc_eip.shared["web_01"]: Creating...
module.eip.hcs_vpc_eip.shared["web_02"]: Creating...
...

Apply complete! Resources: 4 added, 0 changed, 0 destroyed.
```

---

## Step 4 — Verify

### View EIP outputs

```bash
cd environments/dev
terraform output -json | python3 -m json.tool
```

The module outputs:
- `all_eip_ids` — merged map of all EIP IDs (`dedicated` + `shared`)
- `all_eip_addresses` — merged map of all public IP addresses
- `resolved_bandwidth_ids` — map of bandwidth pool IDs

Inspect specific resources:

```bash
terraform state show 'module.eip.hcs_vpc_eip.dedicated["bastion"]' | grep address
# Prints the public IP assigned to the bastion EIP
```

### Verify in HCS Console

1. Go to **EIP** in the HCS console
2. You should see your EIPs listed:
   - `myapp-dev-bastion-eip` with its own bandwidth
   - `myapp-dev-web-eip-01`, `myapp-dev-web-eip-02` in the shared pool
3. Go to **Bandwidth** → check `myapp-dev-web-shared-bw` shows 50 Mbit/s with 2 EIPs attached

---

## Step 5 — Bind EIPs to Instances (Post-ECS Deploy)

After deploying the ECS module, you can bind EIPs to instances by adding `eip_associations` in tfvars. Get the port ID from an ECS instance:

```bash
terraform state show 'module.web.hcs_ecs_compute_instance.instances["web-01"]' \
  | grep network_interface
# Shows port UUID
```

Then add to `terraform.tfvars`:

```hcl
eip_associations = {
  web_01_bind = {
    eip_key = "web_01"
    port_id = "<port-uuid-from-above>"
  }
}
```

And apply:

```bash
terraform plan -var-file="terraform.tfvars" -target=module.eip -out=eip.tfplan
terraform apply eip.tfplan
```

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `bandwidth not found` | `bandwidth_key` in `eip_shared` doesn't match any key in `eip_shared_bandwidths` | Check the key name matches exactly |
| `EIP quota exceeded` | HCS tenant EIP quota reached | Delete unused EIPs or request quota increase |
| `EIP type not found` | `eip_type` in `terraform.tfvars` doesn't match HCS external network name | Check in HCS Console → EIP → Create EIP for valid type values |
| `port_id not found` | EIP association references a port that doesn't exist | Deploy ECS first, then get the port ID from state |
