#!/bin/bash

region="ap-southeast-1"
function_name="lab-hello-world"
role_name="lambda-execution-role"

################## Delete Lambda function ##################

aws lambda delete-function \
  --function-name $function_name \
  --region $region

######################################################################


################## Delete IAM execution role ##################

# Detach the managed policy before the role can be deleted
aws iam detach-role-policy \
  --role-name $role_name \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

aws iam delete-role \
  --role-name $role_name

######################################################################


################## Remove local hand-on artifacts ##################

rm -f trust-policy.json index.py lambda-function.zip response.json

######################################################################
