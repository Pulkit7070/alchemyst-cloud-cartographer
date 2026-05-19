# Alchemyst AI — Cloud Cartographer Assignment
## Master Execution Plan

**Candidate:** Pulkit Saraf
**Deadline:** May 23, 2026 (we ship by May 22 EOD)
**Target outcome:** Top 1% submission → ₹50K/mo offer
**Estimated effort:** 18–22 focused hours over 3 days

---

## 0. Strategic Framing

### What evaluators are actually grading
The assignment is a smokescreen for four signals:

1. **Can you think in systems?** — multi-VM mesh, RPC, network isolation
2. **Do you write reproducible infra?** — Terraform destroy → apply on clean account must work
3. **Do you understand "production"?** — least-privilege IAM, defense in depth, observability
4. **Can you communicate?** — docs, ADRs, architecture diagrams

A working solution scores ~60. A working solution **with security hardening, modular Terraform, IAP-only SSH, Cloud Armor on the public API, a runbook, ADRs, infracost output, and a 100x scaling writeup citing vLLM/TensorRT-LLM/Triton/Dynamo** scores 95+.

### Work mode
Their careers page lists engineering roles as **Remote/On-site (flexible)**. No hard onsite mandate. The DevOps role is functionally remote — the entire job is provisioning cloud resources via code. Ask for remote-first in the negotiation; if they push onsite later, that becomes a separate conversation about relocation/stipend bump.

---

## 1. Target Architecture

### High-level diagram

```
                                  Internet
                                     │
                                     ▼
                          ┌──────────────────────┐
                          │  Cloud Armor (WAF)   │  ← rate limit, geo-block, OWASP rules
                          └──────────┬───────────┘
                                     ▼
                          ┌──────────────────────┐
                          │ External HTTPS LB    │  ← managed TLS cert (Let's Encrypt via GCP)
                          │  alchemyst-api.<dom> │
                          └──────────┬───────────┘
                                     ▼
   ┌─────────────────────── PUBLIC SUBNET (10.10.1.0/24) ──────────────────────┐
   │                                                                           │
   │   ┌─────────────────────────────────────────────────────────────────────┐ │
   │   │  gateway-vm  (e2-small, ext IP, Shielded VM, OS Login)              │ │
   │   │  ├─ systemd: iii-engine.service        (ws://0.0.0.0:49134)         │ │
   │   │  └─ systemd: caller-worker.service     (TS → HTTP :3111)            │ │
   │   └─────────────────────────────────────────────────────────────────────┘ │
   │                                                                           │
   └───────────────────────────────────┬───────────────────────────────────────┘
                                       │  VPC-internal only
                                       │  (firewall: tcp/49134 ← public subnet)
                                       ▼
   ┌──────────────────────── PRIVATE SUBNET (10.10.2.0/24) ────────────────────┐
   │   no public IPs · Private Google Access ON · Cloud NAT for egress         │
   │                                                                           │
   │   ┌─────────────────────────────────────────────────────────────────────┐ │
   │   │  inference-vm  (e2-standard-4, NO ext IP, Shielded VM)              │ │
   │   │  └─ systemd: inference-worker.service                               │ │
   │   │      └─ Python · transformers · gemma-3-270m GGUF Q8 (241 MB)       │ │
   │   └─────────────────────────────────────────────────────────────────────┘ │
   │                                                                           │
   │   SSH access: IAP TCP forwarding only (35.235.240.0/20) — zero public 22 │
   └───────────────────────────────────────────────────────────────────────────┘

   Cross-cutting:
   • VPC Flow Logs → Cloud Logging
   • Cloud Audit Logs (Admin + Data Access)
   • Cloud Monitoring dashboards + alert policies (p99 latency, 5xx rate, VM CPU)
   • Secret Manager (no secrets today, but wired for tomorrow)
   • GCS bucket (versioned, locked) for Terraform remote state
```

### Request lifecycle (sequence)

```
client → Cloud Armor → HTTPS LB → gateway-vm:3111
                                  │
                                  ▼
                          caller-worker (TS)
                                  │  iii RPC: inference::generate
                                  ▼
                          iii-engine (ws :49134, on gateway-vm)
                                  │  routes via WebSocket
                                  ▼
                          inference-worker (Py, on inference-vm)
                                  │  transformers.pipeline()
                                  ▼
                          gemma-3-270m → tokens
                                  │
                          ◄────── response trickles back up
```

### Why these architectural choices (write these into ADRs)

| Decision | Choice | Rationale (vs alternative) |
|----------|--------|---------------------------|
| Cloud | GCP | Pulkit uses GCP at ArmorIQ; free $300 credits; better VPC primitives than AWS for this size |
| IaC | Terraform | Industry standard; vs Pulumi: more reviewers will recognize; vs gcloud scripts: not reproducible |
| Subnet topology | Public + Private + Cloud NAT | Vs single-subnet: proves understanding of defense in depth |
| SSH | IAP TCP forwarding | Vs bastion VM: no extra VM, no public IP, IAM-gated, audit-logged |
| Engine placement | Co-located with caller on gateway-vm | Vs separate engine VM: one fewer VM ($) and one fewer hop (latency); engine port stays VPC-internal anyway |
| Inference VM size | e2-standard-4 (4 vCPU, 16 GB) | gemma-3-270m Q8 is 241 MB; CPU inference benefits from cores; 16 GB leaves headroom |
| Gateway VM size | e2-small | TS proxy is I/O bound, doesn't need cores |
| Runtime | systemd | Vs Docker: lighter for 2 services; vs k8s: massive overkill at this scale (we'll address k8s in scaling writeup) |
| Public exposure | HTTPS LB + Cloud Armor | Vs raw VM port: get TLS + DDoS shielding "for free" |
| State backend | GCS bucket, versioned + object-locked | Vs local state: real teams cannot share local state |

---

## 2. Repository Layout

```
alchemyst-cloud-cartographer/
├── .github/
│   └── workflows/
│       ├── terraform-ci.yml          # fmt, validate, tflint, tfsec, checkov, infracost
│       └── shellcheck.yml            # lint provisioning scripts
├── .pre-commit-config.yaml           # local hooks mirroring CI
├── terraform/
│   ├── backend.tf                    # GCS backend
│   ├── versions.tf                   # pinned providers
│   ├── main.tf                       # root module wiring
│   ├── variables.tf                  # with validation blocks
│   ├── outputs.tf                    # api_url, ssh_commands, costs
│   ├── terraform.tfvars.example
│   └── modules/
│       ├── network/                  # VPC, subnets, NAT, firewall, flow logs
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   ├── outputs.tf
│       │   └── README.md             # terraform-docs auto-generated
│       ├── iam/                      # service accounts, OS Login, IAP bindings
│       ├── compute/                  # gateway-vm + inference-vm + MIG-ready
│       ├── lb/                       # external HTTPS LB + Cloud Armor policy
│       ├── observability/            # dashboards, alert policies, log sinks
│       └── state-bucket/             # one-time bootstrap module
├── ansible/                          # OR cloud-init in compute module
│   ├── gateway.yml                   # installs node, sets up systemd units
│   └── inference.yml                 # installs python, copies model, systemd
├── systemd/
│   ├── iii-engine.service
│   ├── caller-worker.service
│   └── inference-worker.service
├── scripts/
│   ├── bootstrap.sh                  # creates GCS state bucket on first run
│   ├── deploy.sh                     # terraform init+apply + ansible
│   ├── smoke-test.sh                 # curl + assert response shape
│   ├── load-test.js                  # k6 script, 50 vus for 60s
│   ├── chaos-test.sh                 # kill inference worker, verify reconnect
│   └── verify-isolation.sh           # confirms inference VM has no public reachability
├── quickstart/                       # vendored from their repo, unmodified
├── docs/
│   ├── architecture.md               # diagrams + component descriptions
│   ├── RUNBOOK.md                    # restart, redeploy, debug, rollback
│   ├── SECURITY.md                   # threat model + hardening checklist
│   ├── SCALING.md                    # 100x writeup — vLLM/TRT-LLM/Dynamo/GKE
│   ├── COST.md                       # infracost output + monthly estimate
│   └── adr/
│       ├── 0001-cloud-provider-gcp.md
│       ├── 0002-iac-terraform.md
│       ├── 0003-network-topology.md
│       ├── 0004-ssh-via-iap.md
│       ├── 0005-engine-colocation.md
│       └── 0006-systemd-over-docker.md
├── diagrams/
│   ├── architecture.mmd              # mermaid source
│   ├── sequence.mmd
│   └── architecture.png              # rendered
├── Makefile                          # `make deploy`, `make test`, `make destroy`
├── README.md                         # the document that closes the offer
├── LICENSE                           # MIT
└── .gitignore
```

---

## 3. Phase-by-Phase Execution

### Phase 0 — Discovery & Local Validation (3 hrs) — Day 1 Morning

**0.1 Read everything (45 min)**
- [ ] Reread `devops-internship-assignment.md` line-by-line; list every literal requirement
- [ ] Read iii framework docs at https://iii.dev/docs/quickstart end to end
- [ ] Read the quickstart README + `config.yaml` + `iii.worker.yaml`
- [ ] Inspect `workers/caller-worker/` and `workers/inference-worker/` source

**0.2 Run quickstart locally (90 min)**
- [ ] Install: `python3.11`, `bun` (or node 20), `iii` CLI
- [ ] Bring up engine + both workers locally
- [ ] Hit `POST /v1/chat/completions` with curl, confirm a real response
- [ ] Note model load time, response latency, RAM footprint — write to `docs/COST.md` benchmarks section

**0.3 Tooling install (30 min)**
- [ ] `terraform 1.9+`, `tflint`, `tfsec`, `checkov`, `infracost`, `terraform-docs`
- [ ] `gcloud CLI`, authenticated
- [ ] `pre-commit install`

**0.4 GCP bootstrap (15 min)**
- [ ] Create project `alchemyst-cartographer-pulkit`
- [ ] Activate $300 free trial
- [ ] Enable APIs: `compute`, `iap`, `servicenetworking`, `cloudkms`, `secretmanager`, `monitoring`, `logging`, `iam`, `cloudresourcemanager`
- [ ] Run `scripts/bootstrap.sh` → creates GCS state bucket with versioning + object lock

**Exit gate:** local curl returns a real Gemma response. GCP project exists with state bucket.

---

### Phase 1 — Network Foundation (3 hrs) — Day 1 Afternoon

**1.1 `modules/network/`**
- [ ] Custom-mode VPC `alchemyst-vpc` (not auto-mode)
- [ ] Public subnet `10.10.1.0/24` in `asia-south1` (Mumbai for low latency from India)
- [ ] Private subnet `10.10.2.0/24` same region
- [ ] **Private Google Access = true** on both
- [ ] Cloud Router + Cloud NAT for private subnet egress
- [ ] **VPC Flow Logs** enabled (5-sec aggregation, 50% sampling)

**1.2 Firewall rules (deny-by-default mindset)**
- [ ] `allow-iap-ssh`: tcp/22 from `35.235.240.0/20` to tag `iap-ssh` only
- [ ] `allow-engine-internal`: tcp/49134 from public subnet CIDR to tag `iii-engine` only
- [ ] `allow-health-checks`: tcp/3111 from GCP LB CIDRs `35.191.0.0/16` + `130.211.0.0/22` to tag `http-server`
- [ ] `allow-internal-icmp`: for debugging within VPC
- [ ] **No default-allow-* rules.** Explicitly delete them if present.

**1.3 IAM module**
- [ ] Service account `sa-gateway` — minimal: `logging.logWriter`, `monitoring.metricWriter`
- [ ] Service account `sa-inference` — same + `secretmanager.secretAccessor` (future-proofing)
- [ ] OS Login enabled at project level: `enable-oslogin = TRUE`
- [ ] IAP tunnel users group bound to a Google group (or single user for assignment)

**1.4 CI smoke**
- [ ] `terraform fmt -recursive` clean
- [ ] `tflint` clean
- [ ] `tfsec` clean (or documented exceptions in `.tfsec.yml`)
- [ ] `terraform plan` shows expected resources

**Exit gate:** `terraform apply` from a clean state creates the entire network in one shot.

---

### Phase 2 — Compute & Application Deployment (5 hrs) — Day 2 Morning

**2.1 `modules/compute/`**
- [ ] Reserve static internal IP for `inference-vm` (so engine config is stable)
- [ ] `gateway-vm`: e2-small, Ubuntu 22.04 LTS minimal, public subnet, Shielded VM (secure boot + vTPM + integrity monitoring), `sa-gateway`, tags `iap-ssh`, `iii-engine`, `http-server`
- [ ] `inference-vm`: e2-standard-4, Ubuntu 22.04 LTS minimal, private subnet, **no_external_ip = true**, Shielded VM, `sa-inference`, tags `iap-ssh`
- [ ] Both: pd-balanced 30 GB boot disk, automatic OS patch management on, **CMEK-ready** (use Google-managed for now, write code path for CMEK)
- [ ] `metadata_startup_script` runs `cloud-init` that pulls a versioned tarball of the app from a GCS bucket (so VM replacement is trivial)

**2.2 Application packaging**
- [ ] CI step packages `quickstart/` + systemd units into `app-${git_sha}.tar.gz`, uploads to private GCS
- [ ] cloud-init on VM: download tarball → `/opt/alchemyst/` → install deps → enable systemd units

**2.3 systemd units (exact content)**

`systemd/iii-engine.service`:
```ini
[Unit]
Description=iii Engine
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=alchemyst
Group=alchemyst
WorkingDirectory=/opt/alchemyst
Environment="III_ENGINE_HOST=0.0.0.0"
Environment="III_ENGINE_PORT=49134"
ExecStart=/usr/local/bin/iii engine start --config /opt/alchemyst/config.yaml
Restart=always
RestartSec=3
StartLimitBurst=10
StandardOutput=journal
StandardError=journal
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

`systemd/caller-worker.service`:
```ini
[Unit]
Description=iii Caller Worker (HTTP gateway)
After=iii-engine.service
Requires=iii-engine.service

[Service]
Type=simple
User=alchemyst
WorkingDirectory=/opt/alchemyst/quickstart/workers/caller-worker
Environment="III_ENGINE_URL=ws://127.0.0.1:49134"
ExecStart=/usr/bin/bun run start
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

`systemd/inference-worker.service` (deployed to inference-vm):
```ini
[Unit]
Description=iii Inference Worker (Gemma 3 270M)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=alchemyst
WorkingDirectory=/opt/alchemyst/quickstart/workers/inference-worker
Environment="III_ENGINE_URL=ws://10.10.1.10:49134"   # static internal IP of gateway-vm
Environment="HF_HOME=/opt/alchemyst/.cache/huggingface"
ExecStart=/usr/bin/python3 main.py
Restart=always
RestartSec=5
LimitNOFILE=65536
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
```

**2.4 `modules/lb/`**
- [ ] External HTTPS LB → instance group containing `gateway-vm`
- [ ] Google-managed SSL cert (requires owned domain; if none, use self-signed + document tradeoff)
- [ ] Cloud Armor policy: rate limit 100 req/min/IP, OWASP CRS rule preview mode, geo-block none (open API)
- [ ] HTTP→HTTPS redirect
- [ ] Backend health check on `GET /healthz` (add this endpoint to caller-worker if missing)

**2.5 `modules/observability/`**
- [ ] Log sink: VM journald → Cloud Logging (structured)
- [ ] Custom metric: `inference_latency_ms` exported from caller-worker
- [ ] Dashboard: 4 panels — request rate, p50/p95/p99 latency, 5xx rate, VM CPU/mem
- [ ] Alert policies: p99 > 2s for 5 min; 5xx rate > 1%; VM unreachable

**Exit gate:** `terraform apply` → wait 3 minutes → public curl returns Gemma response.

---

### Phase 3 — Validation & Testing (2 hrs) — Day 2 Afternoon

**3.1 Smoke test** (`scripts/smoke-test.sh`)
```bash
#!/usr/bin/env bash
set -euo pipefail
API_URL="$(terraform -chdir=terraform output -raw api_url)"
RESPONSE=$(curl -fsS -X POST "${API_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Say hi in 5 words."}]}')
echo "${RESPONSE}" | jq -e '.choices[0].message.content' >/dev/null
echo "✅ Smoke test passed"
```

**3.2 Isolation test** (`scripts/verify-isolation.sh`)
- [ ] Resolve `inference-vm` internal IP via `gcloud compute instances describe`
- [ ] Confirm no external IP assigned
- [ ] From outside GCP, `nc -zv <internal-ip> 22` → must fail
- [ ] From outside GCP, `nc -zv <gateway-public-ip> 49134` → must fail (firewalled)
- [ ] From outside GCP, `nc -zv <gateway-public-ip> 443` → must succeed

**3.3 Load test** (`scripts/load-test.js` for k6)
- [ ] 50 VUs, 60s ramp, hit `/v1/chat/completions`
- [ ] Capture p50/p95/p99 → paste into `docs/COST.md`

**3.4 Chaos test** (`scripts/chaos-test.sh`)
- [ ] SSH to inference-vm via IAP
- [ ] `sudo systemctl stop inference-worker`
- [ ] Curl API → expect 503 with clean error
- [ ] `sudo systemctl start inference-worker`
- [ ] Curl API within 10s → expect 200 (proves auto-reconnect)

**3.5 Reproducibility test (THE big one)**
- [ ] `terraform destroy -auto-approve`
- [ ] On a freshly-created sibling GCP project: `make bootstrap && make deploy`
- [ ] Smoke test passes within 8 minutes of `apply` completion
- [ ] Record this in a `make demo` Asciinema cast and embed in README

**Exit gate:** all five tests green. Recordings committed.

---

### Phase 4 — Documentation (4 hrs) — Day 2 Evening

The README is the document that gets you the offer. Other candidates will write a paragraph. We write a doc.

**4.1 `README.md` structure**
1. One-paragraph "what this is"
2. Architecture diagram (PNG + mermaid)
3. **Deploy in 3 commands** (with copy-paste blocks)
4. Sample curl + sample response (real values from our test)
5. Smoke test command
6. Tear down
7. Project layout (the tree from §2)
8. Design decisions table → links to ADRs
9. Cost estimate (infracost output)
10. Roadmap / what would change at 100x
11. Author + contact

**4.2 `docs/architecture.md`**
- Mermaid component diagram
- Mermaid sequence diagram
- Component responsibilities table
- Failure-mode analysis (what dies if X happens)

**4.3 `docs/SECURITY.md`**
- Threat model (STRIDE one-liner per category)
- Hardening checklist (CIS-aligned)
- Tested controls (link to `verify-isolation.sh`)
- Known gaps + how to close (CMEK, VPC SC, private LB, Workload Identity Federation for CI)

**4.4 `docs/SCALING.md`** — *the section that closes the offer*

Outline:
1. **Define 100x.** Today: gemma-3-270m at ~50–200ms/request, single VM, ~5 req/s sustained. 100x means either (a) 100x bigger model (e.g. 27B class) at same throughput, or (b) same model at 500 req/s sustained, or (c) both.
2. **(a) 100x bigger model:**
   - Move from CPU to GPU. T4 (16 GB) handles 7B Q4; L4 (24 GB) handles 13B; A100 80 GB handles 27B FP16 or 70B Q4.
   - Switch runtime: `transformers` → **vLLM** (PagedAttention, continuous batching) as default, **TensorRT-LLM** (NVIDIA-compiled kernels, 20–40% throughput uplift) when the model is fixed.
   - Quantization tradeoffs: Q4 (4-bit) cuts VRAM 4× with <2% quality loss on benchmarks; Q8 is the safe middle ground.
3. **(b) 100x throughput:**
   - Replace single VM with **Managed Instance Group** behind **internal HTTP LB**, autoscaled on `inference_latency_ms` or GPU utilization.
   - Adopt **continuous batching** (vLLM default) — single biggest throughput multiplier.
   - At >50 req/s steady, move from MIG to **GKE Autopilot** with **NVIDIA Triton Inference Server** wrapping vLLM/TRT-LLM backends (gives multi-model, dynamic batching, gRPC + HTTP, Prometheus metrics).
   - At >500 req/s or multi-tenant: **NVIDIA Dynamo** for disaggregated prefill/decode, KV-cache-aware routing, multi-node tensor parallelism.
4. **Cross-cutting at 100x:**
   - Speculative decoding (small draft model + big verifier) → ~2× latency win
   - KV-cache offload to CPU/disk for long-context workloads
   - Multi-region with Global LB for geo-latency
   - Cost discipline: spot/preemptible GPU pools for non-latency-sensitive batch; reserved instances for hot path
   - Observability: per-request token counts, time-to-first-token (TTFT), time-per-output-token (TPOT) — not just request latency
5. **What stays the same:** the iii framework's worker abstraction lets us swap inference-worker implementations (Python transformers → vLLM → Triton client) without touching the caller. That's the architectural payoff of going through this RPC layer instead of an in-process call.

**4.5 `docs/RUNBOOK.md`**
- How to SSH (`gcloud compute ssh <vm> --tunnel-through-iap`)
- How to tail logs (`journalctl -fu inference-worker`)
- How to redeploy app without rebuilding infra (`make deploy-app`)
- How to roll back (`terraform apply -var=app_version=<old_sha>`)
- How to rotate model
- How to debug "API returns 502"

**4.6 `docs/COST.md`**
- Run `infracost breakdown` → paste table
- Monthly estimate: gateway-vm e2-small (~$13) + inference-vm e2-standard-4 (~$98) + NAT (~$32) + LB (~$18) + storage (~$2) = **~$163/mo**
- Free-tier offset: $300 credit lasts ~60 days
- Optimization knobs: preemptible inference VM, smaller machine when cold, scale-to-zero via Cloud Run (with cold-start tradeoff)

**4.7 ADRs (1 page each, MADR format)**
- 0001 cloud-provider: GCP — *Context, Decision, Consequences*
- 0002 iac-tool: Terraform
- 0003 network-topology: public+private+NAT
- 0004 ssh-access: IAP TCP forwarding
- 0005 engine-placement: co-located on gateway
- 0006 runtime: systemd (with note on when to migrate to k8s)

**Exit gate:** A stranger can deploy from scratch by reading only the README.

---

### Phase 5 — CI/CD & Polish (2 hrs) — Day 3 Morning

**5.1 `.github/workflows/terraform-ci.yml`**
- On PR to main:
  - `terraform fmt -check -recursive`
  - `terraform validate`
  - `tflint --recursive`
  - `tfsec .` (fail on HIGH+)
  - `checkov -d terraform/`
  - `infracost breakdown` posted as PR comment
- On push to main:
  - `terraform plan` against real state, commented to commit

**5.2 Repo hygiene**
- [ ] Conventional Commits in history (squash early WIP if needed)
- [ ] `LICENSE` (MIT)
- [ ] `.gitignore` covers `.terraform/`, `*.tfstate*`, `*.tfvars`, `.env`
- [ ] Tag a release `v1.0.0` once smoke test passes on fresh project
- [ ] Add badges to README: CI status, license, infracost

**5.3 Submission package**
- [ ] Final repo push
- [ ] Asciinema cast of `make demo` (60–90s) → upload, link in README
- [ ] One-page PDF "executive summary" attached to the email (architecture + outcomes)
- [ ] Draft submission email (template below)

**Exit gate:** repo is public-grade, no `TODO`s, CI green, demo recording linked.

---

## 4. Day-by-Day Schedule

| Day | Block | Work | Hours |
|-----|-------|------|-------|
| **Wed May 20** | AM | Phase 0: discovery + local run + tooling | 3 |
|  | PM | Phase 1: network module + IAM | 3 |
|  | Evening | Buffer / start Phase 2 | 1 |
| **Thu May 21** | AM | Phase 2: compute + app deploy | 5 |
|  | PM | Phase 3: all five validation tests | 2 |
|  | Evening | Phase 4: README + ADRs + scaling writeup | 4 |
| **Fri May 22** | AM | Phase 5: CI, polish, demo recording | 2 |
|  | PM | Final reproducibility run on fresh project | 1 |
|  | EOD | **Submit** | — |

**Total budgeted:** 21 hrs. **Buffer:** ~6 hrs for the inevitable. **Ship date:** May 22 evening (one day early — signals high agency).

---

## 5. Submission Email Template

```
To:   anuran@getalchemystai.com
Cc:   saumitra@getalchemystai.com, khushi@getalchemystai.com
Subject: DevOps Internship Assignment — Pulkit Saraf

Hi Anuran,

Submitting the Cloud Cartographer assignment.

Repo:    https://github.com/Pulkit7070/alchemyst-cloud-cartographer
Demo:    https://asciinema.org/a/<id>   (90 sec, fresh-account deploy)
Summary: https://github.com/.../blob/main/docs/executive-summary.pdf

A few notes on what I optimized for:

1. Reproducibility — the `make demo` flow goes from zero to a working
   public API on a fresh GCP project in ~8 minutes, all via Terraform
   + cloud-init. No manual steps after `gcloud auth`.

2. Defense in depth — inference VM has no public IP, SSH is IAP-only,
   firewall is deny-by-default, Cloud Armor sits in front of the API,
   VPC Flow Logs + Audit Logs are on. scripts/verify-isolation.sh
   proves the private VM is unreachable from the internet.

3. Scaling honestly — docs/SCALING.md walks through what changes at
   100x (vLLM/TensorRT-LLM/Triton/Dynamo, continuous batching,
   speculative decoding) and what stays the same (the iii RPC layer
   is the right abstraction; we'd swap worker implementations, not
   the topology).

Quick context on me: full-stack engineer at ArmorIQ (currently on GCP),
prior work on agent-based inference at Rabbit AI and a Rust KV store
with WAL/B-tree. Excited about this role because the infra-as-product
mindset at Alchemyst is what I want to spend the next few years on.

Happy to walk through any decision live.

— Pulkit
pulkitsaraf.dev@gmail.com · github.com/Pulkit7070
```

---

## 6. Compensation Strategy

**Anchor:** ₹50K/mo, remote-first.

**Justification you'll lead with (if asked):**
- Currently at ArmorIQ on ₹25K — won't take a lateral
- Submission quality demonstrates senior-intern level output
- GCP production experience + agentic systems background (Rabbit AI) — both directly relevant to Alchemyst's stack
- Their last public revenue figure is $1.9M ARR with 25 employees — ₹50K is within their band
- "Salary is no bar" is their language — taking them at their word

**Negotiation floor:** ₹40K. Below that, the deal isn't worth the context-switch from ArmorIQ.

**Ask order in the conversation:**
1. Confirm remote-first
2. Stipend ₹50K
3. Conversion path (intern → FTE) and what compensation looks like at conversion
4. Decision-making autonomy on infra choices

---

## 7. Risks & Mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| iii framework has undocumented behaviors that break in cloud | Medium | Phase 0.2 — get it working locally first, before touching cloud |
| GCP $300 credit insufficient if I leave VMs running | Low | `terraform destroy` between sessions; cost tracking in Phase 4.6 |
| Managed SSL cert needs a domain | Medium | Use nip.io wildcard or self-signed + document; or buy a $1 .xyz domain |
| Cloud Armor / LB add complexity | Medium | Implement them last (Phase 2.4); ship without them if blocked, document as roadmap |
| Reproducibility test fails on a new project | Medium-High | Build the second project from day 1 alongside the first; don't leave to Day 3 |
| Pre-commit / CI tooling rabbit hole | Medium | Time-box Phase 5.1 to 90 min; ship without CI if needed |

---

## 8. Definition of Done (final checklist before sending the email)

- [ ] `terraform destroy && terraform apply` on a brand-new GCP project produces a working API
- [ ] `scripts/smoke-test.sh` exits 0
- [ ] `scripts/verify-isolation.sh` exits 0 (inference VM unreachable from internet)
- [ ] `scripts/chaos-test.sh` exits 0 (worker auto-recovers)
- [ ] `scripts/load-test.js` produces p99 numbers committed to `docs/COST.md`
- [ ] CI green on main branch
- [ ] `infracost breakdown` committed
- [ ] README has architecture diagram, deploy commands, sample curl + response
- [ ] All 6 ADRs written
- [ ] SCALING.md cites vLLM, TensorRT-LLM, Triton, Dynamo with reasoning
- [ ] RUNBOOK.md covers SSH, logs, redeploy, rollback
- [ ] Asciinema cast recorded and linked
- [ ] Executive summary PDF generated
- [ ] Email drafted with all three recipients
- [ ] Submitted by Friday May 22 EOD
