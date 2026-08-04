#!/bin/bash

#Create a namespace for the demo application
kubectl create namespace demo

#Create a deployment for the demo application
tee nginx-deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  namespace: demo
spec:
  replicas: 2
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
        image: nginx:latest
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
EOF

kubectl apply -f nginx-deployment.yaml


tee nginx-service.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  namespace: demo
spec:
  type: LoadBalancer
  selector:
    app: nginx
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
EOF

kubectl apply -f nginx-service.yaml


########### Varify the deployment and service ##################

# Kiểm tra pods
kubectl get pods -n demo

# Kiểm tra service
kubectl get svc -n demo

# Xem chi tiết deployment
kubectl describe deployment nginx-deployment -n demo


#Access the demo application using the LoadBalancer service
kubectl get svc -n demo -w

http://<LoadBalancer-IP>

