# samba-operator Helm chart

A Helm chart for [samba-in-kubernetes/samba-operator](https://github.com/samba-in-kubernetes/samba-operator):
SMB file shares on Kubernetes, declared as `SmbShare` / `SmbCommonConfig` / `SmbSecurityConfig`
custom resources. Upstream ships only kustomize manifests (`make deploy`). This chart is rendered from
upstream's `config/default` for the release in `appVersion` (currently **v0.8**), with pinned images.

```bash
helm install samba-operator oci://ghcr.io/silexconsulting/charts/samba-operator \
  --version 0.1.0 --namespace samba-operator-system --create-namespace
```

| Chart | Operator (`appVersion`) | kube-rbac-proxy |
|---|---|---|
| 0.1.0 | v0.8 | v0.18.1 |

## What's in it

- The CRDs `smbshares`, `smbcommonconfigs` and `smbsecurityconfigs` (in `crds/`).
- The controller Deployment:
  - the manager, plus a `kube-rbac-proxy` sidecar guarding `/metrics`;
  - its ConfigMap, RBAC and metrics Service.
- Differences from upstream `v0.8`:
  - **Pinned images.** Upstream's `v0.8` manifests still reference `gcr.io/kubebuilder/kube-rbac-proxy:v0.8.0`,
    which has been **deleted**, so installs made from them are stuck in `ImagePullBackOff`. This chart uses
    `quay.io/brancz/kube-rbac-proxy:v0.18.1`, as upstream `main` does. The operator is pinned to
    `v0.8` (upstream `main` uses `:latest` with `imagePullPolicy: Always`).
  - **A dedicated ServiceAccount.** Upstream binds the namespace's `default` SA; set
    `serviceAccount.create=false` to keep that behaviour.
  - Operator settings are exposed as values (`config:`, see below).
- **No admission webhooks.** The operator has none: upstream's `config/webhook` is scaffolding only.

## Adopting an existing `make deploy` install

Object names are `<fullname>-<upstream name>`. With release name `samba-operator` in namespace
`samba-operator-system`, they are **exactly** upstream's (`samba-operator-controller-manager`, and so on).
Installing, or syncing with Argo CD, over a kustomize install therefore **adopts it in place**:

- Existing `SmbShare`s, and their smbd Deployments and Services, are untouched.
- The operator only creates missing objects and adjusts replica counts. It never rewrites an existing
  share Deployment or Service.
- The Deployment selector is kept as upstream's `control-plane: controller-manager`, because it is
  immutable.

Before switching, diff the chart against the live objects:

```bash
helm template samba-operator oci://ghcr.io/silexconsulting/charts/samba-operator --version 0.1.0 \
  -n samba-operator-system --include-crds | kubectl diff --server-side --force-conflicts -f -
```

With plain Helm (not Argo CD), existing objects first need Helm ownership metadata
(`meta.helm.sh/release-name`, `meta.helm.sh/release-namespace` and the `app.kubernetes.io/managed-by=Helm`
label), or `helm install` refuses them.

## Configuration

| Value | Default | Notes |
|---|---|---|
| `image.repository` / `tag` / `digest` | `quay.io/samba.org/samba-operator` / appVersion / — | |
| `metrics.authProxy.enabled` | `true` | kube-rbac-proxy sidecar + metrics Service on `:8443` |
| `metrics.authProxy.image.*` | `quay.io/brancz/kube-rbac-proxy:v0.18.1` | |
| `serviceAccount.create` | `true` | `false` + `name: ""` binds the namespace `default` SA (upstream behaviour) |
| `config` | `{}` | Operator settings → `SAMBA_OP_*` env (see below) |
| `nodeArchitectures` | `[amd64]` | Node affinity for the **operator** pod; `[]` to drop |
| `affinity`, `nodeSelector`, `tolerations`, `resources`, `podSecurityContext`, `securityContext`, `priorityClassName`, `podAnnotations`, `podLabels`, `extraArgs`, `extraEnv` | | as usual |

`config` keys are the operator's own setting names. Each is written to the ConfigMap as
`SAMBA_OP_<KEY>`, upper-cased, with `-` → `_`. Useful ones:

```yaml
config:
  smbd-container-image: quay.io/samba.org/samba-server:v0.8   # image for each share's smbd pod
  metrics-exporter-mode: enabled                             # per-share samba-metrics sidecar + Service
  default-node-selector: '{"kubernetes.io/arch": "amd64"}'   # JSON; the built-in default (see below)
  samba-debug-level: "3"
```

### Architectures

Upstream publishes **amd64-only** images, so, like upstream, the chart pins the operator to amd64 nodes.
The operator *also* gives every share's smbd pod a node selector of `kubernetes.io/arch: amd64`. That is
its built-in `default-node-selector`. Override both only when those images can run elsewhere (your own
builds, or emulation):

```yaml
nodeArchitectures: []
config:
  default-node-selector: '{}'
```

## Using it

See [`examples/`](examples/):

- [`default-user-share.yaml`](examples/default-user-share.yaml): a share **without** an
  `SmbSecurityConfig`, published as a LoadBalancer. With no security config, the operator creates its
  **built-in default user `sambauser` / `samba`**; there is no anonymous/guest mode. That's fine for a
  LAN scanner drop-box, but anything else should define its own users.
- [`user-share.yaml`](examples/user-share.yaml): users from a Secret via `SmbSecurityConfig`
  (`mode: user`). Active Directory is `mode: active-directory` (see upstream's
  [howto](https://github.com/samba-in-kubernetes/samba-operator/blob/master/docs/howto.md)).
- [`pinned-lb-ip.yaml`](examples/pinned-lb-ip.yaml): a fixed LoadBalancer IP (see below).

### Storage: RWX for multi-node

Each share runs an smbd pod that mounts the share's PVC. If another workload also mounts that PVC (say,
an app consuming what a scanner drops), the two pods may land on different nodes, so use a
**ReadWriteMany** PVC (Longhorn RWX, NFS, CephFS, …). With `ReadWriteOnce` or node-local storage, both
pods must be on the same node.

### Pinning the LoadBalancer IP

The operator creates each share's Service itself (ClusterIP by default; LoadBalancer with an
`SmbCommonConfig` of `network.publish: external`). It has **no way to set Service annotations or
`loadBalancerIP`**. It does, however, create that Service only once and never update it afterwards.
There are two options:

1. **Declarative (recommended):** keep the share internal and add your own `type: LoadBalancer`
   Service with your LB's IP annotation (e.g. MetalLB `metallb.universe.tf/loadBalancerIPs`). It selects
   the smbd pods by the operator's label `samba-operator.samba.org/service: <SmbShare name>`. See
   [`pinned-lb-ip.yaml`](examples/pinned-lb-ip.yaml).
2. **Imperative:** publish externally, then annotate the operator-created Service once. The annotation
   survives reconciliation, but it is lost if the SmbShare is ever recreated.

## CRDs and upgrades

Helm installs `crds/` on the first install only, and **never upgrades or deletes CRDs**. Before a chart
upgrade that changes CRDs, `kubectl apply --server-side -f charts/samba-operator/crds/`. Argo CD applies
them on every sync.

Deleting the CRDs deletes every `SmbShare`, and with it each share's smbd Deployment, Service and
(operator-created) PVC. **Argo CD users:** set `preserveResourcesOnDeletion` / avoid cascading deletes.

## Development

```bash
helm lint --strict charts/samba-operator
kind create cluster && helm install samba-operator charts/samba-operator -n samba-operator-system --create-namespace --wait
hack/e2e-smb.sh          # SMB write/read through an operator-managed share
hack/sync-upstream.sh v0.9   # regenerate CRDs from a new upstream release; then bump Chart.yaml
```

On Apple-silicon/arm64 kind, add `--set-json 'nodeArchitectures=[]' --set-json 'config={"default-node-selector":"{}"}'`.
The amd64 images then run under emulation.

**Releasing:** bump `version` in `Chart.yaml`, merge, then tag `v<version>`. CI publishes
`oci://ghcr.io/silexconsulting/charts/samba-operator:<version>`.

## License

Apache-2.0, as upstream. See [NOTICE](NOTICE).
