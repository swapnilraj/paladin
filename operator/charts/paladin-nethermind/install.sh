#!/usr/bin/env bash
# Full Paladin + Nethermind setup on a local Kind cluster.
# Run from the repository root: bash operator/charts/paladin-nethermind/install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
KIND_CONFIG="$REPO_ROOT/paladin-kind.yaml"
NAMESPACE="paladin"

echo "==> Step 1: Create Kind cluster"
if kind get clusters 2>/dev/null | grep -q "^paladin$"; then
  echo "    Kind cluster 'paladin' already exists, skipping"
else
  kind create cluster --name paladin --config "$KIND_CONFIG"
fi
kubectl config use-context kind-paladin

echo "==> Step 2: Install cert-manager"
helm repo add jetstack https://charts.jetstack.io --force-update
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.16.1 \
  --set crds.enabled=true \
  --wait

echo "==> Step 3: Install Paladin CRDs"
helm repo add paladin https://LFDT-Paladin.github.io/paladin --force-update
helm upgrade --install paladin-crds paladin/paladin-operator-crd \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --wait

echo "==> Step 4: Install Paladin operator + smart contract deployments (basenet mode)"
# basenet mode deploys: operator + SmartContractDeployment CRs (with bytecode) + TransactionInvoke CRs
# It does NOT create any Besu or Paladin nodes — those come from our chart.
helm upgrade --install paladin paladin/paladin-operator \
  --namespace "$NAMESPACE" \
  --set mode=basenet \
  --set paladin.nodeNamePrefix=node \
  --wait

echo "==> Step 5: Install paladin-nethermind chart (Nethermind + 3 Paladin nodes + domains + registry)"
helm upgrade --install paladin-nethermind "$SCRIPT_DIR" \
  --namespace "$NAMESPACE" \
  --wait --timeout 5m

echo "==> Step 6: Reset SmartContractDeployment statuses to trigger deployment on fresh chain"
# The SmartContractDeployment CRs retain status from previous runs.
# Clear them so the operator re-submits transactions to the new Nethermind instance.
for cr in $(kubectl get smartcontractdeployment -n "$NAMESPACE" -o name 2>/dev/null); do
  kubectl patch "$cr" -n "$NAMESPACE" --type=merge \
    -p '{"status":{"transactionStatus":"","transactionID":""}}' 2>/dev/null || true
done
echo "    SmartContractDeployment statuses reset"

echo ""
echo "Setup complete! Waiting for contracts to deploy..."
echo "(This may take 1-2 minutes as Nethermind mines the contract deployment transactions)"
echo ""
echo "Paladin nodes are accessible on localhost:"
echo "  node1: http://localhost:31548  (WS: ws://localhost:31549)"
echo "  node2: http://localhost:31648  (WS: ws://localhost:31649)"
echo "  node3: http://localhost:31748  (WS: ws://localhost:31749)"
echo ""
echo "Check status with:"
echo "  kubectl get paladin,paladinregistration,paladindomain,paladinregistry -n $NAMESPACE"
