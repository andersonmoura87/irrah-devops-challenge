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
| P0-TF | fmt; init readonly e validate nos três roots; testes mock | A consolidar com saída real, versões e revisão validada |
| P0-DIGEST | Casos válidos e inválidos do validador | A consolidar com resultado dos testes |
| P0-DOCS | Links locais, testes do verificador, `git diff --check` e revisão de claims | A consolidar; verificador não prova veracidade dos claims |
| P0-SCOPE | Status/diff, lockfiles e limites de alteração | A consolidar; working tree com mudanças não é commit final |
| P1-LAB | Ver tabela abaixo (artefatos vs execução vs consolidação) | Parcial: artefatos versionados; execuções locais a consolidar por cenário |
| P2-SLO | `verify-slo-lab`; fases baseline/fault/recovery | A consolidar; thresholds versionados em runbook/`slo.go`, não SLA produção |
| P2-PROVENANCE | `verify-provenance-lab`; Cosign sign+verify local | A consolidar; chaves em `/.evidence/`; OCIR **não** validado |
| OCI | Casos OCI-01–07, OCI-09 em [OCI-VALIDATION-GAPS.md](OCI-VALIDATION-GAPS.md) | Não executados nesta iteração |
| OCI-08 | OKE / workers / deploy (ver registro abaixo) | **Bloqueado** — execução parcial 2026-09-29; ver detalhe sanitizado |

Se uma validação não puder ser executada, registrar como **bloqueada**, sem
transformar inspeção de código em sucesso de runtime. O relatório final deve
distinguir execução local de execução do workflow no GitHub.

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
| Trivy + SBOM + gate High/Critical | Sim (`lab/security/`) | `scan-security` | **A consolidar**; detalhes em `/.evidence/lab-security/` quando existir |
| Observabilidade Prom/Grafana | Sim | `deploy-obs`, `verify-obs` | **A consolidar** |
| Fault injection / recuperação | Sim | `verify-fault-lab`, runbook | **A consolidar** |
| Rolling update / rollback | Sim | `verify-rollout-lab`, runbook | **A consolidar** |
| PostgreSQL local P1 | **Não** | — | **Não aplicável** até haver artefatos no repo |

Este documento **não** lista resultados de scan (contagens CVE, exit code de gate,
révisions de Deployment) enquanto não forem transcritos de forma sanitizada a
partir de uma execução real registrada nos campos do contrato acima.

### P2: contrato de registro

| ID | Entrada típica | Evidência sanitizada esperada | Não registrar como |
| --- | --- | --- | --- |
| P2-SLO | `verify-slo-lab` | Fases baseline/fault/recovery, thresholds citados, exit code, path `/.evidence/lab-slo/` | SLA de produção ou SLO da IRRAH |
| P2-PROVENANCE | `verify-provenance-lab` | Digest da imagem, versão Cosign, resultado verify OK + verify com chave errada FAIL | Assinatura OCIR validada ou Rekor/keyless |

Mesmas regras de campos (UTC real, commit, versões de ferramentas) aplicam-se a P2.
Não preencher métricas SLI ou exit codes neste arquivo sem transcrição de execução.

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
