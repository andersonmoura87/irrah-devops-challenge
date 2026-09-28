# Observabilidade do laboratório local

Stack mínima **Prometheus + Grafana** no namespace `irrah-lab`, contexto
`kind-irrah-lab-133`. Não representa OKE, Managed Prometheus OCI, nem incidente
de produção.

## O que coleta

- **Prometheus** descobre os **dois pods** `lab-http` via `kubernetes_sd_configs`
  (role `pod`) e faz scrape de `/metrics` em cada réplica.
- Métricas expostas pela aplicação: `lab_http_requests_total`,
  `lab_http_request_duration_seconds`, `lab_http_in_flight_requests`, `lab_ready`.

## Grafana

- Datasource Prometheus provisionado por ConfigMap.
- Dashboard **Lab HTTP — operational lab** (uid `lab-http-operational`).
- Acesso anônimo somente leitura (laboratório local; não usar em produção).

## Comandos

```powershell
.\scripts\lab.ps1 -Action deploy-obs
.\scripts\lab.ps1 -Action verify-obs
.\scripts\lab.ps1 -Action down-obs
```

Port-forward manual (opcional):

```powershell
kubectl --context kind-irrah-lab-133 -n irrah-lab port-forward svc/prometheus 9090:9090
kubectl --context kind-irrah-lab-133 -n irrah-lab port-forward svc/grafana 3001:3000
```

Abrir `http://127.0.0.1:3001/d/lab-http-operational`.

## Fault-injection lab

Runbook: [fault-injection-troubleshooting.md](../runbooks/fault-injection-troubleshooting.md)

```powershell
.\scripts\lab.ps1 -Action verify-fault-lab
```
