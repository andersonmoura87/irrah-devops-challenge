# Plano de hardening

## Objetivo e fronteira desta iteração

Preservar a entrega original e tornar seus contratos locais mais verificáveis,
sem reescrever a prova. A **iteração P0** documentada nesta tabela autorizou
**somente P0.1 a P0.7** — registro histórico da fundação, não reescrito como se
P1 já existisse na mesma entrega. O **laboratório P1** foi implementado
**posteriormente** em `lab/` e `scripts/lab.ps1`; P2 e OCI-ONLY seguem como fases
separadas quando aplicável.

O [README original](../../README.md) permanece a fonte das obrigações da IRRAH;
este hardening é uma decisão posterior do projeto.

P0 trata inconsistências e controles da fundação existente; P1 acrescenta
evidência operacional local (parcialmente implementada — ver status abaixo); P2
depende de necessidade demonstrada; OCI-ONLY precisa de ambiente OCI real.

## P0: contratos desta mudança

| Item | Problema / decisão | Artefatos | Aceite verificável |
| --- | --- | --- | --- |
| P0.1 | Evitar resolução silenciosa de dependências e referências móveis de Actions; init sem input/backend e com lockfile readonly, Actions por SHA revisado | Workflows e lockfiles existentes | Três roots inicializam sem alterar lockfiles; Actions apontam para commits identificados; checks locais registrados |
| P0.2 | Testes de módulo não comprovam passagem de configuração dos roots nem contrato do bootstrap | Testes Terraform e CI | Planos mock exercitam staging, production e bootstrap; assertions relevantes e entradas inválidas falham como esperado |
| P0.3 | Digest deve ser validado como string estrita antes de ser aceito pelos gates | Script de validação, testes, release e LF dos scripts em `.gitattributes` | Formato `sha256:` seguido de 64 hexadecimais minúsculos aceito; tamanho, caracteres, espaços e quebras de linha inválidos rejeitados |
| P0.4 | Chave KMS criada sem consumidor Terraform; seed de secret é externo | Contrato em documentação e comentários/testes pertinentes | Fica explícito que associar e verificar `secret.key_id` depende do seed externo; nenhum material secreto é introduzido no Terraform |
| P0.5 | Regra ICMP ampla pode ser confundida com internet aberta ou conectividade comprovada | Contrato de rede e testes Terraform | Preservar protocolo 1, tipo 3/código 4 para PMTUD; explicar dependência de rota/topologia e ausência de NAT/IGW; mock não declara alcançabilidade |
| P0.6 | Faltavam bootstrap, inventário de evidências e limites do hardening; links podem quebrar | Estes documentos, verificador de links e CI | Links locais conferidos, cenários/limites explícitos e comandos reprodutíveis; claims continuam sujeitos a revisão humana |
| P0.7 | Futuros arquivos locais/evidências brutas não devem entrar no Git | `.gitignore` | `/.local/` e `/.evidence/` ignorados na raiz; exemplos e relatórios sanitizados continuam versionáveis |

Esses são critérios de aceite, não um relatório de execução. Os resultados e
eventuais limitações pertencem a [OPERATIONAL-EVIDENCE.md](OPERATIONAL-EVIDENCE.md).

## Status P1 (implementação posterior ao P0)

Itens originalmente listados como backlog P1. **Status no repositório** (artefatos
versionados); execuções locais e consolidação formal pertencem a
[OPERATIONAL-EVIDENCE.md](OPERATIONAL-EVIDENCE.md) — sem presunção de sucesso
retroativo na iteração P0.

| Item P1 | Artefatos / escopo | Status no repo |
| --- | --- | --- |
| Aplicação mínima e imagem (`lab-http`, build por digest/tag documentada) | `lab/app/`, `Dockerfile`; `scripts/lab.ps1` (`build`, `load`, `verify`) | **Implementado** (artefatos); execução local pelo operador |
| Kubernetes local (**kind**): Deployment, Service, SA, probes, limits, shutdown gracioso | `lab/k8s/workload.yaml`, `namespace.yaml`; script não cria o cluster | **Implementado** (manifests + automação); cluster kind pré-existente |
| Rollout / rollback sob controle | `lab/runbooks/rolling-update-rollback.md`; `verify-rollout-lab` | **Implementado** (runbook + ação script) |
| Prometheus / Grafana mínimos; métricas HTTP do lab | `lab/k8s/observability.yaml`, `lab/observability/README.md` | **Implementado**; métricas de **banco** não aplicáveis (sem PostgreSQL no lab) |
| Trivy, gate High/Critical, SBOM CycloneDX | `lab/security/README.md`, [SECURITY-GATES.md](SECURITY-GATES.md); `scan-security` | **Implementado** (fluxo local documentado); evidência bruta em `/.evidence/` |
| Fault injection 5xx/latência e recuperação | Env no Deployment, `lab/runbooks/fault-injection-troubleshooting.md`; `verify-fault-lab` | **Implementado** (mecanismo + cenário script) |
| PostgreSQL local com role restrita e secret fora do Git | — | **Não implementado**; sem manifests, app ou script correspondente no repo |

## Status P2 (implementação local posterior)

Itens de P2 demonstráveis **sem OCI**. Distinção: artefato no repo ≠ execução local ≠
evidência consolidada em [OPERATIONAL-EVIDENCE.md](OPERATIONAL-EVIDENCE.md).

| Item P2 | Artefatos / escopo | Status no repo |
| --- | --- | --- |
| SLI/SLO de laboratório (métricas existentes, objetivos demonstrativos) | `lab/app/slo.go`, `lab/runbooks/sli-slo-lab.md`; `verify-slo-lab` | **Implementado** (contrato + automação); execução local pelo operador |
| Proveniência Cosign (sign + verify, digest local) | `lab/provenance/README.md`; `verify-provenance-lab` | **Implementado** (fluxo local); **não** integra OCIR nem workflow release |
| Assinatura verificada em promoção OCIR / admission OKE | — | **Não implementado**; lacuna explícita |

## Backlog P2 restante, P1 em aberto e OCI-ONLY

| Prioridade | Entrega proposta / valor | Dependências e critério de conclusão | Risco de excesso |
| --- | --- | --- | --- |
| P2 | Consumidor de assinatura no pipeline/registry (p.ex. gate antes de promoção por digest) | Artefato assinado em registry real; política e trust store definidos | Não simular OCIR neste lab |
| OCI-ONLY | Nove casos de integração OCI, incluindo identidade, banco e deploy | Conta/rede/IAM autorizados; [critérios separados](OCI-VALIDATION-GAPS.md) | Não adaptar a arquitetura à Free Tier nem chamar testes locais de prova OCI |
| P1 (restante) | PostgreSQL local conforme linha acima | Depende de caso mínimo de app + credenciais fora do Git | Não tratar como OCI Database gerenciado |

## Decisões mantidas e qualificações

Terraform 1.12.2/provider OCI 7.22.0 e a arquitetura Q1 são preservados. O backend
OCI permanece remoto para uso real; os comandos locais usam `-backend=false`.
O gate de release continua sem build, push, promoção ou deploy. Formato válido de
digest não prova artefato existente; tag com SHA Git não é imutável por natureza.

A chave `secrets` é fundação para seed externo. O contrato exige conferir que o
secret foi criado no Vault/compartment esperado e referencia a chave publicada
em `secrets_key_id`; hoje não há consumidor Terraform nem prova OCI dessa associação.
Não criar secret/data source com conteúdo sensível apenas para preencher a lacuna.

ICMP com `0.0.0.0/0` continua limitado a protocolo **1**, tipo **3**, código **4**
(`fragmentation needed`, PMTUD). Regra de segurança permite tráfego; não cria rota.
A topologia atual tem Service Gateway/OSN, sem NAT/IGW. Não se presume caminho
arbitrário da internet nem se afirma que a regra é sempre inalcançável. Sua
utilidade/alcançabilidade precisa de diagnóstico na topologia OCI efetiva.

## Sequência e encerramento

1. P0.1/P0.2: estabilizar init, versões e contratos dos roots/bootstrap.
2. P0.3: centralizar digest estrito e provar rejeições sem publicar imagens.
3. P0.4/P0.5: explicitar KMS/rede sem alterar arquitetura.
4. P0.6/P0.7: conferir documentação, links, diretórios locais e evidências.
5. Revisar diff e resultados; encerrar P0 (iteração original).

Após P0, o laboratório P1 foi desenvolvido em etapas (`lab/`, `scripts/lab.ps1`).
Itens P1 ainda em aberto no repositório incluem **PostgreSQL local**. P2
(parcial) acrescenta SLI/SLO local e proveniência Cosign verificável no daemon
Docker; **OCI-ONLY** e consumo de assinatura em OCIR permanecem futuros.

P0 está integralmente validado quando os checks exigidos passam, os resultados
são rastreáveis, nenhum controle proposto é apresentado como executado e o diff
fica restrito ao escopo aprovado. Bloqueios devem permanecer como validação
pendente; não equivalem a aprovação. Não há requisito de commit, push,
provisioning cloud, deploy ou instalação de ferramenta para esta etapa.
O [bootstrap local](../BOOTSTRAP.md) concentra comandos e troubleshooting.
