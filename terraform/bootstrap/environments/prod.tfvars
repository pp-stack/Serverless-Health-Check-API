env               = "prod"
aws_region        = "eu-west-1"
project           = "prod-health-check"
state_bucket_name = "prod-health-check-terraform-state"
state_lock_table  = "prod-terraform-locks"

# TODO: replace with your GitHub org/user and repository name
github_org  = "your-github-username"
github_repo = "Serverless-Health-Check-API"

# The OIDC provider is an account-level singleton. If staging already
# bootstrapped it in this same AWS account, leave this false. Set it to
# true only if prod lives in a separate AWS account.
manage_oidc_provider = false
