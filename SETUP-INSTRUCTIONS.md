# Using the Terraform Scripts — Complete Instructions

This document covers everything from installing tools to deploying and managing infrastructure. Follow it in order the first time. After that, day-to-day work is just a few commands.

---

## What the Scripts Do

There are three scripts in the `scripts/` folder:

| Script                 | When to run          | What it does                                                     |
| ---------------------- | -------------------- | ---------------------------------------------------------------- |
| `setup-credentials.sh` | Once per machine     | Creates `~/.hcs-credentials.sh` with your HCS AK/SK              |
| `setup-environment.sh` | Once per environment | Creates `backend.tf` and `terraform.tfvars` for dev/staging/prod |
| `tf.sh`                | Every day            | Runs all Terraform commands with safety checks                   |

---

## Part 1: First-Time Machine Setup

Do this once when you first clone the repo on a new machine.

### Step 1 — Install tfenv and Terraform

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
cd terraform-hcs-repo
tfenv install        # reads .terraform-version automatically
terraform version    # should print 1.7.5
```

---

### Step 2 — Make scripts executable

Do this once after cloning:

```bash
chmod +x scripts/tf.sh
chmod +x scripts/setup-credentials.sh
chmod +x scripts/setup-environment.sh
```

---

### Step 3 — Run the credentials setup wizard

This creates your credentials file in your home directory, outside the repo:

```bash
./scripts/setup-credentials.sh
```

The wizard will ask you for:

| What it asks    | Where to find it                           | Example       |
| --------------- | ------------------------------------------ | ------------- |
| Access Key (AK) | HCS Console → My Credentials → Access Keys | `AKIA3X7...`  |
| Secret Key (SK) | Shown once when you create the AK          | `wJalrXUt...` |

All other config (region, domain, endpoints) is in `terraform.tfvars`.

After the wizard finishes, you will have `~/.hcs-credentials.sh`.

**What that file looks like:**

```bash
export TF_VAR_access_key="AK..."
export TF_VAR_secret_key="SK..."
export AWS_ACCESS_KEY_ID="AK..."
export AWS_SECRET_ACCESS_KEY="SK..."
```

---

### Step 4 — Load credentials into your terminal

Every time you open a new terminal and want to run Terraform:

```bash
source ~/.hcs-credentials.sh
```

You will see:

```
[HCS] Credentials loaded (AK: AKIA****)
```

That's it. Now the `tf.sh` script can see your credentials.

**Optional — auto-load on terminal open:**

If you only use this machine for HCS work, you can make it automatic:

```bash
# For bash
echo 'source ~/.hcs-credentials.sh' >> ~/.bashrc

# For zsh
echo 'source ~/.hcs-credentials.sh' >> ~/.zshrc
```

Only do this on your personal machine. Never on shared or CI machines.

---

## Part 2: First-Time Environment Setup

Do this once per environment (dev, staging, prod). This creates the two gitignored files that hold real values.

### Before you start — create the OBS state bucket

Terraform needs somewhere to store its state file. This bucket must exist before you run any Terraform commands. Create it manually in the HCS Console:

```
HCS Console → OBS → Create Bucket
  Name:    myapp-dev-tfstate      (use your project name)
  Region:  cn-east-3              (your region)
  Policy:  Private
  Versioning: Enabled             (allows state recovery)
```

Write down the bucket name — you will need it in the next step.

---

### Run the environment setup wizard

```bash
# Load credentials first (if not already loaded)
source ~/.hcs-credentials.sh

# Run the wizard
./scripts/setup-environment.sh dev
```

The wizard creates two files in `environments/dev/`:

**`backend.tf`** — tells Terraform where to store state:

```hcl
terraform {
  backend "s3" {
    bucket   = "myapp-dev-tfstate"
    key      = "dev/terraform.tfstate"
    region   = "cn-east-3"
    endpoint = "https://obs.cn-east-3.hcs.company.com"
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
    force_path_style            = true
  }
}
```

**`terraform.tfvars`** — the real values for your environment:

```hcl
hcs_auth_url    = "https://iam.hcs.company.com/v3"
region          = "cn-east-3"
domain_name     = "my-company"
project_name    = "myproject"
skip_tls_verify = false

project     = "myapp"
environment = "dev"
owner       = "platform-team"

vpc_cidr              = "10.10.0.0/16"
availability_zones    = ["cn-east-3a", "cn-east-3b"]
enable_nat_gateway    = true
trusted_ssh_cidr      = "10.0.0.0/8"

key_pair_name      = "my-keypair"
web_instance_count = 2
web_flavor_id      = "c6.large.2"
app_instance_count = 2
app_flavor_id      = "c6.xlarge.2"
```

Review both files after the wizard:

```bash
cat environments/dev/backend.tf
cat environments/dev/terraform.tfvars
```

Fix anything that looks wrong before moving on.

---

## Part 3: Deploying Infrastructure — The Full Workflow

Always follow this order: **init → validate → plan → apply**.

---

### Step 1 — Initialize

```bash
source ~/.hcs-credentials.sh
./scripts/tf.sh dev init
```

What happens:

- Downloads the `hcs` provider plugin (about 50MB, only happens once)
- Connects to your OBS bucket and verifies it can read/write state
- Creates `.terraform.lock.hcl` — commit this file to git

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
- Installing huaweicloud/hcs v2.4.23...

Terraform has been successfully initialized!

[OK]    Initialization complete.

  Next steps:
  ./scripts/tf.sh dev validate   — check syntax
  ./scripts/tf.sh dev plan       — preview changes
```

---

### Step 2 — Validate

```bash
./scripts/tf.sh dev validate
```

Checks your `.tf` files for syntax errors and type mismatches. No API calls made. Fast.

```
▶ Validating Terraform configuration
  Checking syntax and types. No API calls made.

Success! The configuration is valid.

[OK]    Validation passed.
```

If you see errors here, fix your `.tf` files before continuing.

---

### Step 3 — Format (optional but good habit)

```bash
./scripts/tf.sh dev fmt
```

Auto-formats all `.tf` files in the repo to the Terraform standard style. Run this before committing code.

---

### Step 4 — Plan

```bash
./scripts/tf.sh dev plan
```

This is the most important step. Terraform:

1. Calls HCS APIs in read-only mode to check current state
2. Compares what exists against what your `.tf` files describe
3. Prints everything it will create, change, or destroy
4. Saves the plan to `environments/dev/dev.tfplan`

**Reading the plan output:**

```
  + create          green  — new resource, didn't exist before
  ~ update in-place yellow — resource will be modified, no downtime
  -/+ destroy/recreate red — destroyed then recreated (potential downtime)
  - destroy         red   — resource will be permanently deleted
```

On first deploy, you should see only `+ create` lines.

Example first-run plan:

```
Plan: 18 to add, 0 to change, 0 to destroy.
```

Read everything before applying. If you see unexpected destroys or recreates, stop and investigate.

---

### Step 5 — Apply

```bash
./scripts/tf.sh dev apply
```

Applies exactly what was shown in the plan. No new decisions are made.

The script:

1. Detects the saved `dev.tfplan` file
2. Applies it
3. Deletes the plan file after success (so you can't accidentally apply an old plan)

Watch the output as resources are created:

```
hcs_vpc.this: Creating...
hcs_vpc.this: Creation complete after 3s [id=0a1b2c3d-...]

hcs_vpc_subnet.public["public-1"]: Creating...
hcs_vpc_subnet.public["public-1"]: Creation complete after 5s

...

Apply complete! Resources: 18 added, 0 changed, 0 destroyed.

Outputs:

nat_eip = "203.0.113.45"
vpc_id = "0a1b2c3d-4e5f-..."
web_server_private_ips = [
  "10.10.1.10",
  "10.10.2.11",
]
```

---

### Step 6 — View outputs

```bash
./scripts/tf.sh dev output
```

Prints all values defined in `outputs.tf` — IP addresses, VPC IDs, bucket names etc.

---

## Part 4: Day-to-Day Operations

### Making a change

1. Edit your `.tf` file or `terraform.tfvars`
2. Run plan to preview the change
3. Review — make sure only what you intended changed
4. Apply

```bash
# Example: scale web servers from 2 to 4
# Edit environments/dev/terraform.tfvars:
#   web_instance_count = 4

./scripts/tf.sh dev plan    # shows: 2 resources to add
./scripts/tf.sh dev apply   # creates 2 more servers
```

---

### Viewing existing resources in state

```bash
# List every resource Terraform knows about
./scripts/tf.sh dev state list

# Inspect one resource in detail
./scripts/tf.sh dev state show hcs_vpc.this
./scripts/tf.sh dev state show 'module.web_servers.hcs_ecs_compute_instance.this[0]'
```

---

### Refreshing state

If someone made a manual change in the HCS console and your state is out of sync:

```bash
./scripts/tf.sh dev refresh
```

This reads the real attributes from HCS and updates the state file, without creating or destroying anything.

---

### Debugging expressions interactively

```bash
./scripts/tf.sh dev console
```

Opens an interactive console where you can test Terraform expressions against your live state:

```
> var.region
"cn-east-3"

> module.network.vpc_id
"0a1b2c3d-4e5f-..."

> cidrhost("10.0.1.0/24", 5)
"10.0.1.5"

> exit
```

---

### Unlocking a stuck state

If a `terraform apply` or `plan` was interrupted (Ctrl+C, network failure), the state may be left locked. The next command will fail with:

```
Error: Error acquiring the state lock
Lock ID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

To unlock:

```bash
./scripts/tf.sh dev unlock xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

Only do this if you are certain no other terraform process is running against this environment.

---

### Destroying an environment

```bash
./scripts/tf.sh dev destroy
```

The script requires you to type the environment name to confirm, then waits 5 seconds before proceeding.

For production, the script additionally requires you to type `yes-prod` at the production guard prompt before any destructive command.

---

## Part 5: Working With Multiple Environments

Each environment is completely independent. They have separate state files in separate OBS keys.

```bash
# Set up staging after dev is working
./scripts/setup-environment.sh staging
./scripts/tf.sh staging init
./scripts/tf.sh staging plan
./scripts/tf.sh staging apply

# Set up prod
./scripts/setup-environment.sh prod
./scripts/tf.sh prod init
./scripts/tf.sh prod plan
# ← script asks: "Are you sure? Type 'yes-prod' to continue"
./scripts/tf.sh prod apply
```

Changing dev infrastructure never touches staging or prod state.

---

## Part 6: Full Command Reference

```bash
# ── Setup (run once) ──────────────────────────────────────────────
./scripts/setup-credentials.sh              # create ~/.hcs-credentials.sh
./scripts/setup-environment.sh dev          # set up dev environment files

# ── Load credentials (run every session) ─────────────────────────
source ~/.hcs-credentials.sh

# ── Terraform commands ────────────────────────────────────────────
./scripts/tf.sh <env> init                  # download providers, connect backend
./scripts/tf.sh <env> validate              # check syntax, no API calls
./scripts/tf.sh <env> fmt                   # auto-format all .tf files
./scripts/tf.sh <env> plan                  # preview changes
./scripts/tf.sh <env> apply                 # deploy changes
./scripts/tf.sh <env> output                # show outputs
./scripts/tf.sh <env> refresh               # sync state with real HCS
./scripts/tf.sh <env> console               # interactive expression testing
./scripts/tf.sh <env> destroy               # delete everything (with confirmation)

# ── State inspection ──────────────────────────────────────────────
./scripts/tf.sh <env> state list            # list all managed resources
./scripts/tf.sh <env> state show <resource> # inspect one resource
./scripts/tf.sh <env> state rm <resource>   # remove from state (advanced)
./scripts/tf.sh <env> unlock <lock-id>      # force-unlock stuck state
```

---

## Part 7: Troubleshooting

### "Required environment variable not set"

```
[ERROR] The following required environment variables are not set:
  ✗ TF_VAR_access_key
  ✗ TF_VAR_secret_key
```

You forgot to load credentials:

```bash
source ~/.hcs-credentials.sh
```

---

### "backend.tf not found"

```
[ERROR] backend.tf not found in environments/dev
```

Run the environment setup:

```bash
./scripts/setup-environment.sh dev
```

Or create it manually:

```bash
cp backend.tf.example environments/dev/backend.tf
# then edit with your OBS bucket details
```

---

### "terraform.tfvars not found"

```
[ERROR] terraform.tfvars not found in environments/dev
```

```bash
cp environments/dev/terraform.tfvars.example environments/dev/terraform.tfvars
# then fill in your real values
```

---

### "Error configuring S3 Backend"

Usually means the OBS bucket doesn't exist, or the endpoint URL is wrong.

Check:

1. The bucket exists in HCS Console → OBS
2. The endpoint in `backend.tf` matches your HCS OBS endpoint
3. `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are set (done automatically by `source ~/.hcs-credentials.sh`)

---

### "Error acquiring the state lock"

Another terraform process is running (or one crashed and left a lock). See the `unlock` command above.

---

### "No changes. Infrastructure is up-to-date."

This is correct behaviour — it means your real HCS resources match your `.tf` files exactly. Nothing needs to be done.

---

### Provider plugin download fails

If you're on a network with no internet access to the Terraform registry, you need to use a private provider mirror. Ask your HCS/network admin for the internal mirror URL, then set:

```bash
export TF_CLI_CONFIG_FILE="~/.terraform.rc"
```

With `~/.terraform.rc` containing:

```hcl
provider_installation {
  network_mirror {
    url = "https://your-internal-mirror/terraform-providers/"
  }
}
```

---

## Part 8: Security Checklist

Before treating this repo as production-ready, verify:

- `~/.hcs-credentials.sh` has permissions `600` — `ls -la ~/.hcs-credentials.sh`
- `terraform.tfvars` is in `.gitignore` — `git status` should never show it
- `backend.tf` is in `.gitignore` — same check
- `*.tfstate` files never appear in `git status`
- No AK/SK values appear anywhere in `.tf` files
- The OBS state bucket has versioning enabled (allows state recovery)
- Only named individuals in your team have the AK/SK credentials
- Prod credentials are different AK/SK from dev credentials (separate IAM users)
