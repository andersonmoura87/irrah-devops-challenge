# Bootstrap das validações locais

Esta página descreve o hardening P0. Não existe ainda laboratório Kubernetes,
aplicação, imagem de container ou stack de observabilidade executável neste
repositório. O [plano](hardening/HARDENING-PLAN.md) separa essas próximas etapas da
fundação OCI original. `RESPOSTAS.md` continua registrando a entrega do desafio.

## Pré-requisitos e versões

- Git e checkout desta branch; conferir alterações locais antes de validar.
- Terraform **1.12.2**, versão usada pelo CI. Os três lockfiles fixam o provider
  `oracle/oci` **7.22.0**. Os constraints Terraform não substituem esses lockfiles.
- Node.js com suporte ao test runner nativo (`node --test`), sem pacotes npm.
  A estação desta iteração possui **22.12.0**; o CI usa o Node pré-instalado no
  runner, cuja versão deve ser registrada em cada execução.
- Bash para os scripts do digest; no Windows, usar uma instalação já disponível
  de Git Bash ou equivalente. Não executar shell scripts como PowerShell.
- Acesso ao registry do Terraform para baixar o provider quando não houver cache.
  Os testes abaixo não precisam de credenciais, backend ou recursos OCI.

Esta etapa não instala ferramentas. Se um requisito não estiver disponível,
registrar a validação como não executada, com o motivo; não declarar sucesso.
Anotar versões com `terraform version`, `node --version`, `bash --version` e
`git --version`, além de `git rev-parse HEAD` e `git status --short`.

## Validação Terraform sem backend

Executar a partir da raiz do repositório:

```sh
terraform fmt -check -recursive terraform
terraform -chdir=terraform/bootstrap-state init -backend=false -input=false -lockfile=readonly
terraform -chdir=terraform/bootstrap-state validate
terraform -chdir=terraform/bootstrap-state test
terraform -chdir=terraform/environments/staging init -backend=false -input=false -lockfile=readonly
terraform -chdir=terraform/environments/staging validate
terraform -chdir=terraform/environments/staging test
terraform -chdir=terraform/environments/production init -backend=false -input=false -lockfile=readonly
terraform -chdir=terraform/environments/production validate
terraform -chdir=terraform/environments/production test
```

`init -backend=false` prepara módulos/provider, sem inicializar o backend remoto;
não é um procedimento de provisionamento. `-input=false` impede prompts e
`-lockfile=readonly` impede a atualização silenciosa dos lockfiles. Cache do
provider não torna necessária nem autoriza uma chamada à OCI.

Os testes usam provider mock e planos: verificam contratos Terraform, inclusive
os roots e o bootstrap, mas não demonstram IAM, rede, locking ou serviços OCI.
Não executar `plan`/`apply` contra OCI para completar essas verificações.

## Validação de documentação e digest

```sh
node scripts/check-markdown-links.mjs
node --test scripts/check-markdown-links.test.mjs
bash scripts/test-digest.sh
git diff --check
git status --short
git diff --stat
```

O verificador cobre destinos locais em arquivos/diretórios Git tracked ou
untracked não ignorados. Não verifica anchors, URLs externas, HTML ou todo o
CommonMark; ignora blocos de código e código inline. Também não prova que uma
afirmação técnica é verdadeira. O teste de digest cobre formato de entrada,
não existência da imagem, assinatura ou scan.
Claims de implementação e resultados precisam de revisão humana e do
[registro de evidências](hardening/OPERATIONAL-EVIDENCE.md).

## Estado local, limpeza e troubleshooting

`/.local/` é reservado a configuração/material local e `/.evidence/` a resultados
brutos não versionados. Ambos ficam fora do Git; isso não criptografa seu conteúdo
nem substitui permissões de acesso e descarte. Não copiar secrets, tokens, state
ou kubeconfig para relatórios versionados. `.terraform/` é cache local ignorado.

- **Provider indisponível:** conferir rede/cache e erro original. Não remover
  `-lockfile=readonly`, usar `-upgrade` ou editar checksums para fazer o CI passar.
- **Lockfile incompatível:** revisar versão/plataforma e hashes em mudança
  separada, mantendo os três roots coerentes. Não concluir que houve erro OCI.
- **Terraform solicita backend/credencial:** parar; conferir diretório, comando
  e configuração local anterior. Usar checkout de validação sem backend ativo.
- **Teste falha:** guardar nome do teste, comando, versão e saída sanitizada;
  distinguir erro de contrato de indisponibilidade da ferramenta.
- **Bash recebe CRLF:** conferir `.gitattributes`; os scripts `.sh` desta
  mudança devem manter LF, inclusive no checkout Windows.
- **Link falha:** revisar origem/destino e capitalização para runners Linux;
  não apagar documentação para silenciar o verificador.

Não há comando de destruição de laboratório nesta fase: nenhum cluster/container
foi criado por este bootstrap. Para limpar resultados/cache, identificar primeiro
os caminhos gerados, confirmar que ficam dentro deste checkout e que não contêm
state/material necessário; não usar limpeza recursiva genérica como `git clean -xfd`.

## Execução futura do laboratório

A fase P1 ainda depende de implementação e validação. Seu bootstrap deverá
documentar versões, capacidade local, criação, smoke tests, fault injection e
limpeza por nomes explícitos. Não há comando de laboratório funcional a executar
agora. PostgreSQL local não validará PostgreSQL gerenciado; Kubernetes local não
validará OKE, Vault, OCIR ou federação. Essas lacunas estão em
[OCI-VALIDATION-GAPS.md](hardening/OCI-VALIDATION-GAPS.md).
