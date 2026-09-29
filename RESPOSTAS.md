# Respostas — Prova Técnica DevOps/SRE

Este documento reúne as respostas às quatro questões do desafio, com foco em
Infraestrutura como Código, CI/CD, observabilidade/resposta a incidentes e
governança DevSecOps.

A entrega distingue explicitamente:

- **implementado e validado neste repositório**;
- **arquitetura/processo proposto como referência**;
- **itens que dependeriam da aplicação ou de infraestrutura real para validação**.

Os artefatos complementares estão versionados em `terraform/`, `.github/workflows/`,
`docs/` e `lab/`. O diretório `lab/` contém um laboratório operacional local e
reproduzível usado para validar, em Kubernetes kind, aspectos de readiness/liveness,
graceful shutdown, rolling update/rollback, observabilidade com Prometheus/Grafana,
troubleshooting com fault injection e security gates locais com Trivy e SBOM.
Esse laboratório complementa as respostas conceituais e os artefatos de referência;
não representa validação de OKE/OCI nem de um ambiente de produção.

# Questão 1 — Infraestrutura como Código e Segurança

## Requisitos e escolhas

O [README original](README.md) exige Kubernetes, banco relacional gerenciado,
bucket de conversas, staging/production separados e credenciais fora do código,
com DevSecOps. Interpreto a dupla negação como proibição de expor credenciais.
O enunciado aceita estrutura/pseudocódigo Terraform ou descrição detalhada.
OCI/PostgreSQL são preferências adotadas; tenancy/região únicas, OKE Enhanced,
Vault e recursos separados são decisões minhas, não novas exigências da IRRAH.

## Implementação de referência

O [módulo compartilhado](terraform/modules/environment) atende aos roots
[staging](terraform/environments/staging) e [production](terraform/environments/production).
Configura compartment/VCN por ambiente, subnets privadas, OKE com workers
gerenciados, PostgreSQL gerenciado condicional, bucket privado e Vault/chave.
Schema/validações ficam no módulo. Capacidade, versões e backups são parametrizados.

A separação reduz blast radius, com custo maior que compartilhar cluster/banco.
Tenancy, região e administradores permanecem comuns. Não há peering, NAT ou
entrada pública de rede criada para OKE/banco. Dados sintéticos em staging são
política operacional, não garantia do código.

Workload identity está **preparada**: Enhanced e policies vinculadas a cluster,
namespace e service account permitem criar objetos e ler secrets indicados.
O [exemplo Kubernetes](terraform/kubernetes/access.yaml.example) não acrescenta
RoleBinding à aplicação. Pod consumidor, SDK compatível e integração são pendentes.

Terraform cria infraestrutura de secrets, sem abastecer/ler seu conteúdo. A fase
inicial não cria banco; após abastecer o Vault, `database_bootstrap_secret` fornece
OCID/versão para criar PostgreSQL. É referência histórica: `credentials` tem
**ForceNew** no provider selecionado. Mudá-la solicita substituição, bloqueada por
`prevent_destroy`; não é mecanismo normal de rotação. Rotação posterior é operacional.

O [bootstrap de state](terraform/bootstrap-state) tem backend OCI versionado,
com buckets privados/versionados separados para bootstrap, staging e production.
Um administrador cria/importa somente o compartment e bucket iniciais; não há
backend local silencioso. State/plans são sensíveis e não são versionados;
lockfiles são mantidos. Não foram introduzidos serviços adicionais de locking.

O módulo não administra policy na raiz da tenancy. Retenção/lifecycle das conversas
são pré-requisitos administrativos documentados; sem eles, não há expiração automática.
Bucket privado/criptografia não substituem sanitização ou controles organizacionais.

## Evidência e limites

Validação local cobre formatação, schema e quatro planos mock com assertions de
recursos/entradas. **Não houve deployment real**, plan contra OCI, teste IAM/rede,
TLS, locking remoto ou restauração. Criptografia dos serviços/volumes está
representada; TLS dos clientes requer integração. Não se declara conformidade
LGPD, SLA, RPO ou RTO.

A [documentação técnica](docs/architecture/q1-iac-security.md) contém diagrama,
rede, seed/import do state, administração SQL por pod temporário, ciclo de vida
das credenciais, trade-offs e revisões necessárias antes de produção.

# Questão 2 — Pipelines CI/CD e estratégias de deploy

## Requisitos e escolhas

O [README original](README.md) pede pipeline com code review, testes, build, zero
downtime no Kubernetes, mitigação de risco na atualização e rollback rápido. O
enunciado aceita desenho ou descrição; adoto **GitHub Actions** e documentação
em [docs/architecture/q2-cicd-zero-downtime.md](docs/architecture/q2-cicd-zero-downtime.md).

Este repositório **não contém** a aplicação de WhatsApp. Rolling Update
(`maxUnavailable=0`, `maxSurge=1`), promoção por **digest**, OCIR, OIDC GitHub→OCI,
GitHub Environment protegido em production (configuração **externa** proposta)
e expand/contract em migrations são **decisões de referência** alinhadas ao
cenário crítico, não exigências literais do enunciado.

## Implementação de referência

- [`.github/workflows/ci.yml`](.github/workflows/ci.yml): formatação, `validate` e
  `terraform test` (Q1) — únicas verificações executáveis aqui.
- [`.github/workflows/release.yml`](.github/workflows/release.yml): **referência** para
  gates de futura promoção por digest (`workflow_dispatch`); jobs `staging-gate` /
  `production-gate`; **sem** promoção, build, push ou deploy.
- A documentação descreve o pipeline completo no **repositório real da aplicação**
  (testes, build de imagem, push, deploy no OKE privado).

Estratégia K8s: **Rolling Update**; rollback pelo **digest estável anterior**. OKE
privado (Q1) exige conectividade de runner como pré-requisito externo. Sem Helm,
GitOps, mesh ou canary controller.

## Evidência e limites

**Não houve** execução de integração OCIR/OKE/OIDC neste challenge. O release não
promove artefato nem simula deploy; proteções de Environment no GitHub não foram
validadas. CI não substitui testes da aplicação. `maxUnavailable: 0` no Rolling Update
é estratégia documentada, sem garantia de zero downtime comprovada aqui.

# Questão 3 — Observabilidade e Troubleshooting em Tempo Real

## Escopo e abordagem

O [README](README.md) pede investigação, mitigação de gargalo no banco e
post-mortem. Os fatos do cenário são alerta **HTTP 5xx > 5%**, latência elevada
e **CPU do cluster em 98%**, durante pico de ERP/marketing na véspera de Dia das
Mães. CPU alta é sinal de saturação: pode ser causa, consequência ou fator
contribuinte; não prova causa raiz nem justifica adicionar pods automaticamente.

Uso Grafana/Prometheus/Jaeger conforme o enunciado e a plataforma de logs
existente, sem presumir backend. PostgreSQL segue a referência da Q1; compartilhar
banco/cluster entre IA, ERP e Webhooks é hipótese a verificar, não fato fornecido.
Essas ferramentas e a aplicação não foram provisionadas nesta entrega.

## a) Investigação: impacto, Golden Signals e correlação

Reconheceria o alerta no Slack, confirmaria ambiente, intervalo e coleta e abriria
uma timeline. Com atuação paralela, um Incident Commander coordenaria aplicação,
plataforma e banco, registrando fatos, hipóteses, ações e próxima atualização.
Priorizaria **erros e latência junto ao volume**, por refletirem impacto no serviço,
antes de concluir algo pela CPU agregada. Identificaria endpoints/fluxos afetados
e evidência de impacto nos clientes, sem estimar receita ou mensagens perdidas.

| Golden Signal | Primeira leitura e propósito |
| --- | --- |
| Traffic | RPS e mudança de volume/distribuição por endpoint/pod, quando disponíveis; distinguir carga nova de retries |
| Errors | Taxa e contagem de 5xx, tipos e concentração por endpoint/pod; conferir origem e denominador do alerta |
| Latency | p95/p99 e p50 quando útil, incluindo comportamento das falhas/timeouts; localizar início e extensão da degradação |
| Saturation | CPU/memória, throttling, requests/limits, nodes, réplicas, pools e banco; filas/backlog somente se existentes e instrumentados |

No Grafana/Prometheus, alinharia a janela e compararia com histórico disponível,
conferindo mudanças de carga, deploy e configuração. Validaria o denominador dos
98% e desagregaria por node/pod/container. Ausência de série não é ausência de
falha; não inventaria baseline, SLO ou thresholds adicionais.

No Kubernetes, verificaria pods prontos/desejados, distribuição nos nodes, consumo,
requests/limits, throttling, HPA se houver, restarts, OOMKilled, probes e eventos.
CPU alta com throttling pede análise de quota/capacidade; sem throttling, cruzaria
com throughput, retries e dependências. HPA no limite não prova necessidade de
mais réplicas. O acesso à API privada deve estar previamente autorizado (Q1).

Nos logs, buscaria exceções, timeouts, connection errors, pool exhaustion, retries
excessivos e falhas PostgreSQL/downstream. Correlacionaria timestamp, serviço,
pod, endpoint e request/correlation/trace ID quando disponíveis, preservando
evidências sanitizadas sem publicar conteúdo sensível.

No Jaeger, compararia traces lentos/com erro com saudáveis equivalentes,
identificando o caminho crítico na aplicação, banco ou dependência externa.
Spans paralelos não devem ser somados; sampling e falhas de propagação limitam
conclusões. Um span SQL longo não distingue sozinho espera no pool, rede, lock
ou execução: precisa ser cruzado com logs e estado do banco.

**Hipótese exemplificativa:** tráfego cresce, latência/5xx e saturação acompanham,
logs indicam espera por conexão e spans PostgreSQL se alongam. Investigaria
sessões/conexões, limites, pools, locks, queries e recursos do banco para confirmar
ou refutar. Banco saudável com espera apenas no pool sugere investigar a aplicação;
correlação temporal por si só não estabelece causalidade.

O [runbook operacional](docs/runbooks/q3-whatsapp-webhook-incident.md) detalha
essa sequência, exemplos PromQL para 5xx, throughput, p95/p99, CPU, throttling e
restarts, suas dependências e comandos Kubernetes vinculados a hipóteses.

## b) PostgreSQL confirmado como gargalo: estabilizar primeiro

Confirmado gargalo por concorrência das lojas do ERP, minha primeira opção seria
**reduzir a pressão na origem com um controle existente e reversível**, junto ao
dono do consumidor: limitar concorrência e controlar pools, preservando fluxos
críticos. Reduzir processamento não crítico, rate limiting e backpressure dependem
dos controles disponíveis e de decisão de negócio. Não presumiria fila nem
garantia de reprocessamento. Rejeições podem gerar retries e piorar a carga;
respeitaria backoff, idempotência e contrato de aceite dos webhooks.

Antes de escolher a intervenção, cruzaria sessões ativas/ociosas, limite e reserva
de conexões, espera/ocupação dos pools, locks/bloqueadores, duração de queries e
transações, timeouts e CPU/memória/I/O do banco. Leituras leves e autorizadas evitam
agravar a saturação. Pool esgotado sozinho não prova banco esgotado. Consideraria
o conjunto de consumidores e réplicas, não apenas o pool de um pod.

**Mais pods podem abrir mais pools/conexões, aumentar concorrência e piorar o
PostgreSQL.** Não elevaria réplicas, pools ou `max_connections` por reflexo.
Scaling depende do gargalo real e capacidade das dependências. Locks/queries
problemáticas pedem ação direcionada com responsável pelo banco e avaliação
transacional; scaling do banco exige capacidade, quota e risco de interrupção
conhecidos. Rollback pelo digest estável da Q2 cabe com evidência de regressão
recente e compatibilidade de schema/config, não apenas coincidência de horário.

Uma mitigação de baixo risco sustentada por evidência pode preceder a causa raiz
completa. Registraria responsável, efeito esperado, estado anterior e reversão;
observaria o resultado antes de acumular mudanças. **Mitigar** recupera serviço;
**investigar causa raiz** explica a falha; **corrigir definitivamente** reduz
recorrência ou impacto.

Para declarar estabilização, verificaria 5xx e latência no comportamento operacional
esperado, throughput útil sustentável, saturação controlada, réplicas prontas,
ausência de crescimento anormal de restarts e pressão PostgreSQL sem escalada.
Backlog só entra se existir e estiver instrumentado. A queda de erros porque
bloqueamos carga não comprova recuperação. Observaria ausência de novos sintomas
na janela acordada com os responsáveis e reintroduziria carga gradualmente;
enquanto houver restrições relevantes, comunicaria estabilização sob mitigação.

## c) Post-Mortem / Blameless Culture

Após estabilizar, usaria o [template de post-mortem](docs/templates/postmortem.md)
existente para registrar resumo, data/severidade/duração, serviços e impacto
verificável, detecção, timeline, resposta, mitigação e critérios de recuperação.
Separaria causa confirmada, fatores contribuintes e hipóteses abertas, incluindo
o que funcionou, o que não funcionou e lacunas de observabilidade.

A revisão perguntaria quais condições técnicas, processuais ou organizacionais
permitiram a falha, sem procurar culpados. **Blameless preserva accountability:**
ações com owner, prioridade, prazo, critério verificável e follow-up. Priorizaria
recorrência imediata no curto prazo; queries, pooling, capacidade, alertas, testes
e runbooks no médio; evolução arquitetural só quando sustentada pela causa.

A sazonalidade orientaria avaliar capacity planning, load testing, quotas,
autoscaling, capacidade PostgreSQL e preparação para eventos, sem concluir que
a falta desse planejamento causou o incidente. OpenTelemetry seria apenas uma
possível evolução se surgissem lacunas de propagação/correlação, não dependência
ou implementação da Q3.

## Evidência e limites

Entrega documental: resposta, runbook e template preservado. **Não houve execução
de PromQL, kubectl contra produção, consulta ao PostgreSQL, análise de traces
reais, reprodução do incidente ou aplicação de mitigação.** Métricas/labels,
acessos, topologia e controles de carga precisam ser confirmados no ambiente real.
As verificações do repositório não validam eficácia operacional em produção.

# Questão 4 — Cultura DevSecOps e Governança

## Resposta às imagens vulneráveis em produção

O [README](README.md) pede ações estruturais e culturais após a esteira detectar
CVEs críticas em imagens de produção. Trataria o relatório como início de um
processo de remediação com responsáveis, sem concluir que severidade Critical
prova exploração ou impacto. Contexto ajuda a priorizar; não justifica ignorar
vulnerabilidades críticas.

Primeiro relacionaria **CVE → pacote/versão → imagem/digest → workload/ambiente →
owner**, incluindo containers auxiliares quando existentes. Distinguiria imagens
armazenadas no registry, efetivamente executadas e antigas sem workload ativo.
Tag ou imagem corrigida no registry não comprovam correção dos pods atuais.

Com Security e dono do serviço, confirmaria advisory, versão/fix, exposição,
alcançabilidade do componente, exploit conhecido, criticidade, privilégios e
controles compensatórios. Dependência presente não implica uso/exploração, mas
alegação de não utilização precisa de evidência. Críticas exploráveis/expostas
receberiam prioridade máxima. Se necessário, conteria o caminho vulnerável com
controle disponível e impacto avaliado; sinais de comprometimento exigem resposta
coordenada, preservação de evidências e avaliação dos acessos atingidos.

Corrigiria dependência ou base, testaria e reconstruiria a imagem, gerando novo
digest e novo scan. Promoveria o mesmo artefato por staging/production pelo fluxo
da Q2, acompanhando rollout e sinais operacionais da Q3. O fechamento exigiria
evidência de que as réplicas e templates afetados usam a imagem corrigida, ligada
ao relatório e à decisão de promoção. Não apagaria indiscriminadamente imagens
vulneráveis: excluir do registry não corrige containers em execução. Rollback
precisa considerar segurança e compatibilidade; voltar ao digest anterior pode
reintroduzir a CVE e exige decisão de risco, não reversão automática.

## Prevenção no pipeline e governança de exceções

Proponho complementar a Q2 com feedback de dependências no PR, scan da imagem
final após build, decisão de política antes da promoção, reavaliação antes de
production e rescans periódicos das imagens ativas. O resultado deve corresponder
ao digest/plataforma promovidos, com versão do scanner, atualização da base,
horário e cobertura registrados. Digest imutável também pode ganhar novos
findings quando surgem advisories.

**Trivy é a única ferramenta de referência proposta**, por cobrir dependências
suportadas, imagens e geração de SBOM. Antes de adotá-lo, verificaria se o scanner
existente já atende ao processo. Sua cobertura não prova reachability nem ausência
de vulnerabilidades. Não há aplicação/Dockerfile aqui para executar esse fluxo;
não acrescento workflow artificial nem scanner equivalente adicional.

Política proposta: **reter promoção com Critical/High até remediação, classificação
fundamentada ou exceção válida**. Sem fix ou aparente baixa exposição não liberam
automaticamente; falso positivo exige evidência preservada. Outras severidades
também são priorizadas por risco. Scan ausente, falho, desatualizado ou incompatível
com o digest não equivale a aprovação. Emergência exige avaliar o risco de implantar
versus não implantar e uma decisão identificada, sem desligar globalmente o gate.

Exceção seria rara e auditável, contendo CVE/pacote, digest, workload/ambiente,
justificativa, risco residual, controles compensatórios, owner, aprovador distinto,
criação, expiração, plano/prazo e evidência de fechamento. O finding permanece
visível; não há allowlist permanente ou renovação automática. Expiração bloqueia
novas promoções pela exceção e escalona os workloads existentes, sem desligá-los
automaticamente. Prazos de remediação e frescor do scan devem ser aprovados pela
organização; não são SLAs existentes nem números exigidos pela IRRAH.

Manteria bases mínimas e suportadas, versões/digests identificáveis e atualizações
regulares com testes, incluindo rebuild para incorporar fixes mesmo sem mudança
da aplicação. Pinagem sem atualização perpetua vulnerabilidades. **SBOM** ajuda
a inventariar componentes; **assinatura/verificação** trata integridade e identidade
confiável; **proveniência** registra origem/processo de build. São controles
distintos: nenhum atesta imagem livre de CVEs. Assinatura/proveniência ficam como
evolução condicionada à necessidade, sem infraestrutura adicional nesta entrega.

## Cultura, responsabilidades e melhoria contínua

Desenvolvedores corrigem dependências e testam; Platform mantém bases e integração
reutilizável; DevOps/SRE opera promoção e verifica runtime/saúde; Security qualifica
risco e revisa política/exceções; liderança prioriza capacidade e decide risco
conforme autoridade definida. Cada finding tem owner: responsabilidade compartilhada
não é transferir tudo para DevOps nem deixar correções sem responsável.

Security champions, feedback acionável no PR, documentação de remediação e
treinamento orientado aos problemas encontrados reduzem retrabalho. Usaria
aprendizado blameless e o template da Q3 para falhas relevantes de processo,
com ações, prazos e acompanhamento. Não puniria times por contagem bruta de CVEs:
melhor cobertura pode aumentar achados; o incentivo deve ser descobrir e corrigir.

Acompanharia críticas abertas por risco, aging, tempo até remediação verificada,
tempo desde fix disponível, cobertura de scans válidos em digests ativos,
promoções com decisão rastreável, exceções expiradas e bases obsoletas. São
indicadores propostos, com escopo/denominador a definir, para orientar capacidade
e reduzir exposição sem ocultar findings ou sacrificar disponibilidade sem análise.

## Evidência e limites

A [documentação detalhada da Q4](docs/security/q4-container-vulnerability-governance.md)
contém processo, política, exceções, responsabilidades e critérios de fechamento
propostos para a aplicação e a operação.

**Documentação e processo (versionados):** governança de CVEs, política de promoção,
exceções e papéis — sem equivaler, por si só, a execução em produção ou em OCI.

**Executado em laboratório local** (imagem `irrah-lab-http`, kind/Docker host; registro
sanitizado em [docs/hardening/OPERATIONAL-EVIDENCE.md](docs/hardening/OPERATIONAL-EVIDENCE.md)):
scan Trivy da imagem, SBOM CycloneDX, gate **HIGH/CRITICAL** (sem `--ignore-unfixed`),
Cosign `sign-blob` + `verify-blob` sobre digest local e teste negativo com chave pública
incompatível. Esses runs demonstram o **procedimento** e artefatos do hardening P1/P2;
**não** comprovam scan em OCIR, admission/security gate em OKE, deploy em produção,
assinatura de imagem publicada em registry, Rekor/keyless/Fulcio nem ausência absoluta
de vulnerabilidades (resultado depende do scanner, da base de advisories e do instante
do run; SBOM é inventário, não prova de segurança).

**Ainda não executado / fora do escopo destas evidências:** integração dos gates da Q4
no pipeline CI/CD da Q2, scan ou política no registry OCIR, admission em OKE, validação
de workloads em ambiente OCI e fechamento operacional em staging/production conforme
a política proposta.

Os workflows da Q2 permanecem intactos e **não** aplicam automaticamente os gates
descritos na Q4. Não se afirma conformidade regulatória, segurança absoluta ou imagem
livre de CVEs com base apenas na documentação ou nos laboratórios locais registrados.
