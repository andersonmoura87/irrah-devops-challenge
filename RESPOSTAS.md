# Questão 1 — Infraestrutura como Código e Segurança

## Requisitos e escolhas

O [README original](README.md) exige Kubernetes, banco relacional gerenciado,
bucket de conversas, staging/production separados e credenciais fora do código,
com DevSecOps. Interpretamos a dupla negação como proibição de expor credenciais.
O enunciado aceita estrutura/pseudocódigo Terraform ou descrição detalhada.
OCI/PostgreSQL são preferências adotadas; tenancy/região únicas, OKE Enhanced,
Vault e recursos separados são decisões nossas, não novas exigências da IRRAH.

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
enunciado aceita desenho ou descrição; adotamos **GitHub Actions** e documentação
em [docs/architecture/q2-cicd-zero-downtime.md](docs/architecture/q2-cicd-zero-downtime.md).

Este repositório **não contém** a aplicação de WhatsApp. Rolling Update
(`maxUnavailable=0`, `maxSurge=1`), promoção por **digest**, OCIR, OIDC GitHub→OCI,
GitHub Environment protegido em production (configuração **externa** proposta), OIDC
GitHub→OCI e expand/contract em migrations são **decisões de referência** alinhadas ao
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

## Questão pendente

- Questão 4: pendente, não implementada.
