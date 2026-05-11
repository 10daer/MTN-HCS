# MTN-HCS-IAC — Environment Setup Guide

> **Purpose**: Get a brand-new machine ready to deploy any module in this repo.
> Complete this guide **once** before following any module deployment guide.
>
> **Time**: ~20 minutes

---

## Prerequisites

Install the following on the new machine before starting:

| Tool          | Minimum Version | Check               | Install                                                                                            |
| ------------- | --------------- | ------------------- | -------------------------------------------------------------------------------------------------- |
| **Terraform** | `>= 1.6.0`      | `terraform version` | [developer.hashicorp.com/terraform/downloads](https://developer.hashicorp.com/terraform/downloads) |
| **Git**       | any             | `git --version`     | OS package manager                                                                                 |
| **Bash**      | `>= 4.0`        | `bash --version`    | Pre-installed on Linux; `brew install bash` on macOS                                               |

> **macOS note**: The system Bash on macOS is 3.x. The scripts require 4.0+.
>
> ```bash
> brew install bash
> bash --version   # should now show 5.x
> ```

### Verify Terraform version

```bash
terraform version
# Must print: Terraform v1.6.x or higher
# 1.5.x will NOT work — terraform test and mock_provider require 1.6+
```

---

## Step 1a — Clone the Repository

```bash
git clone <repo-url> MTN-HCS-IAC
```

Verify the structure:

```bash
ls
# Expected: modules/ environments/ scripts/ docs/ exempt/ README.md
```

---

Do this once when you first clone the repo on a new machine.

### Step 1b — Install tfenv and Terraform

tfenv manages Terraform versions, like nvm for Node.js.

**Linux / WSL:**

```bash
git clone https://github.com/tfutils/tfenv.git ~/.tfenv
echo 'export PATH="$HOME/.tfenv/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

**macOS:**

```bash
brew install tfenv
```

Then install the version this repo requires:

```bash
cd MTN-HCS-IAC
tfenv install        # reads .terraform-version automatically
terraform version    # should print 1.7.5
```

---

## Step 2a — Make Scripts Executable

This is a one-time step. Scripts are committed without the execute bit.

```bash
chmod +x scripts/*.sh
```

Verify:

```bash
ls -la scripts/
# All four .sh files should show -rwxr-xr-x
# tf.sh  setup-credentials.sh  setup-environment.sh  test-module.sh
```

### Step 2b — Verify the test runner works (no credentials needed)

Before touching any credentials, confirm that static and unit tests pass for all modules. This validates your Terraform installation and the codebase in one shot.

```bash
# Requires Terraform >= 1.6
./scripts/test-module.sh --all --level static   # fmt + validate every module
./scripts/test-module.sh --all --level unit     # mock-provider tests, no credentials
```

Both commands should exit with `ALL PASSED`. If not, see [docs/TESTING.md](docs/TESTING.md) for troubleshooting.

---

## Step 3 — Set Up HCS Credentials

Your HCS Access Key (AK) and Secret Key (SK) must never be stored in the repo. The repo uses a credentials file in your **home directory** (`~/.hcs-credentials.sh`) which is outside git.

### Run the credentials wizard

```bash
./scripts/setup-credentials.sh
```

The wizard will:

1. Ask for your **Access Key** (AK) — visible as you type
2. Ask for your **Secret Key** (SK) — hidden input
3. Write `~/.hcs-credentials.sh` with permissions `600` (only you can read it)
4. Automatically source the file to confirm it works

You'll see:

```
[OK]    Credentials sourced successfully
        AK (masked): AMO4****
```

### What the credentials file contains

```bash
# ~/.hcs-credentials.sh (auto-generated — never commit this)
export TF_VAR_access_key="<your-ak>"
export TF_VAR_secret_key="<your-sk>"
export AWS_ACCESS_KEY_ID="<your-ak>"
export AWS_SECRET_ACCESS_KEY="<your-sk>"
```

> **Why both `TF_VAR_*` and `AWS_*`?**
>
> - `TF_VAR_access_key` / `TF_VAR_secret_key` → used by the HCS provider
> - `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` → used by Terraform's S3 backend to authenticate to OBS (HCS OBS is S3-compatible)
>   Both must be set for `terraform init` and all subsequent commands to work.

### Load credentials in every new terminal session

After the one-time setup, run this at the start of every terminal session:

```bash
source ~/.hcs-credentials.sh
# Prints: [HCS] Credentials loaded (AK: AMO4****)
```

**Optional — auto-load on every terminal open** (personal machine only, never CI):

```bash
# zsh (macOS default):
echo 'source ~/.hcs-credentials.sh' >> ~/.zshrc

# bash:
echo 'source ~/.hcs-credentials.sh' >> ~/.bashrc
```

### Finding your AK/SK in the HCS Console

1. Log in to the HCS console
2. Click your account name (top-right) → **My Credentials**
3. Go to **Access Keys** tab
4. Click **Create Access Key**
5. Download the CSV — the SK is **only shown once**. Store it safely.

---

## Step 4 — Create the OBS State Bucket (Manual, One-Time)

> **Skip this step if you only want to use LOCAL state for testing.**
> Local state stores the state file on your laptop and needs no OBS bucket.
> See [LOCAL-VS-REMOTE-STATE.md](LOCAL-VS-REMOTE-STATE.md) for when to use which.
> For any shared environment (dev with multiple devs, staging, prod), do this step.

Terraform stores its state in HCS OBS. This bucket must exist **before** `terraform init` can run. Terraform cannot create its own backend bucket.

1. Log in to the HCS console
2. Navigate to **OBS** (Object Storage Service) → **Create Bucket**
3. Fill in:
   - **Bucket name**: `<project>-<env>-tfstate` (e.g. `myapp-dev-tfstate`)
   - **Region**: match your deployment region (e.g. `lagos-mtn-1`)
   - **Storage class**: Standard
   - **ACL**: Private
   - **Default encryption**: optional (recommended for prod)
4. Enable **Versioning** — this protects state history and allows recovery from accidental corruption
5. Click **Create**

Note down:

- The **bucket name** you chose
- The **OBS endpoint URL** for your region (e.g. `https://obs.lagos-mtn-1.mtn.com`)

> **One bucket per environment**: If you are setting up staging and prod later, create a separate bucket for each:
>
> - `myapp-dev-tfstate`
> - `myapp-staging-tfstate`
> - `myapp-prod-tfstate`

---

## Step 5 — Configure Environment Files

Two files must be created locally per environment. Both are `.gitignore`d — never commit them.

### Choosing a backend: LOCAL or REMOTE?

The setup wizard will ask which kind of state backend you want:

| Choice | What it is | When to pick it |
|---|---|---|
| **REMOTE** (HCS OBS) | State stored in a shared OBS bucket | Default. Use for any shared environment (dev with multiple devs, staging, prod, CI). Requires Step 4 done. |
| **LOCAL** | State stored as a file on your laptop | Personal testing / sandbox / learning. Skip Step 4. Never use for staging or prod. |

If unsure, pick **remote**. See [LOCAL-VS-REMOTE-STATE.md](LOCAL-VS-REMOTE-STATE.md) for a deeper explanation, including how to switch between the two later.

### Option A — Use the setup script (recommended)

```bash
source ~/.hcs-credentials.sh    # credentials must be loaded first

./scripts/setup-environment.sh dev
# When prompted "Which backend? [local/remote]", pick one.
```

The script will interactively prompt for:

- **Backend type:** local or remote
- If remote: OBS bucket name, key, region, and endpoint (from Step 4)
- HCS region, domain/tenant name, VDC project name
- Project name, owner tag
- Network CIDRs, availability zones, SSH key pair name
- ECS instance counts and flavors

It writes both files automatically. Review them after:

```bash
cat environments/dev/backend.tf
cat environments/dev/terraform.tfvars
```

### Option B — Configure manually

#### `environments/dev/backend.tf` (remote / OBS — default)

```bash
cp environments/dev/backend.tf.example environments/dev/backend.tf
```

Edit the file to look like this (replace placeholder values):

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    hcs = {
      source  = "huaweicloud/hcs"
      version = "~> 2.4.0"
    }
  }

  backend "s3" {
    bucket   = "myapp-dev-tfstate"                    # your OBS bucket name from Step 4
    key      = "dev/terraform.tfstate"                # path within the bucket
    region   = "lagos-mtn-1"                          # your HCS region name
    endpoint = "https://obs.lagos-mtn-1.mtn.com"     # your OBS endpoint URL

    # Required for non-AWS S3-compatible backends
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
    force_path_style            = true
  }
}
```

#### `environments/dev/backend.tf` (local — testing only)

If you picked local state instead, copy the local template — no editing needed:

```bash
cp environments/dev/backend-local.tf.example environments/dev/backend.tf
```

The state file will be created at `environments/dev/terraform.tfstate` after `init` (gitignored). Reminder: local state is only suitable for personal testing — see [LOCAL-VS-REMOTE-STATE.md](LOCAL-VS-REMOTE-STATE.md).

#### `environments/dev/terraform.tfvars`

```bash
cp environments/dev/terraform.tfvars.example environments/dev/terraform.tfvars
```

Open `environments/dev/terraform.tfvars` and fill in at minimum these required sections. See individual module deployment guides for module-specific values.

**Required base values:**

```hcl
# ── HCS Connection ───────────────────────────────────────────────────────────
# Leave access_key and secret_key empty — loaded from TF_VAR_ env vars
access_key      = ""
secret_key      = ""

hcs_auth_url    = ""                           # leave empty for AK/SK auth
region          = "MTN_Cloud"                  # your HCS region name
domain_name     = "IT-DEPT"                    # your HCS tenant/domain name
project_name    = "lagos-mtn-1_A_and_E"       # your HCS VDC project name
skip_tls_verify = true                         # true for self-signed HCS certs

# ── Service Endpoints ────────────────────────────────────────────────────────
# Required for private HCS — replace with your actual endpoint hostnames
endpoints = {
  ecs = "https://ecs.lagos-mtn-1.mtn.com"
  ims = "https://ims.lagos-mtn-1.mtn.com"
  vpc = "https://vpc.lagos-mtn-1.mtn.com"
  evs = "https://evs.lagos-mtn-1.mtn.com"
  nat = "https://nat.lagos-mtn-1.mtn.com"
  obs = "https://obs.lagos-mtn-1.mtn.com"
  iam = "https://iam-apigateway-proxy.mtn.com"
}

# ── Project Metadata ─────────────────────────────────────────────────────────
project     = "myapp"           # short name — used as prefix in all resource names
environment = "dev"
owner       = "platform-team"
```

> All other module-specific values (network CIDRs, ECS flavors, CCE node pools, etc.) are added on top of these base values as you deploy each module. Refer to each module's deployment guide.

---

## Step 6 — Initialize Terraform

With credentials loaded and both files in place:

```bash
source ~/.hcs-credentials.sh    # always do this first in a new terminal

./scripts/tf.sh dev init
```

What this does:

1. Downloads the `huaweicloud/hcs` provider plugin (version `~> 2.4.0`)
2. Connects to your OBS bucket and verifies access
3. Creates `.terraform/` directory locally (gitignored)
4. Creates `.terraform.lock.hcl` — **commit this file** to lock the provider version for the team

Expected output:

```
▶ Initializing Terraform
  This will:
    • Download the HCS provider plugin
    • Connect to the OBS remote state backend
    • Create .terraform.lock.hcl (commit this file)

Initializing the backend...

Successfully configured the backend "s3"!

Initializing provider plugins...
- Finding huaweicloud/hcs versions matching "~> 2.4.0"...
- Installing huaweicloud/hcs v2.4.x...

Terraform has been successfully initialized!
```

### Init troubleshooting

| Error                               | Cause                                      | Fix                                                |
| ----------------------------------- | ------------------------------------------ | -------------------------------------------------- |
| `Failed to get existing workspaces` | OBS bucket doesn't exist or wrong endpoint | Re-check Step 4 and the endpoint in `backend.tf`   |
| `No valid credential sources found` | Credentials not exported                   | Run `source ~/.hcs-credentials.sh`                 |
| `Invalid endpoint`                  | Wrong OBS endpoint URL                     | Verify with your HCS admin                         |
| `dial tcp: no route to host`        | No network connectivity to HCS             | Check VPN / network access                         |
| `AccessDenied`                      | AK/SK has no OBS permissions               | Grant OBS access to the account in the HCS console |

---

## Step 7 — Validate the Configuration

```bash
./scripts/tf.sh dev validate
```

This checks `.tf` syntax and type-correctness without making any API calls. Run it whenever you edit `terraform.tfvars` or any `.tf` file.

Expected output:

```
▶ Validating Terraform configuration
  Checking syntax and types. No API calls made.

Success! The configuration is valid.
```

Fix any errors before proceeding. Common issues:

- Missing required variable values in `terraform.tfvars`
- Typos in variable names
- Wrong type (e.g. string where number expected)

---

## Setup Complete

Your environment is ready. You can now follow any of the module deployment guides:

| Module Guide            | What It Deploys             | Deploy Order                   |
| ----------------------- | --------------------------- | ------------------------------ |
| `01-MODULE-NETWORK.md`  | VPC, subnets, NAT gateway   | **1st — no dependencies**      |
| `02-MODULE-SECURITY.md` | Security groups             | **2nd — after network**        |
| `03-MODULE-EIP.md`      | EIPs and bandwidth pools    | 3rd — after network            |
| `04-MODULE-ECS.md`      | Web and app tier servers    | 4th — after network + security |
| `05-MODULE-OBS.md`      | Object storage buckets      | Any time — no dependencies     |
| `06-MODULE-VDC.md`      | Users, groups, roles        | Any time — no dependencies     |
| `07-MODULE-CCE.md`      | Kubernetes cluster + nodes  | After network + security       |
| `08-MODULE-GAUSSDB.md`  | GaussDB OpenGauss instances | After network + security       |
| `09-MODULE-RDS.md`      | RDS MySQL/PostgreSQL        | After network + security       |

> **Quick reference**:
>
> ```bash
> source ~/.hcs-credentials.sh   # every new terminal
> ./scripts/tf.sh dev plan       # always plan before applying
> ./scripts/tf.sh dev apply      # apply the saved plan
> ```
