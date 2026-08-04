#!/bin/bash

MY_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
kubectl version --client

# Install eksctl
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin
eksctl version

# Configure AWS CLI
aws configure
# Nhập: AWS Access Key ID, AWS Secret Access Key, Default region (ví dụ: ap-southeast-1)


#Create VPC and IAM Roles

tee <<EOF > eks-trust-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF


#Create IAM Role for EKS Cluster
aws iam create-role --role-name eks-cluster-role --assume-role-policy-document file://eks-trust-policy.json

#Attach the AmazonEKSClusterPolicy to the EKS Cluster Role
aws iam attach-role-policy \
  --role-name eks-cluster-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy

aws iam attach-role-policy \
  --role-name eks-cluster-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy

aws iam attach-role-policy \
  --role-name eks-cluster-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

#Create VPC for EKS Cluster
  VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=eks-vpc}]' \
  --query 'Vpc.VpcId' \
  --output text)

echo "VPC ID: $VPC_ID"

#Enable DNS hostnames for the VPC
aws ec2 modify-vpc-attribute \
  --vpc-id $VPC_ID \
  --enable-dns-hostnames

#Create Internet Gateway for the VPC
IGW_ID=$(aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=eks-igw}]' \
  --query 'InternetGateway.InternetGatewayId' \
  --output text)

aws ec2 attach-internet-gateway \
  --internet-gateway-id $IGW_ID \
  --vpc-id $VPC_ID

echo "IGW ID: $IGW_ID"


#Create Subnets for EKS Cluster
 
 # Subnet 1
SUBNET1_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.1.0/24 \
  --availability-zone ap-southeast-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=eks-subnet-1}]' \
  --query 'Subnet.SubnetId' \
  --output text)

  # Subnet 2
SUBNET2_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.2.0/24 \
  --availability-zone ap-southeast-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=eks-subnet-2}]' \
  --query 'Subnet.SubnetId' \
  --output text)

echo "Subnet 1 ID: $SUBNET1_ID" #Subnet 1 ID: subnet-0a1c0e4c59c806dc1
echo "Subnet 2 ID: $SUBNET2_ID" #Subnet 2 ID: subnet-01ad0522e94437beb


#Create Route Table and Associate with Subnets
RT_ID=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=eks-rt}]' \
  --query 'RouteTable.RouteTableId' \
  --output text)

aws ec2 create-route \
  --route-table-id $RT_ID \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $IGW_ID

aws ec2 associate-route-table \
  --subnet-id $SUBNET1_ID \
  --route-table-id $RT_ID

aws ec2 associate-route-table \
  --subnet-id $SUBNET2_ID \
  --route-table-id $RT_ID

echo "Route Table ID: $RT_ID"
#Route Table ID: rtb-06310107d0e1f89ba


SG_ID=$(aws ec2 create-security-group \
  --group-name eks-sg \
  --description "Security group for EKS cluster" \
  --vpc-id $VPC_ID \
  --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=eks-sg}]' \
  --query 'GroupId' \
  --output text)

# Allow inbound traffic from within the VPC
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol all \
  --cidr 10.0.0.0/16

echo "Security Group ID: $SG_ID"
#Security Group ID: sg-0411dc3bbac2eb3a0

############################################### CREATE EKS CLUSTER ###############################################

#Create a JSON file for the EKS cluster configuration
tee <<EOF > eks-cluster-config.json    
{
  "name": "my-eks-cluster",
  "version": "1.31",
  "roleArn": "arn:aws:iam::470562161805:role/eks-cluster-role",
  "resourcesVpcConfig": {
    "subnetIds": [
      "subnet-0a1c0e4c59c806dc1",
      "subnet-01ad0522e94437beb"
    ],
    "securityGroupIds": [
      "sg-0411dc3bbac2eb3a0"
    ],
    "endpointPublicAccess": true,
    "endpointPrivateAccess": false
  },
  "logging": {
    "clusterLogging": [
      {
        "types": ["api", "audit", "authenticator", "controllerManager", "scheduler"],
        "enabled": true
      }
    ]
  }
}
EOF

#Create the EKS cluster using the configuration file
aws eks create-cluster --cli-input-json file://eks-cluster-config.json

#Check the status of the EKS cluster creation
aws eks describe-cluster --name my-eks-cluster --query 'cluster.status'

#Create the EKS cluster using eksctl (recommended) - (optional)
eksctl create cluster \
  --name my-eks-cluster \
  --version 1.28 \
  --region ap-southeast-1 \
  --nodes 2 \
  --node-type t3.medium \
  --enable-ssm

#Create IAM Role for EKS Node Group
cat > eks-node-trust-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

cat eks-node-trust-policy.json

#Create the IAM role for the EKS node group
aws iam create-role \
  --role-name eks-node-role \
  --assume-role-policy-document file://eks-node-trust-policy.json

echo "Node role created!"

#Assign the necessary policies to the EKS node role
# Policy 1
aws iam attach-role-policy \
  --role-name eks-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy

echo "Policy 1 attached"

# Policy 2
aws iam attach-role-policy \
  --role-name eks-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy

echo "Policy 2 attached"

# Policy 3
aws iam attach-role-policy \
  --role-name eks-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

echo "Policy 3 attached"

aws iam get-role --role-name eks-node-role


eksctl create cluster \
  --name my-eks-cluster \
  --version 1.30 \
  --region ap-southeast-1 \
  --nodegroup-name my-node-group \
  --nodes 2 \
  --node-type t3.medium



#Output:
#{
#    "Role": {
#        "Path": "/",
#        "RoleName": "eks-node-role",
#        "RoleId": "AROAJ5Z7J6K3X4EX4Y5",
#        "Arn": "arn:aws:iam::470562161805:role/eks-node-role",
#        "CreateDate": "2024-06-19T10:15:30Z",
#        "AssumeRolePolicyDocument": {
#            "Version": "2012-10-17",
#            "Statement": [
#                {
#                    "Effect": "Allow",
#                    "Principal": {
#                        "Service": "ec2.amazonaws.com"
#                    },
#                    "Action": "sts:AssumeRole"
#                }
#            ]
#        },
#        "MaxSessionDuration": 3600,
#        "RoleLastUsed": {
#            "LastUsedDate": "2024-06-19T10:15: 30Z",
#            "Region": "ap-southeast-1"
#        }
#    }
#}  




#Create a JSON file for the EKS node group configuration
#tee <<EOF > node-group.json
#  {
#  "clusterName": "my-eks-cluster",
#  "nodegroupName": "my-node-group",
#  "scalingConfig": {
#    "minSize": 2,
#    "maxSize": 4,
#    "desiredSize": 2
#  },
#  "instanceTypes": ["t3.medium"],
#  "subnets": [
#    "subnet-0a1c0e4c59c806dc1",
#    "subnet-01ad0522e94437beb"
#  ],
#  "nodeRole": "arn:aws:iam::${MY_ACCOUNT_ID}:role/eks-node-role",
#  "tags": {
#    "Environment": "lab"
#  }
#}
#EOF

#Create the EKS node group using the configuration file
#aws eks create-nodegroup --cli-input-json file://node-group.json

#Check the status of the EKS node group creation
 #aws eks describe-nodegroup \
 # --cluster-name my-eks-cluster \
 # --nodegroup-name my-node-group \
 # --query 'nodegroup.status'

#--> Node group status: Failed because subnet is not assigned the public IP address. To fix this, you need to enable auto-assign public IP for the subnets used by the node group.

#Enable auto-assign public IP for the subnets used by the node group
# Subnet 1
#aws ec2 modify-subnet-attribute \
#  --subnet-id subnet-0a1c0e4c59c806dc1 \
#  --map-public-ip-on-launch \
#  --region ap-southeast-1

#echo "Subnet 1 fixed"

# Subnet 2
#aws ec2 modify-subnet-attribute \
#  --subnet-id subnet-01ad0522e94437beb \
#  --map-public-ip-on-launch \
#  --region ap-southeast-1

#echo "Subnet 2 fixed"

#Check the subnets to confirm that auto-assign public IP is enabled
#aws ec2 describe-subnets \
#  --subnet-ids subnet-0a1c0e4c59c806dc1 subnet-01ad0522e94437beb \
#  --region ap-southeast-1 \
#  --query 'Subnets[*].[SubnetId,MapPublicIpOnLaunch]' \
#  --output table


#delete the EKS node group
#aws eks delete-nodegroup \
#  --cluster-name my-eks-cluster \
#  --nodegroup-name my-node-group \
#  --region ap-southeast-1

# Chờ ~2 phút
#echo "Waiting for deletion..."
#sleep 120

#aws eks describe-nodegroup \
#  --cluster-name my-eks-cluster \
#  --nodegroup-name my-node-group \
#  --region ap-southeast-1 2>&1 | grep -i "does not exist" && echo "Deleted successfully"


#recreate the EKS node group using the configuration file
#aws eks create-nodegroup --cli-input-json file://node-group.json
#echo "Node group creating... wait 5 minutes"

#validate the EKS node group creation
# Chờ ~5 phút
#watch -n 5 "aws eks describe-nodegroup \
#  --cluster-name my-eks-cluster \
#  --nodegroup-name my-node-group \
#  --region ap-southeast-1 \
#  --query 'nodegroup.status'"

# Hoặc chạy 1 lần
#aws eks describe-nodegroup \
#  --cluster-name my-eks-cluster \
#  --nodegroup-name my-node-group \
#  --region ap-southeast-1 \
#  --query 'nodegroup.status'


#Varify the EKS cluster
kubectl get nodes
kubectl cluster-info 


