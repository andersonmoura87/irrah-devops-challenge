# Registro de evidências do hardening

## Como interpretar o registro

Código versionado demonstra configuração; uma execução local demonstra apenas o
comportamento exercitado. Testes mock não validam serviços OCI. Documentar um
procedimento não equivale a executá-lo. Este arquivo não substitui logs/resultados
de cada execução nem o histórico da entrega original.

| Camada | O que pode ser evidência | Limite |
| --- | --- | --- |
| Estática | Diff, configuração, links e revisão de claims | Não comprova integração/runtime |
| Local P0 | fmt, init readonly, validate, planos mock, testes dos scripts | Não autentica nem provisiona OCI |
| Local P1 | Artefatos em `lab/` + ações `scripts/lab.ps1` (build, deploy, scan, rollout, fault, observabilidade) | Laboratório **local**; não valida OKE/OCIR/produção; PostgreSQL P1 **não** implementado no repo |
| Local P2 | SLI/SLO (`verify-slo-lab`) e proveniência Cosign (`verify-provenance-lab`) | Objetivos **demonstrativos**; Cosign **não** prova OCIR/OKE |
| Evidência bruta P1/P2 | Saídas em `/.evidence/` (gitignored), p.ex. lab-security, lab-rollout, lab-slo, lab-provenance | Não versionada por padrão; não substitui registro sanitizado aqui |
| OCI-ONLY | Respostas e auditoria reais de integrações autorizadas | Maioria **não executada**; **OCI-08** parcialmente exercido e **bloqueado** (capacidade A1); OKE **não** operacional para workload |

## Contrato de cada execução

Usar um registro por cenário e conservar sucessos, falhas e bloqueios. Não usar
um commit como identificador da versão final se havia alterações locais.

| Campo | Conteúdo exigido |
| --- | --- |
| Identificação | ID único, operador/CI run, cenário e objetivo |
| Código | Commit base (`git rev-parse HEAD`), branch e working tree limpo/sujo; se sujo, referência/hash do diff sanitizado que foi validado |
| Artefato | Digest e plataforma da imagem quando houver; em P0: não aplicável, nenhuma imagem construída |
| Tempo | Início/fim em UTC, formato ISO 8601; não preencher com data estimada |
| Ambiente | SO/arquitetura e versões efetivas de Terraform/provider, Node/Bash e ferramentas usadas |
| Entrada | Comando, parâmetros não secretos, fixture/cenário e pré-condições |
| Expectativa | Resultado positivo/negativo esperado e critério de aceite |
| Resultado | Não executado, aprovado, reprovado ou bloqueado; exit code e observação factual |
| Evidência | Caminhos dos artefatos sanitizados, hashes quando necessários e vínculo à execução |
| Limites | O que não foi exercitado; motivo de bloqueio; próxima verificação necessária |

## Execuções desta iteração

Resultados P0 devem ser consolidados a partir das saídas reais pelo executor;
este documento não atribui aprovação antecipada aos comandos do bootstrap.

| ID | Verificação | Situação do registro |
| --- | --- | --- |
| P0-TF | fmt; init readonly e validate nos três roots; testes mock | **Aprovado** (validação local Q1); registro sanitizado abaixo; mocks **não** validam OCI real |
| P0-DIGEST | Casos válidos e inválidos do validador | **Aprovado** (validação local do contrato); registro sanitizado abaixo; **não** comprova runtime OCI |
| P0-DOCS | Links locais, testes do verificador, `git diff --check` e revisão de claims | A consolidar; verificador não prova veracidade dos claims |
| P0-SCOPE | Status/diff, lockfiles e limites de alteração | A consolidar; working tree com mudanças não é commit final |
| P1-LAB | Ver tabela abaixo (artefatos vs execução vs consolidação) | Parcial: artefatos versionados; execuções locais a consolidar por cenário |
| P2-SLO | `verify-slo-lab`; fases baseline/fault/recovery | **Aprovado** (lab local 2026-09-29); registro sanitizado abaixo; thresholds versionados em runbook/`slo.go`; **não** SLA de produção; OCI/OKE **não** validados |
| P2-PROVENANCE | `verify-provenance-lab`; Cosign sign+verify local | **Aprovado** (lab local 2026-09-29); registro sanitizado abaixo; chaves/bundle em `/.evidence/` (gitignored); OCIR/OKE/Rekor **não** validados |
| OCI | Casos OCI-01–07, OCI-09 em [OCI-VALIDATION-GAPS.md](OCI-VALIDATION-GAPS.md) | Não executados nesta iteração |
| OCI-08 | OKE / workers / deploy (ver registro abaixo) | **Bloqueado** — execução parcial 2026-09-29; ver detalhe sanitizado |

Se uma validação não puder ser executada, registrar como **bloqueada**, sem
transformar inspeção de código em sucesso de runtime. O relatório final deve
distinguir execução local de execução do workflow no GitHub.

P0-TF e P0-DIGEST estão transcritos nas subseções seguintes. Demais itens P0 permanecem
**a consolidar** até execução registrada da mesma forma.

### P0-TF — registro sanitizado (Q1 Terraform local)

Validação **local** da configuração Terraform da Q1. Provider OCI **mockado** em
`terraform test`; sucesso **não** transforma mocks em evidência de recursos OCI reais.

| Campo | Conteúdo |
| --- | --- |
| Identificação | P0-TF / Q1; objetivo: `init` (backend off, lockfile readonly), `validate` e `terraform test` nos três roots |
| Código (base observado) | Commit **07a414d** (antes da consolidação documental deste registro) |
| Ambiente | Terraform **1.16.2** (`windows_amd64`); provider **oracle/oci v7.22.0** (lockfile readonly reutilizado); execução local; **sem** `terraform apply`; **sem** recurso OCI provisionado |
| Entrada | Por root: `terraform init -backend=false -lockfile=readonly` e `terraform validate`; `terraform test` nos arquivos de teste versionados |
| `terraform/bootstrap-state` | init: **PASS**; validate: **PASS**; `tests/bootstrap.tftest.hcl`: `isolated_backend_contract` **PASS**, `reject_shared_state_group` **PASS** — **2** passed, **0** failed |
| `terraform/environments/staging` | init: **PASS**; validate: **PASS**; `tests/q1.tftest.hcl`: `foundation_without_database`, `database_from_secret_reference`, `reject_admin_secret_in_workload`, `reject_unrestricted_admin_network` — **PASS**; `tests/root.tftest.hcl`: `staging_root_contract` — **PASS** — **5** passed, **0** failed |
| `terraform/environments/production` | init: **PASS**; validate: **PASS**; `tests/root.tftest.hcl`: `production_root_contract` — **PASS** — **1** passed, **0** failed |
| Total `terraform test` | **8** passed, **0** failed (inclui casos negativos que **devem** ser rejeitados pelo contrato — observados como **PASS** no teste) |
| Resultado global | **Aprovado** para critério P0-TF local (configuração + contratos mockados) |
| **Validado (local)** | Formatação/configuração Terraform exercitada via init readonly + validate nos três roots; contratos dos `terraform test`; **8** testes **PASS** / **0** **FAIL**; rejeições negativas esperadas nos testes de política |
| **Não validado** | Backend remoto OCI real; IAM efetivo na OCI; criação real de VCN/OKE/PostgreSQL/Object Storage/Vault; conectividade; disponibilidade; comportamento multi-AZ; `terraform apply`; ambiente OCI operacional; conteúdo de `terraform.tfvars` ou identificadores de tenancy/compartment/grupos |
| Limites | Mocks e `terraform test` comprovam **contratos declarados**, não runtime OCI; ver **OCI-08** e lacunas OCI para provisionamento real |

### P0-DIGEST — registro sanitizado (validador de digest local)

Validação **local** do contrato sintático de digest em `scripts/validate-digest.sh`
(exercitado por `scripts/test-digest.sh`). Execução observada **sem** alteração do
working tree.

| Campo | Conteúdo |
| --- | --- |
| Identificação | P0-DIGEST; objetivo: aceitar digests válidos e rejeitar entradas inválidas conforme contrato |
| Entrada | `bash scripts/test-digest.sh` (execução local) |
| Contrato | Prefixo `sha256:` seguido **exatamente** de **64** caracteres hexadecimais **minúsculos** (`scripts/validate-digest.sh`) |
| Resultado | **18** passed, **0** failed |
| Casos válidos (aceitos) | `valid`, `valid_hex_letters` — **2** |
| Casos inválidos (rejeitados) | `invalid_prefix`, `invalid_suffix`, `newline_before`, `newline_after`, `original_multiline_regression`, `carriage_return_before`, `carriage_return_after`, `crlf_after`, `leading_space`, `trailing_space`, `embedded_space`, `short`, `long`, `uppercase`, `non_hex`, `empty` — **16** |
| Artefatos versionados | `scripts/test-digest.sh`, `scripts/validate-digest.sh` |
| Integração declarada (repo) | [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml) executa `scripts/test-digest.sh`; [`.github/workflows/release.yml`](../../.github/workflows/release.yml) usa `scripts/validate-digest.sh` para validar `image_digest` — **sem** registro neste documento de run específico do GitHub Actions |
| Resultado global | **Aprovado** para critério P0-DIGEST local (contrato + casos de teste) |
| Limites | **Não** comprova build/push de imagem; **não** comprova publicação em OCIR; **não** comprova promoção real por digest; **não** comprova deploy em OKE; validação sintática **não** substitui evidência de runtime OCI |

### P1-LAB: artefatos, execução e consolidação

Interpretação obrigatória (não misturar camadas):

| Dimensão | O que o repositório sustenta | O que **não** afirmar sem registro |
| --- | --- | --- |
| **(a) Artefatos versionados** | `lab/app`, `lab/k8s`, runbooks, `lab/security/README.md`, `lab/observability/README.md`, `scripts/lab.ps1` com ações documentadas nos runbooks | Que uma execução específica ocorreu em CI ou OCI |
| **(b) Verificações locais** | Podem ser disparadas pelo operador (`verify`, `scan-security`, `verify-fault-lab`, `verify-rollout-lab`, etc.) em kind + Docker | Sucesso universal ou equivalência a produção |
| **(c) Evidência bruta** | Diretório `/.evidence/` (subpastas p.ex. lab-security, lab-rollout) — ignorado pelo Git | Versionar JSON/SBOM completos ou digests como prova oficial neste arquivo |
| **(d) OCI/OKE/produção** | Lacunas em [OCI-VALIDATION-GAPS.md](OCI-VALIDATION-GAPS.md) | Validar OCIR, OKE, Vault ou PostgreSQL gerenciado via kind local |

| Escopo P1 | Artefato no repo | Execução local (script/runbook) | Registro consolidado neste doc |
| --- | --- | --- | --- |
| Build / smoke HTTP | Sim | `build`, `load`, `deploy`, `verify` | **A consolidar** por operador (sem timestamps/digests inventados aqui) |
| Trivy + SBOM + gate High/Critical | Sim (`lab/security/`) | `scan-security` | **Aprovado** (lab local 2026-09-29); registro sanitizado abaixo; OCIR/OKE admission **não** validados |
| Observabilidade Prom/Grafana | Sim | `deploy-obs`, `verify-obs` | **A consolidar** |
| Fault injection / recuperação | Sim | `verify-fault-lab`, runbook | **A consolidar** |
| Rolling update / rollback | Sim | `verify-rollout-lab`, runbook | **A consolidar** |
| PostgreSQL local P1 | **Não** | — | **Não aplicável** até haver artefatos no repo |

O scan Trivy/SBOM/gate High–Critical (Q4) está transcrito na subseção seguinte.
Demais cenários P1 (build, observabilidade, fault, rollout) permanecem **a consolidar**
até execução registrada nos campos do contrato acima.

### P1-LAB — scan Trivy/SBOM gate Q4 — registro sanitizado (2026-09-29T03:51:33Z)

Laboratório local no Docker host (`scan-security`). Artefatos em `lab/security/`
descrevem o procedimento; esta subseção consolida **uma** execução observada — não
substitui scan em registry nem admission em cluster.

| Campo | Conteúdo |
| --- | --- |
| Identificação | P1-LAB / Q4; objetivo: scan de vulnerabilidades, SBOM CycloneDX e gate **HIGH/CRITICAL** sobre imagem lab |
| Tempo (UTC) | Run principal **2026-09-29T03:51:33Z** (id de pasta de evidência `20260929T035133Z`) |
| Entrada | `.\scripts\lab.ps1 -Action scan-security` (imagem lab construída localmente) |
| Artefato | Imagem `irrah-lab-http:0.1.0`; referência `irrah-lab-http@sha256:0b17f44368496728ec3a44d7d8b24ba34188a8b53689264f2a68effe2bb72b7e` |
| Scanner | Trivy **0.59.1** (`aquasec/trivy:0.59.1`) |
| Política do gate | Severidades **HIGH** e **CRITICAL**; **sem** `--ignore-unfixed` |
| Resultado do gate | **PASS**, exit **0** |
| Contagens (relatório agregado) | CRITICAL=**0**, HIGH=**0**, MEDIUM=**0**, LOW=**0**, UNKNOWN=**0** |
| Alvo observado | Target=**lab-http**, Type=**gobinary** — CRITICAL=**0**, HIGH=**0**, MEDIUM=**0**, LOW=**0** |
| SBOM | CycloneDX **1.6** (`bomFormat=CycloneDX`); **3** componentes — inventário; **não** prova de segurança |
| Artefatos locais (gitignored) | `trivy-report.json`, `sbom.cyclonedx.json`, `gate-high-critical.txt`, `execution-summary.md` |
| Evidência bruta | `/.evidence/lab-security/20260929T035133Z/` — local, gitignored; **não** versionar |
| Limites | Execução **somente** em laboratório local; **não** comprova scan em OCIR; **não** comprova admission/security gate em OKE; zero CVEs nesta execução **não** implica ausência absoluta de vulnerabilidades — depende da base de vulnerabilidades e das capacidades do Trivy na data do run; SBOM não substitui análise de risco nem política de deploy |

### P2: contrato de registro

| ID | Entrada típica | Evidência sanitizada esperada | Não registrar como |
| --- | --- | --- | --- |
| P2-SLO | `verify-slo-lab` | Fases baseline/fault/recovery, thresholds citados, exit code, path `/.evidence/lab-slo/` | SLA de produção ou SLO da IRRAH |
| P2-PROVENANCE | `verify-provenance-lab` | Digest da imagem, versão Cosign, resultado verify OK + verify com chave errada FAIL | Assinatura OCIR validada ou Rekor/keyless |

Mesmas regras de campos (UTC real, commit, versões de ferramentas) aplicam-se a P2.
P2-SLO e P2-PROVENANCE estão transcritos nas subseções abaixo (objetivos **demonstrativos**
de laboratório; **não** SLA/SLO de produção da IRRAH).

### P2-SLO — registro sanitizado (2026-09-29T04:37:06Z)

Laboratório local em kind (`verify-slo-lab`). **Não** valida OCI, OKE, ambiente
multi-AZ nem produção; thresholds citados são os do lab versionados no repositório.

| Campo | Conteúdo |
| --- | --- |
| Identificação | P2-SLO; objetivo: medir SLIs em fases baseline → fault (injeção) → recovery e comparar aos limiares do lab |
| Tempo (UTC) | Run principal **2026-09-29T04:37:06Z** (id de pasta de evidência `20260929T043706Z`) |
| Ambiente | Cluster **kind-irrah-lab-133**; namespace **irrah-lab** |
| Entrada | `.\scripts\lab.ps1 -Action verify-slo-lab` |
| Limiares (lab) | `success_ratio` ≥ **0.92**; taxa **503** ≤ **0.04**; **p95** ≤ **0.12** s; réplicas **Ready** ≥ **1.9** |
| Fase baseline | **PASS** — `success_ratio=1`, `rate503=0`, `p95=0.0048` s, `ready=2` |
| Fase fault | **FAIL** (**esperado** pelo desenho do experimento) — `success_ratio=0.0297`, `rate503=0.8694`, `p95=0.48` s, `ready=2`; violações deliberadas dos limiares: success ratio **0.0297** (mín. **0.92**); taxa 503 **0.8694** (máx. **0.04**); p95 **0.48** s (máx. **0.12** s) — confirma detecção de degradação sob fault injection, não falha operacional do script |
| Fase recovery | **PASS** — `success_ratio=1`, `rate503=0`, `p95=0.0048` s, `ready=2` |
| Estado final | Fault **off**; **2/2** pods **Ready** |
| Resultado global | **Aprovado** para o critério do lab (baseline e recovery passam; fault reprova os SLIs conforme esperado) |
| Evidência bruta | `/.evidence/lab-slo/20260929T043706Z/` — local, gitignored; **não** versionar |
| Limites | Sem validação em OCI/OKE/produção; limiares não são compromisso de SLA; kind single-node não representa multi-AZ |

### P2-PROVENANCE — registro sanitizado (2026-09-29T04:00:35Z)

Laboratório local no Docker host (`verify-provenance-lab`). **Não** é assinatura de
imagem no OCIR, **não** prova deploy em OKE e **não** substitui pipeline de release.

| Campo | Conteúdo |
| --- | --- |
| Identificação | P2-PROVENANCE; objetivo: `sign-blob` + `verify-blob` sobre digest local; teste negativo com chave pública incompatível |
| Tempo (UTC) | Run principal **2026-09-29T04:00:35Z** (id de pasta de evidência) |
| Entrada | `.\scripts\lab.ps1 -Action verify-provenance-lab` (após build da imagem lab) |
| Artefato | Imagem `irrah-lab-http:0.1.0`; digest assinado `sha256:0b17f44368496728ec3a44d7d8b24ba34188a8b53689264f2a68effe2bb72b7e` |
| Ferramenta | Cosign `gcr.io/projectsigstore/cosign:v2.4.1`; `sign-blob` com `--tlog-upload=false`; `verify-blob` com `--insecure-ignore-tlog=true` (**transparency log Rekor não verificado**) |
| Teste positivo | `verify-blob` com chave pública do par que assinou o blob: **aprovado**, exit **0**, mensagem observada **Verified OK** |
| Teste negativo | Segundo par de chaves efêmeras; **mesmo** `artifact.digest` e **mesmo** `bundle.json` da assinatura original; `verify-blob` com chave pública errada: **reprovado**, exit **1**; erro observado: `invalid signature when validating ASN.1 encoded signature` — falha na **validação criptográfica** (assinatura não confere com a chave), não por arquivo ausente ou path inválido |
| Resultado global | **Aprovado** para o critério do lab (positivo passa; negativo falha por chave incompatível) |
| Evidência bruta | `/.evidence/lab-provenance/20260929T040035Z/` — local, gitignored; contém chaves efêmeras e bundle; **não** versionar |
| Limites | Sem integração OCIR/OKE; sem keyless/Fulcio; sem alegação de verificação de tlog; consumidor de produção exigiria política distinta (digest + confiança no emissor do bundle) |

### OCI-08 — registro sanitizado (2026-09-29)

| Campo | Conteúdo |
| --- | --- |
| Resultado | **Bloqueado** (não aprovado; OKE **não** operacional para carga) |
| Causa observada | **OUT_OF_HOST_CAPACITY** / **Out of host capacity** na criação de instâncias **VM.Standard.A1.Flex** (node pool); Capacity Report A1 **OUT_OF_HOST_CAPACITY** nos três Fault Domains consultados em **sa-saopaulo-1** |
| Escopo efetivamente testado | Provisionamento do control plane (**ACTIVE**); criação do managed node pool A1 (1 OCPU, 6 GB); falha **NODEPOOL_CREATE** / **LaunchInstance**; Compute Capacity Report para A1 (FD-1, FD-2, FD-3); investigação documental/capacity de **VM.Standard.A2.Flex** (suporte OKE e imagens aarch64 confirmados; A2 **AVAILABLE** só em FD-1; **não** provisionado — premissa de custo) |
| O que **não** foi validado | Workers Ready; DNS de pods; pull OCIR; deploy/rollout/smoke/rollback; PostgreSQL gerenciado; demais integrações OCI-01–07; **Terraform/IAM/rede end-to-end** como prova desta execução (permanece configuração declarada + este bloqueio de runtime) |
| Evidência bruta | Console/OCI CLI/Capacity Report — **não** versionada aqui; sem OCIDs completos neste registro |
| Próximo passo | Repetir quando houver capacidade A1 (ou decisão explícita de shape/custo alternativo) e então executar critérios pendentes de OCI-08 |

## Retenção e conteúdo seguro

`/.evidence/` guarda saídas locais brutas e fica ignorado. Relatórios versionados
devem conter apenas dados sanitizados. Definir prazo de retenção e acesso antes
de publicar artefatos CI; não existe upload/retenção operacional implementado
por este documento.

Não registrar JWT/RPST, senhas, auth tokens, chaves, conteúdo de secret, state,
plan sensível, kubeconfig ou logs de conversas. Evitar ambiente completo e
debug de SDK em logs compartilhados. Metadados como OCIDs/topologia também
exigem avaliação antes de divulgação. Hash não torna material secreto público.

No P1, cada teste operacional **deve** vincular commit, digest/plataforma quando
houver, configuração, tráfego/carga, janela UTC e sinais antes/durante/depois —
preenchidos pelo executor; não usar valores estimados neste registro. Arquivos de
dashboard ou screenshots sem dados identificáveis não demonstram recuperação.
Os cenários devem identificar explicitamente **laboratório local** (incluindo fault
injection quando aplicável).
