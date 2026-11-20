# Role OIDC do laboratorio SAM

Estes arquivos sao definicoes locais para revisao. Sua criacao no repositorio
nao cria nem atualiza roles na AWS.

| Role proposta | Trust | Policy de permissoes |
| --- | --- | --- |
| `residencia-sam-lab-deploy` | `github-actions-trust-policy.json` | `github-actions-permissions-policy.json` |

O workflow assume uma unica role via OIDC. O comando `sam deploy` nao informa
`--role-arn`: ao criar a stack sem role de servico, o CloudFormation usa uma
sessao temporaria baseada nas credenciais da role do Actions para provisionar
as Lambdas. As permissoes ficam consolidadas na policy dessa role.

As definicoes correspondem a conta `113011715524`, regiao `us-east-1`, stack
`residencia-sam-lab` e aos nomes/roles do template SAM atual. Se esses destinos
mudarem, as policies tambem precisam ser revisadas.

## GitHub Actions

### Criar ou atualizar a role via PowerShell

Os scripts usam explicitamente o profile `treinamento` e verificam se a conta
autenticada e `113011715524` antes de alterar IAM. Leem os JSONs ao lado do
script usando `$PSScriptRoot`, independentemente do diretorio de execucao.

Na raiz do repositorio, para criar a role e a inline policy `sam-lab-deploy`:

```powershell
.\infrastructure\sam\iam\create-role.ps1
```

Se a role ja existir, a criacao falha sem sobrescreve-la. Para aplicar futuras
alteracoes nos dois JSONs a role existente:

```powershell
.\infrastructure\sam\iam\update-role.ps1
```

Para visualizar a acao sem fazer chamadas AWS:

```powershell
.\infrastructure\sam\iam\create-role.ps1 -WhatIf
.\infrastructure\sam\iam\update-role.ps1 -WhatIf
```

As atualizacoes de trust e permissoes sao chamadas separadas, sem transacao.
Se a segunda chamada falhar, o script informa a alteracao parcial; apos corrigir
a causa, execute `update-role.ps1`. A atualizacao substitui a trust e a inline
policy `sam-lab-deploy`, preservando outras policies e configuracoes da role.
Os scripts nao criam o provider OIDC nem configuram GitHub Variables.

A trust permite somente o subject imutavel deste repositorio com o Environment
`sam-lab` e audience `sts.amazonaws.com`. Antes de usar, configure no GitHub o
Environment `sam-lab` para permitir deploy somente da branch `main`. Quando ha
Environment, o subject OIDC usa seu nome e nao inclui a branch; a condicao do
workflow complementa, mas nao substitui, essa protecao no Environment.

Valores previstos para as Repository/Environment Variables:

```text
AWS_REGION=us-east-1
SAM_AWS_ROLE_ARN=arn:aws:iam::113011715524:role/residencia-sam-lab-deploy
SAM_ARTIFACT_BUCKET=residencia-catchup-artifacts-113011715524-us-east-1
```

O Actions pode enviar/ler objetos somente no prefixo `residencia-sam-lab/`
desse bucket existente. `ListBucket` lista metadados/chaves no bucket; nao
concede leitura do conteudo de objetos fora do prefixo. `GetTemplateSummary`
usa `Resource: "*"` para analisar templates sem uma stack associada.

O deploy cria e executa change sets somente da stack do laboratorio. Nao e
necessaria uma role de servico separada do CloudFormation. A permissao adicional
para o ARN do transform SAM e necessaria para processar o template.
A verificacao le somente as novas funcoes/versoes. A role nao pode invocar
funcoes, ler secrets ou modificar roles. Ela pode atualizar diretamente o codigo
das tres novas Lambdas, pois o CloudFormation depende dessas mesmas permissoes.

## CloudFormation

A role OIDC permite ao CloudFormation criar/atualizar/excluir as tres novas funcoes,
suas versoes e aliases. As permissoes de exclusao sao necessarias tambem para
rollback e substituicao de recursos, sempre restritas aos nomes do laboratorio.
O Actions nao recebe `DeleteStack` nesta proposta; a remocao da stack sera uma
acao administrativa separada.

`iam:PassRole` permite associar somente as tres roles de execucao existentes
ao servico Lambda. Nao concede permissao para modificar essas roles.
As consultas EC2 usam `Resource: "*"` porque essas operacoes Describe nao
suportam restricao por ARN, e ficam limitadas a `us-east-1`. Nao ha permissoes
de escrita EC2, RDS, SQS, API Gateway ou Secrets Manager na role OIDC.

As roles de execucao reutilizadas continuam responsaveis por logs, acesso aos
recursos da aplicacao e interfaces de rede Lambda. Sua existencia e suas
policies permanecem sob gestao da stack principal. Reutiliza-las compartilha
suas permissoes com as novas funcoes; nao fornece isolamento dos dados.

## Validacao e limites

Se uma stack existente ja tiver uma role de servico associada, o CloudFormation
continua usando essa role mesmo sem `--role-arn`. Este desenho pressupoe uma
stack nova sem role de servico associada; antes de reutilizar uma stack,
confira seu atributo `RoleARN`.

Os JSONs podem ser verificados localmente quanto a sintaxe e escopo. Isso
nao substitui validacao IAM/Access Analyzer nem uma execucao real do deploy.
SCPs, boundaries, policies de recursos e alteracoes futuras podem afetar o
acesso efetivo. Nenhum deploy foi realizado com estas policies.

Referencias:

- [Permissoes SAM e CloudFormation](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/sam-permissions-cloudformation.html)
- [Controle de acesso CloudFormation e transform SAM](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/control-access-with-iam.html)
- [Referencia de acoes CloudFormation](https://docs.aws.amazon.com/service-authorization/latest/reference/list_cloudformation.html)
- [PassRole](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_passrole.html)
- [OIDC com AWS no GitHub](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws)
