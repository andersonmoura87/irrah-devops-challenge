# Fault-injection / troubleshooting lab — lab-http

**Laboratório local** (`kind-irrah-lab-133`, namespace `irrah-lab`). Não é incidente de
produção, não valida OKE/OCI/PostgreSQL gerenciado.

## Mecanismo de falha

Degradação **reversível** via variáveis de ambiente no Deployment `lab-http` (sem API HTTP
pública de chaos):

| Variável | Efeito |
| --- | --- |
| `LAB_FAULT_LATENCY_MS` | Atraso artificial em `GET /` (0–30000 ms) |
| `LAB_FAULT_ERROR_PERCENT` | Fração determinística de `GET /` que retorna **503** (~percentual) |

Probes `/healthz`, `/readyz` e scrape `/metrics` **não** passam pela injeção.

Ativação típica:

```powershell
.\scripts\lab.ps1 -Action fault-on
.\scripts\lab.ps1 -Action fault-traffic
.\scripts\lab.ps1 -Action fault-off
```

Recuperação: `fault-off` zera env vars e aguarda rollout; métricas devem voltar ao baseline.

## Fluxo sintoma → evidência → hipótese → diagnóstico → recuperação

| Fase | O que observar | Evidência | Hipótese inicial | Como confirmar/refutar |
| --- | --- | --- | --- | --- |
| Baseline | Serviço saudável | `up{job="lab-http"}==1`, baixa taxa 503, p95 baixo | Sem degradação | PromQL abaixo |
| Ativar falha | Latência/erros em `/` | Aumento de `rate(...code="503")`, p95 sobe | Configuração de fault ou regressão de app | `kubectl get deploy lab-http -o yaml` → env LAB_FAULT_* |
| Tráfego | Clientes veem 503/lentidão | Histograma e contadores por pod | Saturação vs fault local | Comparar pods; fault é simétrico entre réplicas |
| Diagnóstico | Causa no lab | Env não-zero + métricas 503/latência | Injeção intencional ativa | Não é CPU cluster/OKE; probes ainda OK |
| Recuperação | Restaurar SLO operacional do lab | 503 → ~0, p95 cai, `lab_ready==1`, checks HTTP 200 | Fault desligado | `fault-off` + `verify` |

Correlação temporal **não** implica causalidade em produção; aqui a causalidade é **esperada**
porque o operador ativou env vars documentadas.

## PromQL (exemplos — adaptar janela)

Taxa de 5xx da aplicação (lab usa 503):

```promql
sum(rate(lab_http_requests_total{job="lab-http",code="503"}[2m]))
```

Taxa total de requisições bem-sucedidas:

```promql
sum(rate(lab_http_requests_total{job="lab-http",code="200"}[2m]))
```

p95 de latência do handler:

```promql
histogram_quantile(0.95, sum by (le) (rate(lab_http_request_duration_seconds_bucket{job="lab-http"}[2m])))
```

Readiness agregada:

```promql
min(lab_ready{job="lab-http"})
```

Targets saudáveis (scrape):

```promql
count(up{job="lab-http"} == 1)
```

## Grafana

Dashboard provisionado **Lab HTTP — operational lab** (`uid=lab-http-operational`):
painéis de taxa por `code`, p95, in-flight e `lab_ready`.

## Comandos úteis (contexto `kind-irrah-lab-133`)

```powershell
kubectl --context kind-irrah-lab-133 -n irrah-lab get deploy lab-http -o jsonpath='{.spec.template.spec.containers[0].env}'
kubectl --context kind-irrah-lab-133 -n irrah-lab exec deploy/prometheus -c prometheus -- wget -qO- 'http://127.0.0.1:9090/api/v1/query?query=sum(rate(lab_http_requests_total{job=%22lab-http%22,code=%22503%22}[2m]))'
```

Cenário automatizado: `.\scripts\lab.ps1 -Action verify-fault-lab`

## Limitações

- Fault afeta só `GET /`; não simula gargalo PostgreSQL nem CPU 98% do enunciado Q3.
- Percentual de erro é **determinístico por contador**, não aleatório.
- Reinício de pod zera contadores de métricas (não o TSDB inteiro).
