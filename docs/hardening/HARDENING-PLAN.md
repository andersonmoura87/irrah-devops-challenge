# Plano de hardening

## Objetivo e fronteira desta iteração

Preservar a entrega original e tornar seus contratos locais mais verificáveis,
sem reescrever a prova. Esta iteração autoriza **somente P0.1 a P0.7**. P1, P2 e
OCI-ONLY são backlog: não representam recursos criados nem testes executados.
O [README original](../../README.md) permanece a fonte das obrigações da IRRAH;
este hardening é uma decisão posterior do projeto.

P0 trata inconsistências e controles da fundação existente; P1 acrescentará
evidência operacional local; P2 depende de necessidade demonstrada; OCI-ONLY
precisa de ambiente OCI real e não será executado nesta branch.

## P0: contratos desta mudança

| Item | Problema / decisão | Artefatos | Aceite verificável |
| --- | --- | --- | --- |
| P0.1 | Evitar resolução silenciosa de dependências e referências móveis de Actions; init sem input/backend e com lockfile readonly, Actions por SHA revisado | Workflows e lockfiles existentes | Três roots inicializam sem alterar lockfiles; Actions apontam para commits identificados; checks locais registrados |
| P0.2 | Testes de módulo não comprovam passagem de configuração dos roots nem contrato do bootstrap | Testes Terraform e CI | Planos mock exercitam staging, production e bootstrap; assertions relevantes e entradas inválidas falham como esperado |
| P0.3 | Digest deve ser validado como string estrita antes de ser aceito pelos gates | Script de validação, testes, release e LF dos scripts em `.gitattributes` | Formato `sha256:` seguido de 64 hexadecimais minúsculos aceito; tamanho, caracteres, espaços e quebras de linha inválidos rejeitados |
| P0.4 | Chave KMS criada sem consumidor Terraform; seed de secret é externo | Contrato em documentação e comentários/testes pertinentes | Fica explícito que associar e verificar `secret.key_id` depende do seed externo; nenhum material secreto é introduzido no Terraform |
| P0.5 | Regra ICMP ampla pode ser confundida com internet aberta ou conectividade comprovada | Contrato de rede e testes Terraform | Preservar protocolo 1, tipo 3/código 4 para PMTUD; explicar dependência de rota/topologia e ausência de NAT/IGW; mock não declara alcançabilidade |
| P0.6 | Faltavam bootstrap, inventário de evidências e limites do hardening; links podem quebrar | Estes documentos, verificador de links e CI | Links locais conferidos, cenários/limites explícitos e comandos reprodutíveis; claims continuam sujeitos a revisão humana |
| P0.7 | Futuros arquivos locais/evidências brutas não devem entrar no Git | `.gitignore` | `/.local/` e `/.evidence/` ignorados na raiz; exemplos e relatórios sanitizados continuam versionáveis |

Esses são critérios de aceite, não um relatório de execução. Os resultados e
eventuais limitações pertencem a [OPERATIONAL-EVIDENCE.md](OPERATIONAL-EVIDENCE.md).

## Backlog posterior, sem implementação nesta fase

| Prioridade | Entrega proposta / valor | Dependências e critério de conclusão | Risco de excesso |
| --- | --- | --- | --- |
| P1 | Aplicação mínima de laboratório e imagem com build identificável por digest | P0 concluído; build repetível, smoke test e vínculo commit/imagem/plataforma registrados | Não recriar a aplicação WhatsApp nem seu domínio de negócio |
| P1 | Um Kubernetes local: **kind**; Deployment, Service, ServiceAccount, probes, requests/limits e shutdown gracioso | Runtime de containers disponível; rollout e rollback realmente executados sob tráfego controlado | Um cluster é suficiente para evidência local; não simula isolamento OCI |
| P1 | PostgreSQL local com role de aplicação restrita e secret fora do Git | Caso mínimo da aplicação; acesso permitido e proibido demonstrados, healthcheck e conexões observados | Não criar operador nem tratar esse banco como OCI gerenciado |
| P1 | Prometheus/Grafana mínimos com métricas HTTP e Kubernetes; métricas do banco quando instrumentadas | Aplicação e cluster; dados reais do lab para RPS, 5xx, p95, CPU, memória e restarts, sem inventar métricas ausentes | Sem stack de logs/tracing completa por padrão |
| P1 | Trivy sobre imagem construída, política Critical/High, SBOM e retenção de evidência | Build/digest; scanner e política com casos positivos/negativos; [contrato dos gates](SECURITY-GATES.md) | Um scanner, sem adicionar ferramenta equivalente |
| P1 | Fault injection controlada de 5xx/latência, investigação e recuperação | Métricas e carga delimitada; antes/durante/depois e mitigação reversível registrados | Não apresentar como incidente real de produção; pressão de recurso exige limite seguro |
| P2 | Assinatura/proveniência e controles adicionais de disponibilidade | Somente se resolverem necessidade identificada; consumidor valida o controle | Não acrescentar ferramentas apenas para assinar um artefato sem verificação |
| OCI-ONLY | Nove casos de integração OCI, incluindo identidade, banco e deploy | Conta/rede/IAM autorizados; [critérios separados](OCI-VALIDATION-GAPS.md) | Não adaptar a arquitetura à Free Tier nem chamar testes locais de prova OCI |

## Decisões mantidas e qualificações

Terraform 1.12.2/provider OCI 7.22.0 e a arquitetura Q1 são preservados. O backend
OCI permanece remoto para uso real; os comandos locais usam `-backend=false`.
O gate de release continua sem build, push, promoção ou deploy. Formato válido de
digest não prova artefato existente; tag com SHA Git não é imutável por natureza.

A chave `secrets` é fundação para seed externo. O contrato exige conferir que o
secret foi criado no Vault/compartment esperado e referencia a chave publicada
em `secrets_key_id`; hoje não há consumidor Terraform nem prova OCI dessa associação.
Não criar secret/data source com conteúdo sensível apenas para preencher a lacuna.

ICMP com `0.0.0.0/0` continua limitado a protocolo **1**, tipo **3**, código **4**
(`fragmentation needed`, PMTUD). Regra de segurança permite tráfego; não cria rota.
A topologia atual tem Service Gateway/OSN, sem NAT/IGW. Não se presume caminho
arbitrário da internet nem se afirma que a regra é sempre inalcançável. Sua
utilidade/alcançabilidade precisa de diagnóstico na topologia OCI efetiva.

## Sequência e encerramento

1. P0.1/P0.2: estabilizar init, versões e contratos dos roots/bootstrap.
2. P0.3: centralizar digest estrito e provar rejeições sem publicar imagens.
3. P0.4/P0.5: explicitar KMS/rede sem alterar arquitetura.
4. P0.6/P0.7: conferir documentação, links, diretórios locais e evidências.
5. Revisar diff e resultados; encerrar P0. A implementação de P1 depende de nova
   autorização; iniciar pelo build/app, depois kind/banco, observabilidade,
   security gates e cenários de falha. P2/OCI-ONLY permanecem separados.

P0 está integralmente validado quando os checks exigidos passam, os resultados
são rastreáveis, nenhum controle proposto é apresentado como executado e o diff
fica restrito ao escopo aprovado. Bloqueios devem permanecer como validação
pendente; não equivalem a aprovação. Não há requisito de commit, push,
provisioning cloud, deploy ou instalação de ferramenta para esta etapa.
O [bootstrap local](../BOOTSTRAP.md) concentra comandos e troubleshooting.
