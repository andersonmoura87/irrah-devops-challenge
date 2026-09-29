# Lacunas de validação OCI

**Casos OCI-ONLY** exigem ambiente OCI real; testes Terraform mock, Kubernetes/
PostgreSQL locais ou credenciais fictícias **não** substituem essas evidências.
Até **2026-09-29**, **OCI-01 a OCI-07 e OCI-09 permanecem não executados** neste
repositório. **OCI-08** foi **parcialmente executado e bloqueado** (detalhe abaixo).
A arquitetura original permanece em
[Q1](../architecture/q1-iac-security.md) e [Q2](../architecture/q2-cicd-zero-downtime.md).

## Terminologia e pré-condições

OKE workload identity identifica **cluster + namespace + ServiceAccount** e
exige Enhanced, consumidor e SDK/signer compatível. A Q1 prepara cluster/policy
e SA de exemplo; não entrega aplicação consumidora. A identidade é compartilhada
por pods com essa combinação; acesso para criar pods usando a SA deve ser revisto.

Workload mapping existe no fluxo documentado para acesso **cross-compartment**;
não confundir com o resource principal usado na autenticação. Os recursos Q1
estão no mesmo compartment por ambiente, sem necessidade cross-compartment
demonstrada. Não adicionar mapping/dynamic group por hábito. Confirmar requisitos
do SDK escolhido antes do teste. [Referência OKE](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contenggrantingworkloadaccesstoresources.htm).

OCI anunciou JWT externo→RPST em 26/08/2026, incluindo GitHub Actions. O fluxo
documentado exige trust, claims, identidade alvo e autenticação da própria troca
por OAuth client, Service Principal ou Instance Principal; o exemplo OAuth usa
client secret. Portanto `id-token: write` sozinho não demonstra autenticação OCI
sem credencial estática. A versão/recurso recente não é automaticamente capacidade
do provider 7.22.0 fixado aqui. [Anúncio](https://docs.oracle.com/en-us/iaas/releasenotes/identity/jwt_to_rpst_token_exchange_for_workload_identity_federation.htm),
[token exchange](https://docs.oracle.com/en-us/iaas/Content/Identity/api-getstarted/token_exchange_grant_type_workload_id-federation.htm).

RPST para APIs OCI também não demonstra autenticação Docker/OCIR. A documentação
geral usa auth token; existe exemplo oficial de helper com Instance Principal.
Escolher/provar uma integração específica continua pendente, sem presumir que
broker é obrigatório ou que federação direta é impossível.
[Push OCIR](https://docs.oracle.com/en-us/iaas/Content/Registry/Tasks/registrypushingimagesusingthedockercli.htm),
[helper com Instance Principal](https://docs.oracle.com/en/learn/cred-helper/index.html).

Antes de executar: ambiente autorizado com dados sintéticos, orçamento/quotas,
conectividade privada, identidades administrativas temporárias, revisão de grants
herdados e plano de limpeza. Registrar rede, principal, versões, horário UTC e
request IDs sanitizados. Distinguir erro de DNS/rede, TLS, autenticação e autorização.
Não adicionar NAT/IGW nem remover controles para converter falhas em aprovação.

## Nove casos de aceite futuro

| ID / estado | Evidência atual e teste positivo futuro | Teste negativo e critério de conclusão |
| --- | --- | --- |
| OCI-01 — Workload identity / IAM / mapping — **não executado** | Enhanced/policy/SA preparados. Consumidor usa signer suportado, identidade reconhecida no Audit e upload sintético `OBJECT_CREATE` no bucket próprio; validar multipart/retry se usado | Outra SA/namespace/cluster, leitura, sobrescrita, exclusão e bucket/ambiente/state indevido são negados; revisar heranças IAM. Confirmar same-compartment; mapping cross-compartment somente se surgir essa necessidade |
| OCI-02 — Vault / KMS — **não executado** | Vault/chave e allowlist de OCIDs; seed é externo. Conferir `secret.key_id = secrets_key_id`, Vault e compartment esperados; consumidor usa secret autorizado sem imprimir conteúdo | Secret administrativo/não autorizado/outro ambiente é negado. Revogação impede nova leitura após propagação; não apaga material já lido/cacheado |
| OCI-03 — PostgreSQL / TLS — **não executado** | Banco é condicional à referência bootstrap; NSG5432 e backup declarados. DB operacional, conexão privada, role mínima e cliente `verify-full` com CA/FQDN corretos | Origem indevida e operações SQL fora dos grants falham. CA incorreta/hostname incompatível falham por TLS com rede alcançável; conexão TCP ou `require` não bastam |
| OCI-04 — Rotação — **não executado** | Procedimento externo, referência bootstrap histórica/ForceNew. Nova versão/credencial funciona em nova conexão; consumidor renova pools sem replacement Terraform | Senha antiga falha em nova conexão; sessões já abertas não contam como falha de rotação. Registrar janela, recuperação e retirada de acessos temporários |
| OCI-05 — Backup / restore drill — **não executado** | Backup diário parametrizado. Backup real concluído e restore em DB separado recuperam marcadores sintéticos, roles e integridade; medir duração/ponto recuperado | Origem permanece íntegra; destinos/credenciais não se confundem. Evidência inclui IDs distintos, verificações e limpeza autorizada, sem SLA/RPO/RTO presumidos |
| OCI-06 — GitHub OIDC→OCI — **não executado** | Nenhum trust/job autenticador. Troca JWT→RPST pelo método escolhido e chamada API permitida; provar versões e tratamento seguro da credencial da troca | Claims incorretos, token expirado e caller não autorizado são rejeitados. Evidência distingue IAM/trust de Docker login, sem publicar JWT/RPST/chave |
| OCI-07 — OCIR — **não executado** | Apenas referência Q2. Push restrito ao repo, pull por digest e comparação de plataforma/artefato; OKE obtém imagem privada por mecanismo aprovado | Outro repo/identidade sem grant são negados. Separar autenticação do push CI, pull pelo kubelet e SDK do pod; workload identity da app não prova pull |
| OCI-08 — OKE / rede / deploy — **parcialmente executado / bloqueado** | **Executado (2026-09-29):** control plane OKE provisionado e **ACTIVE**; tentativa de node pool gerenciado **VM.Standard.A1.Flex** (1 OCPU, 6 GB). **NODEPOOL_CREATE** falhou em **LaunchInstance** com **Out of host capacity**. **Compute Capacity Report** (região **sa-saopaulo-1**, três Fault Domains disponíveis no AD): **VM.Standard.A1.Flex** → **OUT_OF_HOST_CAPACITY** em FD-1, FD-2 e FD-3. **Nenhum worker A1** provisionado; **nenhum node Ready**. Cluster ACTIVE **≠** plataforma pronta para workload. **Investigado, não provisionado:** **VM.Standard.A2.Flex** listado entre shapes suportados pelo OKE; imagens OKE **aarch64** compatíveis existem; Capacity Report A2 → **AVAILABLE** em FD-1, **OUT_OF_HOST_CAPACITY** em FD-2 e FD-3; descartado nesta validação por alterar a premissa de custo do laboratório. **Ainda pendente (critérios futuros):** bootstrap Ready, DNS de pods, pull/serviços via OSN, PMTUD na topologia real, deploy por digest, rollout/smoke/rollback, testes negativos de rede/IAM | Destino externo sem rota, origem/ambiente/namespace indevido e acesso público não autorizado falham. Readiness falha impede aceite; registrar caminhos/regras e sintomas sem alegar disponibilidade garantida |
| OCI-09 — Backend / bootstrap — **não executado** | Seed/import remoto preservam recursos sem recriação; executores próprios acessam seus buckets; lock impede dois escritores concorrentes; recuperar versão de state em ensaio isolado | Grupo de staging não acessa state production e vice-versa; sem permissão não lê/escreve/retira lock. Conferir lineage/serial e plano após recuperação; não publicar state nem forçar unlock de escritor ativo |

## Limites específicos preservados

Secret OCID/versão são metadados; conteúdo é material secreto. O procedimento KMS
futuro será:

1. Obter os IDs esperados da fundação do ambiente, incluindo o output
   `secrets_key_id`, Vault e compartment, sem ler secret.
2. No seed externo autorizado, selecionar explicitamente esse Vault e essa chave
   para criar o secret; material não passa pelo Terraform.
3. Consultar apenas detalhes via Console ou **GetSecret**/SDK e comparar
   `key_id`, `vault_id` e `compartment_id` com os valores esperados. Não usar
   **GetSecretBundle** para esta conferência, pois ele retorna conteúdo.
4. Se houver divergência, reprovar o contrato e investigar sem trocar chave ou
   recriar recurso automaticamente. Divergência não prova ausência de criptografia;
   prova que a associação esperada não foi confirmada. Guardar somente metadados
   sanitizados e resultado da comparação.

A distinção é documentada em [detalhes do secret](https://docs.oracle.com/en-us/iaas/Content/secret-management/Tasks/view-secret-details.htm)
e no [modelo Secret do SDK](https://docs.oracle.com/en-us/iaas/tools/python/latest/api/vault/models/oci.vault.models.Secret.html).
Nenhum secret/data source com senha será acrescentado ao Terraform para simular
esse resultado. Terraform não detecta cópia de senha nem rotação externa efetiva.

ICMP amplo na regra dos workers é somente protocolo 1, tipo 3/código 4 para
PMTUD. Alcançabilidade depende de rotas/origens reais. Service Gateway/OSN sem
NAT/IGW não prova caminho da internet nem prova que todos os erros externos sejam
impossíveis. Assertions locais validam regra, não tráfego OCI.

As políticas administrativas de lifecycle também não foram executadas. Nenhum
ensaio isolado demonstra conformidade ou cobre todos os controles operacionais.
O ensaio OCI-09 exige plano de recuperação revisado e cópia isolada de state,
mantendo o state ativo e seus locks intactos. Não publicar state como evidência.

Para banco, o roteiro futuro deve usar a CA/FQDN do serviço em
[`verify-full`](https://docs.oracle.com/en/learn/oci-pgsql-ssl/index.html), avaliar a
[operação de reset administrativo](https://docs.oracle.com/en-us/iaas/Content/postgresql/reset-db-admin-credentials.htm)
sem alterar o input histórico Terraform e restaurar em
[DB separado a partir de backup](https://docs.oracle.com/en-us/iaas/Content/postgresql/create-db-from-backup.htm).
Preencher os resultados somente após execução real no formato de
[OPERATIONAL-EVIDENCE.md](OPERATIONAL-EVIDENCE.md).
