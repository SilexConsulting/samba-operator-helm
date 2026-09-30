#!/usr/bin/env bash
# End-to-end check against the current kube context: the chart must already be installed.
# Creates examples/user-share.yaml, writes a file over SMB from a client pod, reads it back,
# and checks it landed on the share's PVC. Cleans up afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."

NS=smb-demo
SHARE=smb-users-share

cleanup() {
  kubectl -n "$NS" delete pod smbclient --ignore-not-found --wait=false >/dev/null 2>&1 || true
  kubectl delete -f examples/user-share.yaml --ignore-not-found --timeout=120s >/dev/null 2>&1 || true
  kubectl delete namespace "$NS" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f examples/user-share.yaml

echo "Waiting for the operator to create the smbd Deployment..."
for _ in $(seq 1 60); do
  kubectl -n "$NS" get deploy "$SHARE" >/dev/null 2>&1 && break
  sleep 5
done
kubectl -n "$NS" rollout status "deploy/$SHARE" --timeout=300s

kubectl -n "$NS" run smbclient --image=alpine:3.22 --restart=Never --command -- sh -euc "
  apk add -q --no-cache samba-client >/dev/null
  echo 'hello over SMB' > /tmp/probe.txt
  smbclient //$SHARE.$NS.svc.cluster.local/$SHARE -U alice%change-me -c 'put /tmp/probe.txt probe.txt'
  smbclient //$SHARE.$NS.svc.cluster.local/$SHARE -U alice%change-me -c 'get probe.txt /tmp/back.txt'
  cmp /tmp/probe.txt /tmp/back.txt"
kubectl -n "$NS" wait --for=jsonpath='{.status.phase}'=Succeeded pod/smbclient --timeout=180s \
  || { kubectl -n "$NS" logs smbclient; exit 1; }

kubectl -n "$NS" exec "deploy/$SHARE" -c samba -- sh -c 'grep -q "hello over SMB" /mnt/*/probe.txt'
echo "PASS: SMB write/read through the operator-managed share works."
