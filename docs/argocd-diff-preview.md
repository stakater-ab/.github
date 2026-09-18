# Reusable: ArgoCD Diff Preview

`.github/workflows/argocd-diff-preview.yaml` — one place for the ArgoCD Diff Preview
CI used across Stakater gitops repos. Replaces the per-repo / per-cluster inline
workflows (originally ztp-playbook-generated) that broke on every infra migration
because each hardcoded a Vault URL + per-tree `FILE_REGEX`/`paths`.

Tracked in **SA-8566**.

## What it fixes vs the old inline workflows

- **No hardcoded dead vault URLs** — the vault URL/role/secret are caller inputs. When
  a cluster's vault moves, you edit one thin caller, not a 113-line workflow.
- **Dynamic scoping (`FILES_CHANGED`)** — renders only the Applications whose files the
  PR changed, instead of the whole tree (~70+ apps). This simultaneously:
  - fixes the scope gap (a PR to *any* cluster tree gets a real preview), and
  - kills the `ssh: handshake failed: EOF` storm + 180s timeout (few apps → few
    `git ls-remote`, so GitHub doesn't throttle the connection burst).
- **`timeout` default 600s** (was a hardcoded 180s that intermittently timed out).
- **`tailnet` toggle** — adds the `tailscale/github-action` step only when the target
  Vault is tailnet-only.
- **Injection-hardened** — the untrusted `github.head_ref` is passed via `env:`, never
  inline in a `run:`.

## Caller — prod (public vault, one workflow)

`stakater-cloud-gitops-prod/.github/workflows/pull_request.yaml`:

```yaml
name: ArgoCD Diff Preview
on:
  pull_request:
    branches: [main]
jobs:
  diff:
    uses: stakater-ab/.github/.github/workflows/argocd-diff-preview.yaml@main
    permissions:
      contents: read
      id-token: write
      pull-requests: write
    with:
      vault-url: https://openbao.apps.r0gt99vm.stakater.cloud
      vault-role: stakater-ab-stakater-cloud-gitops-prod
      vault-secrets: |
        stakater/data/stakater-ab-stakater-cloud-gitops-prod sshPrivateKey | sshPrivateKey ;
      argocd-repo-url: git@github.com:stakater-ab/stakater-cloud-gitops-prod.git
      argocd-namespace: rh-openshift-gitops-instance
      file-regex: /registry/
      tailnet: false
    secrets: inherit
```

That ~18-line caller replaces the current 113-line inline workflow. With dynamic
`FILES_CHANGED`, one caller covers **all** cluster trees in the repo — no per-cluster
copies, no per-tree `paths` triggers to go stale.

## Caller — nonprod (tailnet vault)

If nonprod authenticates against **one** live vault for all clusters, it's also a single
caller (recommended — collapses the 6 rotting `pull_request_<cluster>.yaml` files into one):

```yaml
name: ArgoCD Diff Preview
on:
  pull_request:
    branches: [main]
jobs:
  diff:
    uses: stakater-ab/.github/.github/workflows/argocd-diff-preview.yaml@main
    permissions: { contents: read, id-token: write, pull-requests: write }
    with:
      vault-url: https://openbao.apps.eu-1.ndskuue5.stakater.cloud   # a live, stable vault
      vault-role: stakater-ab-stakater-cloud-gitops-nonprod
      vault-secrets: |
        stakater/data/stakater-cloud-gitops-nonprod sshPrivateKey | sshPrivateKey ;
      argocd-repo-url: git@github.com:stakater-ab/stakater-cloud-gitops-nonprod.git
      argocd-namespace: openshift-gitops
      tailnet: true
    secrets: inherit   # passes org GHCR_* + repo TS_OAUTH_* through
```

`tailnet: true` requires `TS_OAUTH_CLIENT_ID` / `TS_OAUTH_SECRET` (repo or org secrets)
and a tailnet ACL allowing `tag:ci` → the vault VIP `:8200`.

## Per-vault prerequisites (once per target vault)

The chosen Vault must have, for the caller's `vault-role`:
- a `githubactionsjwt` JWT auth mount configured for GitHub OIDC, with a role bound to
  the repo and **`bound_audiences: ["https://github.com/stakater-ab"]`** (the GH OIDC
  token carries an `aud`; a role without a bound audience returns HTTP 400), and
- the deploy-key secret at the path named in `vault-secrets` (managed via ESO / GitOps,
  not seeded imperatively — imperative seeding is what got lost in past migrations).
