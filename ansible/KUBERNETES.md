# Kubernetes Deployment Guide

This guide explains how to use Ansible to deploy Lean blockchain nodes to Kubernetes instead of Docker.

## Prerequisites

### 1. Kubernetes Cluster

You need a running Kubernetes cluster. Options:

- **Local Testing**: [Minikube](https://minikube.sigs.k8s.io/docs/), [kind](https://kind.sigs.k8s.io/), or [Docker Desktop Kubernetes](https://docs.docker.com/desktop/kubernetes/)
- **Production**: Any managed K8s service (GKE, EKS, AKS, etc.)

### 2. Install kubectl

```bash
# macOS
brew install kubectl

# Verify installation
kubectl version --client
```

### 3. Configure kubectl

Ensure `kubectl` is configured to point to your cluster:

```bash
kubectl cluster-info
```

### 4. Install Ansible Kubernetes Collection

```bash
cd ansible
ansible-galaxy install -r requirements.yml
```

This installs the `kubernetes.core` collection.

## Kubernetes Deployment vs Docker

### Key Differences

| Aspect | Docker | Kubernetes |
|--------|--------|------------|
| **Orchestration** | Single container per host | Pod orchestration |
| **Networking** | Host network mode | Service-based networking |
| **Storage** | Host bind mounts | PersistentVolumeClaims |
| **Scaling** | Manual | Automatic with Deployments |
| **Access** | Direct host ports | Services + port-forwarding |
| **Config** | Volume mounts | ConfigMaps (if needed) |

### When to Use Each

**Use Docker for:**
- Local development and testing
- Single-node deployments
- Simple setups without orchestration needs
- Direct host port access

**Use Kubernetes for:**
- Production-like multi-node testing
- Multi-host deployments
- Automated scaling and management
- Service discovery
- Isolated environments

## Deployment

### Quick Start

Deploy a single node to Kubernetes:

```bash
./ansible-deploy.sh --node zeam_0 --network-dir local-devnet --deployment-mode kubernetes
```

Deploy all nodes:

```bash
./ansible-deploy.sh --node all --network-dir local-devnet --deployment-mode kubernetes
```

### Configuration Variables

Kubernetes-specific variables in `ansible/inventory/group_vars/all.yml`:

```yaml
# Kubernetes settings
k8s_namespace: lean-network              # Namespace for all nodes
k8s_storage_class: standard              # Storage class for PVCs
k8s_storage_size: 10Gi                   # Storage size per node
k8s_cpu_request: "100m"                  # CPU request
k8s_memory_request: "256Mi"              # Memory request
k8s_cpu_limit: "1000m"                   # CPU limit
k8s_memory_limit: "2Gi"                  # Memory limit
```

### Override Settings

You can override Kubernetes settings per deployment:

```bash
# Use custom namespace
ansible-playbook -i inventory/hosts.yml playbooks/deploy-nodes.yml \
  -e "deployment_mode=kubernetes" \
  -e "k8s_namespace=my-custom-namespace" \
  -e "node_names=zeam_0"
```

## Accessing Deployed Nodes

### Checking Status

```bash
# List all resources in namespace
kubectl get all -n lean-network

# List pods
kubectl get pods -n lean-network

# View pod logs
kubectl logs -n lean-network zeam_0 -f

# Describe pod details
kubectl describe pod -n lean-network zeam_0
```

### Accessing Metrics

Kubernetes uses Services for networking. To access metrics:

**Option 1: Port Forward** (Recommended for local access)
```bash
# Forward metrics port to localhost
kubectl port-forward -n lean-network svc/zeam_0-metrics 8080:8080

# Access metrics
curl http://localhost:8080/metrics
```

**Option 2: NodePort Services**
Metrics services are configured as NodePort. Find the assigned port:

```bash
kubectl get svc -n lean-network zeam_0-metrics
```

Then access via `<node-ip>:<nodeport>`.

### Accessing QUIC Port

QUIC ports use ClusterIP services (internal cluster access only). To access from outside:

```bash
# Port forward QUIC port
kubectl port-forward -n lean-network svc/zeam_0-quic 9000:9000
```

## Storage

### Persistent Volumes

Each node gets a PersistentVolumeClaim for its data directory:

- **PVC Name**: `<node_name>-data`
- **Size**: 10Gi (configurable via `k8s_storage_size`)
- **Access Mode**: ReadWriteOnce

### View Storage

```bash
# List PVCs
kubectl get pvc -n lean-network

# Describe PVC
kubectl describe pvc -n lean-network zeam_0-data

# View persistent volumes
kubectl get pv
```

### Storage Classes

Update `k8s_storage_class` based on your cluster:

- **GKE**: `standard` or `ssd`
- **AWS EKS**: `gp3` or `gp2`
- **Azure AKS**: `managed` or `premium`
- **Local/Minikube**: `standard` or `hostpath`

For local development with Minikube:

```bash
minikube start
# Uses hostpath storage by default
```

## Networking

### Services Created

For each node, two services are created:

1. **Metrics Service** (`<node_name>-metrics`)
   - Type: NodePort
   - Exposes metrics port
   
2. **QUIC Service** (`<node_name>-quic`)
   - Type: ClusterIP
   - Internal cluster access only

### Peer Discovery

Nodes discover each other via:
- **ENR fields** in genesis configuration
- **Service DNS names** within cluster: `<service_name>.<namespace>.svc.cluster.local`
- Example: `zeam_0-quic.lean-network.svc.cluster.local`

### Firewall Rules

For cloud deployments, ensure firewall rules allow:
- NodePort port range: `30000-32767`
- Specific ports if configured

## Troubleshooting

### Pod Not Starting

```bash
# Check pod status
kubectl get pods -n lean-network

# View logs
kubectl logs -n lean-network <pod-name>

# Describe events
kubectl describe pod -n lean-network <pod-name>
```

### PVC Not Binding

```bash
# Check PVC status
kubectl get pvc -n lean-network

# Check storage classes
kubectl get storageclass

# For Minikube, ensure storage provisioner is running
minikube addons list | grep storage
```

### Cannot Access Services

```bash
# Verify services exist
kubectl get svc -n lean-network

# Check service endpoints
kubectl get endpoints -n lean-network

# Test connectivity from within cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://zeam_0-metrics:8080/metrics
```

### Permission Issues

For Pod Security Policies or SELinux:

```bash
# Check pod security context
kubectl get pod -n lean-network <pod-name> -o json | jq '.spec.securityContext'

# For testing, you can temporarily disable PSP
kubectl delete podsecuritypolicy --all
```

## Cleanup

### Remove All Resources

```bash
# Delete namespace (removes everything)
kubectl delete namespace lean-network

# Or delete specific resources
kubectl delete deployment zeam_0 -n lean-network
kubectl delete svc zeam_0-metrics zeam_0-quic -n lean-network
kubectl delete pvc zeam_0-data -n lean-network
```

### Redeploy with Clean State

```bash
./ansible-deploy.sh --node all --network-dir local-devnet \
  --deployment-mode kubernetes \
  --clean-data \
  --generate-genesis
```

This will:
1. Clean existing data
2. Regenerate genesis files
3. Create new PVCs with fresh data

## Advanced Usage

### Custom Resource Limits

Override resource limits per deployment:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/deploy-nodes.yml \
  -e "deployment_mode=kubernetes" \
  -e "k8s_cpu_limit=2000m" \
  -e "k8s_memory_limit=4Gi" \
  -e "node_names=zeam_0"
```

### Multi-Node Deployment

Deploy to a multi-node Kubernetes cluster:

```bash
# Deploy multiple nodes
./ansible-deploy.sh --node "zeam_0,ream_0,qlean_0" \
  --network-dir local-devnet \
  --deployment-mode kubernetes

# Verify all pods are running
kubectl get pods -n lean-network -o wide
```

### External Genesis Files

If your genesis files are stored externally (S3, Git, etc.):

1. Create a ConfigMap or Secret with the files
2. Update the deployment manifest to reference it
3. Mount the ConfigMap/Secret volume

Example ConfigMap:

```bash
# Create ConfigMap from directory
kubectl create configmap genesis-config -n lean-network \
  --from-file=/path/to/genesis/

# Update deployment to use ConfigMap
# Edit manifest or use kubectl patch
```

## Comparison with Docker

### Example: Deploying zeam_0

**With Docker:**
```bash
./ansible-deploy.sh --node zeam_0 --network-dir local-devnet
docker logs zeam_0
curl http://localhost:8080/metrics
```

**With Kubernetes:**
```bash
./ansible-deploy.sh --node zeam_0 --network-dir local-devnet --deployment-mode kubernetes
kubectl logs -n lean-network zeam_0 -f
kubectl port-forward -n lean-network svc/zeam_0-metrics 8080:8080
curl http://localhost:8080/metrics
```

### Network Discovery

**Docker (host network):**
- Nodes can discover each other via `localhost` or actual IPs
- Direct port access on host

**Kubernetes:**
- Nodes discover via service DNS names
- Requires port-forwarding or ingress for external access
- Internal cluster networking handled automatically

## Best Practices

1. **Use separate namespaces** for different environments (dev, staging, prod)
2. **Set appropriate resource limits** based on node requirements
3. **Use PersistentVolumes** for production (not hostPath)
4. **Implement health checks** in manifests
5. **Use secrets** for sensitive data (not ConfigMaps)
6. **Enable monitoring** (Prometheus) for production
7. **Set up backups** for PVC data
8. **Use RBAC** to restrict access to resources

## Integration with CI/CD

Example GitHub Actions workflow:

```yaml
name: Deploy to Kubernetes

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup kubectl
        uses: azure/setup-kubectl@v3
        
      - name: Configure Kubernetes
        run: |
          echo "${{ secrets.KUBECONFIG }}" > kubeconfig.yaml
          export KUBECONFIG=kubeconfig.yaml
          
      - name: Deploy with Ansible
        run: |
          cd ansible
          ansible-galaxy install -r requirements.yml
          ansible-playbook -i inventory/hosts.yml playbooks/deploy-nodes.yml \
            -e "deployment_mode=kubernetes" \
            -e "node_names=all"
```

## Support

For issues or questions:
1. Check this guide first
2. Review pod logs: `kubectl logs -n lean-network <pod-name>`
3. Check cluster events: `kubectl get events -n lean-network --sort-by=.metadata.creationTimestamp`
4. Consult main README: `../README.md`

