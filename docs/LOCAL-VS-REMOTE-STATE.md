# Local vs Remote Terraform State — Plain-English Guide

> **TL;DR**
> - **REMOTE state** (HCS OBS) is the default. Use it for any environment more than one person touches.
> - **LOCAL state** (file on your laptop) is for **personal testing only**. Never use it for staging or prod.
> - You switch by replacing `backend.tf` and running `terraform init -reconfigure`.

---

## What is "state" and why do I care?

Every time Terraform creates a resource (a VPC, a server, a bucket…), it writes the resource's ID and attributes into a **state file**. That file is Terraform's memory.

Without state, Terraform can't tell the difference between "this VPC already exists" and "I need to create a VPC". It would try to recreate everything on every run.

The state file is plain JSON. It can live in one of two places.

---

## The two options

### Option 1 — REMOTE state (default, recommended for shared work)

The state file lives in a **shared OBS bucket** in HCS. Every team member reads and writes the same file.

**Pros**
- Whole team sees the same picture
- Built-in locking — two people can't apply at the same time
- Versioned (if the bucket has versioning on) — you can roll back state corruption
- Survives losing your laptop

**Cons**
- Requires a working OBS bucket before you can even run `terraform init`
- A network blip can interrupt operations
- Slower to read (round-trip to OBS each time)

**Backend file:** `environments/<env>/backend.tf.example`

```hcl
terraform {
  backend "s3" {
    bucket   = "myapp-dev-tfstate"
    key      = "dev/terraform.tfstate"
    region   = "MTN_Cloud"
    endpoint = "https://obs.lagos-mtn-1.mtn.com"

    skip_credentials_validation = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
    force_path_style            = true
  }
}
```

### Option 2 — LOCAL state (testing only)

The state file lives at `environments/<env>/terraform.tfstate` on **your laptop only**. Nobody else sees it.

**Pros**
- Zero setup — no OBS bucket, no shared resources
- Fast — file read/write only
- Perfect sandbox — you can't accidentally affect the team's real state
- Works offline (for `validate` / `fmt` / `plan` against cached data)

**Cons**
- **Only you have it.** If your laptop dies, the state is gone.
- **No locking.** If you run two `apply`s at once on the same machine, state can corrupt.
- **Cannot share work.** Another developer can't continue where you left off.
- **NEVER use for prod/staging.**

**Backend file:** `environments/<env>/backend-local.tf.example`

```hcl
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
```

---

## Which one should I use?

| Scenario | Use |
|---|---|
| Production deployment | **Remote** |
| Staging environment | **Remote** |
| Shared dev environment (multiple devs apply) | **Remote** |
| Personal sandbox — testing a module change before opening a PR | **Local** |
| Reproducing a bug in isolation | **Local** |
| Learning what `terraform apply` does without risk | **Local** |
| CI/CD pipeline | **Remote** (CI has no persistent disk) |

If you're not sure: **use remote**. Local is the special case.

---

## How to switch (step by step)

### Switching FROM remote TO local

You're set up with the OBS backend and want to switch to a local file for testing.

```bash
cd environments/dev

# 1) Optional but recommended — back up your current remote state to a file
terraform state pull > backup-before-switch.tfstate.json

# 2) Replace backend.tf with the local template
cp backend-local.tf.example backend.tf

# 3) Re-initialize. Terraform will notice the backend changed and ask
#    whether to copy state from OBS down to your laptop. Say YES.
terraform init -migrate-state
# Or use the wrapper:
./scripts/tf.sh dev init -migrate-state
```

After that, your state is at `environments/dev/terraform.tfstate` (gitignored).

### Switching FROM local TO remote

You've been testing locally and now want to push your work to the shared OBS state.

> **⚠ DANGER:** If a remote state already exists and contains different resources, the migration will overwrite or merge them. Double-check the plan before applying after a migration. When in doubt, stash your local state and re-import resources manually.

```bash
cd environments/dev

# 1) Make sure the remote OBS bucket exists (see docs/00-SETUP.md Step 4)

# 2) Replace backend.tf with the remote template and fill in values
cp backend.tf.example backend.tf
# … edit backend.tf and set bucket/key/region/endpoint …

# 3) Re-initialize. Terraform will offer to copy your local state up to OBS.
terraform init -migrate-state
# Or:
./scripts/tf.sh dev init -migrate-state
```

### Switching without migrating state (start fresh)

If you don't care about your current state and want a clean slate:

```bash
cp backend-local.tf.example backend.tf      # or backend.tf.example for remote
./scripts/tf.sh dev init -reconfigure       # -reconfigure = "don't migrate, just start fresh"
```

`-reconfigure` is **destructive to local state knowledge** — Terraform will forget what it created. The actual HCS resources stay; you'd have to `terraform import` them back to manage them again.

---

## Setting up local state from scratch (one command)

If you've never set up the environment, the wizard now asks which backend you want:

```bash
source ~/.hcs-credentials.sh
./scripts/setup-environment.sh dev
# When prompted "Which backend? [local/remote]", type: local
```

Or, the manual two-step:

```bash
cp environments/dev/backend-local.tf.example environments/dev/backend.tf
./scripts/tf.sh dev init
```

---

## Knowing which backend is active

The `tf.sh` wrapper prints it in the banner every time you run a command:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Terraform HCS Wrapper
  Environment  : dev
  Command      : plan
  Directory    : environments/dev
  Backend      : LOCAL (file on this machine)     ← look here
  Timestamp    : 2026-05-11 14:30:00
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

If it says `LOCAL` for `staging` or `prod`, the script will print an additional warning. Stop and fix it.

You can also check directly:

```bash
grep '^[[:space:]]*backend' environments/dev/backend.tf
# backend "local" {     ← you're on local
# backend "s3"    {     ← you're on remote
```

---

## Common mistakes and how to spot them

| Symptom | What happened | Fix |
|---|---|---|
| "Backend reinitialization required" | You changed `backend.tf` but didn't re-init | `./scripts/tf.sh <env> init -reconfigure` |
| "Initial configuration of the requested backend" | First time using this backend | `./scripts/tf.sh <env> init` |
| Plan shows everything as "create" after switching backends | You did `-reconfigure` instead of `-migrate-state` and lost state | If resources still exist in HCS: `terraform import` them back. If not, the new plan is correct. |
| Two team members' applies overwrite each other | Someone is on local state in a "shared" environment | Switch to remote. Local state cannot be shared. |
| `terraform.tfstate` shows up in `git status` | Local backend in use; file is gitignored so this shouldn't happen unless gitignore was edited | Check `.gitignore` still contains `*.tfstate` |

---

## Files at a glance

```
MTN-HCS-IAC/
├── backend-local.tf.example                   # Local state template (root reference copy)
├── backend.tf.example                         # Remote (OBS) state template (root reference copy)
└── environments/
    └── dev/
        ├── backend.tf                         # ← the active backend (gitignored, copy of one of the below)
        ├── backend.tf.example                 # ← copy this for REMOTE (OBS) state
        ├── backend-local.tf.example           # ← copy this for LOCAL state
        ├── terraform.tfstate                  # ← exists only when using LOCAL backend (gitignored)
        └── ...
```

**Reminder:** `backend.tf` and `*.tfstate` are both in `.gitignore`. They never get committed. If you ever see them in `git status`, something is wrong — check `.gitignore`.

---

## When in doubt

1. Read the banner — the `Backend:` line tells you what's active.
2. If you're testing alone, use **local**.
3. If anyone else needs to see what you've deployed, use **remote**.
4. For `prod` or `staging`, the answer is always **remote**.
