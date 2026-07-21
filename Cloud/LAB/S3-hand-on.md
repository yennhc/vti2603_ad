
---

##  Setup

```bash
yourname="ynguyen"
bucket="$yourname-lab-bucket-$(date +%s)"
```

Bucket name is suffixed with a timestamp to satisfy S3's global-uniqueness requirement.

---

## 1. Investigate

Check current identity and existing permissions before making any changes.

```bash
# Check who you are
aws sts get-caller-identity

# List attached policies for the user
aws iam list-attached-user-policies --user-name admin-user

# List inline policies
aws iam list-user-policies --user-name admin-user

# Check if user is in any groups
aws iam list-groups-for-user --user-name admin-user
```

---

## 2. Add S3 full access to admin-user

```bash
aws iam attach-user-policy \
  --user-name admin-user \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
```

---

## 3. Create S3

```bash
# List bucket
aws s3 ls

#Remove s3 bucket
aws s3 rm s3://$bucket --recursive --region ap-southeast-1

#Delete S3 bucket
aws s3api delete-bucket \
    --bucket $bucket \
    --region ap-southeast-1


# Create bucket
aws s3api create-bucket \
  --bucket $bucket \
  --region ap-southeast-1 \
  --create-bucket-configuration LocationConstraint=ap-southeast-1

# Put bucket versioning
aws s3api put-bucket-versioning \
  --bucket $bucket \
  --versioning-configuration Status=Enabled \
  --region ap-southeast-1
```

---

--- Delete bucket with versioning --- 
```bash
# Delete all object versions (including delete markers)
aws s3api list-object-versions \
  --bucket $bucket \
  --region ap-southeast-1 \
  --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
  --output json | \
  aws s3api delete-objects \
    --bucket $bucket \
    --region ap-southeast-1 \
    --delete file:///dev/stdin

# Delete all delete markers
aws s3api list-object-versions \
  --bucket $bucket \
  --region ap-southeast-1 \
  --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
  --output json | \
  aws s3api delete-objects \
    --bucket $bucket \
    --region ap-southeast-1 \
    --delete file:///dev/stdin

# Now delete the bucket
aws s3api delete-bucket \
  --bucket $bucket \
  --region ap-southeast-1

#Or the simpler shortcut — force delete with rb:
aws s3 rb s3://$bucket --force --region ap-southeast-1



```

## 4. Upload & Download

```bash
# Create local folder
mkdir -p my_data && cd my_data

echo "hello world" > hello.txt

# Create my_data/ "folder" marker on the bucket
aws s3api put-object \
  --bucket $bucket \
  --key my_data/ \
  --region ap-southeast-1

# Upload file to S3
aws s3 cp hello.txt s3://$bucket/my_data/ --region ap-southeast-1

# View file hello.txt in bucket (stream to stdout)
aws s3 cp s3://$bucket/my_data/hello.txt - --region ap-southeast-1

# Upload folder to S3
aws s3 cp my_data s3://$bucket/my_data_1 --recursive --region ap-southeast-1

# List objects in bucket
aws s3 ls s3://$bucket --region ap-southeast-1

# Download objects from bucket
aws s3 cp s3://$bucket/my_data/ ./downloaded_data --recursive --region ap-southeast-1
```

---

## 5. Lifecycle rule

Apply a lifecycle configuration (`lifecycle.json`) that expires old noncurrent versions and transitions objects to cheaper storage classes over time.

```bash
aws s3api put-bucket-lifecycle-configuration \
--bucket $bucket \
--lifecycle-configuration file://lifecycle.json
```

`lifecycle.json`:

```json
{
  "Rules": [
    {
      "ID": "DeleteOldVersions",
      "Filter": {},
      "Status": "Enabled",
      "NoncurrentVersionExpiration": {
        "NoncurrentDays": 30
      }
    },
    {
      "ID": "TransitionToGlacier",
      "Filter": {},
      "Status": "Enabled",
      "Transitions": [
        {
          "Days": 30,
          "StorageClass": "STANDARD_IA"
        },
        {
          "Days": 90,
          "StorageClass": "GLACIER"
        }
      ]
    }
  ]
}
```

- **DeleteOldVersions**: noncurrent object versions (from versioning) expire after 30 days.
- **TransitionToGlacier**: objects move to Standard-IA at 30 days, then to Glacier at 90 days.


---

## 6. View lifecycle configuration

```bash
aws s3api get-bucket-lifecycle-configuration \
    --bucket $bucket \
    --region ap-southeast-1
```

---

## 7. Lifecycle rule expiration

```bash
# Upload a file
aws s3 cp test.txt s3://$bucket/test.txt

# Upload the same file again (creates a new version)
aws s3 cp test.txt s3://$bucket/test.txt

# List objects with versioning (you'll see 2 versions)
aws s3api list-objects-v2 \
  --bucket $bucket \
  --prefix test.txt \
  --output json

# Wait 30 days...
# Then check again - the noncurrent version should be gone
``` 

