# Registro de evidências do hardening

## Como interpretar o registro

Código versionado demonstra configuração; uma execução local demonstra apenas o
comportamento exercitado. Testes mock não validam serviços OCI. Documentar um
procedimento não equivale a executá-lo. Este arquivo não substitui logs/resultados
de cada execução nem o histórico da entrega original.

| Camada | O que pode ser evidência | Limite |
| --- | --- | --- |
| Estática | Diff, configuração, links e revisão de claims | Não comprova integração/runtime |
| Local P0 | fmt, init readonly, validate, planos mock, testes dos scripts | Não autentica nem provisiona OCI |
| Local P1 | Build/scan/SBOM, rollout, métricas e fault injection reais do lab | Ainda não implementado/executado nesta fase |
| OCI-ONLY | Respostas e auditoria reais de integrações autorizadas | Não executado nesta branch |

## Contrato de cada execução

Usar um registro por cenário e conservar sucessos, falhas e bloqueios. Não usar
um commit como identificador da versão final se havia alterações locais.

| Campo | Conteúdo exigido |
| --- | --- |
| Identificação | ID único, operador/CI run, cenário e objetivo |
| Código | Commit base (`git rev-parse HEAD`), branch e working tree limpo/sujo; se sujo, referência/hash do diff sanitizado que foi validado |
| Artefato | Digest e plataforma da imagem quando houver; em P0: não aplicável, nenhuma imagem construída |
| Tempo | Início/fim em UTC, formato ISO 8601; não preencher com data estimada |
| Ambiente | SO/arquitetura e versões efetivas de Terraform/provider, Node/Bash e ferramentas usadas |
| Entrada | Comando, parâmetros não secretos, fixture/cenário e pré-condições |
| Expectativa | Resultado positivo/negativo esperado e critério de aceite |
| Resultado | Não executado, aprovado, reprovado ou bloqueado; exit code e observação factual |
| Evidência | Caminhos dos artefatos sanitizados, hashes quando necessários e vínculo à execução |
| Limites | O que não foi exercitado; motivo de bloqueio; próxima verificação necessária |

## Execuções desta iteração

Resultados P0 devem ser consolidados a partir das saídas reais pelo executor;
este documento não atribui aprovação antecipada aos comandos do bootstrap.

| ID | Verificação | Situação do registro |
| --- | --- | --- |
| P0-TF | fmt; init readonly e validate nos três roots; testes mock | A consolidar com saída real, versões e revisão validada |
| P0-DIGEST | Casos válidos e inválidos do validador | A consolidar com resultado dos testes |
| P0-DOCS | Links locais, testes do verificador, `git diff --check` e revisão de claims | A consolidar; verificador não prova veracidade dos claims |
| P0-SCOPE | Status/diff, lockfiles e limites de alteração | A consolidar; working tree com mudanças não é commit final |
| P1-LAB | Build/scan/SBOM, aplicação, Kubernetes, PostgreSQL, métricas, rollout/rollback e fault injection | Não implementado/não executado nesta fase |
| OCI | Casos de [OCI-VALIDATION-GAPS.md](OCI-VALIDATION-GAPS.md) | Não executados; exigem ambiente OCI real |

Se uma validação não puder ser executada, registrar como **bloqueada**, sem
transformar inspeção de código em sucesso de runtime. O relatório final deve
distinguir execução local de execução do workflow no GitHub.

## Retenção e conteúdo seguro

`/.evidence/` guarda saídas locais brutas e fica ignorado. Relatórios versionados
devem conter apenas dados sanitizados. Definir prazo de retenção e acesso antes
de publicar artefatos CI; não existe upload/retenção operacional implementado
por este documento.

Não registrar JWT/RPST, senhas, auth tokens, chaves, conteúdo de secret, state,
plan sensível, kubeconfig ou logs de conversas. Evitar ambiente completo e
debug de SDK em logs compartilhados. Metadados como OCIDs/topologia também
exigem avaliação antes de divulgação. Hash não torna material secreto público.

No P1, cada teste operacional deverá vincular commit, digest/plataforma,
configuração, tráfego/carga, janela UTC e sinais antes/durante/depois. Arquivos de
dashboard ou screenshots sem dados identificáveis não demonstram recuperação.
Os cenários terão identificação explícita de **laboratório com fault injection**.
