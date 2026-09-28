# Security gates locais — lab-http

Laboratório **local** sobre a imagem `irrah-lab-http:0.1.0`. Não valida OCIR,
policies OCI, pipeline GitHub nem conformidade de produção. Alinha-se ao contrato
descrito em [SECURITY-GATES.md](../../docs/hardening/SECURITY-GATES.md), executado
somente neste ambiente.

## Política do gate (esta etapa)

| Regra | Detalhe |
| --- | --- |
| Scanner | **Trivy** `0.59.1` via container `aquasec/trivy:0.59.1` |
| Alvo | Imagem Docker local já construída (`docker load` / `lab.ps1 build`) |
| Escopo | `--scanners vuln` (sem secret scan neste fluxo) |
| Bloqueio | Qualquer vulnerabilidade **HIGH** ou **CRITICAL** → exit code **1** |
| `--ignore-unfixed` | **Não usado** — findings sem fix entram na decisão |
| SBOM | **CycloneDX** JSON (`sbom.cyclonedx.json`) do mesmo artefato |
| Exceções formais | Não implementadas neste repo; ver contrato futuro em SECURITY-GATES |

**Distinções obrigatórias**

- **Detectada:** CVE reportada pelo Trivy na camada/binário escaneado.
- **Explorabilidade:** depende de runtime, rede, configuração e uso real — **não**
  inferida automaticamente pelo gate.
- **Decisão:** gate binário (pass/fail) + revisão humana para MEDIUM/LOW e contexto.

## Comandos reproduzíveis

```powershell
.\scripts\lab.ps1 -Action build
.\scripts\lab.ps1 -Action scan-security
```

Equivalente manual (PowerShell, paths absolutos do checkout):

```powershell
$repo = "<caminho-do-repositorio>"
$run = Join-Path $repo ".evidence/lab-security/run-manual"
New-Item -ItemType Directory -Force -Path $run | Out-Null
docker run --rm `
  -v /var/run/docker.sock:/var/run/docker.sock `
  -v "$repo/.evidence/trivy-cache:/root/.cache/trivy" `
  -v "${run}:/out" `
  aquasec/trivy:0.59.1 image --scanners vuln --format json -o /out/trivy-report.json irrah-lab-http:0.1.0
docker run --rm `
  -v /var/run/docker.sock:/var/run/docker.sock `
  -v "$repo/.evidence/trivy-cache:/root/.cache/trivy" `
  -v "${run}:/out" `
  aquasec/trivy:0.59.1 image --format cyclonedx -o /out/sbom.cyclonedx.json irrah-lab-http:0.1.0
docker run --rm `
  -v /var/run/docker.sock:/var/run/docker.sock `
  -v "$repo/.evidence/trivy-cache:/root/.cache/trivy" `
  aquasec/trivy:0.59.1 image --scanners vuln --severity HIGH,CRITICAL --exit-code 1 --format table irrah-lab-http:0.1.0
```

## O que versionar no Git

| Versionar | Não versionar |
| --- | --- |
| Este README, script `lab.ps1`, Dockerfile | Relatórios JSON completos, SBOM gerada, cache Trivy |
| Política e comandos | `/.evidence/` (já no `.gitignore`) |

Opcional: colar no PR um **resumo sanitizado** (digest, contagem por severidade,
resultado do gate) — não o JSON integral.

## Limitações

- Imagem **scratch + Go estático**: poucas camadas OS; gate limpo **não** prova
  segurança do código Go nem de bases futuras (distroful).
- DB de vulnerabilidades muda diariamente; repetir scan em outra data pode alterar
  resultados.
- SBOM CycloneDX aqui descreve inventário detectado pelo Trivy, não assinatura
  (P2 no plano de hardening).
- Com zero findings HIGH/CRITICAL, o Trivy pode **não** criar
  `gate-high-critical.txt`; o exit code **0** do gate continua sendo a evidência
  primária, junto com `trivy-report.json`.
