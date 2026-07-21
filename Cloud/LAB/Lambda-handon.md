# Lambda Hands-on Script Walkthrough
---

## 0. Setup

```bash
region="ap-southeast-1"
function_name="lab-hello-world"
role_name="lambda-execution-role"
```

---

## 1. Investigate

Check current identity and capture the account ID (needed to build the role ARN later).

```bash
# Check who you are / get account id
aws sts get-caller-identity

account_id=$(aws sts get-caller-identity --query Account --output text)
```

---

## 2. Create IAM execution policy

Write the trust policy that allows the Lambda service to assume the role, create the role, and attach the AWS-managed basic execution policy (CloudWatch Logs access).

```bash
# Trust policy: allows the Lambda service to assume this role
cat > trust-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create the execution role
aws iam create-role \
  --role-name $role_name \
  --assume-role-policy-document file://trust-policy.json

# Attach basic execution policy (grants CloudWatch Logs access)
aws iam attach-role-policy \
  --role-name $role_name \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# IAM role propagation can take a few seconds before it's usable by Lambda
sleep 10
```

---

## 3. Create function code

Write the Lambda handler and package it into a deployment zip.

```python
def lambda_handler(event, context):
    """
    Simple Hello World Lambda function

    event: Input data from trigger (S3, API Gateway, etc)
    context: Metadata about function execution
    """
    print(f"Event received: {event}")

    return {
        'statusCode': 200,
        'body': 'Hello from Lambda!'
    }
```

```bash
zip lambda-function.zip index.py
```

---

## 4. Deploy to Lambda

Create the function using the role built from `account_id` + `role_name`, then test-invoke it and print the response.

```bash
aws lambda create-function \
  --function-name $function_name \
  --runtime python3.11 \
  --role arn:aws:iam::${account_id}:role/${role_name} \
  --handler index.lambda_handler \
  --zip-file fileb://lambda-function.zip \
  --region $region

# Test invoke
aws lambda invoke \
  --function-name $function_name \
  --payload '{"key": "value"}' \
  response.json \
  --region $region \
  --cli-binary-format raw-in-base64-out

cat response.json
```

Expected `response.json`:

```json
{"statusCode": 200, "body": "Hello from Lambda!"}
```

---

## Cleanup

See [`Lambda-cleanup.sh`](Lambda-cleanup.sh) to delete the function, IAM role, and local generated files after the lab.
