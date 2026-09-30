#!/usr/bin/env bash
# Regenerate charts/samba-operator/crds/ from an upstream samba-operator release, and print the
# upstream RBAC so it can be compared with templates/rbac.yaml.
#
#   hack/sync-upstream.sh v0.8
#
# Then: review `git diff`, update appVersion/version in Chart.yaml (and the artifacthub
# annotations), and compare the printed RBAC with templates/rbac.yaml.
set -euo pipefail
TAG=${1:?usage: $0 <upstream tag, e.g. v0.8>}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

git -c advice.detachedHead=false clone -q --depth 1 --branch "$TAG" https://github.com/samba-in-kubernetes/samba-operator.git "$WORK/src"
kustomize build "$WORK/src/config/default" > "$WORK/all.yaml"

for crd in smbcommonconfigs smbsecurityconfigs smbshares; do
  {
    echo "# Generated from samba-in-kubernetes/samba-operator $TAG (config/crd) — do not edit by hand;"
    echo "# regenerate with hack/sync-upstream.sh."
    yq "select(.kind==\"CustomResourceDefinition\" and .metadata.name==\"$crd.samba-operator.samba.org\") | del(.metadata.creationTimestamp)" \
      "$WORK/all.yaml"
  } > "$ROOT/charts/samba-operator/crds/$crd.yaml"
done

echo "---- upstream RBAC ($TAG) — compare with charts/samba-operator/templates/rbac.yaml"
yq 'select(.kind=="Role" or .kind=="ClusterRole") | {"name": .metadata.name, "rules": .rules}' "$WORK/all.yaml"
echo "---- upstream images ($TAG)"
grep -E 'image:' "$WORK/all.yaml" | sort -u
