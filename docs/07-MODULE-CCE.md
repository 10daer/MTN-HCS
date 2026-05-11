# Module Deployment: CCE (Cloud Container Engine / Kubernetes)
## `modules/cce`

> **Prerequisites**: [00-SETUP.md](00-SETUP.md) complete, [01-MODULE-NETWORK.md](01-MODULE-NETWORK.md) applied, [02-MODULE-SECURITY.md](02-MODULE-SECURITY.md) applied.
> **Deploy order**: After network and security. CCE places worker nodes in private subnets.
> **Estimated apply time**: 25–40 minutes (cluster: 15–30 min, node pool: 5–10 min)

---

## What This Module Creates

| Resource | HCS Type | Description |
|---|---|---|
| Cluster | `hcs_cce_cluster` | Kubernetes control plane — fully managed by HCS |
| Node pools | `hcs_cce_node_pool` | Worker node groups (flavor, disk, autoscaling) |
| Namespaces | `hcs_cce_namespace` | Kubernetes namespaces provisioned immediately after cluster creation |

---

## Step 1 — Choose Cluster Flavor and Network Type

### Cluster flavors

| Flavor | Masters | Max Nodes | HA | Use case |
|---|---|---|---|---|
| `cce.s1.small` | 1 | 50 | No | Dev / test |
| `cce.s1.medium` | 1 | 200 | No | Small non-HA prod |
| `cce.s2.small` | 3 | 50 | Yes | HA dev |
| `cce.s2.medium` | 3 | 200 | Yes | Standard HA prod |
| `cce.s2.large` | 3 | 1000 | Yes | Large HA prod |

> `cce.s1.*` → `cce_cluster_multi_az = false`. `cce.s2.*` → `cce_cluster_multi_az = true`. Mismatch causes a plan error.

### Container network types

| Type | How it works | Best for |
|---|---|---|
| `overlay_l2` | VXLAN tunnel over VPC | Dev — simplest, no VPC changes needed |
| `vpc-router` | VPC static routes for pod CIDRs | Better performance — recommended for prod |
| `eni` | Pods get real VPC ENI addresses | Best performance, most IPs consumed |

For dev: use `overlay_l2`. For prod: use `vpc-router` or `eni`.

---

## Step 2 — Add CCE Values to `terraform.tfvars`

```hcl
# ── CCE — Cluster ─────────────────────────────────────────────────────────────
cce_cluster_flavor_id      = "cce.s1.small"
cce_container_network_type = "overlay_l2"
cce_container_network_cidr = ""        # empty = provider default (172.16.0.0/16)
cce_service_network_cidr   = ""        # empty = provider default (10.247.0.0/16)
cce_kube_proxy_mode        = "iptables"  # iptables | ipvs
cce_cluster_eip            = ""        # empty = private API server only
                                        # set to EIP address to expose API publicly
cce_cluster_multi_az       = false     # false for cce.s1.*, true for cce.s2.*

# ── CCE — Node Pools ──────────────────────────────────────────────────────────
cce_node_pools = {
  workers = {
    flavor_id          = "s3.large.4"    # 2 vCPU / 8 GB
    initial_node_count = 2
    availability_zone  = "az1.dc0"       # must match one of your availability_zones
    root_volume_size   = 50              # GB — node OS disk
    root_volume_type   = "SSD"
    data_volumes = [
      { size = 100, volumetype = "SSD" } # container image and runtime storage
    ]
    autoscaling_enabled      = false
    min_node_count           = 0
    max_node_count           = 0
    scale_down_cooldown_time = 0
    priority               = 1
    runtime                = "containerd"
    labels                 = { role = "worker" }
    tags                   = {}
    taints                 = []
  }
}

# ── CCE — Namespaces ──────────────────────────────────────────────────────────
cce_namespaces = {
  app        = { labels = { team = "backend" } }
  monitoring = { labels = { team = "platform" } }
  ingress    = { labels = { team = "platform" } }
}
```

### Multi-node-pool example (for mixed workloads)

```hcl
cce_node_pools = {
  # Standard workers with autoscaling
  workers = {
    flavor_id          = "c6.xlarge.4"
    initial_node_count = 3
    availability_zone  = "az1.dc0"
    root_volume_size   = 50
    root_volume_type   = "SSD"
    data_volumes       = [{ size = 100, volumetype = "SSD" }]
    autoscaling_enabled      = true
    min_node_count           = 2
    max_node_count           = 10
    scale_down_cooldown_time = 300
    priority               = 1
    runtime                = "containerd"
    labels                 = { role = "worker" }
    tags                   = {}
    taints                 = []
  }

  # Dedicated GPU pool with taint to repel non-GPU workloads
  gpu_nodes = {
    flavor_id          = "g3.4xlarge.4"
    initial_node_count = 1
    availability_zone  = "az1.dc0"
    root_volume_size   = 100
    root_volume_type   = "SSD"
    data_volumes       = [{ size = 200, volumetype = "SSD" }]
    autoscaling_enabled      = false
    min_node_count           = 0
    max_node_count           = 0
    scale_down_cooldown_time = 0
    priority               = 2
    runtime                = "containerd"
    labels                 = { role = "gpu" }
    tags                   = {}
    taints = [
      { key = "nvidia.com/gpu", value = "true", effect = "NoSchedule" }
    ]
  }
}
```

---

## Step 3 — Plan

```bash
source ~/.hcs-credentials.sh

cd environments/dev
terraform plan \
  -var-file="terraform.tfvars" \
  -target=module.cce \
  -out=cce.tfplan
```

> If network and security haven't been applied yet, add `-target=module.network -target=module.security` to the plan command.

### What to verify

```
# module.cce.hcs_cce_cluster.this will be created
  + name                   = "myapp-dev-cluster"
  + flavor_id              = "cce.s1.small"
  + vpc_id                 = "<vpc-id>"           ← from module.network
  + subnet_id              = "<private-subnet-id>" ← first private subnet
  + container_network_type = "overlay_l2"
  + multi_az               = false

# module.cce.hcs_cce_node_pool.pools["workers"] will be created
  + name               = "myapp-dev-workers"
  + flavor_id          = "s3.large.4"
  + initial_node_count = 2

# module.cce.hcs_cce_namespace.namespaces["app"] will be created
# module.cce.hcs_cce_namespace.namespaces["monitoring"] will be created
# module.cce.hcs_cce_namespace.namespaces["ingress"] will be created
```

Confirm:
- ✅ `vpc_id` and `subnet_id` have real values (not `null`)
- ✅ Cluster flavor and `multi_az` are consistent (`s1.*` = false)
- ✅ Node flavor, count, and AZ are correct
- ✅ All namespaces from `cce_namespaces` are listed

---

## Step 4 — Apply

```bash
terraform apply cce.tfplan
```

> ⏱ **Do not interrupt this command.** The cluster takes 15–30 minutes, node pool takes a further 5–10 minutes.

```
module.cce.hcs_cce_cluster.this: Creating...
module.cce.hcs_cce_cluster.this: Still creating... [10m0s elapsed]
...
module.cce.hcs_cce_cluster.this: Creation complete after 22m14s

module.cce.hcs_cce_node_pool.pools["workers"]: Creating...
...
module.cce.hcs_cce_node_pool.pools["workers"]: Creation complete after 8m45s

module.cce.hcs_cce_namespace.namespaces["app"]: Creating...
module.cce.hcs_cce_namespace.namespaces["monitoring"]: Creating...
module.cce.hcs_cce_namespace.namespaces["ingress"]: Creating...

Apply complete! Resources: 5 added, 0 changed, 0 destroyed.
```

---

## Step 5 — Get kubeconfig and Verify with kubectl

### Extract kubeconfig from state

```bash
cd environments/dev

terraform state show module.cce.hcs_cce_cluster.this \
  | grep kube_config_raw \
  | awk -F'"' '{print $2}' \
  | sed 's/\\n/\n/g' \
  > ~/.kube/hcs-dev.kubeconfig
```

Or download from HCS Console:
1. CCE → Clusters → `myapp-dev-cluster`
2. **Connection Information** tab → **Download kubeconfig**

### Configure kubectl

```bash
export KUBECONFIG=~/.kube/hcs-dev.kubeconfig

kubectl cluster-info
# Kubernetes control plane is running at https://<api-ip>:5443

kubectl get nodes
# NAME                STATUS   ROLES    AGE   VERSION
# myapp-dev-xxxxx     Ready    <none>   5m    v1.28.x
# myapp-dev-yyyyy     Ready    <none>   5m    v1.28.x

kubectl get namespaces
# Should include: app, monitoring, ingress (plus default, kube-system, kube-public)
```

> **If API server is unreachable**: With `cce_cluster_eip = ""`, the API server has only a private IP. You must be on the VPC (VPN, bastion host, or running kubectl from an ECS instance inside the VPC).

### Deploy a test pod

```bash
kubectl run test-pod \
  --image=nginx:alpine \
  --restart=Never \
  --namespace=app

kubectl get pod test-pod -n app -w
# Wait for: test-pod   1/1   Running

kubectl delete pod test-pod -n app
```

### Verify in HCS Console

1. CCE → Clusters → `myapp-dev-cluster` → status **Available**
2. **Node Pools** tab → `workers` → 2 nodes **Active**
3. **Namespaces** tab → `app`, `monitoring`, `ingress` present

---

## Scaling and Updates

### Scale node count

```hcl
# terraform.tfvars
cce_node_pools = {
  workers = {
    initial_node_count = 4   # was 2
    ...
  }
}
```

```bash
terraform plan -var-file="terraform.tfvars" -target=module.cce -out=cce.tfplan
terraform apply cce.tfplan
# In-place update — existing nodes not touched; 2 new nodes added
```

### Enable autoscaling after initial deploy

```hcl
cce_node_pools = {
  workers = {
    autoscaling_enabled      = true
    min_node_count           = 2
    max_node_count           = 10
    scale_down_cooldown_time = 300
    ...
  }
}
```

Apply with `-target=module.cce` — this is an **in-place update** to the node pool.

### Add a new node pool

Add a new key to `cce_node_pools` in tfvars and apply. Terraform creates the new pool without touching existing ones.

---

## Destroy Considerations

The module is configured with `delete_storage_on_destroy = true` in `dev/main.tf`. When destroyed:
- All EVS volumes on nodes are **deleted**
- OBS buckets created by CCE are **deleted**

For prod, change this to `false` before destroying to preserve data.

```bash
# Destroy just CCE:
cd environments/dev
terraform destroy -var-file="terraform.tfvars" -target=module.cce
```

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `cluster flavor not available` | Flavor not in your region | Check HCS Console → CCE → Create Cluster |
| `multi_az mismatch` | `cce.s1.*` with `multi_az = true` | Set `cce_cluster_multi_az = false` for s1 flavors |
| `container CIDR conflicts with VPC` | `cce_container_network_cidr` overlaps with VPC CIDR | Change to a non-overlapping CIDR (e.g. `172.16.0.0/16`) |
| `node flavor not found` | Node pool flavor not available in AZ | Pick from HCS Console → ECS → Flavors |
| `nodes NotReady` | Nodes can't pull container images | Check NAT gateway is working — nodes need outbound internet |
| `kubectl: connection refused` | API server private-only, you're outside VPC | Use VPN, bastion, or set `cce_cluster_eip` to expose API publicly |
| `node pool stuck >45 min` | HCS resource shortage or AZ capacity | Try different AZ, check HCS Console events |
