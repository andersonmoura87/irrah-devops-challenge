# SLI / SLO — laboratório local (P2)

**Não é SLA de produção nem promessa da IRRAH.** Objetivos **demonstrativos** para
exercitar métricas já expostas por `lab-http` e consultadas via Prometheus no
namespace `irrah-lab` (cluster kind documentado nos outros runbooks).

## SLIs (indicadores)

| SLI | PromQL (instantâneo, janela `[2m]`) | Notas |
| --- | --- | --- |
| Taxa HTTP 200 | `sum(rate(lab_http_requests_total{job="lab-http",code="200"}[2m]))` | Somente tráfego de aplicação em `/` |
| Taxa HTTP 503 | `sum(rate(lab_http_requests_total{job="lab-http",code="503"}[2m]))` | Fault injection |
| Success ratio | `rate200 / (rate200 + rate503)` quando denominador > 0; senão `1` | Não inclui 404/405 no ratio |
| Latência p95 | `histogram_quantile(0.95, sum by (le) (rate(lab_http_request_duration_seconds_bucket{job="lab-http"}[2m])))` | Handler de aplicação |
| Readiness | `sum(lab_ready{job="lab-http"})` | Gauge por pod |

Probes e scrape de `/metrics` não entram nos contadores de aplicação.

## SLOs de laboratório (thresholds configurados)

**Fonte de verdade:** [`lab/config/slo.json`](../config/slo.json). Go
(`LoadLabSLOTargets` / testes em `lab/app/slo.go`) e `scripts/lab.ps1`
(`Get-LabSLOThresholds`) leem o mesmo arquivo — não duplicar valores em código.

| Campo JSON | Objetivo | Interpretação |
| --- | --- | --- |
| `minSuccessRatio` | Success ratio mínimo (**0,92**) | Baseline saudável após tráfego leve |
| `max503Rate` | Taxa 503 máxima (**0,04** req/s soma) | Baseline sem fault |
| `maxP95Seconds` | p95 máximo (**0,12 s**) | Baseline sem latência artificial |
| `minReadySum` | Readiness mínima (**1,9**) | ~2 réplicas Ready |

Durante fault controlado (`LAB_FAULT_*`), espera-se **violação** de pelo menos um
objetivo. Após `fault-off` e janela de recuperação, os objetivos devem voltar a
atender.

## Execução

```powershell
.\scripts\lab.ps1 -Action verify-slo-lab
```

Pré-requisitos: `deploy`, `deploy-obs`, cluster kind existente, Prometheus com
targets `lab-http` up.

Evidência sanitizada: `/.evidence/lab-slo/<UTC>/execution-summary.md` (gitignored).

## Limitações

- Single-node kind; não prova SLO multi-AZ, CDN ou balanceador externo.
- Janela `[2m]` depende de scrape 15s e volume modesto de tráfego — não é teste de carga.
- Números de uma execução **não** devem ser copiados para este runbook como “resultado oficial”.
