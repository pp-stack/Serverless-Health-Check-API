# Serverless Health Check API

A fully-automated, production-ready serverless health-check API deployed on AWS using Terraform and GitHub Actions. This project demonstrates infrastructure as code, multi-environment deployments, security best practices, and CI/CD automation.

## 📋 Overview

This repository implements a simple health-check endpoint (`/health`) that:
1. Accepts GET or POST requests. POST requests must carry a JSON body containing a `payload` key (returns 400 if missing); GET is treated as a plain liveness check and requires no body.
2. Logs the request to CloudWatch
3. Stores request details in DynamoDB with a unique ID
4. Returns a 200 OK response with status information

The infrastructure is deployed across two environments:
- **Staging** (eu-west-1): Auto-deployed on push to `staging` branch
- **Production** (eu-west-1): Requires manual approval before deployment

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ API Gateway (REST API)                                      │
│ - GET/POST /health endpoint                                 │
│ - Request validation on POST (requires 'payload' key)       │
│ - Throttling: 50 req/s, 100 burst                          │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ Lambda Function (Python 3.12)                                │
│ - Validates JSON payload on POST                            │
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
- Dedicated CI/CD deploy role per environment (`staging-terraform-deploy-role` / `prod-terraform-deploy-role`), federated via GitHub OIDC (no long-lived AWS keys in GitHub), scoped to that environment's own `${env}-*` resources wherever AWS's IAM model allows resource-level ARNs. The one exception is API Gateway management, whose IAM model authorizes by HTTP verb against generated resource IDs rather than resource names — see `terraform/bootstrap/main.tf` for the reasoning.

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

✅ **Additional hardening**
- Point-in-time recovery enabled on both DynamoDB tables
- X-Ray active tracing on the Lambda function and the API Gateway stage
- `create_before_destroy` on the REST API to avoid downtime on replacement
- CloudWatch log retention set to 400 days

### Deferred Bonus Items

A few Checkov findings map directly to this project's own "Bonus Points (Optional)" list rather than a required item, and are intentionally left unaddressed with an inline `checkov:skip` + justification at each resource:

- **Customer-managed KMS key** (`CKV_AWS_119`, `CKV_AWS_158`, `CKV_AWS_173`) — both DynamoDB tables, the Lambda log group, and the Lambda environment variables currently use AWS-owned/managed encryption keys, which already satisfies the required "Encryption Everywhere" item. A CMK is listed as bonus.
- **Lambda in its own VPC** (`CKV_AWS_117`) — would need a NAT gateway or VPC endpoints for DynamoDB/CloudWatch egress, real recurring cost for a simple health check. Listed as bonus.
- **API key authentication on `/health`** (`CKV_AWS_59`) — this is meant to be a publicly callable liveness check, matching the spec's own curl-command requirement. Listed as bonus.

Two more findings are the same bonus category applied to alternate mechanisms:
- **API Gateway client-certificate auth** (`CKV2_AWS_51`) — another bonus-tier auth mechanism (like API keys); this is meant to be a publicly callable health check.
- **API Gateway WAFv2 web ACL** (`CKV2_AWS_29`) — an extra protection layer beyond what the spec asks for; the required DDoS/abuse mitigation (throttling) is already implemented via `aws_api_gateway_method_settings`.

A few other findings were suppressed as inappropriate for this specific workload rather than deferred as bonus work:
- **API Gateway response caching** (`CKV_AWS_120`, `CKV_AWS_225`) — caching a liveness check would make it report stale state instead of the current one.
- **Lambda DLQ** (`CKV_AWS_116`) — this Lambda is only ever invoked synchronously via API Gateway; a DLQ catches failed *async* invocations, which never happen here.
- **Lambda code-signing** (`CKV_AWS_272`) — needs a signing profile and a publish-time signing step; disproportionate infrastructure for this exercise.
- **Lambda reserved concurrency** (`CKV_AWS_115`) — a capacity/cost choice, not a security control; would just add another way for this simple function to throttle itself.
- **API Gateway access logging** (`CKV_AWS_76`) — needs the account-level `aws_api_gateway_account` CloudWatch role, a singleton shared by every API Gateway in the account/region. The current per-environment module structure isn't set up to safely co-manage that setting across separate staging/prod applies, so it's deferred rather than risk one environment's apply fighting another's.
- **GET method request validation** (`CKV2_AWS_53`) — GET has no request body to validate; the required `payload`-key check applies only to POST, which does have a validator attached.
- **State bucket hardening** (`CKV_AWS_18` access logging, `CKV_AWS_144` cross-region replication, `CKV_AWS_145` default KMS encryption, `CKV2_AWS_62` event notifications) — all real options for the Terraform state bucket, but disproportionate infrastructure (a log-target bucket, a second bucket in another region, a KMS key) for this exercise's remote state, which is already versioned, AES256-encrypted, and lock-protected. A lifecycle rule expiring noncurrent versions after 90 days *is* implemented, since that one's essentially free.

### A note on Checkov suppression comment placement

Checkov's Terraform parser only honors `# checkov:skip=<ID>:<reason>` when the comment line falls **inside** the resource's `{ }` block (its line number must be strictly between the block's start and end line) — a comment placed directly above the `resource` line, which is the convention several other tools (and Checkov's own GitHub Actions framework) accept, is silently ignored for Terraform. All suppressions in this repo are placed inside their resource blocks for that reason.

## 📦 Prerequisites

### AWS Account Setup

You need an AWS account and an initial credential (e.g. an admin IAM user, or `aws configure`) **only** to run the one-time bootstrap below. Every deployment after that runs through GitHub Actions with no long-lived AWS keys.

### One-time bootstrap (state backend + deploy roles)

The Terraform in `terraform/bootstrap/` creates, per environment:
- An S3 bucket + DynamoDB table for encrypted, locked Terraform remote state
- The GitHub OIDC provider (account-level, created once)
- A dedicated, least-privilege `${env}-terraform-deploy-role` that the CI pipeline assumes to deploy the actual health-check infrastructure

Before running it:
1. Fork/clone this repo and make it public.
2. Edit `terraform/bootstrap/environments/staging.tfvars` and `prod.tfvars`, replacing `github_org`/`github_repo` with your actual GitHub org/user and repo name.
3. Bootstrap can be run either locally or via the `Initial Deploy (Bootstrap)` GitHub Action:

   **Locally** (simplest for a first run):
   ```bash
   cd terraform/bootstrap
   terraform init
   terraform apply -var-file=environments/staging.tfvars
   terraform apply -var-file=environments/prod.tfvars   # manage_oidc_provider=false, reuses the OIDC provider from staging
   ```
   Note the `deploy_role_arn` output for each environment.

   **Via GitHub Actions** (`.github/workflows/initial-deploy.yml`, manual `workflow_dispatch`): since the deploy role doesn't exist until this runs, it needs its own one-time bootstrap credential — an admin-level IAM role you create by hand once, stored as the `AWS_BOOTSTRAP_ROLE_TO_ASSUME` secret on a `staging-bootstrap` / `prod-bootstrap` GitHub Environment. This is the same chicken-and-egg every OIDC setup has; running bootstrap locally avoids needing it at all.

4. **Create GitHub Secrets/Environments** for the actual deploy pipelines:
   - GitHub Environment `staging`, secret `AWS_ROLE_TO_ASSUME` = the `staging-terraform-deploy-role` ARN from step 3
   - GitHub Environment `prod`, secret `AWS_ROLE_TO_ASSUME` = the `prod-terraform-deploy-role` ARN from step 3
   - GitHub Environment `prod-approval` (no secrets needed) — used purely as a manual approval gate; add required reviewers under Settings → Environments

### Local Development (Optional)

To test locally, install:
- Terraform >= 1.8.5
- Python 3.12
- AWS CLI v2
- Git

## 🚀 CI/CD Pipeline

There are four workflows under `.github/workflows/`:

| Workflow | Trigger | Purpose |
|---|---|---|
| `pr-verify.yml` | Any pull request into `staging` or `prod` | Security scan + IaC validation + a **read-only** `terraform plan` for both environments, posted as a PR comment. Never applies. |
| `deploy-staging.yml` | Push to `staging` | Full pipeline, ending in an automatic `terraform apply` to the staging environment. |
| `deploy-prod.yml` | Push to `prod` | Same pipeline, gated by a manual approval step before `terraform apply` to production. |
| `initial-deploy.yml` | Manual (`workflow_dispatch`) | One-time/occasional bootstrap of the state backend + OIDC deploy role (see Prerequisites above). |

### Pipeline Overview (deploy-staging / deploy-prod)

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

#### PR Verification (Automatic)

Every pull request into `staging` or `prod` triggers `pr-verify.yml`: dependency/IaC scanning plus a `terraform plan` for both environments, so reviewers see the infrastructure diff before merge without anything actually being applied.

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
aws apigateway get-rest-apis --region eu-west-1
aws apigateway get-stages --rest-api-id <API_ID> --region eu-west-1
```

Or from Terraform output:
```bash
cd terraform
terraform init -backend-config=backend-configs/staging.backend
terraform output api_invoke_url
```

### Example: Send a Request

```bash
API_URL="https://<api_id>.execute-api.eu-west-1.amazonaws.com/staging/health"

# GET - plain liveness check, no body required (should return 200)
curl -X GET "$API_URL"

# POST with valid payload (should return 200)
curl -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -d '{"payload": "Health check data"}'

# Response:
# {
#   "status": "healthy",
#   "message": "Request processed and saved.",
#   "id": "550e8400-e29b-41d4-a716-446655440000"
# }

# POST missing payload (should return 400)
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
│   ├── pr-verify.yml                # PR check: scan + validate + plan (no apply)
│   ├── deploy-staging.yml           # Staging CI/CD pipeline
│   ├── deploy-prod.yml              # Production CI/CD pipeline
│   └── initial-deploy.yml           # One-time bootstrap workflow
├── terraform/
│   ├── main.tf                      # Root module, wires components
│   ├── variables.tf                 # Root variables
│   ├── outputs.tf                   # Root outputs (API URL)
│   ├── bootstrap/
│   │   ├── main.tf                  # State backend + OIDC provider + deploy role
│   │   ├── variables.tf
│   │   └── environments/
│   │       ├── staging.tfvars       # Bootstrap vars (staging)
│   │       └── prod.tfvars          # Bootstrap vars (prod)
│   ├── modules/
│   │   ├── dynamodb/
│   │   │   ├── main.tf              # DynamoDB table (SSE enabled)
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── lambda/
│   │   │   ├── main.tf              # Lambda function + IAM role + log group
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   └── api/
│   │       ├── main.tf              # API Gateway (REST, /health GET+POST, validation, throttling)
│   │       └── variables.tf
│   ├── environments/
│   │   ├── staging.tfvars           # Staging variable overrides (app module)
│   │   └── prod.tfvars              # Production variable overrides (app module)
│   └── backend-configs/
│       ├── staging.backend          # S3 remote state config (staging)
│       └── prod.backend             # S3 remote state config (prod)
├── lambda/
│   ├── handler.py                   # Lambda function logic
│   ├── requirements.txt             # Python dependencies (boto3)
│   └── deployment.zip               # Packaged Lambda (generated by CI)
├── .gitignore                       # Git ignore rules
└── README.md                        # This file
```

## 🎯 Design Choices & Assumptions

### Terraform Architecture

**Modular Design**: Separated resources into reusable modules:
- `dynamodb`: DynamoDB table with SSE (can be reused across projects)
- `lambda`: Lambda function + scoped IAM role + log group
- `api`: API Gateway with validation and throttling
- `bootstrap`: One-time setup for remote state (S3 + DynamoDB lock table) plus the GitHub OIDC provider and per-environment deploy role

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

**Assumption**: State buckets already exist in AWS; user creates them via the bootstrap process (locally or via `initial-deploy.yml`) described in Prerequisites.

**Note on bootstrap's own state**: `terraform/bootstrap` intentionally has no remote backend of its own (it's what creates one), so it uses local state. When run via `initial-deploy.yml` that local state is cached across workflow runs with `actions/cache` so re-running the workflow updates existing resources rather than trying to recreate them — a deliberate, narrow trade-off for this one-time bootstrap module, not a general pattern.

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

**Deploy Role Policy** (`terraform/bootstrap/main.tf`):
- One dedicated role per environment (`staging-terraform-deploy-role`, `prod-terraform-deploy-role`), assumed only from this repo via GitHub OIDC (`sts:AssumeRoleWithWebIdentity`, condition-scoped to `repo:<org>/<repo>:*`)
- Every statement scopes `Resource` to that environment's own `${env}-*` name prefix where the AWS action supports resource-level ARNs (DynamoDB, Lambda, IAM roles, CloudWatch Logs)
- The one exception is API Gateway: its management API has no resource-name ARNs — permissions are granted by HTTP verb (`apigateway:GET/POST/PUT/PATCH/DELETE`) against the generic `/restapis` path, since REST API IDs don't exist until after creation. This is a wildcard the AWS IAM model makes mandatory, not one chosen for convenience.

### Multi-Environment Handling

**Staging vs. Production**:
- `terraform/environments/staging.tfvars` / `prod.tfvars`: app module vars, both in eu-west-1
- `terraform/bootstrap/environments/staging.tfvars` / `prod.tfvars`: bootstrap-only vars (state bucket/lock table names, GitHub org/repo, OIDC provider ownership)
- Resource names prefixed with env (e.g., `staging-requests-db`, `prod-requests-db`)
- Separate state files via backend config

**Benefit**: Isolated state per environment, prevents accidental cross-environment changes.

### GitHub OIDC Authentication

**Why not static credentials**:
- No AWS access keys in GitHub secrets
- OIDC token is short-lived (1 hour)
- Automatic credential rotation
- Better for secret management

**Assumption**: The GitHub OIDC provider and per-environment deploy role are created by the one-time bootstrap step (see Prerequisites), not assumed to pre-exist.

### CI/CD Security Scanning

**Trivy** (Dependency scanning):
- Scans `lambda/` directory for vulnerabilities
- Results in SARIF format → GitHub Security tab
- No need for separate `safety` tool (redundant)
- The upload-to-Security-tab step uses `continue-on-error: true`: it needs GitHub Advanced Security, which isn't available on private repositories under the free plan. The scan itself still always runs; only the upload can fail (e.g. while this repo is private), and that no longer blocks the pipeline. Once the repo is public (or on a plan with Advanced Security), results start appearing in the Security tab automatically - no workflow change needed.

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

The handler expects an API Gateway proxy-style event (it reads `httpMethod` and a JSON-encoded `body`), so a direct invoke needs to mimic that shape:

```bash
cat > test-event.json <<'EOF'
{
  "httpMethod": "POST",
  "body": "{\"payload\": \"test\"}"
}
EOF

aws lambda invoke \
  --function-name staging-health-check-function \
  --cli-binary-format raw-in-base64-out \
  --payload file://test-event.json \
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
