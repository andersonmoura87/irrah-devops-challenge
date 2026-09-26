# Q3 — Incidente no microsserviço de Webhooks do WhatsApp

## Objetivo, escopo e limites

Procedimento proposto para investigar, isolar e mitigar o cenário da
[Questão 3](../../README.md). O enunciado informa sábado à tarde, véspera de Dia
das Mães, pico no ERP e marketing WhatsApp, alerta Grafana no Slack com **HTTP
5xx > 5%**, latência elevada e **CPU do cluster em 98%**. Não fornece causa raiz.

Grafana/Prometheus/Jaeger pertencem ao cenário; não foram instalados neste
repositório. Usar a plataforma de logs existente, sem presumir backend.
PostgreSQL é a escolha de referência coerente com a Q1, mas IA, ERP e Webhooks
não têm topologia compartilhada comprovada. Confirmar quais consumidores usam
qual banco antes de atribuir a pressão do ERP ao serviço de Webhooks.

**Nenhuma consulta PromQL/SQL, comando Kubernetes, análise de traces ou mitigação
foi executada contra um ambiente real nesta entrega.** Nomes entre `<...>` devem
ser substituídos após identificar o ambiente. Não há novos serviços ou dashboards.

## Triage: confirmar, dimensionar e coordenar

1. Reconhecer o alerta no Slack, registrar horário/fuso e abrir uma timeline com
   fatos, hipóteses, ações e responsáveis. Designar um coordenador (Incident
   Commander) se houver atuação paralela; acionar aplicação/plataforma e banco
   conforme os sinais. Combinar próxima atualização de status sem criar um rito
   que atrase a restauração.
2. Confirmar **primeiro erros e latência com volume de tráfego**, por serem mais
   próximos do impacto no serviço. No Grafana, conferir datasource, ambiente,
   intervalo, origem da medição HTTP, numerador/denominador e regra do alerta.
   Distinguir erro do serviço de erro em camada anterior, se ela existir.
   Conferir atualização/coleta: ausência de dados não é serviço saudável.
3. Dimensionar endpoints, pods e funcionalidades afetados; verificar relatos de
   clientes e sinais do ERP disponíveis. CPU é infraestrutura; 5xx/latência
   representam degradação do serviço; efeito em lojas/mensagens depende de
   evidência funcional. Não estimar perdas financeiras ou mensagens perdidas.
4. Alinhar a mesma janela temporal nos gráficos, logs e traces. Comparar com o
   período anterior disponível e comportamento operacional conhecido, sem
   inventar baseline, SLO ou limiares. Verificar deploys, configurações e mudanças
   de carga recentes; pausar mudanças não essenciais durante a investigação.
5. Investigar em paralelo aplicação/Kubernetes e dependências. Guardar links e
   amostras sanitizadas. Uma hipótese bem sustentada pode justificar mitigação
   reversível antes de explicar toda a causa raiz; registrar efeito e reversão.

**Mitigação** reduz impacto agora. **Causa raiz** explica o mecanismo e as
condições do incidente. **Correção definitiva** reduz recorrência ou impacto.
Silenciar um alerta ou reduzir CPU isoladamente não cumpre esses objetivos.

## Golden Signals no Grafana/Prometheus — letra (a)

| Sinal | Pergunta operacional | Correlação necessária |
| --- | --- | --- |
| Traffic | RPS/volume ou distribuição de carga mudaram? | Endpoints, pods e origem quando instrumentados; distinguir requisições originais de retries |
| Errors | Onde se concentram 5xx e quais tipos de erro ocorrem? | Taxa e contagem, endpoint/pod, logs; queda de RPS pode alterar o denominador |
| Latency | p95/p99 pioraram? p50 também, se útil? | Sucessos e falhas, timeouts e dependências; média pode ocultar a cauda |
| Saturation | Qual recurso limita o trabalho útil? | CPU/memória, throttling, requests/limits, nodes, réplicas, pools e banco; backlog somente se existir e estiver instrumentado |

Para os **98%**, conferir o que o painel divide por quê: CPU total, allocatable,
requests ou limits? É agregado do cluster ou concentração em um node? Decompor
por node/pod/container. CPU alta pode ser causa, consequência, fator contribuinte
ou apenas sintoma correlacionado; não identifica o gargalo sozinha.

### Exemplos de PromQL, não executados

As métricas HTTP abaixo são **EXEMPLOS convencionais**, não nomes conhecidos da
IRRAH. Adaptar métricas, labels e seletores à instrumentação. Selecionar apenas
production, cluster e serviço investigados; se o datasource agrega clusters,
acrescentar o filtro real de cluster em todos os seletores. Nos exemplos K8s,
selecionar uma fonte de scrape por alvo para evitar duplicar séries.

`5m`/`15m` são janelas ilustrativas de consulta, não metas ou thresholds. Ajustar
à coleta e duração do incidente. Aplicar `rate` aos counters antes de somar;
as funções estão descritas na [referência Prometheus](https://prometheus.io/docs/prometheus/latest/querying/functions/).
Cada expressão é uma consulta independente, mesmo quando agrupada no mesmo bloco.

**Qual o throughput observado, em requisições por segundo?**

```promql
sum(rate(http_requests_total{job="<job-http>"}[5m]))
```

**Qual a proporção de respostas 5xx no mesmo conjunto de requisições?**

```promql
100 * sum(rate(http_requests_total{job="<job-http>",status=~"5.."}[5m]))
  / sum(rate(http_requests_total{job="<job-http>"}[5m]))
```

Não interpretar denominador zero, série ausente ou coleta interrompida como zero
erros. Se a série de 5xx nunca foi emitida, confirmar o comportamento da
instrumentação; não preencher qualquer ausência com zero. Para localizar um
endpoint/pod, usar labels reais e a mesma agregação no numerador e denominador.

**Qual a latência de cauda, em segundos, no histograma HTTP clássico?**

```promql
# p95
histogram_quantile(0.95,
  sum by (le) (rate(http_request_duration_seconds_bucket{job="<job-http>"}[5m]))
)
# p99
histogram_quantile(0.99,
  sum by (le) (rate(http_request_duration_seconds_bucket{job="<job-http>"}[5m]))
)
```

Exige buckets compatíveis, incluindo `+Inf`; manter `le` na agregação. Não tirar
média dos percentis dos pods. São estimativas e dependem da resolução dos buckets;
verificar se timeouts/falhas entram na medição. Não aplicar essa forma a summaries
ou histogramas nativos sem adaptação. Com pouco tráfego, avaliar também amostras.

**Quais containers consomem CPU? Há limitação por quota?**

```promql
# Uso em cores, não porcentagem do cluster
sum by (pod, container) (
  rate(container_cpu_usage_seconds_total{namespace="<namespace>",pod=~"<regex-pods>",container!="",container!="POD"}[5m])
)
# Porcentagem dos períodos CFS que tiveram throttling
100 * sum by (pod, container) (
  rate(container_cpu_cfs_throttled_periods_total{namespace="<namespace>",pod=~"<regex-pods>",container!="",container!="POD"}[5m])
) / sum by (pod, container) (
  rate(container_cpu_cfs_periods_total{namespace="<namespace>",pod=~"<regex-pods>",container!="",container!="POD"}[5m])
)
```

Dependem da coleta [cAdvisor/kubelet](https://github.com/google/cadvisor/blob/master/docs/storage/prometheus.md)
e da disponibilidade dos counters CFS no runtime. A razão mede períodos afetados,
não porcentagem de CPU perdida nem tempo total bloqueado. Denominador zero ou
série ausente impede essa leitura. Confrontar com limits, capacidade e latência.

**Houve reinícios recentes nos containers do serviço?**

```promql
sum by (pod, container) (
  increase(kube_pod_container_status_restarts_total{namespace="<namespace>",pod=~"<regex-pods>"}[15m])
)
```

Depende de [kube-state-metrics](https://github.com/kubernetes/kube-state-metrics/blob/main/docs/metrics/workload/pod-metrics.md)
coletado pelo Prometheus. `increase` extrapola e pode resultar em fração; não é
uma contagem forense. Troca/deleção de pods e lacunas de coleta exigem conferir
eventos e estado anterior. Nenhum desses componentes foi instalado pela Q3.

## Kubernetes: isolar workload, node e capacidade

Antes dos comandos, confirmar `kubectl config current-context`, cluster e namespace.
O acesso exige conectividade e RBAC autorizados. A [Q1](../architecture/q1-iac-security.md)
tem API OKE privada: este runbook não cria acesso nem libera endpoints públicos.
Os comandos são exemplos de leitura, a adaptar; o namespace de IA da Q1 não deve
ser presumido como namespace de Webhooks.

| Hipótese investigada | Comando de exemplo | Como interpretar |
| --- | --- | --- |
| Carga concentrada ou falta de réplicas prontas | `kubectl get pods -n <namespace> -o wide` | Readiness, restarts, Pending e distribuição por node; comparar réplicas desejadas/disponíveis no workload |
| Containers ou nodes concentrando consumo | `kubectl top pods -n <namespace> --containers` e `kubectl top nodes` | CPU/memória atuais; não substituem histórico nem mostram throttling |
| Requests/limits, OOMKilled, crashes ou probes | `kubectl describe pod <pod> -n <namespace>` | Conferir requests/limits, último estado, motivo de término e eventos; distinguir OOM de outros motivos de restart |
| Falha da aplicação após restart | `kubectl logs <pod> -n <namespace> -c <container> --since=15m --tail=200 --timestamps` | Buscar exceção/timeout; usar `--previous` para instância anterior quando disponível |
| Scheduling, evictions ou falhas de probes | `kubectl get events -n <namespace> --sort-by=.lastTimestamp` | Correlacionar com início do impacto; eventos expiram e não são histórico completo |
| HPA no limite ou sem métricas | `kubectl get hpa -n <namespace>` | Se existir, conferir atual/desejado/máximo e condições com `kubectl describe hpa <hpa> -n <namespace>` |
| Node indisponível ou sob pressão | `kubectl describe node <node>` | Condições, allocatable e eventos; requests alocados não são consumo medido |

`kubectl top` exige Metrics API, normalmente Metrics Server; sua disponibilidade
não é presumida. Consulte a [referência Kubernetes](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_top/).
Janelas e limite de linhas dos logs são exemplos para conter a coleta, não prova
de ausência de erro fora da amostra.

CPU alta **com** throttling leva a conferir quota/limits e capacidade; removê-los
indiscriminadamente pode prejudicar outros workloads. CPU alta **sem** throttling
pede correlação com trabalho útil, retries e dependências. Restarts pedem causa
de término/probes/eventos. HPA no máximo exige identificar o gargalo e capacidade
de nodes/banco antes de aumentar réplicas.

## Logs e Jaeger: testar a hipótese de dependência lenta

Na plataforma de logs existente, buscar 5xx, exceptions, timeouts, connection
errors, pool exhaustion, retries e falhas PostgreSQL/downstream na mesma janela.
Relacionar **timestamp + serviço + pod + endpoint + request/correlation/trace ID**
quando disponíveis. Comparar solicitações lentas/com erro com solicitações
saudáveis equivalentes. O bucket de conversas da Q1 não implica backend de logs
operacionais. Evitar payloads, tokens e dados pessoais em Slack, Git e post-mortem;
preservar evidência restrita e usar referências/amostras sanitizadas.

No Jaeger, filtrar serviço/operação, intervalo, duração e marcações de erro
disponíveis; abrir a timeline dos traces lentos e com erro. Localizar a parcela
do caminho crítico na aplicação, PostgreSQL ou dependência externa. Não somar
spans paralelos como se fossem sequenciais. Verificar tentativas repetidas e
timeouts; correlacionar IDs com logs quando compatíveis. Busca por tags e limites
da UI dependem da configuração, conforme a [documentação Jaeger](https://www.jaegertracing.io/docs/latest/frontend-ui/).

Um span de banco longo pode incluir espera no pool, rede, lock ou execução,
dependendo da instrumentação. Conferir seus limites antes de interpretar;
cruzar com pools e estado do PostgreSQL. Ausência de span/erro pode ser lacuna de
propagação, instrumentação ou sampling; traces amostrados não medem a taxa global
de erros. Não aumentar coleta irrestrita no pico.

**Exemplo de hipótese, não fato:** tráfego sobe, latência cresce, saturação/5xx
acompanham, logs mostram pool exhaustion e spans PostgreSQL se alongam. A hipótese
de pressão no banco ganha força se sessões/esperas e recursos corroborarem.
Se o banco estiver saudável e houver espera apenas para obter conexão, investigar
pool/vazamento na aplicação. Correlação temporal isolada não estabelece causa.

## PostgreSQL e pontos de decisão

Com o responsável pelo banco, usar métricas gerenciadas/logs existentes e acesso
SQL autorizado, privado e com TLS. Confirmar endpoint, banco e consumidores;
permissões podem limitar a visão de outras sessões. Não copiar credenciais para
comandos ou ampliar grants por conveniência. Fazer leituras pontuais, sem coleta
agressiva nem `EXPLAIN ANALYZE` de consultas caras durante a saturação.

| Evidência a conferir | O que distingue |
| --- | --- |
| Sessões por consumidor/estado, `pg_stat_activity`, limite configurado de conexões e reservas administrativas | Conexão aberta não equivale a query ativa; considerar todos os bancos/consumidores do servidor, não só Webhooks |
| Pool ocupado/livre, espera de aquisição, limites por instância e número de instâncias, se expostos | Pool pequeno/vazamento ou pressão agregada no servidor; elevar o pool pode ampliar concorrência |
| `state`, `wait_event_type`, `wait_event`, duração ativa e da transação | Distinguir execução e esperas; `query_start` de sessão inativa refere-se à última query, não a trabalho ainda ativo |
| `pg_locks` e `pg_blocking_pids(pid)` nas sessões relevantes | Identificar bloqueador e bloqueadas, inclusive transação ociosa aberta; evitar polling frequente de locks |
| Queries lentas, logs/`pg_stat_statements` se já habilitados, CPU/memória/I/O/latência de storage | Distinguir volume de concorrência, query custosa e gargalo de recurso; estatística acumulada exige comparar a janela, não ranking histórico isolado |

Essas leituras se apoiam nas referências de [atividade PostgreSQL](https://www.postgresql.org/docs/current/monitoring-stats.html)
e [sessões bloqueadoras](https://www.postgresql.org/docs/current/functions-info.html#FUNCTIONS-INFO-SESSION).
Validar versão/permissões do serviço gerenciado; não instalar extensão ou
reiniciar o banco para obter evidência no meio do incidente.

| Hipótese | Evidência que a sustenta ou enfraquece | Próxima decisão |
| --- | --- | --- |
| Saturação na aplicação | CPU/throttling ou crashes nos pods afetados; banco sem pressão enfraquece hipótese de gargalo SQL | Corrigir/reverter mudança identificada ou avaliar capacidade, preservando limites do banco |
| Concorrência pressionando PostgreSQL | Espera no pool + conexões/queries/recursos do servidor pressionados + dependência confirmada | Reduzir concorrência na origem; observar banco e serviço juntos |
| Bloqueio ou query específica | Cadeia de locks/duração confirma uma sessão/consulta; CPU alta do cluster sozinha não basta | Atuação direcionada com responsável pelo banco, avaliando transação e efeito |
| Falha de rede/dependência externa | Logs de conexão/timeout e spans compatíveis, banco sem evidência correspondente | Acionar dono da dependência/plataforma e verificar o caminho afetado |
| Regressão de release | Mudança recente + alteração nos erros/queries/código dos pods novos; horário sozinho é insuficiente | Considerar rollback compatível, usando digest estável da Q2 |

## Mitigação imediata — letra (b)

**Confirmado gargalo PostgreSQL por concorrência, a primeira opção é reduzir a
pressão na origem com um controle já disponível e reversível.** Escolher o
consumidor comprovado, preservar operações críticas e acordar com aplicação/ERP
a redução temporária de trabalho não crítico. Marketing não é automaticamente
descartável nem está comprovado como consumidor desse banco.

Registrar responsável, evidência, escopo, configuração anterior, efeito esperado
e forma de desfazer cada ação. Observar o efeito antes de acumular mudanças; se
não ajudar ou agravar sintomas, reverter quando seguro e revisar a hipótese.

| Opção condicionada à evidência e a controles existentes | Risco / cuidado operacional |
| --- | --- |
| Limitar concorrência e controlar pools dos consumidores identificados | Considerar conexões agregadas de todas as réplicas/serviços e preservar acesso administrativo; não elevar `max_connections` ou pool por reflexo |
| Rate limiting/backpressure, reduzir processamento não crítico com dono do fluxo | Confirmar contratos de retries, backoff e idempotência; rejeições podem gerar nova onda de carga. Não devolver sucesso a trabalho não aceito/processado conforme contrato |
| Load shedding/degradação controlada | Somente se arquitetura e negócio permitirem; registrar clientes/funcionalidades afetados. Não inventar fila, persistência ou reprocessamento garantido |
| Tratar lock/query problemática identificada | Cancelar consulta ou encerrar sessão apenas com responsável pelo banco e impacto transacional avaliado; cancelar query não equivale a encerrar sessão. Conferir liberação do bloqueio e tratamento no cliente; não matar sessões em massa |
| Scaling do banco quando recurso efetivamente limita | Verificar suporte, quota, prazo, custo e possível restart/failover no serviço gerenciado; pode não aliviar lock ou query ruim e não é restauração instantânea |
| Rollback com forte evidência de regressão | Voltar ao digest estável conhecido da Q2, verificando schema/config; migration incompatível impede rollback simples. O workflow deste repo não executa deploy |

Se o controle desejado não existir, não improvisar um componente durante o pico:
escalonar ao dono do consumidor para a redução operacional disponível e segura.
Sem opção segura, manter coordenação e mitigação assistida; registrar a limitação.

**Mais pods podem piorar o banco:** mais réplicas abrem mais pools, aumentam
conexões/queries concorrentes e pressão no PostgreSQL. Avaliar HPA e demanda
agregada antes de scale-out; não desligar HPA nem reduzir réplicas cegamente.
Scaling de aplicação só ajuda quando o gargalo está nela, existe capacidade nos
nodes e as dependências suportam a carga adicional. Aumentar CPU não corrige
automaticamente lock, timeout ou tempestade de retries.

## Validação da recuperação e comunicação

Usar a mesma origem/janela de observação dos sinais anteriores. Definir com os
responsáveis o comportamento operacional esperado e a janela de acompanhamento
com base no histórico/alertas existentes; não inventar SLO ou tempo fixo.

- 5xx retornam ao comportamento/limiar esperado e p95/p99 se recuperam, incluindo
  falhas/timeouts na leitura; apenas ficar abaixo do alerta de 5% não encerra o incidente.
- Há throughput útil sustentável e funcionamento dos fluxos afetados, usando
  tráfego observado e verificações já disponíveis. Não confundir queda de erros
  por rejeição de carga/ausência de tráfego com recuperação da experiência.
- CPU/throttling/memória controlados, réplicas prontas e sem crescimento anormal
  de restarts; pools, conexões, locks e recursos do banco sem pressão crescente.
- Backlog estabiliza/reduz **somente se existir e estiver instrumentado**; verificar
  retries pendentes conforme contrato. Não afirmar ausência de perda/duplicação
  sem evidência dos fluxos de dados.
- Não surgem novos sintomas críticos durante a janela acordada. Reintroduzir
  gradualmente a carga suspensa; se voltar a degradar, retomar a proteção segura.

Enquanto restrições relevantes persistirem, comunicar **serviço estabilizado sob
mitigação**, não recuperação plena. O coordenador registra situação, impacto
conhecido, incertezas, ação/dono e próxima atualização no canal do incidente;
times de aplicação/plataforma/banco dividem investigação. Escalar quando faltar
acesso, evidência ou autoridade para uma ação. Validar recuperação com os donos
dos fluxos antes do encerramento e manter investigação causal separada.

## Pós-incidente — letra (c)

Preencher o [template de post-mortem](../templates/postmortem.md) com timeline,
impacto verificável, detecção, resposta, mitigação e evidências de recuperação.
Distinguir duração observada desde detecção de início real do impacto, se
desconhecido. Explicitar causa confirmada, fatores contribuintes e hipóteses
ainda abertas; não preencher lacunas com o cenário hipotético deste documento.

Revisar com envolvidos o que funcionou, o que falhou e quais condições técnicas,
processuais ou organizacionais permitiram o incidente. **Blameless não elimina
accountability:** cada ação tem owner, prioridade, prazo, critério verificável
de conclusão e follow-up até validar sua eficácia.

Priorizar recorrência imediata no curto prazo; queries/pooling, capacidade,
alertas, testes e runbooks no médio; mudanças arquiteturais somente com causa
que as justifique. A sazonalidade motiva revisar load testing, quotas, capacidade
PostgreSQL, autoscaling e readiness para eventos; pre-scaling é opção a avaliar,
não prova de que faltou capacity planning. Se houver falhas de propagação ou
instrumentação fragmentada, OpenTelemetry pode ser evolução futura condicionada,
sem implementação ou dependência nesta Q3.

## Pressupostos para uso real

Revisar nomes/labels, histogramas e fontes disponíveis; acesso privado/RBAC/SQL;
topologia real; contratos de retries/idempotência; controles de carga já
existentes; comportamento esperado e responsáveis pela operação. Não há baseline,
limiares adicionais, SLO/SLA ou ferramentas novas presumidos. As referências
técnicas explicam os exemplos, sem acrescentar requisitos ao README. Esta entrega
é documental; não demonstra integração, reprodução do incidente ou eficácia de
uma mitigação em produção. Q4 permanece fora do escopo.
