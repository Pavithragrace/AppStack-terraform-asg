# Step-by-step (ready)

## A) Create remote backend (S3 + DynamoDB)
```bash
cd backend-bootstrap
cp terraform.tfvars.example terraform.tfvars
# Edit state_bucket_name (unique)
terraform init
terraform apply
```

Copy outputs:
- state_bucket_name
- dynamodb_table_name

## B) Enable backend for main terraform
Go to `terraform/` and:
1) Copy `backend.tf.example` -> `backend.tf`
2) Replace bucket + table values
3) Run:
```bash
terraform init -reconfigure
```

## C) Deploy infrastructure (ALB + ASG + RDS + S3 + WAF)
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Fill db_password + static_bucket_prefix (+ app_repo_url)
terraform plan
terraform apply
```

## D) Validate
Open:
- terraform output -raw application_url
Then:
- /health must return 200

## E) Zero-downtime deployment (ASG Instance Refresh)
Change in terraform.tfvars:
- app_repo_ref (or any LT input)
Then:
```bash
terraform apply
```
In AWS Console: Auto Scaling Group -> Instance refresh.

## F) Cleanup
```bash
terraform destroy
cd ../backend-bootstrap
terraform destroy
```
