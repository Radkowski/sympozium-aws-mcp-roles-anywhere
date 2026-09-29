# AWS MCP over IAM Roles Anywhere

A self-contained bundle that gives a **Sympozium agent** access to the managed
**AWS MCP Server** — authenticated with **temporary AWS credentials from IAM
Roles Anywhere**, so a workload running outside AWS (e.g. on Kubernetes at a
non-AWS provider) needs **no static AWS keys**.

- **What the agent gets:** the AWS MCP tools, chiefly `aws___run_script` (a
  sandboxed boto3 environment covering 300+ AWS services), plus documentation
  and discovery tools. This lets the agent inspect/operate the AWS account.
- **How it authenticates:** a workload X.509 certificate → `aws_signing_helper`
  → IAM Roles Anywhere → short-lived STS credentials → SigV4-signed calls to the
  AWS MCP endpoint.
- **How access is bounded:** by the **IAM role** the certificate assumes (e.g.
  `ViewOnlyAccess` for read-only inventory). The role — not a client flag — is
  the real security boundary.

---

## How it works

```
agent (Sympozium)
   │  MCP tool calls
   ▼
mcp-bridge (Sympozium sidecar)  ── stdio ──►  our container:
                                                mcp-proxy-for-aws-cli
                                                   │  needs AWS creds to sign SigV4
                                                   ▼
                                                AWS SDK credential chain
                                                   │  credential_process
                                                   ▼
                                                aws_signing_helper
                                                   │  presents workload cert
                                                   ▼
                                                IAM Roles Anywhere ──► short-lived STS creds
                                                   │
                                                   ▼
                                    SigV4-signed HTTPS ──► https://aws-mcp.<region>.api.aws/mcp
                                                   │
                                                   ▼
                                                real AWS APIs (bounded by the IAM role)
```

Key points:

- **One container, not two.** The proxy and the credential helper live in the
  **same** container. The proxy's AWS SDK invokes the helper via
  `credential_process`; credentials are obtained on demand and **auto-renewed**
  when they expire — no restarts, and they never touch disk or the agent.
- **Credentials never reach the model.** They stay inside the proxy container.
  MCP carries tool calls, not secrets.
- **Read-only is enforced by IAM.** `MCP_READ_ONLY=false` exposes
  `aws___run_script` (the proxy's `--read-only` flag would otherwise hide it,
  since it is annotated write-capable). The account is protected because the
  assumed role (e.g. `ViewOnlyAccess`) simply cannot perform writes — any write
  attempt returns `AccessDenied` at the AWS API layer.

---

## Contents

```
aws-mcp/
├── README.md                     ← this file (how it works)
├── INSTALL.ipynb                 ← every install step, from scratch (run this)
├── container/                    ← the MCP proxy + Roles Anywhere helper image
│   ├── Dockerfile                  pins mcp-proxy-for-aws-cli + aws_signing_helper (URL+SHA)
│   └── entrypoint.sh               builds the proxy command; guards HTTPS / static-creds / read-only
├── k8s/
│   └── mcpserver.yaml            ← Sympozium MCPServer template (REPLACE_* placeholders)
└── provisioning/
    ├── iam-roles-anywhere-lab.ipynb  creates CA+cert, trust anchor, profile, role in AWS
    ├── pyproject.toml / uv.lock      Python deps for the provisioning notebook
    └── .gitignore                    ignores work/ (cert, key, credentials — never commit)
```

---

## Prerequisites

- **AWS account** with permissions to create IAM roles/policies and IAM Roles
  Anywhere trust anchors/profiles. Configure access with `aws configure` /
  `aws sso login` before running the provisioning notebook.
- **Region:** the AWS MCP Server is offered only in **`us-east-1`** and
  **`eu-central-1`** (see the AWS General Reference). Create the Roles Anywhere
  resources in the same region you target.
- **A container registry** you can push to, and a Kubernetes cluster running
  Sympozium (with the `MCPServer` CRD). For a private registry, an
  `imagePullSecret` must already exist in the target namespace.
- **CLIs:** `podman` (or `docker`), `kubectl`, `aws`, plus `git`/`curl` for the
  provisioning notebook. Python 3 with `boto3` for that notebook's kernel.

---

## Install

Open **`INSTALL.ipynb`** and follow it top to bottom. In outline:

1. Set parameters (region, namespace, agent, registry, image tag).
2. Prerequisite checks — including **your cluster node architecture**.
3. Run `provisioning/iam-roles-anywhere-lab.ipynb` to create the AWS resources
   and issue the workload certificate.
4. Build the image **for the node architecture** (amd64 or arm64).
5. Push the image.
6. Create the `aws-mcp-certificate` Secret (cert + key).
7. Render and apply `k8s/mcpserver.yaml`; attach the pull Secret to the SA.
8. Attach the MCP server to your agent and run a read-only test.

---

## Operational notes

- **Pods inherit `imagePullSecrets` from the ServiceAccount only at creation.**
  After patching the SA, **delete the pod** so it is recreated with the secret.
- **`MCPServer` READY reflects pod readiness**, and `status.toolCount` may show
  empty even when tools work (a known controller cosmetic issue). Verify with a
  real call through the agent, not the status field.
- **Never commit the private key.** It lives under `provisioning/work/`, which is
  gitignored, and enters the cluster only as the `aws-mcp-certificate` Secret.

---

## Security notes

- The IAM role is the access boundary. Scope its permissions to the minimum the
  agent needs; `job-function/ViewOnlyAccess` gives read-only inventory (List/
  Describe) without object contents, `ReadOnlyAccess` is broader.
- For belt-and-suspenders you can additionally constrain the role's trust/permission
  policy with the `aws:CalledViaAWSMCP` / `aws:ViaAWSMCPService` context keys, so
  that calls made *through* the AWS MCP service are limited independently of the
  role's own breadth.
- Certificate rotation is separate from credential renewal: after replacing the
  workload certificate, the next credential acquisition uses it (or restart the
  MCP Deployment). Keep the CA private key outside the cluster.
