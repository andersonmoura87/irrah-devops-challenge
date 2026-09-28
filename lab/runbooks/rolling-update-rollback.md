# Rolling update e rollback — lab-http

**Escopo:** cluster `kind-irrah-lab-133`, namespace `irrah-lab`. Laboratório local;
não comprova zero-downtime em OKE multi-AZ, PDB em escala ou comportamento de
Ingress/Service mesh.

## O que o Kubernetes garante (neste cenário)

Com `strategy.rollingUpdate.maxUnavailable: 0` e `maxSurge: 1`:

- Novos Pods só **substituem** capacidade Ready existente depois que passam no
  **readinessProbe**.
- Durante um rollout **saudável**, o Service continua apontando para endpoints Ready;
  com 2 réplicas e surge 1, pode haver brevemente 3 Pods, dos quais 2+ Ready.
- `kubectl rollout undo` reverte o template do Deployment para a **revision**
  anterior registrada em `ControllerRevision` / histórico do Deployment.

## O que este lab single-node **não** comprova

- Disponibilidade sob falha de nó, particionamento ou múltiplos workers.
- Convergência de kube-proxy/IPVS vs endpoints em todos os dataplanes.
- Rollback de **dados** ou migrações; apenas spec do Deployment (imagem, probes, env).
- SLO de latência durante troca; apenas checks HTTP simples e métricas Prometheus.

No kind com `imagePullPolicy: Never`, trocar o conteúdo mantendo a **mesma tag** não altera
o template do Deployment; use `kubectl rollout restart` após `kind load` para pegar o novo
digest.

## Pré-requisitos

```powershell
.\scripts\lab.ps1 -Action deploy
.\scripts\lab.ps1 -Action deploy-obs
.\scripts\lab.ps1 -Action verify
.\scripts\lab.ps1 -Action fault-off
```

## Cenário automatizado

```powershell
.\scripts\lab.ps1 -Action verify-rollout-lab
```

Fluxo resumido:

1. **Baseline** — 2/2 Ready, fault injection desligada, snapshots (`deploy`, `rs`, `pods`, `rollout history`).
2. **Rollout saudável** — imagem `irrah-lab-http:0.1.1` (versão exposta em `GET /`), `rollout status`, checks HTTP durante a troca, métricas `lab_ready` / taxa 200.
3. **Rollout defeituoso (controlado)** — patch do **readinessProbe** para path inexistente (`/readyz-broken`); app inalterada. Novos Pods não ficam Ready → rollout **trava** (`ProgressDeadlineExceeded` após `progressDeadlineSeconds`); Service mantém endpoints antigos Ready.
4. **Rollback** — `kubectl rollout undo`, confirmação de revision e ReplicaSets.
5. **Restauração** — `kubectl apply -f lab/k8s/workload.yaml` (imagem `0.1.0`, probes corretas), `fault-off`, `verify` + observabilidade.

Evidências brutas: `/.evidence/lab-rollout/<UTC>/` (gitignored).

## Comandos manuais úteis

```powershell
$ctx = 'kind-irrah-lab-133'
$ns = 'irrah-lab'
kubectl --context $ctx -n $ns get deploy,rs,pods -l app.kubernetes.io/name=lab-http -o wide
kubectl --context $ctx -n $ns rollout history deployment/lab-http
kubectl --context $ctx -n $ns rollout status deployment/lab-http --timeout=180s
kubectl --context $ctx -n $ns set image deployment/lab-http http=irrah-lab-http:0.1.1
kubectl --context $ctx -n $ns rollout undo deployment/lab-http
kubectl --context $ctx -n $ns apply -f lab/k8s/workload.yaml
```

Durante rollout, inspecionar revisions:

```powershell
kubectl --context $ctx -n $ns get rs -l app.kubernetes.io/name=lab-http \
  -o custom-columns=NAME:.metadata.name,REV:.metadata.annotations.deployment\.kubernetes\.io/revision,DESIRED:.spec.replicas,READY:.status.readyReplicas,IMAGE:.spec.template.spec.containers[0].image
```

## Tratamento / decisão

| Situação | Detecção | Ação |
| --- | --- | --- |
| Rollout saudável | `rollout status` success, 2/2 Ready, `/` retorna nova `version` | Manter revision ou aplicar manifest baseline |
| Probe quebrada | Novo RS com READY=0, deployment `Progressing=False`, HTTP ainda 200 nos Pods antigos | `rollout undo` |
| Imagem errada (lab) | `ErrImageNeverPull` com `imagePullPolicy: Never` | `rollout undo` + corrigir tag/`kind load` |

Não ocultar falhas: se o rollout defeituoso completar indevidamente, investigar probes e limites antes de repetir o exercício.
