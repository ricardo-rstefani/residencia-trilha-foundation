[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'
$roleName = 'residencia-sam-lab-deploy'
$policyName = 'sam-lab-deploy'
$expectedAccount = '113011715524'
$trustPath = Join-Path $PSScriptRoot 'github-actions-trust-policy.json'
$permissionsPath = Join-Path $PSScriptRoot 'github-actions-permissions-policy.json'

function Invoke-TrainingAws {
    param([string[]]$Arguments)
    $result = & aws @Arguments --profile treinamento --region us-east-1 --no-cli-pager
    if ($LASTEXITCODE -ne 0) {
        throw "AWS CLI falhou: $($Arguments[0]) $($Arguments[1]). Operacao interrompida."
    }
    return $result
}

# Validate both local documents before making any AWS calls.
Get-Content -LiteralPath $trustPath -Raw | ConvertFrom-Json | Out-Null
Get-Content -LiteralPath $permissionsPath -Raw | ConvertFrom-Json | Out-Null
Get-Command aws -ErrorAction Stop | Out-Null

if ($PSCmdlet.ShouldProcess("$roleName na conta $expectedAccount (profile treinamento)", 'Criar role OIDC e sua inline policy')) {
    $identity = Invoke-TrainingAws -Arguments @('sts', 'get-caller-identity', '--output', 'json') | ConvertFrom-Json
    if ($identity.Account -ne $expectedAccount) {
        throw "O profile treinamento aponta para a conta $($identity.Account); esperada $expectedAccount."
    }

    # CreateRole fails if the role already exists; use update-role.ps1 in that case.
    Invoke-TrainingAws -Arguments @(
        'iam', 'create-role', '--role-name', $roleName,
        '--assume-role-policy-document', "file://$trustPath",
        '--description', 'GitHub Actions OIDC deploy da stack residencia-sam-lab',
        '--output', 'json'
    ) | Out-Null

    try {
        Invoke-TrainingAws -Arguments @(
            'iam', 'put-role-policy', '--role-name', $roleName,
            '--policy-name', $policyName, '--policy-document', "file://$permissionsPath"
        ) | Out-Null
    }
    catch {
        throw "A role foi criada, mas a inline policy nao foi aplicada. Corrija a causa e execute update-role.ps1. Detalhe: $_"
    }

    Write-Host "Role criada com a policy ${policyName}: arn:aws:iam::${expectedAccount}:role/$roleName"
}
