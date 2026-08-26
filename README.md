# Serverless Health Check API

A fully-automated, production-ready serverless health-check API deployed on AWS using Terraform and GitHub Actions. This project demonstrates infrastructure as code, multi-environment deployments, security best practices, and CI/CD automation.

## 📋 Overview

This repository implements a simple health-check endpoint (`/health`) that:
1. Accepts POST requests with a JSON payload containing a `payload` key
2. Validates the incoming request (returns 400 if `payload` is missing)
3. Logs the request to CloudWatch
4. Stores request details in DynamoDB with a unique ID
5. Returns a 200 OK response with status information

The infrastructure is deployed across two environments:
- **Staging** (eu-west-1): Auto-deployed on push to `staging` branch
- **Production** (eu-west-1): Requires manual approval before deployment

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ API Gateway (REST API)                                      │
│ - POST /health endpoint                                     │
│ - Request validation (requires 'payload' key)              │
│ - Throttling: 50 req/s, 100 burst                          │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ Lambda Function (Python 3.14)                                │
│ - Validates JSON payload                                    │
│ - Logs to CloudWatch                                        │
│ - Writes to DynamoDB table                                  │
│ - IAM role: Least-privilege (logs + DynamoDB:PutItem)      │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ DynamoDB Table (Server-Side Encryption enabled)            │
│ - Partition key: id (string)                                │
│ - Pay-per-request billing                                   │
│ - SSE enabled by default                                    │
└─────────────────────────────────────────────────────────────┘
```

## 🔐 Security Features

✅ **Encryption Everywhere**
- DynamoDB Server-Side Encryption (SSE) enabled
- Remote state encrypted in S3 (AES256)
- State lock table with SSE

✅ **Least-Privilege IAM**
- Lambda role scoped to specific resources (no wildcards)
- Lambda can only write to its specific DynamoDB table
- Lambda can only write logs to its own CloudWatch log group

✅ **Input Validation**
- API Gateway request model validation
- Lambda validates required `payload` key
- Returns 400 for invalid/missing payload

✅ **API Gateway Protection**
- Throttling: 50 requests/second, 100 burst
- Request validation prevents invalid JSON
- CloudWatch metrics and logging enabled

✅ **CI/CD Security**
- Trivy filesystem vulnerability scanning
- Checkov IaC security scanning (soft-fail for warnings)
- GitHub OIDC for credential-less AWS access
- Pinned action versions

## 📦 Prerequisites

### AWS Account Setup

1. **Create AWS Account** with credentials:
   - Access Key ID
   - Secret Access Key
   - Or configure AWS CLI: `aws configure`

2. **Create S3 buckets for remote state** (unique globally):
   ```bash
   # Staging state bucket
   aws s3 mb s3://staging-health-check-terraform-state --region us-east-1
   
   # Prod state bucket
   aws s3 mb s3://prod-health-check-terraform-state --region eu-west-1
   ```

3. **Enable versioning on state buckets**:
   ```bash
   aws s3api put-bucket-versioning \
     --bucket staging-health-check-terraform-state \
     --versioning-configuration Status=Enabled \
     --region us-east-1
   ```

### GitHub Setup

1. **Fork this repository** and make it public

2. **Configure GitHub OIDC for AWS** (recommended):
   - Follow AWS docs: [Use GitHub Actions with AWS](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
   - Create IAM role with trust policy for GitHub:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": {
           "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
         },
         "Action": "sts:AssumeRoleWithWebIdentity",
         "Condition": {
           "StringLike": {
             "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/Serverless-Health-Check-API:*"
           }
         }
       }
     ]
   }
   ```

3. **Create GitHub Secrets** (required):
   - `AWS_ROLE_TO_ASSUME`: ARN of the IAM role created above
     - Format: `arn:aws:iam::ACCOUNT_ID:role/github-actions-role`

### Local Development (Optional)

To test locally, install:
- Terraform >= 1.8.5
- Python 3.14
- AWS CLI v2
- Git

## 🚀 CI/CD Pipeline

### Pipeline Overview

Both workflows (staging and prod) follow this flow:

```
1. Security Scan (Trivy)
   └─ Filesystem vulnerability scan of Lambda
   └─ Results uploaded to GitHub Security tab

2. IaC Validation (parallel)
   ├─ Terraform fmt check
   ├─ Terraform validate
   └─ Checkov IaC security scan

3. Package Lambda
   ├─ Install dependencies from requirements.txt
   ├─ Bundle into deployment.zip
   └─ Upload as artifact (5-day retention)

4. Deploy (Staging)
   ├─ Auto-deploy on push to `staging` branch
   ├─ Terraform init → plan → apply
   └─ Output API endpoint

5. Deploy (Production)
   ├─ Requires manual approval via GitHub environment
   ├─ Runs after approval
   └─ Terraform init → plan → apply to eu-west-1
```

### Triggering Deployments

#### Staging Deployment (Automatic)

Push to the `staging` branch:

GitHub Actions will automatically:
1. Run security scans
2. Validate Terraform
3. Package Lambda
4. Deploy to AWS staging environment

Check deployment status in GitHub Actions tab.

#### Production Deployment (Manual Approval)

1. Push to the `prod` branch:

2. GitHub Actions will:
   - Run all security/validation jobs
   - Package Lambda
   - Wait for manual approval at environment `prod-approval`

3. Approve deployment:
   - Go to GitHub Actions → `Deploy Prod` workflow run
   - Click "Review deployments"
   - Click "Approve and deploy"

4. Deployment proceeds to production (eu-west-1)

## 📡 Testing the Endpoint

### Get the API Endpoint URL

From GitHub Actions logs or via AWS CLI:
```bash
aws apigateway get-rest-apis --region us-east-1
aws apigateway get-stages --rest-api-id <API_ID> --region us-east-1
```

Or from Terraform output:
```bash
cd terraform
terraform init -backend-config=backend-configs/staging.backend
terraform output api_invoke_url
```

### Example: Send a Request

```bash
API_URL="https://<api_id>.execute-api.us-east-1.amazonaws.com/staging/health"

# Valid request (should return 200)
curl -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -d '{"payload": "Health check data"}'

# Response:
# {
#   "status": "healthy",
#   "message": "Request processed and saved.",
#   "id": "550e8400-e29b-41d4-a716-446655440000"
# }

# Invalid request (missing payload, should return 400)
curl -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -d '{}'

# Response:
# {
#   "error": "Missing required key 'payload'"
# }
```

### View Logs

DynamoDB items stored:
```bash
aws dynamodb scan \
  --table-name staging-requests-db \
  --region eu-west-1
```

CloudWatch logs:
```bash
aws logs tail /aws/lambda/staging-health-check-function \
  --region eu-west-1 \
  --follow
```

## 🏗️ Project Structure

```
Serverless-Health-Check-API/
├── .github/workflows/
│   ├── deploy-staging.yml          # Staging CI/CD pipeline
│   └── deploy-prod.yml             # Production CI/CD pipeline
├── terraform/
│   ├── main.tf                     # Root module, wires components
│   ├── variables.tf                # Root variables
│   ├── outputs.tf                  # Root outputs (API URL)
│   ├── bootstrap/
│   │   ├── main.tf                 # S3 state bucket + DynamoDB lock table
│   │   └── variables.tf
│   ├── modules/
│   │   ├── dynamodb/
│   │   │   ├── main.tf             # DynamoDB table (SSE enabled)
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── lambda/
│   │   │   ├── main.tf             # Lambda function + IAM role
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   └── api/
│   │       ├── main.tf             # API Gateway (REST, /health, validation, throttling)
│   │       └── variables.tf
│   ├── environments/
│   │   ├── staging.tfvars          # Staging variable overrides
│   │   └── prod.tfvars             # Production variable overrides
│   └── backend-configs/
│       ├── staging.backend         # S3 remote state config (staging)
│       └── prod.backend            # S3 remote state config (prod)
├── lambda/
│   ├── handler.py                  # Lambda function logic
│   ├── requirements.txt            # Python dependencies (boto3)
│   └── deployment.zip              # Packaged Lambda (generated by CI)
├── .gitignore                       # Git ignore rules
└── README.md                        # This file
```

## 🎯 Design Choices & Assumptions

### Terraform Architecture

**Modular Design**: Separated resources into reusable modules:
- `dynamodb`: DynamoDB table with SSE (can be reused across projects)
- `lambda`: Lambda function + scoped IAM role
- `api`: API Gateway with validation and throttling
- `bootstrap`: One-time setup for remote state (S3 + DynamoDB lock table)

**Benefits**:
- Reusable across multiple projects
- Clear separation of concerns
- Easy to extend (e.g., add KMS CMK for encryption)

### Remote State Management

**S3 + DynamoDB Lock Table**:
- State stored in versioned S3 bucket (AES256 encryption)
- DynamoDB table prevents concurrent applies
- Both encrypted at rest
- Backend config in `terraform/backend-configs/` (separate from tfvars)

**Assumption**: State buckets already exist in AWS; user creates them via bootstrap process.

### Lambda Packaging

**CI-Based Packaging**:
- Lambda dependencies installed in CI (`pip install -r requirements.txt -t package/`)
- Entire directory zipped as `lambda/deployment.zip`
- Artifact stored 5 days for debugging

**Why**: Keeps repository clean, dependencies resolved consistently in CI environment.

### API Gateway Validation

**Request Model + Validator**:
- API Gateway validates JSON schema before Lambda invocation
- `payload` key is required
- Invalid requests rejected at API layer (400 Bad Request)
- Reduces Lambda invocation cost and improves security

**Why**: Protects Lambda from malformed input, reduces unnecessary executions.

### IAM Least Privilege

**Lambda Role Policy**:
```json
{
  "Effect": "Allow",
  "Action": ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
  "Resource": "arn:aws:logs:REGION:ACCOUNT:log-group:/aws/lambda/FUNCTION_NAME:*"
},
{
  "Effect": "Allow",
  "Action": ["dynamodb:PutItem"],
  "Resource": "DYNAMODB_TABLE_ARN"
}
```
- No wildcards (*) in resource ARNs
- Only allows PutItem to its specific table
- Only logs to its specific log group

### Multi-Environment Handling

**Staging vs. Production**:
- `terraform/environments/staging.tfvars`: staging vars (us-east-1)
- `terraform/environments/prod.tfvars`: prod vars (eu-west-1)
- Resource names prefixed with env (e.g., `staging-requests-db`, `prod-requests-db`)
- Separate state files via backend config

**Benefit**: Isolated state per environment, prevents accidental cross-environment changes.

### GitHub OIDC Authentication

**Why not static credentials**:
- No AWS access keys in GitHub secrets
- OIDC token is short-lived (1 hour)
- Automatic credential rotation
- Better for secret management

**Assumption**: AWS account has OIDC provider configured for GitHub.

### CI/CD Security Scanning

**Trivy** (Dependency scanning):
- Scans `lambda/` directory for vulnerabilities
- Results in SARIF format → GitHub Security tab
- No need for separate `safety` tool (redundant)

**Checkov** (IaC scanning):
- Checks Terraform against security best practices
- `soft_fail: true` allows warnings in STG but not in PROD
- Catches issues like missing encryption, overly permissive IAM

### Throttling Strategy

**50 req/s, 100 burst**:
- Protects backend from DDoS
- Suitable for health-check endpoints
- Configurable in `terraform/modules/api/main.tf`

## 🔧 Local Development / Troubleshooting

### Initialize Terraform Locally

```bash
cd terraform

# Initialize backend with staging config
terraform init -backend-config=backend-configs/staging.backend

# View what will be deployed
terraform plan -var-file=environments/staging.tfvars

# Deploy to staging (requires AWS credentials)
terraform apply -var-file=environments/staging.tfvars
```

### Destroy Environment

```bash
cd terraform

terraform destroy -var-file=environments/staging.tfvars
```

### View CloudWatch Logs

```bash
# Real-time tail
aws logs tail /aws/lambda/staging-health-check-function --follow

# Get recent logs
aws logs tail /aws/lambda/staging-health-check-function --max-items 20
```

### Lambda Invocation Testing

```bash
# Direct Lambda invocation
aws lambda invoke \
  --function-name staging-health-check-function \
  --payload '{"payload": "test"}' \
  --region eu-west-1 \
  response.json

cat response.json
```

## 📝 Commit Message Guidelines

For clear commit history (used in review):

```
<type>(<scope>): <subject>

<body>

Closes #issue (if applicable)
```

**Types**: `feat`, `fix`, `docs`, `infra`, `ci`, `test`

**Examples**:
- `infra(terraform): add DynamoDB table with SSE`
- `ci(workflows): update action versions to v4`
- `feat(lambda): validate payload key in POST request`
- `docs(readme): add deployment instructions`

## 📚 References

- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)
- [GitHub Actions Security](https://docs.github.com/en/actions/security-guides)
- [AWS Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/lambda-intro-execution-role.html)
- [DynamoDB Encryption](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/encryption.html)
- [API Gateway Request Validation](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-request-validation.html)

## 📄 License

This project is provided as-is for evaluation purposes.

---

**Last Updated**: August 2026
