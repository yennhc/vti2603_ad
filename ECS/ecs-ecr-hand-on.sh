#!/bin/bash

###############################Step1: Create a simple web application and Dockerfile###############################

#Create directory for the project
mkdir -p /home/ec2-user/ecs-ecr-lab

#Create index.html file
cat <<EOT >> /home/ec2-user/ecs-ecr-lab/index.html
<!doctype html>
<html>
  <head>
    <title>ECS + ECR Lab</title>
  </head>
  <body>
    <h1>Chào từ Amazon ECS Fargate!</h1>
    <p>Image này được lưu trong Amazon ECR.</p>
  </body>
</html>
EOT

#Create Dockerfile
cat <<EOT >> /home/ec2-user/ecs-ecr-lab/Dockerfile
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 80
EOT


#Try to build the Docker image
cd /home/ec2-user/ecs-ecr-lab
#docker build -t ecs-ecr-lab:1.0 .
docker build --platform linux/amd64 -t ecs-ecr-lab:1.0 .
docker run --rm -dp 8080:80 ecs-ecr-lab:1.0

###############################Step2: Create repository in ECR and push image###############################

#Set environment variables
export AWS_REGION=ap-southeast-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export REPOSITORY=ecs-ecr-lab

#Create ECR repository
aws ecr create-repository --repository-name $REPOSITORY --region $AWS_REGION



#Login to ECR and push the Docker image
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

#Tag the Docker image and push it to ECR
docker tag ecs-ecr-lab:1.0 \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$REPOSITORY:1.0

#Push the Docker image to ECR
docker push \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$REPOSITORY:1.0


################################Step3: Create ECS cluster and task definition###############################

#Create a service-linked role for ECS
aws iam create-service-linked-role \
  --aws-service-name ecs.amazonaws.com

#Create new definition for ECS task
cat <<EOT >> /home/ec2-user/ecs-ecr-lab/task-definition.json
{
  "family": "ecs-ecr-lab-task",
  "networkMode": "awsvpc",
  "containerDefinitions": [
    {
      "name": "ecs-ecr-lab-container",
      "image": "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$REPOSITORY:1.0",
      "portMappings": [
        {
          "containerPort": 80,
          "hostPort": 80,
          "protocol": "tcp"
        }
      ],
      "essential": true
    }
  ],
  "requiresCompatibilities": [
    "FARGATE"
  ],
  "cpu": "256",
  "memory": "512"
}
EOT

