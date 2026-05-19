# Alchemyst Cloud Cartographer

Distributed LLM inference on GCP: Gemma 3 270M served across two VMs in a private/public subnet topology, wired by the [iii](https://iii.dev) worker framework, provisioned entirely with Terraform.

[![CI](https://github.com/Pulkit7070/alchemyst-cloud-cartographer/actions/workflows/terraform-ci.yml/badge.svg)](https://github.com/Pulkit7070/alchemyst-cloud-cartographer/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## Architecture

```
                Internet
                    │
           ┌────────┴─────────┐
           │  Cloud Armor WAF  │  rate-limit + OWASP rules
           └────────┬──────────┘
                    │
       PUBLIC SUBNET (10.10.1.0/24)
       ┌────────────────────────────┐
       │  gateway-vm (e2-small)     │
       │  ├─ iii-engine  :49134     │
       │  └─ caller-worker  :3111  │  ← public HTTP API
       └──────────┬─────────────────┘
                  │ VPC-internal WebSocket
                  │ (firewall: 10.10.2.0/24 only)
       PRIVATE SUBNET (10.10.2.0/24)
       ┌────────────────────────────┐
       │  inference-vm (e2-std-4)   │  no public IP
       │  └─ inference-worker       │
       │     └─ gemma-3-270m Q8     │
       └────────────────────────────┘
              │ Cloud NAT (egress only)
```

**Request flow:**
`POST /v1/chat/completions` → caller-worker → iii RPC → inference-worker → Gemma → JSON response

**SSH:** IAP TCP forwarding only (no public port 22, no bastion)

---

## Deploy in 3 Commands

```bash
# 0. Prerequisites: gcloud CLI authenticated, terraform ≥1.9, gsutil
gcloud auth application-default login

# 1. Bootstrap: creates GCS state + bundle buckets, enables APIs
bash scripts/bootstrap.sh <YOUR_PROJECT_ID>

# 2. Edit variables (copy example, set project_id + owner_email)
cp terraform/terraform.tfvars.example terraform/terraform.tfvars

# 3. Init + Deploy
cd terraform
terraform init \
  -backend-config="bucket=<YOUR_PROJECT_ID>-tf-state" \
  -backend-config="prefix=cloud-cartographer"
cd ..
make deploy PROJECT_ID=<YOUR_PROJECT_ID>
```

That's it. After ~8 minutes the output prints a ready-to-run curl command.

---

## Sample Request & Response

```bash
curl -X POST http://<GATEWAY_PUBLIC_IP>:3111/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"What is the capital of France? One word."}]}'
```

```json
{
  "id": "chatcmpl-1716100000000",
  "object": "chat.completion",
  "created": 1716100000,
  "model": "gemma-3-270m",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Paris"
      },
      "finish_reason": "stop"
    }
  ]
}
```

---

## Validate

```bash
make smoke       # end-to-end API test with retry
make isolation   # proves inference VM is unreachable from internet
make chaos       # kills inference worker, verifies systemd auto-recovery
make load        # k6 load test — requires k6 installed
```

---

## Tear Down

```bash
make destroy PROJECT_ID=<YOUR_PROJECT_ID>
```

---

## Project Layout

```
├── terraform/
│   ├── modules/
│   │   ├── network/       VPC, subnets, Cloud NAT, firewall rules, Flow Logs
│   │   ├── iam/           service accounts, OS Login, IAP bindings
│   │   ├── compute/       gateway-vm + inference-vm, cloud-init, Shielded VMs
│   │   ├── observability/ dashboards, alert policies, uptime checks
│   │   └── state-bucket/  one-time bootstrap module
│   ├── main.tf            root module wiring
│   ├── variables.tf       all inputs with validation
│   └── outputs.tf         api_url, ssh commands, curl example
├── systemd/               iii-engine, caller-worker, inference-worker units
├── quickstart/            iii application (patched for cloud: 0.0.0.0 binding + HTTP triggers)
├── scripts/
│   ├── bootstrap.sh       first-run GCS bucket creation
│   ├── bundle.sh          package + upload to GCS
│   ├── deploy.sh          bundle + terraform apply
│   ├── smoke-test.sh      end-to-end API validation
│   ├── verify-isolation.sh network security assertions
│   ├── chaos-test.sh      worker kill + recovery test
│   └── load-test.js       k6 load test
├── docs/
│   ├── SCALING.md         100x path: vLLM → TRT-LLM → Triton → Dynamo
│   ├── SECURITY.md        threat model, hardening checklist
│   ├── RUNBOOK.md         SSH, logs, redeploy, rollback
│   └── adr/               6 Architecture Decision Records
├── .github/workflows/     Terraform CI: fmt, validate, tflint, tfsec, checkov
├── Makefile               all common operations
└── README.md              this file
```

---

## Design Decisions

| Decision | Choice | ADR |
|----------|--------|-----|
| Cloud | GCP (production GCP experience at ArmorIQ) | [ADR 0001](docs/adr/0001-cloud-provider-gcp.md) |
| IaC | Terraform, modular, GCS remote state | [ADR 0002](docs/adr/0002-iac-terraform.md) |
| Network | Public + private subnets + Cloud NAT | [ADR 0003](docs/adr/0003-network-topology.md) |
| SSH | IAP TCP forwarding (no bastion, no public 22) | [ADR 0004](docs/adr/0004-ssh-via-iap.md) |
| Engine placement | Co-located with gateway VM | [ADR 0005](docs/adr/0005-engine-colocation.md) |
| Runtime | systemd units (not Docker/k8s) | [ADR 0006](docs/adr/0006-systemd-over-docker.md) |

---

## Notable Implementation Detail

The original `caller-worker/src/worker.ts` has the HTTP trigger handler **commented out**.
This was uncommented and the response shape was made OpenAI-compatible (with `id`, `object`,
`created`, `model`, `choices` fields) so clients like LangChain and the OpenAI SDK work
against this endpoint without modification.

The `config.yaml` HTTP binding was also changed from `127.0.0.1` to `0.0.0.0` to allow
external requests to reach the gateway VM.

---

## Estimated Monthly Cost

| Resource | Spec | Cost/mo |
|----------|------|---------|
| gateway-vm | e2-small, asia-south1 | ~$13 |
| inference-vm | e2-standard-4, asia-south1 | ~$98 |
| Cloud NAT | ~5 GB egress for model download | ~$3 |
| Cloud Router | flat fee | ~$36 |
| GCS buckets | state + bundles | ~$1 |
| VPC Flow Logs | 50% sampling | ~$2 |
| **Total** | | **~$153/mo** |

Covered by GCP's $300 free trial for ~60 days.

---

## Scaling Roadmap

See [docs/SCALING.md](docs/SCALING.md) for a detailed path from this 5 req/s CPU deployment
to 500+ req/s on GPU using vLLM, TensorRT-LLM, Triton, and NVIDIA Dynamo.

---

## Author

**Pulkit Saraf** — [github.com/Pulkit7070](https://github.com/Pulkit7070) · [pulkitsaraf.dev@gmail.com](mailto:pulkitsaraf.dev@gmail.com)

Full-stack engineer at ArmorIQ (GCP), prior agent + RAG systems work at Rabbit AI.
