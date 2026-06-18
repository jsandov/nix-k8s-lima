# nix-k8s-lima AI Gateway MVP — Implementation Report

**Audience:** the flake owner (jsandov) implementing the PRD "Claude Code → local Envoy AI Gateway → Anthropic" MVP on the `nix-k8s-lima` flake.
**Date:** 2026-06-18. **Status:** decision-grade. All three linchpin claims **confirmed** by adversarial verification, with two required corrections (kind node-image pin; `ANTHROPIC_BASE_URL` path prefix).

---

## 1. Executive summary + recommended architecture

Build the MVP on a **kind** cluster (already bundled in the flake [F1]) running a **pinned** Kubernetes node image, install **Envoy Gateway v1.8.1** then layer **Envoy AI Gateway v0.7.0** on top via OCI Helm charts, and route Claude Code at it through `kubectl port-forward`. The decisive finding — **confirmed against primary sources** — is that Envoy AI Gateway **natively supports Anthropic as a first-party provider** (schema enum `Anthropic`, `BackendSecurityPolicy` type `AnthropicAPIKey`, native `POST /anthropic/v1/messages` with streaming + extended thinking) [1][2][3], so you get the full PRD value (native GenAI token metrics, gateway-side key injection, QuotaPolicy budgets) rather than a degraded OpenAI-translation shim. The one runtime gotcha is that the native endpoint is path-prefixed at `/anthropic/v1/messages`, while Claude Code appends `/v1/messages` to `ANTHROPIC_BASE_URL` — resolved trivially by setting `ANTHROPIC_BASE_URL=http://localhost:8888/anthropic` [4][5]. Package this by mirroring the flake's existing `rke2-*` `writeShellApplication` pattern into a new `ai-gw-*` script family, vendoring manifests as in-repo assets under `manifests/ai-gateway/`, pinning chart versions literally, and moving `helm` from Homebrew to nixpkgs (`pkgs.kubernetes-helm`) [F2][14].

```
┌──────────────┐  ANTHROPIC_BASE_URL=                    ┌──────────────── kind cluster (k8s v1.35.5) ─────────────────┐
│  Claude Code │  http://localhost:8888/anthropic        │                                                              │
│   (your Mac) │  ANTHROPIC_API_KEY=<placeholder>        │  ns: envoy-gateway-system        ns: envoy-ai-gateway-sys   │
│              │ ──POST /v1/messages──┐                   │  ┌─────────────────────┐         ┌───────────────────────┐  │
└──────────────┘                      │                   │  │ Envoy Gateway ctrl  │         │ ai-gateway-controller │  │
                                      ▼                   │  └─────────┬───────────┘         └───────────┬───────────┘  │
                          kubectl port-forward            │            │ programs                       │ reconciles    │
                          svc/<envoy-...> 8888:80 ────────┼──────►┌────▼─────────────────────────────────▼──────────┐  │
                                                          │       │  Envoy data-plane proxy (Service, ClusterIP)     │  │
                                                          │       │  AIGatewayRoute → AIServiceBackend(Anthropic)    │  │
                                                          │       │  + BackendSecurityPolicy(AnthropicAPIKey secret) │  │
                                                          │       └──────────────────────┬───────────────────────────┘  │
                                                          └──────────────────────────────┼──────────────────────────────┘
                                                            gateway injects REAL sk-ant   │ TLS (SNI api.anthropic.com)
                                                            key, dials :443               ▼
                                                                              ┌──────────────────────┐
                                                                              │  api.anthropic.com    │
                                                                              └──────────────────────┘
```

The real `sk-ant-…` key lives only in a cluster Secret (injected upstream by the gateway [3][6]); the developer shell holds a placeholder. That secret/injection point is the natural home for the future FR7 token-budget/allowlist enforcement.

---

## 2. Linchpin verdicts

### V1 — "Envoy AI Gateway natively routes to Anthropic (`/v1/messages` at `api.anthropic.com`)" → **CONFIRMED**

- Native first-party provider since **v0.4.0** (Nov 2025): "Native integration with Anthropic's API at api.anthropic.com" + "Native x-api-key header-based authentication" — not an OpenAI shim [1].
- Schema abstraction is real: `examples/basic/anthropic.yaml` defines `AIServiceBackend` with `spec.schema.name: Anthropic`, a `Backend` with fqdn `api.anthropic.com:443`, and a `BackendSecurityPolicy` type `AnthropicAPIKey` [2].
- Native Messages API end-to-end: `POST /anthropic/v1/messages` is **"Fully Supported"** including streaming and extended thinking [3].
- **Corrected fact / caveat (non-fatal):** the native route is path-prefixed `/anthropic/v1/messages`, NOT bare `/v1/messages`. Because Claude Code appends `/v1/messages` to `ANTHROPIC_BASE_URL` [5], setting the base URL to `http://localhost:8888/anthropic` produces exactly the native route. The gateway must also forward `anthropic-version` and `anthropic-beta` headers (Anthropic's stated hard requirement) and ideally serve `/v1/messages/count_tokens` [4][5].
- **Consequence:** the PRD's chosen architecture stands. FR1–FR6 are satisfiable with the native provider, giving GenAI token metrics + gateway key injection + QuotaPolicy for free. **If it had been refuted**, the fallback would be a plain Envoy Gateway `HTTPRoute` passthrough to `api.anthropic.com` (still satisfies bare routing FR3/FR5) but you would **lose** native token metrics, `BackendSecurityPolicy` injection, and `QuotaPolicy` — gutting FR6/FR7's reason to pick AI Gateway over plain Envoy. **The fallback is documented in §4 anyway** as the M0 smoke-test path and a safety net.

### V2 — "Version-compat matrix (AI-GW v0.7.0 + EG v1.8.1 + Gateway API v1.5.1 + kind/k8s) installs together" → **CONFIRMED, with one required correction**

- Two independently-authored official tables agree on every shared dimension: AI Gateway compat matrix pins v0.7.x → EG v1.8.x+ / Gateway API v1.5.x / Envoy v1.38.x / k8s v1.32+ [7]; the EG release matrix independently confirms the v1.8 line bundles Gateway API v1.5.1 + Envoy distroless-v1.38.0 and supports k8s v1.32–v1.35 [8]. No transitive skew.
- **Correction (load-bearing):** **do NOT use kind's default node image.** kind v0.32.0 defaults to **k8s v1.36.1**, which is **above** EG v1.8's supported ceiling (v1.35) [9]. Pin a supported image — `kindest/node:v1.35.5` (also v1.34.8 / v1.33.12), all within range and arm64-capable [9].
- **Note on the AI-GW↔EG floor discrepancy:** the v0.7 release notes mention an EG **1.7** baseline while the current prerequisites/compat docs say EG **1.8.1+** [7][10]. The compat matrix [7] (which post-dates the release notes) is authoritative for the pinned pair; install **EG v1.8.1 with AI-GW v0.7.0**.
- **Consequence:** verified stack = **AI-GW v0.7.0 → EG v1.8.1 (Gateway API v1.5.1 + Envoy v1.38.0) → k8s v1.35.5 on kind v0.32.0.** Letting kind pick its default silently runs an untested k8s version (reproducibility/FR risk), so the node image **must** be pinned in the checked-in kind config.

### V3 — "`ANTHROPIC_BASE_URL=http://localhost:8080` (+ key) routes Claude Code through the gateway incl. interactive" → **CONFIRMED, corrected**

- Claude Code appends `/v1/messages` to the base URL, works over plaintext HTTP to localhost (no TLS to the local gateway), and works interactively (one-time key approval for a non-subscription key; `-p` one-shot skips the prompt) [5][11].
- `ANTHROPIC_API_KEY` → `x-api-key` header; `ANTHROPIC_AUTH_TOKEN` → `Authorization: Bearer` (the latter wins if both set) [11].
- **Corrected fact:** the base URL **must include `/anthropic`** for the stock gateway (`http://localhost:8888/anthropic`), else every request 404s. Trailing-slash mismatches also 404 — make the route prefix-robust [4][12].
- **Consequence:** a naive `http://localhost:8080` produces a 404 on every call despite "correct" env vars — a silent non-functional MVP. This single line is the highest-risk integration detail and is called out in §4 and §8.

---

## 3. Version / compatibility matrix (pinned)

| Component | Pinned version | Source of pin | Notes |
|---|---|---|---|
| **Envoy AI Gateway** | **v0.7.0** (rel. 2026-06-04) | [13][7] | Native Anthropic since v0.4.0; v1.0 targeted end-June 2026. Pin the tag, **never** `v0.0.0-latest` [14]. |
| **Envoy Gateway** | **v1.8.1** (rel. ~2026-06-04/05) | [8][15] | v1.8 line; EOL 2026-11-08. Default chart bundles Gateway API + EG CRDs [15]. |
| **Gateway API** | **v1.5.1** (bundled) | [8] | Comes with EG v1.8.1 chart — no separate CRD install on the default path [15]. |
| **Envoy Proxy** | distroless-v1.38.0 (bundled) | [8] | Transitive via EG v1.8.1. |
| **kind** | **v0.32.0** | [9] | Already a candidate via `pkgs.kind` [F1]. |
| **Kubernetes (node image)** | **`kindest/node:v1.35.5`** (digest-pinned) | [9] | **NOT** kind's default v1.36.1 (above EG ceiling). amd64+arm64. |
| **Helm** | nixpkgs `kubernetes-helm` | [14][F2] | Move off Homebrew (see §5). Helm ≥3.x pulls OCI charts. |
| **CRD API group** | `aigateway.envoyproxy.io/v1beta1` (preferred), `v1alpha1` | [1][2] | Backend CRD is `gateway.envoyproxy.io/v1alpha1`; BackendTLSPolicy is `gateway.networking.k8s.io/v1alpha3`. |

Helm OCI sources: `oci://docker.io/envoyproxy/gateway-helm`, `oci://docker.io/envoyproxy/ai-gateway-crds-helm`, `oci://docker.io/envoyproxy/ai-gateway-helm` [14][15].

---

## 4. Step-by-step MVP install + verify, mapped to FR1–FR6

> Run with `KUBECONFIG` set to the kind cluster. Namespaces: `envoy-gateway-system`, `envoy-ai-gateway-system`, and `default` (route/backend/secret).

### FR1 — kind cluster (pinned node image)

`kind-cluster.yaml` (checked into `manifests/ai-gateway/`):
```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ai-gw
nodes:
  - role: control-plane
    image: kindest/node:v1.35.5@sha256:<digest-for-v1.35.5>   # pin digest; NOT default v1.36.1
```
```bash
kind create cluster --config manifests/ai-gateway/kind-cluster.yaml
```

### FR2 — install gateways (Helm + CRDs)

```bash
# Envoy Gateway (bundles Gateway API v1.5.1 + EG CRDs — no separate CRD step)
helm install eg oci://docker.io/envoyproxy/gateway-helm --version v1.8.1 \
  -n envoy-gateway-system --create-namespace
kubectl wait --timeout=5m -n envoy-gateway-system deployment/envoy-gateway \
  --for=condition=Available

# Envoy AI Gateway — CRDs chart THEN controller chart, pinned to v0.7.0
helm install aieg-crd oci://docker.io/envoyproxy/ai-gateway-crds-helm --version v0.7.0 \
  -n envoy-ai-gateway-system --create-namespace
helm install aieg oci://docker.io/envoyproxy/ai-gateway-helm --version v0.7.0 \
  -n envoy-ai-gateway-system
kubectl wait --timeout=2m -n envoy-ai-gateway-system deployment/ai-gateway-controller \
  --for=condition=Available
```
[14][15]

### FR3 — Anthropic route + backend (apply in-repo manifests)

Adapt `examples/basic/anthropic.yaml` [2]. Shape (`manifests/ai-gateway/anthropic.yaml`):

```yaml
# GatewayClass + Gateway (HTTP/80 listener; port-forward handles local access)
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata: { name: eg }
spec: { controllerName: gateway.envoyproxy.io/gatewayclass-controller }
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: { name: eg, namespace: default }
spec:
  gatewayClassName: eg
  listeners: [{ name: http, protocol: HTTP, port: 80 }]
---
apiVersion: aigateway.envoyproxy.io/v1beta1
kind: AIGatewayRoute
metadata: { name: anthropic-route, namespace: default }
spec:
  parentRefs: [{ name: eg, kind: Gateway, group: gateway.networking.k8s.io }]
  rules:
    - matches: [{ headers: [{ name: x-ai-eg-model, value: claude-sonnet-4-5 }] }]
      backendRefs: [{ name: anthropic-backend }]
---
apiVersion: aigateway.envoyproxy.io/v1beta1
kind: AIServiceBackend
metadata: { name: anthropic-backend, namespace: default }
spec:
  schema: { name: Anthropic }          # native first-party provider
  backendRef: { name: anthropic-fqdn, kind: Backend, group: gateway.envoyproxy.io }
---
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: Backend
metadata: { name: anthropic-fqdn, namespace: default }
spec:
  endpoints: [{ fqdn: { hostname: api.anthropic.com, port: 443 } }]
---
apiVersion: gateway.networking.k8s.io/v1alpha3
kind: BackendTLSPolicy
metadata: { name: anthropic-tls, namespace: default }
spec:
  targetRefs: [{ group: gateway.envoyproxy.io, kind: Backend, name: anthropic-fqdn }]
  validation:
    wellKnownCACertificates: System          # system CA trust to api.anthropic.com
    hostname: api.anthropic.com               # SNI
---
apiVersion: aigateway.envoyproxy.io/v1beta1
kind: BackendSecurityPolicy
metadata: { name: anthropic-auth, namespace: default }
spec:
  type: AnthropicAPIKey
  anthropicAPIKey: { secretRef: { name: anthropic-apikey } }
  targetRefs: [{ group: aigateway.envoyproxy.io, kind: AIServiceBackend, name: anthropic-backend }]
```
The real key lives only in the Secret (gateway injects it upstream [3][6]):
```bash
kubectl create secret generic anthropic-apikey -n default \
  --from-literal=apiKey="$REAL_SK_ANT_KEY"
kubectl apply -f manifests/ai-gateway/anthropic.yaml
```

> **Routing-header note (verify on Mac):** the AIGatewayRoute matches `x-ai-eg-model`, but Claude Code sends the model in the JSON **body**, not as a header. AI Gateway is documented to derive the route from `body.model`, but confirm empirically; if not, add `ANTHROPIC_CUSTOM_HEADERS="x-ai-eg-model: claude-sonnet-4-5"` [11] or a single catch-all rule (no header match) for the MVP.

**Fallback route (only if native is refuted on your version)** — plain `HTTPRoute` passthrough, no AI-GW CRDs:
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
spec:
  parentRefs: [{ name: eg }]
  rules:
    - matches: [{ path: { type: PathPrefix, value: /v1/messages } }]
      backendRefs: [{ name: anthropic-fqdn, group: gateway.envoyproxy.io, kind: Backend, port: 443 }]
```
This still satisfies FR1–FR5 (bare routing) but forfeits FR6 token metrics / FR7 enforcement — use only as a safety net.

### FR4 — port-forward to localhost

```bash
ENVOY_SVC=$(kubectl get svc -n envoy-gateway-system \
  --selector=gateway.envoyproxy.io/owning-gateway-namespace=default,gateway.envoyproxy.io/owning-gateway-name=eg \
  -o jsonpath='{.items[0].metadata.name}')
kubectl -n envoy-gateway-system port-forward "service/${ENVOY_SVC}" 8888:80
```
The data-plane Service is auto-created **in `envoy-gateway-system`** with a dynamic name; resolve via the owning-gateway selector, never hardcode [16][8].

### FR5 — point Claude Code at the gateway

```bash
export ANTHROPIC_BASE_URL=http://localhost:8888/anthropic   # /anthropic prefix is mandatory
export ANTHROPIC_API_KEY=placeholder-local-token            # real key is in the cluster Secret
```
[4][5][11]

### FR6 — verify (one-shot then interactive)

```bash
# One-shot (no interactive approval prompt):
ANTHROPIC_BASE_URL=http://localhost:8888/anthropic ANTHROPIC_API_KEY=placeholder \
  claude -p 'reply with the single word OK'

# Interactive (approve the non-subscription key once):
claude
```
Confirm traffic traversed the gateway via metrics (see §7). FR6 logging/metrics should not depend on the ephemeral port-forward process.

---

## 5. The Nix implementation plan on `nix-k8s-lima`

**Verified ground truth** (read from disk): flake is **darwin-only** (`systems = ["aarch64-darwin" "x86_64-darwin"]`, Lima is mac-only), uses `nixpkgs-25.05-darwin`, **no `flake.lock`**, has `lib.packages`/`lib.scripts` exports, `apps`/`packages`/`devShells` per-system, `toolset = buildEnv(packages.nix ++ attrValues scripts)`, `mkApp` wiring in `flake.nix` [F2]. `modules/scripts.nix` uses `mkScript = name: text: pkgs.writeShellApplication { runtimeInputs = [lima colima coreutils gnused]; }` and references assets via `${self}/lima/rke2-lima.yaml.tmpl` rendered with `sed` placeholder substitution. `pkgs.kind` is **already** in `modules/packages.nix`; **`helm` is sourced from Homebrew** (`modules/homebrew-brews.nix`), not nixpkgs. Manifests already live in-repo (`manifests/alpine-pod.yaml`) [F1].

### Decisions

1. **Move helm to nixpkgs.** Add `pkgs.kubernetes-helm` to `modules/packages.nix` so `nix run`/`nix shell` users get a version-pinned helm without Homebrew [14]. Remove `"helm"` from `homebrew-brews.nix` (or keep it commented as legacy) to avoid two helms on PATH.
2. **Mirror the `rke2-*` pattern** with a new `ai-gw-*` script family driving **kind + helm + kubectl** (not Lima/RKE2). Reuse the existing `pkgs.kind`.
3. **Vendor manifests as in-repo assets** under `manifests/ai-gateway/*.yaml`, referenced via `${self}` exactly like `rke2-lima.yaml.tmpl`. The `ai-gw-claude-env` placeholder remap (e.g. `@port@`) follows the existing `sed`-substitution convention.
4. **Pin chart versions literally** as `--version vX.Y.Z` in the scripts. This is "reproducible-enough" for the flake's no-lock/no-CI posture; document that helm pulls OCI at runtime (not hermetic). Heavier nixhelm/kubenix vendoring is overkill here.
5. **Stay darwin-only for now**, but add a **follow-up** to extend `systems` with `aarch64-linux`/`x86_64-linux` **for the kind-only `ai-gw-*` apps** (kind is cross-platform; Lima/RKE2 stays darwin-gated). This would also let CI validate the gateway flow. Gate so the Lima surface never evaluates on Linux.

### New flake apps

`ai-gw-up`, `ai-gw-down`, `ai-gw-status`, `ai-gw-logs`, `ai-gw-claude-env` — each registered in `flake.nix` `apps` via `mkApp` (they auto-join `toolset` through `attrValues scripts`).

- **`ai-gw-up`** — `kind create cluster --config ${self}/manifests/ai-gateway/kind-cluster.yaml` → `helm install eg …gateway-helm --version v1.8.1` → both AI-GW charts `--version v0.7.0` → `kubectl wait` → `kubectl apply -f ${self}/manifests/ai-gateway/anthropic.yaml` → resolve `$ENVOY_SVC` → `kubectl port-forward`.
- **`ai-gw-down`** — `kind delete cluster --name ai-gw`.
- **`ai-gw-status`** — `kubectl get pods,gateways,aigatewayroutes -A`.
- **`ai-gw-logs`** — `stern`/`kubectl logs` on `ai-gateway-controller` + the Envoy data-plane pod.
- **`ai-gw-claude-env`** — prints `export ANTHROPIC_BASE_URL=http://localhost:8888/anthropic` + `ANTHROPIC_API_KEY` guidance to stdout (eval-friendly, mirroring `rke2-kubeconfig`).

`runtimeInputs` for these = `[ kind kubectl kubernetes-helm coreutils gnused ]`. Add a parallel `mkScript` (or extend the existing one's `runtimeInputs`).

### Concrete file tree of additions

```
nix-k8s-lima/
├── flake.nix                          # EDIT: add ai-gw-{up,down,status,logs,claude-env} to `apps` via mkApp
├── modules/
│   ├── packages.nix                   # EDIT: + pkgs.kubernetes-helm
│   ├── homebrew-brews.nix             # EDIT: remove/comment "helm"
│   ├── scripts.nix                    # EDIT: + ai-gw-* mkScript derivations (kind/helm/kubectl runtimeInputs)
│   └── home-manager.nix               # EDIT (opt): surface ai-gw-* if it enumerates scripts
└── manifests/
    └── ai-gateway/                    # NEW assets, referenced via ${self}
        ├── kind-cluster.yaml          # pinned kindest/node:v1.35.5 (digest)
        ├── anthropic.yaml             # GatewayClass+Gateway+AIGatewayRoute+AIServiceBackend+Backend+BackendTLSPolicy+BackendSecurityPolicy
        └── README.md                  # secret creation + ANTHROPIC_BASE_URL contract (the /anthropic trap)
```

Also extend `k8s-help` with an "AI GATEWAY" section. No new flake inputs; no `flake.lock` introduced.

---

## 6. Resolving the PRD's 4 open questions

1. **kind vs minikube → kind.** kind is upstream-pure, arm64-capable, reproducible via digest-pinned node images + checked-in `v1alpha4` config, **already bundled** by the flake, and is what AI Gateway's own prerequisites doc documents/tests against (minikube is not mentioned) [10][9][F1]. Pin `kindest/node:v1.35.5`, not the default.
2. **Raw logs vs metrics → metrics (built-in GenAI), with access logs as a supplement.** AI Gateway emits OTel GenAI metrics (`gen_ai.client.token.usage` by `gen_ai_token_type`, labeled `gen_ai_request_model`) to Prometheus for free [6] — per-model input/output token attribution without hand-rolling. Use Envoy access logs keyed on `X-Claude-Code-Session-Id`/`X-Claude-Code-Agent-Id` only for session/subagent attribution [4].
3. **First cost-control experiment → native `QuotaPolicy` token budget.** The gateway already meters tokens on the request path, so server-side token budgeting is the lowest-effort first control [1][6]. **Caveat:** v0.7 was partly gated on quota-policy work — confirm `QuotaPolicy` enforcement is GA on the pinned version before relying on it; if not, fall back to access-log token accounting first. Treat deterministic context compression as a later custom filter.
4. **Anthropic-only vs multi-provider manifest structure → structure for multi-provider, ship Anthropic-only.** Keep **one** `AIGatewayRoute` with per-model rules and **one** `AIServiceBackend` + `BackendSecurityPolicy` per provider. The schema enum already includes OpenAI/Bedrock/Vertex/GCPAnthropic/AWSAnthropic [1], and routing is by `x-ai-eg-model`, so adding a provider later is purely additive — no restructuring.

---

## 7. Observability + the FR7 cost-control insertion point

**Prove traffic traverses the gateway NOW:**
- Hit the Prometheus endpoint on `ai-gateway-controller`/Envoy and confirm `gen_ai.client.token.usage{gen_ai_request_model="claude-sonnet-4-5"}` increments after a `claude -p` call [6].
- Tail `ai-gw-logs`; an Envoy access-log line per `/anthropic/v1/messages` is direct proof.
- Negative check: stop the port-forward → Claude Code fails. Confirms it is not bypassing to `api.anthropic.com` directly.

**FR7 insertion point** — the request already passes through Envoy's filter chain at the `AIGatewayRoute`/data-plane proxy, and the real key is injected at `BackendSecurityPolicy`. Map each Future item:

| Future item | Mechanism | Where |
|---|---|---|
| Token budgets / rate limits | **AI Gateway `QuotaPolicy`** (native token metering) | CRD on the route; server-side, on-path [1][6] |
| Per-session / per-subagent attribution & caps | Envoy **ext_proc** or Lua filter reading `X-Claude-Code-Session-Id` / `X-Claude-Code-Agent-Id` | EnvoyExtensionPolicy on the route [4] |
| Deterministic context compression | **ext_proc** (external gRPC) or **Wasm** filter rewriting the request body | inserted at AIGatewayRoute; **must stream**, see §8 |
| Model allowlist | `AIGatewayRoute` header/body match rules | route rules [1] |
| Key isolation / rotation | the `AnthropicAPIKey` Secret (gateway-injected) | `BackendSecurityPolicy` [3][6] |

---

## 8. Risks & gotchas + mitigations

1. **`/anthropic` path prefix (V3).** Bare `http://localhost:8888` → 404 on every request. **Mitigation:** `ANTHROPIC_BASE_URL=http://localhost:8888/anthropic`; document in `manifests/ai-gateway/README.md`; also handle trailing-slash 404 with a prefix-robust route [4][12].
2. **kind default k8s too new (V2).** Default v1.36.1 > EG ceiling v1.35. **Mitigation:** pin `kindest/node:v1.35.5@sha256:…` in the checked-in config [9].
3. **Version skew AI-GW↔EG.** Release-notes 1.7 vs compat-doc 1.8.1 [7][10]. **Mitigation:** trust the compat matrix — EG **v1.8.1** + AI-GW **v0.7.0**; never `v0.0.0-latest` [14].
4. **arm64 host (your Mac is Apple Silicon; this analysis ran on a Raspberry Pi).** kind node images are arm64; **verify** EG + AI-GW + Envoy container images publish arm64 manifests, else pods won't schedule [9]. (Likely fine on Apple Silicon; confirm.)
5. **Streaming/SSE buffering.** Envoy or any future ext_proc/compression filter that buffers breaks SSE and can trip Claude Code's 5-min idle abort. **Mitigation:** keep Envoy response streaming; set `API_TIMEOUT_MS` high and `API_FORCE_IDLE_TIMEOUT=0` when a compression filter is added; HTTPRoute/listener timeouts above long generations [5][12].
6. **TLS to Anthropic upstream.** `BackendTLSPolicy` needs system CA trust + SNI `api.anthropic.com` — a common first-run failure if omitted. **Mitigation:** `wellKnownCACertificates: System` + `hostname: api.anthropic.com` (already in §4) [2].
7. **Header forwarding.** If Envoy drops `anthropic-version`/`anthropic-beta`, Claude Code features degrade silently; dropped `X-Claude-Code-*` loses cost attribution [4][5]. **Mitigation:** verify forwarding; don't strip headers.
8. **Key leak.** Putting the real `sk-ant` in the shell bypasses the gateway budget point. **Mitigation:** placeholder in shell, real key only in the cluster Secret [3][6].
9. **Routing by body model not header.** `x-ai-eg-model` match vs body `model`. **Mitigation:** verify body-derived routing; else inject via `ANTHROPIC_CUSTOM_HEADERS` or use a header-less catch-all rule for the MVP [11].
10. **darwin-only / no flake.lock / no CI.** Flake can't self-validate the gateway flow on the build host, and runtime helm pulls aren't hermetic. **Mitigation:** literal version pins + digest-pinned node image; add Linux systems for the kind-only apps as a follow-up to enable CI [F2].
11. **EG EOL 2026-11-08 + AI-GW pre-1.0.** ~5-month upgrade horizon; CRD fields may shift before v1.0 (end-June 2026) [8][13]. **Mitigation:** pin now, schedule an upgrade pass.

---

## 9. Phased milestone plan

**M0 — Routing proof.** kind (pinned image) + EG v1.8.1 + AI-GW v0.7.0 installed via `ai-gw-up`; Anthropic manifests applied; `claude -p 'OK'` returns through the gateway; interactive session works.
*Acceptance:* `ai-gw-up` succeeds end-to-end; one-shot **and** interactive Claude Code calls succeed; stopping the port-forward breaks Claude Code (proves traversal). Maps to FR1–FR5. *(Optional EG quickstart.yaml smoke test before layering AI-GW.)*

**M1 — Observability.** GenAI Prometheus metrics scraped; `ai-gw-logs` shows per-request access logs; per-model token usage visible.
*Acceptance:* `gen_ai.client.token.usage` increments per call with correct `gen_ai_request_model`; an access-log line per `/anthropic/v1/messages` request. Maps to FR6.

**M2 — First cost control.** `QuotaPolicy` token budget enforced (or access-log token accounting if QuotaPolicy not GA on v0.7); budget breach blocks/limits requests.
*Acceptance:* exceeding the configured token budget produces the expected gateway response (429/limit) without breaking SSE for in-budget requests. Maps to FR7 (insertion point proven).

---

## 10. References

1. Envoy AI Gateway v0.4 release notes (native Anthropic provider) — https://aigateway.envoyproxy.io/release-notes/v0.4/
2. `examples/basic/anthropic.yaml` (schema/Backend/TLS/security policy) — https://github.com/envoyproxy/ai-gateway/blob/main/examples/basic/anthropic.yaml
3. Supported endpoints (`POST /anthropic/v1/messages` fully supported) — https://aigateway.envoyproxy.io/docs/capabilities/llm-integrations/supported-endpoints/
4. Claude Code LLM gateway requirements / attribution headers — https://code.claude.com/docs/en/llm-gateway
5. Claude Code env vars (`ANTHROPIC_BASE_URL`, timeouts) — https://code.claude.com/docs/en/env-vars
6. Envoy AI Gateway observability (GenAI token metrics) — https://aigateway.envoyproxy.io/docs/capabilities/observability/tracing/
7. Envoy AI Gateway compatibility matrix — https://aigateway.envoyproxy.io/docs/compatibility/
8. Envoy Gateway release matrix — https://gateway.envoyproxy.io/news/releases/matrix/
9. kind releases (v0.32.0, node images) — https://github.com/kubernetes-sigs/kind/releases
10. Envoy AI Gateway prerequisites — https://aigateway.envoyproxy.io/docs/getting-started/prerequisites/
11. Claude Code authentication (key vs auth-token headers) — https://code.claude.com/docs/en/authentication
12. Routing Claude through a custom endpoint (trailing-slash/SSE gotchas) — https://fazm.ai/blog/route-claude-api-through-custom-endpoint-anthropic-base-url
13. Envoy AI Gateway releases (v0.7.0) — https://github.com/envoyproxy/ai-gateway/releases
14. Envoy AI Gateway installation (pin version, not v0.0.0-latest) — https://aigateway.envoyproxy.io/docs/getting-started/installation/
15. Envoy Gateway Helm install — https://gateway.envoyproxy.io/docs/install/install-helm/
16. Envoy Gateway quickstart (port-forward via owning-gateway selector) — https://gateway.envoyproxy.io/docs/tasks/quickstart/

**Local sources (verified on disk):**
- F1. `/root/gh_repos/nix-k8s-lima/modules/packages.nix` (kind present), `…/homebrew-brews.nix` (helm via brew), `…/manifests/alpine-pod.yaml` (in-repo asset convention)
- F2. `/root/gh_repos/nix-k8s-lima/flake.nix` (darwin-only systems, no flake.lock, apps/mkApp/toolset) + `…/modules/scripts.nix` (`mkScript` writeShellApplication, `${self}` asset + sed-placeholder pattern)

---

## Confidence & gaps — confirm on your Mac

All three linchpins are **confirmed**; the flake layout is **verified from disk**. Empirically confirm on the Apple-Silicon Mac before declaring M0 done:
1. **`ANTHROPIC_BASE_URL=http://localhost:8888/anthropic`** actually lands Claude Code's `/v1/messages` on the native route (the single highest-risk detail).
2. **Route matching** when the model is only in the request body (body-derived `x-ai-eg-model` vs needing a header/catch-all rule).
3. **arm64 container manifests** exist for EG v1.8.1 + AI-GW v0.7.0 + Envoy v1.38.0 (pods schedule on Apple Silicon).
4. **`QuotaPolicy` enforcement GA** on v0.7.0 (it was partly gated) — else M2 starts with log-based token accounting.
5. **Exact `kindest/node:v1.35.5` sha256 digest** for the pinned config, and that the chart `--version v0.7.0` OCI tag resolves (vs a `v0.0.0-<hash>` form).
6. **`helm` source swap** doesn't leave a stale Homebrew `helm` shadowing the nixpkgs one on PATH.
