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

if ($PSCmdlet.ShouldProcess("$roleName na conta $expectedAccount (profile treinamento)", 'Atualizar trust e inline policy da role OIDC')) {
    $identity = Invoke-TrainingAws -Arguments @('sts', 'get-caller-identity', '--output', 'json') | ConvertFrom-Json
    if ($identity.Account -ne $expectedAccount) {
        throw "O profile treinamento aponta para a conta $($identity.Account); esperada $expectedAccount."
    }

    # Fail before mutations if the role does not exist or cannot be read.
    Invoke-TrainingAws -Arguments @('iam', 'get-role', '--role-name', $roleName, '--output', 'json') | Out-Null

    Invoke-TrainingAws -Arguments @(
        'iam', 'update-assume-role-policy', '--role-name', $roleName,
        '--policy-document', "file://$trustPath"
    ) | Out-Null

    try {
        Invoke-TrainingAws -Arguments @(
            'iam', 'put-role-policy', '--role-name', $roleName,
            '--policy-name', $policyName, '--policy-document', "file://$permissionsPath"
        ) | Out-Null
    }
    catch {
        throw "A trust foi atualizada, mas a inline policy nao foi aplicada. Corrija a causa e execute este script novamente. Detalhe: $_"
    }

    Write-Host "Trust e policy $policyName atualizadas na role $roleName."
}
