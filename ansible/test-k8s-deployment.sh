#!/bin/bash
# Test script for Kubernetes Ansible deployment
# Usage: ./test-k8s-deployment.sh [cleanup]

set -e

echo "========================================="
echo "Testing Kubernetes Ansible Deployment"
echo "========================================="

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if we should clean up at the end
CLEANUP=false
if [[ "$1" == "cleanup" ]]; then
    CLEANUP=true
fi

# Check prerequisites
echo -e "${YELLOW}1. Checking prerequisites...${NC}"

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl not found. Please install kubectl.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ kubectl installed${NC}"

if ! command -v ansible &> /dev/null; then
    echo -e "${RED}❌ ansible not found. Please install Ansible.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Ansible installed${NC}"

if ! command -v yq &> /dev/null; then
    echo -e "${RED}❌ yq not found. Please install yq.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ yq installed${NC}"

# Check cluster
echo -e "${YELLOW}2. Checking Kubernetes cluster...${NC}"
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}❌ Cannot connect to Kubernetes cluster.${NC}"
    echo "Please ensure a cluster is running:"
    echo "  - minikube start"
    echo "  - kind create cluster"
    echo "  - Docker Desktop → Enable Kubernetes"
    exit 1
fi
echo -e "${GREEN}✓ Cluster accessible${NC}"

# Get cluster context
CONTEXT=$(kubectl config current-context)
echo -e "${GREEN}  Using context: ${CONTEXT}${NC}"

# Check Ansible collections
echo -e "${YELLOW}3. Checking Ansible collections...${NC}"
cd ansible

if ! ansible-galaxy collection list | grep -q "kubernetes.core"; then
    echo -e "${YELLOW}⚠ kubernetes.core collection not found. Installing...${NC}"
    ansible-galaxy install -r requirements.yml
fi
echo -e "${GREEN}✓ Collections installed${NC}"

cd ..

# Generate genesis files if they don't exist
echo -e "${YELLOW}4. Checking genesis files...${NC}"
if [ ! -f "local-devnet/genesis/validator-config.yaml" ]; then
    echo -e "${YELLOW}⚠ Genesis files not found. Please create local-devnet/genesis/validator-config.yaml${NC}"
    exit 1
fi

if [ ! -f "local-devnet/genesis/validators.yaml" ] || [ ! -f "local-devnet/genesis/nodes.yaml" ]; then
    echo -e "${YELLOW}⚠ Generating genesis files...${NC}"
    ./generate-genesis.sh local-devnet/genesis
fi
echo -e "${GREEN}✓ Genesis files ready${NC}"

# Syntax check
echo -e "${YELLOW}5. Checking Ansible syntax...${NC}"
cd ansible
if ! ansible-playbook --syntax-check playbooks/deploy-nodes.yml &> /dev/null; then
    echo -e "${RED}❌ Syntax check failed${NC}"
    ansible-playbook --syntax-check playbooks/deploy-nodes.yml
    exit 1
fi
echo -e "${GREEN}✓ Syntax check passed${NC}"
cd ..

# Dry run
echo -e "${YELLOW}6. Running dry run...${NC}"
if ! ./ansible-deploy.sh --node zeam_0 --network-dir local-devnet --deployment-mode kubernetes --check > /tmp/ansible-dryrun.log 2>&1; then
    echo -e "${RED}❌ Dry run failed${NC}"
    cat /tmp/ansible-dryrun.log
    exit 1
fi
echo -e "${GREEN}✓ Dry run passed${NC}"

# Clean up any existing test deployment
echo -e "${YELLOW}7. Cleaning up any existing test deployment...${NC}"
if kubectl get namespace lean-network &> /dev/null; then
    kubectl delete namespace lean-network --ignore-not-found=true
    sleep 2
fi
echo -e "${GREEN}✓ Cleanup complete${NC}"

# Deploy single node
echo -e "${YELLOW}8. Deploying test node (zeam_0)...${NC}"
if ! ./ansible-deploy.sh --node zeam_0 --network-dir local-devnet --deployment-mode kubernetes > /tmp/ansible-deploy.log 2>&1; then
    echo -e "${RED}❌ Deployment failed${NC}"
    cat /tmp/ansible-deploy.log
    exit 1
fi
echo -e "${GREEN}✓ Deployment initiated${NC}"

# Wait for pod to be ready
echo -e "${YELLOW}9. Waiting for pod to be ready (max 2 minutes)...${NC}"
if ! kubectl wait --for=condition=ready pod -l app=zeam_0 -n lean-network --timeout=120s 2>&1; then
    echo -e "${RED}❌ Pod did not become ready${NC}"
    echo "Pod status:"
    kubectl get pods -n lean-network
    echo ""
    echo "Recent events:"
    kubectl get events -n lean-network --sort-by=.metadata.creationTimestamp | tail -10
    exit 1
fi
echo -e "${GREEN}✓ Pod is ready${NC}"

# Verify resources
echo -e "${YELLOW}10. Verifying resources...${NC}"

NAMESPACE_EXISTS=$(kubectl get namespace lean-network -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")
if [ -z "$NAMESPACE_EXISTS" ]; then
    echo -e "${RED}❌ Namespace not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Namespace exists${NC}"

PVC_EXISTS=$(kubectl get pvc -n lean-network -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -z "$PVC_EXISTS" ]; then
    echo -e "${RED}❌ PVC not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ PVC exists and bound${NC}"

DEPLOYMENT_EXISTS=$(kubectl get deployment -n lean-network -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -z "$DEPLOYMENT_EXISTS" ]; then
    echo -e "${RED}❌ Deployment not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Deployment exists${NC}"

POD_STATUS=$(kubectl get pods -n lean-network -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
if [ "$POD_STATUS" != "Running" ]; then
    echo -e "${RED}❌ Pod not running (status: $POD_STATUS)${NC}"
    kubectl get pods -n lean-network
    exit 1
fi
echo -e "${GREEN}✓ Pod is running${NC}"

# Check logs
echo -e "${YELLOW}11. Checking logs...${NC}"
POD_NAME=$(kubectl get pods -n lean-network -l app=zeam_0 -o jsonpath='{.items[0].metadata.name}')
LOG_CHECK=$(kubectl logs -n lean-network $POD_NAME --tail=10 2>&1 | grep -i "error\|fatal" || echo "no errors")
if [ "$LOG_CHECK" != "no errors" ]; then
    echo -e "${YELLOW}⚠ Found errors in logs:${NC}"
    kubectl logs -n lean-network $POD_NAME --tail=50
else
    echo -e "${GREEN}✓ No critical errors in logs${NC}"
fi

# Summary
echo ""
echo "========================================="
echo -e "${GREEN}✅ All basic checks passed!${NC}"
echo "========================================="
echo ""
echo "Resources created:"
kubectl get all,pvc -n lean-network
echo ""
echo "To view pod logs:"
echo "  kubectl logs -n lean-network $POD_NAME -f"
echo ""
echo "To port forward metrics:"
echo "  kubectl port-forward -n lean-network svc/zeam_0-metrics 8080:8080"
echo "  curl http://localhost:8080/metrics"
echo ""

# Cleanup if requested
if [ "$CLEANUP" = true ]; then
    echo -e "${YELLOW}Cleaning up test deployment...${NC}"
    kubectl delete namespace lean-network --ignore-not-found=true
    echo -e "${GREEN}✓ Cleanup complete${NC}"
else
    echo -e "${YELLOW}Test deployment left running in 'lean-network' namespace.${NC}"
    echo "To clean up manually:"
    echo "  kubectl delete namespace lean-network"
fi

# Remove temp files
rm -f /tmp/ansible-dryrun.log /tmp/ansible-deploy.log

echo ""
echo "Test complete!"

