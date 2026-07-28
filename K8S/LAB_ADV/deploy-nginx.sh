#!/bin/bash
#==============================================================================
# deploy-nginx.sh — Deploy Nginx on Kubernetes
#
# This script creates:
#   1. A Namespace (optional, configurable)
#   2. A Deployment running nginx with configurable replicas
#   3. A Service (NodePort) to expose nginx externally
#
# Usage:
#   bash deploy-nginx.sh [deploy|status|cleanup]
#
# Prerequisites:
#   - kubectl installed and configured (pointing to a running cluster)
#   - A running Kubernetes cluster (minikube, kind, k3s, EKS, GKE, etc.)
#==============================================================================

set -euo pipefail

# ──────────────────────────── Configuration ────────────────────────────
NAMESPACE="nginx-demo"
DEPLOYMENT_NAME="nginx-deployment"
SERVICE_NAME="nginx-service"
NGINX_IMAGE="nginx:1.27"
REPLICAS=2
CONTAINER_PORT=80
SERVICE_PORT=80
NODE_PORT=30080

# ──────────────────────────── Color helpers ────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }

# ──────────────────────────── Pre-flight checks ────────────────────────
preflight() {
    info "Running pre-flight checks..."

    if ! command -v kubectl &>/dev/null; then
        error "kubectl is not installed. Please install it first."
        echo "  → https://kubernetes.io/docs/tasks/tools/"
        exit 1
    fi

    if ! kubectl cluster-info &>/dev/null; then
        error "Cannot connect to a Kubernetes cluster."
        echo "  → Make sure your cluster is running and kubeconfig is set."
        exit 1
    fi

    success "kubectl is available and cluster is reachable."
}

# ──────────────────────────── Deploy ───────────────────────────────────
deploy() {
    preflight

    info "Creating namespace '${NAMESPACE}' (if not exists)..."
    kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

    info "Applying Nginx Deployment (${REPLICAS} replicas, image: ${NGINX_IMAGE})..."
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${DEPLOYMENT_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: nginx
spec:
  replicas: ${REPLICAS}
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: ${NGINX_IMAGE}
          ports:
            - containerPort: ${CONTAINER_PORT}
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "250m"
              memory: "256Mi"
          readinessProbe:
            httpGet:
              path: /
              port: ${CONTAINER_PORT}
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /
              port: ${CONTAINER_PORT}
            initialDelaySeconds: 10
            periodSeconds: 15
EOF

    info "Applying NodePort Service (port ${SERVICE_PORT} → nodePort ${NODE_PORT})..."
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: ${SERVICE_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: nginx
spec:
  type: NodePort
  selector:
    app: nginx
  ports:
    - protocol: TCP
      port: ${SERVICE_PORT}
      targetPort: ${CONTAINER_PORT}
      nodePort: ${NODE_PORT}
EOF

    info "Waiting for deployment to be ready..."
    kubectl rollout status deployment/"${DEPLOYMENT_NAME}" \
        -n "${NAMESPACE}" --timeout=120s

    echo ""
    success "Nginx deployed successfully!"
    echo ""
    show_access_info
}

# ──────────────────────────── Status ───────────────────────────────────
status() {
    info "Deployment status in namespace '${NAMESPACE}':"
    echo "─────────────────────────────────────────────────"

    echo ""
    info "Pods:"
    kubectl get pods -n "${NAMESPACE}" -l app=nginx -o wide 2>/dev/null \
        || warn "No pods found."

    echo ""
    info "Deployment:"
    kubectl get deployment "${DEPLOYMENT_NAME}" -n "${NAMESPACE}" -o wide 2>/dev/null \
        || warn "Deployment not found."

    echo ""
    info "Service:"
    kubectl get service "${SERVICE_NAME}" -n "${NAMESPACE}" -o wide 2>/dev/null \
        || warn "Service not found."

    echo ""
    show_access_info
}

# ──────────────────────────── Cleanup ──────────────────────────────────
cleanup() {
    warn "This will delete ALL nginx resources in namespace '${NAMESPACE}'."
    read -rp "Are you sure? (y/N): " confirm
    if [[ "${confirm}" =~ ^[Yy]$ ]]; then
        info "Deleting service..."
        kubectl delete service "${SERVICE_NAME}" -n "${NAMESPACE}" --ignore-not-found
        info "Deleting deployment..."
        kubectl delete deployment "${DEPLOYMENT_NAME}" -n "${NAMESPACE}" --ignore-not-found
        info "Deleting namespace..."
        kubectl delete namespace "${NAMESPACE}" --ignore-not-found
        success "Cleanup complete."
    else
        info "Cleanup cancelled."
    fi
}

# ──────────────────────────── Access info ──────────────────────────────
show_access_info() {
    info "Access Nginx at:"
    echo "  ┌──────────────────────────────────────────────────┐"
    echo "  │  NodePort:  http://<NODE_IP>:${NODE_PORT}        │"

    # If minikube is available, show the minikube URL
    if command -v minikube &>/dev/null; then
        MINIKUBE_IP=$(minikube ip 2>/dev/null || true)
        if [[ -n "${MINIKUBE_IP}" ]]; then
            echo "  │  Minikube:  http://${MINIKUBE_IP}:${NODE_PORT}        │"
        fi
    fi

    echo "  │  Port-fwd:  kubectl port-forward              │"
    echo "  │             svc/${SERVICE_NAME} 8080:${SERVICE_PORT}  │"
    echo "  │             -n ${NAMESPACE}                    │"
    echo "  │             → http://localhost:8080             │"
    echo "  └──────────────────────────────────────────────────┘"
}

# ──────────────────────────── Usage ────────────────────────────────────
usage() {
    echo "Usage: $0 {deploy|status|cleanup}"
    echo ""
    echo "  deploy   - Create namespace, deployment, and service for Nginx"
    echo "  status   - Show current state of the Nginx deployment"
    echo "  cleanup  - Remove all Nginx resources from the cluster"
}

# ──────────────────────────── Main ─────────────────────────────────────
case "${1:-}" in
    deploy)  deploy  ;;
    status)  status  ;;
    cleanup) cleanup ;;
    *)       usage   ;;
esac
