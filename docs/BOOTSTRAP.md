# Bootstrap das validações locais

Esta página descreve o **hardening P0** (validações Terraform, digest e
documentação) tal como foi definido na iteração original. O **laboratório
operacional P1** (`lab/`, `scripts/lab.ps1`) foi implementado **depois** dessa
fundação; não faz parte do escopo P0 abaixo, mas já existe no repositório para
execução local. O [plano](hardening/HARDENING-PLAN.md) separa P0, P1, P2 e
OCI-ONLY. `RESPOSTAS.md` registra a entrega do desafio e referências ao lab
quando aplicável.

Laboratório local **≠** OKE, OCIR, Vault ou produção; ver
[OCI-VALIDATION-GAPS.md](hardening/OCI-VALIDATION-GAPS.md).

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

O bootstrap P0 **não** cria cluster Kubernetes nem containers de aplicação. Para
limpar resultados/cache das validações P0, identificar primeiro os caminhos
gerados, confirmar que ficam dentro deste checkout e que não contêm
state/material necessário; não usar limpeza recursiva genérica como `git clean -xfd`.

## Laboratório operacional (P1)

O P1 acrescenta evidência operacional **local** (kind, métricas, gates de
segurança, cenários controlados). Entry point: **`scripts/lab.ps1`**, que exige
**PowerShell** (no Windows nativo; em Linux/macOS, PowerShell Core instalado).
O script **não** cria o cluster kind; pressupõe um cluster existente conforme
documentado nos runbooks (por exemplo `kind-irrah-lab-133`).

Artefatos versionados (visão geral):

| Área | Caminho |
| --- | --- |
| Aplicação e imagem | `lab/app/` (Go, `Dockerfile`; tags documentadas nos runbooks) |
| Manifests Kubernetes | `lab/k8s/` (namespace, workload, observabilidade) |
| Observabilidade | `lab/observability/README.md`, `lab/k8s/observability.yaml` |
| Security gates (Trivy/SBOM) | `lab/security/README.md` |
| Runbooks | `lab/runbooks/` (fault injection, rolling update/rollback) |

Ações típicas (consulte `-Action` no script; lista completa no próprio
`scripts/lab.ps1`): `build`, `load`, `deploy`, `verify`, `deploy-obs`,
`verify-obs`, `scan-security`, `verify-fault-lab`, `verify-rollout-lab`, `down`,
`down-obs`, `fault-on` / `fault-off`. Detalhes, políticas e limites ficam nos
READMEs e runbooks do `lab/` — este bootstrap não substitui essa documentação.

Evidência bruta de execuções (relatórios Trivy, snapshots de rollout, etc.)
deve ir para **`/.evidence/`** (gitignored). Relatórios versionados só com dados
sanitizados; o [registro de evidências](hardening/OPERATIONAL-EVIDENCE.md)
diferencia artefato versionado, execução local e lacunas OCI.

PostgreSQL local **não** faz parte do lab atual no repositório. Kubernetes local
não valida OKE, Vault, OCIR ou federação. Essas lacunas permanecem em
[OCI-VALIDATION-GAPS.md](hardening/OCI-VALIDATION-GAPS.md).
