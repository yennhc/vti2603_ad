#!/bin/bash

#############################################################################
# EKS Lab - Phase 5: Deploy Applications
# 
# Công việc:
# - Deploy Frontend (Node.js)
# - Deploy Backend (Python Flask)
# - Deploy Database (PostgreSQL)
# - Configure Load Balancer
#
# Thời gian: ~20 minutes
#############################################################################

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
REGION="ap-southeast-1"
PROFILE="${AWS_PROFILE:-default}"
LAB_NAME="eks-lab"
CLUSTER_NAME="${LAB_NAME}-cluster"
NAMESPACE="app-lab"
DB_NAME="postgres"
DB_USER="postgres"
DB_PASSWORD="EksLab@2024"  # Change in production!

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}EKS Lab - Phase 5: Deploy Applications${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function: Print step
print_step() {
    echo -e "${YELLOW}→ $1${NC}"
}

# Function: Print success
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# ============================================================================
# STEP 1: Verify cluster
# ============================================================================
print_step "Verifying cluster access..."

if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Cannot access cluster. Please complete Phase 1-4 first.${NC}"
    exit 1
fi

print_success "Cluster access verified"

# ============================================================================
# STEP 2: Create database secret
# ============================================================================
print_step "Creating database credentials secret..."

kubectl create secret generic db-credentials \
    --from-literal=username=$DB_USER \
    --from-literal=password=$DB_PASSWORD \
    --from-literal=database=$DB_NAME \
    -n $NAMESPACE \
    --dry-run=client -o yaml | kubectl apply -f -

print_success "Database secret created"

# ============================================================================
# STEP 3: Deploy PostgreSQL Database
# ============================================================================
print_step "Deploying PostgreSQL Database..."

cat <<EOF | kubectl apply -f -
---
# PersistentVolumeClaim for PostgreSQL
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ebs-gp3
  resources:
    requests:
      storage: 10Gi
---
# ConfigMap for PostgreSQL configuration
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgres-config
  namespace: $NAMESPACE
data:
  POSTGRES_DB: $DB_NAME
  POSTGRES_USER: $DB_USER
---
# PostgreSQL StatefulSet
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: $NAMESPACE
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
      tier: database
  template:
    metadata:
      labels:
        app: postgres
        tier: database
    spec:
      containers:
      - name: postgres
        image: postgres:15-alpine
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 5432
          name: postgres
        envFrom:
        - configMapRef:
            name: postgres-config
        env:
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: password
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        volumeMounts:
        - name: postgres-storage
          mountPath: /var/lib/postgresql/data
        livenessProbe:
          exec:
            command:
            - /bin/sh
            - -c
            - pg_isready -U $DB_USER
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          exec:
            command:
            - /bin/sh
            - -c
            - pg_isready -U $DB_USER
          initialDelaySeconds: 10
          periodSeconds: 5
      volumes:
      - name: postgres-storage
        persistentVolumeClaim:
          claimName: postgres-pvc
---
# PostgreSQL Service
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: $NAMESPACE
  labels:
    app: postgres
    tier: database
spec:
  type: ClusterIP
  ports:
  - port: 5432
    targetPort: 5432
    name: postgres
  selector:
    app: postgres
    tier: database
EOF

print_success "PostgreSQL deployed"

# ============================================================================
# STEP 4: Wait for database to be ready
# ============================================================================
print_step "Waiting for PostgreSQL to be ready..."

kubectl wait --for=condition=ready pod \
    -l app=postgres,tier=database \
    -n $NAMESPACE \
    --timeout=300s 2>/dev/null || true

READY_PODS=$(kubectl get pods -n $NAMESPACE -l app=postgres --no-headers | grep -c Running || echo 0)
while [ "$READY_PODS" = "0" ]; do
    echo -n "."
    sleep 5
    READY_PODS=$(kubectl get pods -n $NAMESPACE -l app=postgres --no-headers | grep -c Running || echo 0)
done
echo ""

print_success "PostgreSQL is ready"

# ============================================================================
# STEP 5: Deploy Backend API (Python Flask)
# ============================================================================
print_step "Deploying Backend API (Python Flask)..."

cat <<EOF | kubectl apply -f -
---
# ConfigMap for Backend configuration
apiVersion: v1
kind: ConfigMap
metadata:
  name: backend-config
  namespace: $NAMESPACE
data:
  DATABASE_URL: "postgresql://$DB_USER:@postgres:5432/$DB_NAME"
  FLASK_ENV: "production"
---
# Backend Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-api
  namespace: $NAMESPACE
  labels:
    app: backend
    tier: backend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: backend
      tier: backend
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: backend
        tier: backend
    spec:
      serviceAccountName: app-sa
      containers:
      - name: api
        image: python:3.11-slim
        imagePullPolicy: IfNotPresent
        command:
        - /bin/bash
        - -c
        - |
          pip install flask psycopg2-binary &&
          python -c "
import os
from flask import Flask, jsonify
from datetime import datetime

app = Flask(__name__)

@app.route('/api/health', methods=['GET'])
def health():
    return jsonify({'status': 'healthy', 'timestamp': datetime.utcnow().isoformat()})

@app.route('/api/info', methods=['GET'])
def info():
    return jsonify({
        'service': 'backend-api',
        'version': '1.0.0',
        'hostname': os.environ.get('HOSTNAME', 'unknown')
    })

@app.route('/api/db-status', methods=['GET'])
def db_status():
    import psycopg2
    try:
        conn = psycopg2.connect(
            host='postgres',
            user='postgres',
            password=os.environ.get('DB_PASSWORD'),
            database='postgres'
        )
        conn.close()
        return jsonify({'database': 'connected'})
    except Exception as e:
        return jsonify({'database': 'error', 'message': str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
          "
        ports:
        - containerPort: 5000
          name: http
        envFrom:
        - configMapRef:
            name: backend-config
        env:
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: password
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
        livenessProbe:
          httpGet:
            path: /api/health
            port: 5000
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /api/health
            port: 5000
          initialDelaySeconds: 5
          periodSeconds: 5
---
# Backend Service
apiVersion: v1
kind: Service
metadata:
  name: backend-api
  namespace: $NAMESPACE
  labels:
    app: backend
    tier: backend
spec:
  type: ClusterIP
  ports:
  - port: 5000
    targetPort: 5000
    name: http
  selector:
    app: backend
    tier: backend
EOF

print_success "Backend API deployed"

# ============================================================================
# STEP 6: Deploy Frontend (Node.js Nginx)
# ============================================================================
print_step "Deploying Frontend (Nginx)..."

cat <<EOF | kubectl apply -f -
---
# ConfigMap for Nginx configuration
apiVersion: v1
kind: ConfigMap
metadata:
  name: frontend-config
  namespace: $NAMESPACE
data:
  nginx.conf: |
    user nginx;
    worker_processes auto;
    error_log /var/log/nginx/error.log warn;
    pid /var/run/nginx.pid;
    
    events {
        worker_connections 1024;
    }
    
    http {
        include /etc/nginx/mime.types;
        default_type application/octet-stream;
        
        log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                        '\$status \$body_bytes_sent "\$http_referer" '
                        '"\$http_user_agent" "\$http_x_forwarded_for"';
        
        access_log /var/log/nginx/access.log main;
        
        sendfile on;
        tcp_nopush on;
        tcp_nodelay on;
        keepalive_timeout 65;
        types_hash_max_size 2048;
        
        upstream backend {
            server backend-api:5000;
        }
        
        server {
            listen 8080;
            server_name _;
            
            location / {
                root /usr/share/nginx/html;
                try_files \$uri /index.html;
            }
            
            location /api/ {
                proxy_pass http://backend/;
                proxy_set_header Host \$host;
                proxy_set_header X-Real-IP \$remote_addr;
                proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto \$scheme;
            }
            
            location /health {
                access_log off;
                return 200 "healthy\n";
                add_header Content-Type text/plain;
            }
        }
    }
---
# Frontend Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: $NAMESPACE
  labels:
    app: frontend
    tier: frontend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
      tier: frontend
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: frontend
        tier: frontend
    spec:
      serviceAccountName: app-sa
      containers:
      - name: nginx
        image: nginx:latest
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 8080
          name: http
        volumeMounts:
        - name: nginx-config
          mountPath: /etc/nginx
          readOnly: true
        - name: html
          mountPath: /usr/share/nginx/html
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
      initContainers:
      - name: init-html
        image: busybox
        command: ['sh', '-c']
        args:
        - |
          mkdir -p /html
          cat > /html/index.html << 'HTML'
          <!DOCTYPE html>
          <html>
          <head>
              <title>EKS Lab - Sample Application</title>
              <style>
                  body { font-family: Arial, sans-serif; margin: 50px; }
                  .container { max-width: 800px; margin: 0 auto; }
                  .status { padding: 10px; margin: 10px 0; background: #e8f5e9; border-radius: 4px; }
                  .error { background: #ffebee; }
                  button { padding: 10px 20px; margin: 5px; cursor: pointer; }
              </style>
          </head>
          <body>
              <div class="container">
                  <h1>🎉 EKS Lab - Sample Application</h1>
                  <p>This is a 3-tier application running on AWS EKS</p>
                  
                  <h2>Application Status</h2>
                  <div id="status"></div>
                  
                  <h2>API Tests</h2>
                  <button onclick="testHealth()">Check API Health</button>
                  <button onclick="testInfo()">Get API Info</button>
                  <button onclick="testDB()">Check Database</button>
                  <div id="results"></div>
              </div>
              
              <script>
                  async function testHealth() {
                      try {
                          const response = await fetch('/api/health');
                          const data = await response.json();
                          document.getElementById('results').innerHTML = 
                              '<div class="status"><strong>Health:</strong> ' + JSON.stringify(data) + '</div>';
                      } catch (e) {
                          document.getElementById('results').innerHTML = 
                              '<div class="status error"><strong>Error:</strong> ' + e.message + '</div>';
                      }
                  }
                  
                  async function testInfo() {
                      try {
                          const response = await fetch('/api/info');
                          const data = await response.json();
                          document.getElementById('results').innerHTML = 
                              '<div class="status"><strong>Info:</strong> ' + JSON.stringify(data) + '</div>';
                      } catch (e) {
                          document.getElementById('results').innerHTML = 
                              '<div class="status error"><strong>Error:</strong> ' + e.message + '</div>';
                      }
                  }
                  
                  async function testDB() {
                      try {
                          const response = await fetch('/api/db-status');
                          const data = await response.json();
                          document.getElementById('results').innerHTML = 
                              '<div class="status"><strong>Database:</strong> ' + JSON.stringify(data) + '</div>';
                      } catch (e) {
                          document.getElementById('results').innerHTML = 
                              '<div class="status error"><strong>Error:</strong> ' + e.message + '</div>';
                      }
                  }
                  
                  // Auto-load status
                  window.onload = testHealth;
              </script>
          </body>
          </html>
          HTML
        volumeMounts:
        - name: html
          mountPath: /html
      volumes:
      - name: nginx-config
        configMap:
          name: frontend-config
      - name: html
        emptyDir: {}
---
# Frontend Service
apiVersion: v1
kind: Service
metadata:
  name: frontend
  namespace: $NAMESPACE
  labels:
    app: frontend
    tier: frontend
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 8080
    name: http
  selector:
    app: frontend
    tier: frontend
EOF

print_success "Frontend deployed"

# ============================================================================
# STEP 7: Wait for deployments
# ============================================================================
print_step "Waiting for all deployments to be ready..."

kubectl wait --for=condition=available --timeout=300s deployment/backend-api -n $NAMESPACE 2>/dev/null || true
kubectl wait --for=condition=available --timeout=300s deployment/frontend -n $NAMESPACE 2>/dev/null || true

print_success "All deployments are ready"

# ============================================================================
# STEP 8: Get Load Balancer details
# ============================================================================
print_step "Retrieving Load Balancer information..."

EXTERNAL_IP=""
WAIT_TIME=0
MAX_WAIT=120

while [ -z "$EXTERNAL_IP" ] && [ $WAIT_TIME -lt $MAX_WAIT ]; do
    EXTERNAL_IP=$(kubectl get svc frontend -n $NAMESPACE --no-headers | awk '{print $4}')
    if [ "$EXTERNAL_IP" = "<pending>" ] || [ -z "$EXTERNAL_IP" ]; then
        EXTERNAL_IP=""
    fi
    
    if [ -z "$EXTERNAL_IP" ]; then
        echo -n "."
        sleep 5
        WAIT_TIME=$((WAIT_TIME + 5))
    fi
done

if [ -z "$EXTERNAL_IP" ] || [ "$EXTERNAL_IP" = "<pending>" ]; then
    EXTERNAL_IP="<pending - check with: kubectl get svc frontend -n $NAMESPACE>"
fi

print_success "Load Balancer configured"

# ============================================================================
# STEP 9: Display application endpoints
# ============================================================================
echo ""
echo "Application Deployments:"
echo "─────────────────────────────────────────"
kubectl get deployments -n $NAMESPACE
echo ""
echo "Application Services:"
echo "─────────────────────────────────────────"
kubectl get svc -n $NAMESPACE
echo ""
echo "Application Pods:"
echo "─────────────────────────────────────────"
kubectl get pods -n $NAMESPACE
echo ""
echo "Persistent Volumes:"
echo "─────────────────────────────────────────"
kubectl get pvc -n $NAMESPACE
echo ""

# ============================================================================
# Summary
# ============================================================================
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✓ Phase 5 Completed Successfully!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Application Information:"
echo "─────────────────────────────────────────"
echo "Frontend URL:              http://$EXTERNAL_IP"
echo "Frontend (direct):         http://$EXTERNAL_IP:80"
echo "Backend API:               http://backend-api:5000"
echo "Database:                  postgres://postgres:****@postgres:5432/postgres"
echo ""
echo "Useful Commands:"
echo "─────────────────────────────────────────"
echo "View logs:                 kubectl logs -n $NAMESPACE -l app=frontend"
echo "Shell into pod:            kubectl exec -it -n $NAMESPACE <pod-name> -- /bin/bash"
echo "Port forward:              kubectl port-forward -n $NAMESPACE svc/frontend 8080:80"
echo "Watch pods:                kubectl get pods -n $NAMESPACE -w"
echo ""
echo -e "${YELLOW}Next step: Run Phase 6 to run validation tests${NC}"
echo "bash phase-6-validation-tests.sh"
echo ""
