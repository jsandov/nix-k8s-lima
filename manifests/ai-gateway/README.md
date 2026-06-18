# Local Claude Code AI gateway (Envoy AI Gateway → Anthropic)

M0 scaffold for the PRD *"Local Kubernetes AI Gateway for Claude Code Cost Control."*
Routes Claude Code through a local **kind** cluster running **Envoy Gateway** + **Envoy AI
Gateway** (native Anthropic provider) to `api.anthropic.com`. See the full design in
[`../../docs/ai-gateway-prd-research.md`](../../docs/ai-gateway-prd-research.md).

## Pinned stack

| Component | Version |
|---|---|
| Envoy AI Gateway | `v0.7.0` |
| Envoy Gateway | `v1.8.1` (bundles Gateway API `v1.5.1` + Envoy `v1.38.0`) |
| Kubernetes (kind node) | `kindest/node:v1.35.5` (NOT kind's default v1.36.x — above EG's ceiling) |

## Quickstart

```sh
# 1. Real Anthropic key goes ONLY into the cluster Secret (never your shell/git):
export ANTHROPIC_GATEWAY_API_KEY=sk-ant-...

# 2. Bring it up (creates kind cluster, installs both gateways, applies routing,
#    then port-forwards localhost:8888 -> the Envoy data-plane). Blocking.
nix run .#ai-gw-up

# 3. In another shell, point Claude Code at the gateway and test:
eval "$(nix run .#ai-gw-claude-env)"
claude -p 'reply with the single word OK'

# Inspect / tear down:
nix run .#ai-gw-status
nix run .#ai-gw-logs
nix run .#ai-gw-down
```

## The two things that WILL bite you

1. **`ANTHROPIC_BASE_URL` must include the `/anthropic` path prefix** —
   `http://localhost:8888/anthropic`. Claude Code appends `/v1/messages`, producing the
   native route `/anthropic/v1/messages`. A bare `http://localhost:8888` **404s every
   request** despite "correct" env vars. (`ai-gw-claude-env` sets this correctly.)
2. **Do not use kind's default node image** — it's k8s v1.36.x, above Envoy Gateway v1.8's
   supported ceiling (v1.35). `kind-cluster.yaml` pins `v1.35.5`.

## Key handling

The real `sk-ant-…` key lives **only** in the in-cluster Secret `ai-gw-anthropic-apikey`
(created by `ai-gw-up` from `$ANTHROPIC_GATEWAY_API_KEY`); the gateway injects it on the
upstream call. Your shell's `ANTHROPIC_API_KEY` stays a placeholder. That Secret /
`BackendSecurityPolicy` is the natural home for the future FR7 token-budget / model-allowlist
enforcement.

## Confirm on a real Mac (can't be validated on Linux/no-nix)

- The `/anthropic` base URL lands Claude Code's `/v1/messages` on the native route.
- **Model routing**: this route matches `x-ai-eg-model` via `RegularExpression: claude.*`
  (the AI gateway derives `x-ai-eg-model` from the request body `model`). If your pinned
  AI-GW version rejects regex header matches, switch to per-model `type: Exact` rules.
- arm64 container images exist for EG/AI-GW/Envoy (Apple Silicon scheduling).
- `QuotaPolicy` enforcement GA on v0.7 (the first cost-control milestone, M2).
- Pin the exact `kindest/node:v1.35.5@sha256:…` digest for reproducibility.
