# Proveniência local da imagem lab (P2)

Demonstração **local** do ciclo assinatura → verificação sobre o **digest** da
imagem Docker `irrah-lab-http:0.1.0`. **Não** integra OCIR, **não** valida OKE
nem adiciona gate Cosign ao workflow `release.yml` (este continua validando apenas
formato do digest).

## Trust model (laboratório)

| Elemento | Decisão |
| --- | --- |
| Producer | Operador local (`docker build` / `lab.ps1 build`) |
| Artefato identificado | Digest `sha256:…` de `docker inspect` (arquivo `artifact.digest`) |
| Assinatura | **Cosign** `v2.4.1` (`gcr.io/projectsigstore/cosign:v2.4.1`), `sign-blob` + `bundle.json` (`--tlog-upload=false` no lab) |
| Chave privada | **Ephemeral**, gerada em `/.evidence/lab-provenance/<run>/` — **nunca** no Git |
| Consumer | `verify-provenance-lab` executa `cosign verify-blob` (chave correta passa; chave errada falha) |
| Falha | Exit code ≠ 0 se verificação falhar |

Isto **não** é assinatura OCI no manifest no registry (Cosign `sign` contra OCIR),
nem Sigstore keyless/Rekor em CI. O consumidor de produção futuro precisaria
política explícita: digest promovido = digest assinado + bundle confiável.

## Fluxo reproduzível

```powershell
.\scripts\lab.ps1 -Action build
.\scripts\lab.ps1 -Action verify-provenance-lab
```

Passos internos: `docker inspect` → gravar digest → `cosign generate-key-pair` →
`cosign sign-blob` → `cosign verify-blob` → tentativa com chave errada (deve
falhar) → resumo sanitizado em `/.evidence/lab-provenance/`.

## Lacunas declaradas

- Sem push para OCIR; bundle local não protege registry remoto.
- Sem transparência Rekor/Fulcio; confiança limitada ao par de chaves do run.
- Workflow GitHub **não** executa Cosign nesta fase P2.
- `registries-lab.toml` permanece no repo apenas como referência opcional; o fluxo
  atual usa **sign-blob** e não depende de registry HTTP.
