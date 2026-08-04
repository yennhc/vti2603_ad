# Sơ đồ Lab Triển khai AWS EKS trong Thực tế

## 1. Sơ đồ Kiến trúc Tổng quan

```
┌────────────────────────────── AWS Account ──────────────────────────┐
│                                                                       │
│  ┌──────────────────── VPC (10.0.0.0/16) ──────────────────┐        │
│  │                                                           │        │
│  │  Public Subnets (NAT Gateway, IGW)                       │        │
│  │  ┌─────────────────┐      ┌──────────────────┐          │        │
│  │  │  Public SN-1    │      │  Public SN-2     │          │        │
│  │  │  (10.0.1.0/24)  │      │  (10.0.2.0/24)   │          │        │
│  │  └────────┬────────┘      └────────┬─────────┘          │        │
│  │           │                        │                    │        │
│  │  ┌────────▼────────────────────────▼──────┐             │        │
│  │  │  Internet Gateway (IGW)                 │             │        │
│  │  │  & NAT Gateway                          │             │        │
│  │  └─────────────────────────────────────────┘             │        │
│  │                                                           │        │
│  │  Private Subnets (EKS Nodes)                             │        │
│  │  ┌─────────────────┐      ┌──────────────────┐          │        │
│  │  │ Private SN-1    │      │ Private SN-2     │          │        │
│  │  │ (10.0.10.0/24)  │      │ (10.0.11.0/24)   │          │        │
│  │  │                 │      │                  │          │        │
│  │  │  ┌──────────┐   │      │  ┌──────────┐    │          │        │
│  │  │  │ Node-1   │   │      │  │ Node-2   │    │          │        │
│  │  │  │ (t3.med) │   │      │  │ (t3.med) │    │          │        │
│  │  │  └──────────┘   │      │  └──────────┘    │          │        │
│  │  │                 │      │                  │          │        │
│  │  │  ┌──────────┐   │      │  ┌──────────┐    │          │        │
│  │  │  │ Node-3   │   │      │  │ Fargate  │    │          │        │
│  │  │  │ (t3.med) │   │      │  │ Profile  │    │          │        │
│  │  │  └──────────┘   │      │  └──────────┘    │          │        │
│  │  └─────────────────┘      └──────────────────┘          │        │
│  │           ▲                         ▲                    │        │
│  │           │                         │                    │        │
│  │           └─────────────┬───────────┘                    │        │
│  │                         │                                │        │
│  │           ┌─────────────▼─────────────┐                 │        │
│  │           │  EKS Control Plane        │                 │        │
│  │           │  (AWS Managed)            │                 │        │
│  │           │  - API Server             │                 │        │
│  │           │  - etcd                   │                 │        │
│  │           │  - Controllers            │                 │        │
│  │           └───────────────────────────┘                 │        │
│  │                                                           │        │
│  └───────────────────────────────────────────────────────────┘        │
│                                                                       │
│  ┌──────────────────── Storage ──────────────────────┐               │
│  │                                                    │               │
│  │  ┌──────────────┐  ┌──────────────┐              │               │
│  │  │ EBS Volumes  │  │ EFS FileShare│              │               │
│  │  │ (Persistent) │  │ (Shared)     │              │               │
│  │  └──────────────┘  └──────────────┘              │               │
│  └────────────────────────────────────────────────────┘               │
│                                                                       │
│  ┌──────────────────── Load Balancing ───────────────────┐           │
│  │                                                        │           │
│  │  ┌──────────────┐  ┌──────────────┐                 │           │
│  │  │ NLB (TCP/UDP)│  │ ALB (HTTP/s) │                 │           │
│  │  └──────────────┘  └──────────────┘                 │           │
│  └────────────────────────────────────────────────────────┘           │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘
```

## 2. Chi tiết Node Groups

```
┌────── Managed Node Group (Auto Scaling) ──────┐
│                                               │
│  Min: 2 nodes  |  Desired: 3  |  Max: 5      │
│                                               │
│  Instance Type: t3.medium                     │
│  Disk: 20GB gp3 EBS                          │
│  IAM Role: EKS-NodeInstanceRole              │
│                                               │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │  Node-1  │  │  Node-2  │  │  Node-3  │   │
│  │ 10.0.10.5│  │ 10.0.11.7│  │ 10.0.10.8│   │
│  └──────────┘  └──────────┘  └──────────┘   │
│                                               │
│  OS: Amazon Linux 2 / Ubuntu 24.04           │
│  Runtime: containerd                         │
│  CNI: AWS VPC CNI (Calico optional)          │
│                                               │
└───────────────────────────────────────────────┘

┌─────── Fargate Profile (Serverless) ────────┐
│                                             │
│  Namespace: fargate-ns                      │
│  Labels: workload=fargate                   │
│                                             │
│  ┌──────────────────────────────────────┐  │
│  │  Fargate Pod 1  Fargate Pod 2         │  │
│  │  (Auto-sized)   (Auto-sized)          │  │
│  └──────────────────────────────────────┘  │
│                                             │
│  Không cần quản lý instances                │
│  Chi phí cao hơn nhưng không lo worker      │
│                                             │
└─────────────────────────────────────────────┘
```

## 3. Quy trình Triển khai Lab (Step-by-step)

```
┌─────────────────────────────────────────────────────────────┐
│             PHASE 1: PREREQUISITE & PLANNING                │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Setup AWS Account & Credentials                        │
│     └─ AWS CLI, IAM user, Access Keys                     │
│                                                             │
│  2. Design Network Architecture                            │
│     └─ VPC CIDR: 10.0.0.0/16                             │
│     └─ Public Subnets: 10.0.1.0/24, 10.0.2.0/24         │
│     └─ Private Subnets: 10.0.10.0/24, 10.0.11.0/24       │
│                                                             │
│  3. Plan Security Groups & IAM Roles                       │
│     └─ Control Plane SG                                   │
│     └─ Node SG                                            │
│     └─ Node IAM Role + Policies                           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
        │
        │ Create VPC, Subnets, IGW, NAT GW
        ▼
┌─────────────────────────────────────────────────────────────┐
│          PHASE 2: CREATE EKS CLUSTER                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Create EKS Cluster                                     │
│     └─ Name: eks-lab-cluster                             │
│     └─ Version: 1.30 (latest)                            │
│     └─ Endpoint: public + private                        │
│     └─ Role: eks-service-role                            │
│                                                             │
│  2. Enable Control Plane Logging                           │
│     └─ API Server logs                                   │
│     └─ Controller Manager logs                           │
│     └─ Scheduler logs                                    │
│     └─ Auth logs                                         │
│     └─ Audit logs                                        │
│                                                             │
│  3. Configure Networking                                   │
│     └─ Associate Public/Private Subnets                 │
│     └─ Configure Security Groups                        │
│     └─ Enable VPC CNI                                   │
│                                                             │
│  ⏱️  Wait: 10-15 minutes                                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
        │
        │ Cluster ACTIVE
        ▼
┌─────────────────────────────────────────────────────────────┐
│         PHASE 3: ADD NODE GROUPS & COMPUTE                 │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Create Managed Node Group                              │
│     └─ Name: primary-nodes                               │
│     └─ Instance: t3.medium (2-5 nodes)                  │
│     └─ AMI Type: Amazon Linux 2                          │
│     └─ Disk: 20GB gp3                                    │
│                                                             │
│  2. Tag Nodes                                              │
│     └─ Environment: lab                                  │
│     └─ Tier: application                                 │
│                                                             │
│  3. Create Fargate Profile (Optional)                      │
│     └─ Namespace: fargate                               │
│     └─ Pod Execution Role: fargate-pod-execution-role   │
│                                                             │
│  ⏱️  Wait: 5-10 minutes                                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
        │
        │ Nodes Ready
        ▼
┌─────────────────────────────────────────────────────────────┐
│         PHASE 4: CONFIGURE & VALIDATE CLUSTER              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Update kubeconfig                                      │
│     └─ aws eks update-kubeconfig --region ap-southeast-1 │
│                                                             │
│  2. Verify Cluster Connection                              │
│     └─ kubectl get nodes                                 │
│     └─ kubectl get pods -A                               │
│                                                             │
│  3. Install/Configure Add-ons                              │
│     └─ VPC CNI                                           │
│     └─ CoreDNS                                           │
│     └─ kube-proxy                                        │
│     └─ Calico (optional)                                 │
│                                                             │
│  4. Setup Storage Classes                                  │
│     └─ EBS (gp3)                                         │
│     └─ EFS (optional)                                    │
│                                                             │
│  5. Configure RBAC                                         │
│     └─ Create namespaces: default, kube-system, etc.    │
│     └─ Setup service accounts                            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
        │
        │ Cluster Ready
        ▼
┌─────────────────────────────────────────────────────────────┐
│       PHASE 5: DEPLOY SAMPLE APPLICATIONS                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Deploy Nginx Ingress                                   │
│     └─ Helm chart: ingress-nginx                         │
│     └─ Type: LoadBalancer (ALB)                          │
│                                                             │
│  2. Deploy Sample App                                      │
│     └─ App 1: Flask/Python API                           │
│     └─ App 2: Node.js Frontend                           │
│     └─ App 3: Database (PostgreSQL Helm)                │
│                                                             │
│  3. Setup Persistent Volume                                │
│     └─ EBS-backed PVC                                    │
│     └─ Test attach/detach                                │
│                                                             │
│  4. Configure Monitoring                                   │
│     └─ CloudWatch Container Insights                     │
│     └─ Prometheus (optional)                             │
│     └─ Grafana (optional)                                │
│                                                             │
│  5. Setup Logging                                          │
│     └─ CloudWatch Logs                                   │
│     └─ Fluent Bit daemonset                              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
        │
        │ Applications Running
        ▼
┌─────────────────────────────────────────────────────────────┐
│          PHASE 6: TESTING & VALIDATION                     │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Connectivity Tests                                     │
│     └─ kubectl exec pod -- curl service                 │
│     └─ Test ingress access                               │
│     └─ Verify DNS resolution                             │
│                                                             │
│  2. Scaling Tests                                          │
│     └─ Scale deployment: 1 → 5 → 1 replicas            │
│     └─ Verify node autoscaling (2 → 5 → 2)            │
│     └─ Check rolling updates                             │
│                                                             │
│  3. Storage Tests                                          │
│     └─ Create/Write to PVC                               │
│     └─ Delete pod, verify data persistence               │
│     └─ Expand volume size                                │
│                                                             │
│  4. High Availability Tests                                │
│     └─ Drain node (kubectl drain)                       │
│     └─ Terminate node, verify recovery                   │
│     └─ Chaos engineering (optional)                      │
│                                                             │
│  5. Cost Analysis                                          │
│     └─ AWS Cost Explorer                                 │
│     └─ Estimate monthly cost                             │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## 4. Chi tiết Deployment - Ứng dụng mẫu

```yaml
┌─────────────────────────────────────────────┐
│  Namespace: app-lab                         │
│                                             │
│  ┌────────────────────────────────────┐   │
│  │ Frontend (Node.js)                 │   │
│  │ - Deployment: 3 replicas           │   │
│  │ - Service: LoadBalancer            │   │
│  │ - Port: 8080 → ALB:80              │   │
│  │ - Image: node:18-alpine            │   │
│  │ - CPU: 100m, Memory: 128Mi         │   │
│  └────────────────────────────────────┘   │
│           │                                 │
│           │ HTTP 10.1.x.x:5000            │
│           ▼                                 │
│  ┌────────────────────────────────────┐   │
│  │ Backend API (Python Flask)         │   │
│  │ - Deployment: 2 replicas           │   │
│  │ - Service: ClusterIP               │   │
│  │ - Port: 5000                       │   │
│  │ - CPU: 150m, Memory: 256Mi         │   │
│  │ - ConfigMap: app-config            │   │
│  └────────────────────────────────────┘   │
│           │                                 │
│           │ TCP localhost:5432             │
│           ▼                                 │
│  ┌────────────────────────────────────┐   │
│  │ Database (PostgreSQL Helm)         │   │
│  │ - StatefulSet: 1 replica           │   │
│  │ - Service: ClusterIP               │   │
│  │ - PVC: 10GB EBS gp3                │   │
│  │ - Port: 5432                       │   │
│  │ - Secret: db-credentials           │   │
│  └────────────────────────────────────┘   │
│                                             │
└─────────────────────────────────────────────┘
```

## 5. Chi tiết Security & Access

```
┌──────── IAM & RBAC Configuration ────────┐
│                                          │
│  AWS IAM                                 │
│  ├─ EKS Service Role                    │
│  │  └─ AmazonEKSServiceRolePolicy       │
│  │                                       │
│  ├─ Node Instance Role                  │
│  │  ├─ AmazonEKSWorkerNodePolicy       │
│  │  ├─ AmazonEKS_CNI_Policy            │
│  │  └─ AmazonEC2ContainerRegistryRead  │
│  │                                       │
│  └─ Fargate Pod Execution Role          │
│     └─ AmazonEKSFargatePodExecutionRole│
│                                          │
│  Kubernetes RBAC                         │
│  ├─ admin                               │
│  │  └─ Full cluster access              │
│  │                                       │
│  ├─ developer                           │
│  │  ├─ get, list, watch pods           │
│  │  ├─ logs, exec                      │
│  │  └─ create, delete: deployment only │
│  │                                       │
│  └─ viewer                              │
│     └─ get, list, watch only           │
│                                          │
│  Network Policy (Calico)                 │
│  ├─ Ingress: Allow Frontend ↔ Backend  │
│  ├─ Ingress: Allow Backend ↔ Database  │
│  └─ Egress: Deny all external (default)│
│                                          │
└──────────────────────────────────────────┘
```

## 6. Monitoring & Observability

```
┌─── CloudWatch Integration ────┐
│                               │
│  Container Insights           │
│  ├─ Node metrics              │
│  ├─ Pod metrics               │
│  ├─ CPU, Memory, Disk         │
│  └─ Custom metrics            │
│                               │
│  Log Groups                   │
│  ├─ /aws/eks/eks-lab-cluster │
│  │  └─ Includes:              │
│  │     ├─ API Server logs     │
│  │     ├─ Controller logs     │
│  │     ├─ Scheduler logs      │
│  │     └─ Audit logs          │
│  │                             │
│  │  └─ CloudWatch Logs Insight│
│  │     └─ Query & analyze     │
│  │                             │
│  └─ Alarms                    │
│     ├─ CPU > 80%              │
│     ├─ Memory > 75%           │
│     ├─ Pod CrashLoopBackOff   │
│     └─ Node NotReady          │
│                               │
└───────────────────────────────┘
```

## 7. Checklist Validation Lab

```
CONNECTIVITY & BASIC OPERATIONS
☐ kubectl get nodes (All nodes Ready)
☐ kubectl get pods -A (All system pods Running)
☐ kubectl get svc (Services have EXTERNAL-IP)
☐ DNS resolution: nslookup kubernetes.default

POD DEPLOYMENT
☐ Create deployment from YAML
☐ kubectl logs pod-name (Logs accessible)
☐ kubectl exec pod -- sh (Shell access works)
☐ Port-forward to service (kubectl port-forward)

LOAD BALANCING
☐ Service type LoadBalancer → ALB created
☐ External IP assigned (Elastic IP)
☐ curl http://external-ip (Response OK)

SCALING
☐ kubectl scale deployment app --replicas=5
☐ Nodes auto-scale up (2→5 nodes)
☐ Pods distributed across nodes
☐ Scale down: kubectl scale deployment app --replicas=1
☐ Nodes auto-scale down (5→2 nodes)

STORAGE
☐ Create PVC, bind to PVC
☐ Write file to mounted volume
☐ Delete pod, verify file persists
☐ Expand PVC size (kubectl patch pvc)

MONITORING
☐ CloudWatch Container Insights active
☐ Logs appearing in CloudWatch
☐ Metrics dashboard showing data
☐ Alarms triggered for high resource

HIGH AVAILABILITY
☐ kubectl drain node-1 (Evict pods)
☐ Pods reschedule to other nodes
☐ Scale deployment during drain
☐ Terminate node (ASG replaces it)
☐ Verify zero downtime

CLEANUP
☐ Delete load balancers (ELB/ALB)
☐ Delete persistent volumes (EBS)
☐ Delete node groups
☐ Delete EKS cluster
☐ Delete VPC & subnets
☐ Verify no orphaned resources
```
