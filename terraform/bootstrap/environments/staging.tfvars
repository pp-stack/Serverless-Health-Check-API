env               = "staging"
aws_region        = "eu-west-1"
project           = "staging-health-check"
state_bucket_name = "staging-health-check-terraform-state"
state_lock_table  = "staging-terraform-locks"

github_org  = "pp-stack"
github_repo = "Serverless-Health-Check-API"

# Creates the account's GitHub OIDC provider. If prod bootstraps into the
# same AWS account, set manage_oidc_provider = false there instead.
manage_oidc_provider = true

# Configures the account's API Gateway CloudWatch Logs role. If prod
# bootstraps into the same AWS account, set this to false there instead.
manage_apigateway_account_settings = true
