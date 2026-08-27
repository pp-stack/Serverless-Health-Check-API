env               = "prod"
aws_region        = "eu-west-1"
project           = "prod-health-check"
state_bucket_name = "prod-health-check-terraform-state"
state_lock_table  = "prod-terraform-locks"

github_org  = "pp-stack"
github_repo = "Serverless-Health-Check-API"

# The OIDC provider is an account-level singleton. If staging already
# bootstrapped it in this same AWS account, leave this false. Set it to
# true only if prod lives in a separate AWS account.
manage_oidc_provider = false

# Same singleton reasoning as manage_oidc_provider above - the API Gateway
# CloudWatch Logs role is account/region-wide, not per-environment.
manage_apigateway_account_settings = false
