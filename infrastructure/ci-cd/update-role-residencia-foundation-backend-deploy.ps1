$policyPath = Join-Path $PSScriptRoot 'trust-policy.json'

aws iam update-assume-role-policy --role-name residencia-foundation-backend-deploy --policy-document "file://$policyPath" --profile treinamento