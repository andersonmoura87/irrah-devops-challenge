# Contrato futuro dos security gates

**Proposta para P1, não implementada nem executada em P0.** Não há aplicação,
Dockerfile, imagem construída, Trivy executado, SBOM gerada ou gate de scan no
pipeline atual. A [Q4](../security/q4-container-vulnerability-governance.md) mantém
o contexto de governança; este documento define o contrato verificável do futuro
laboratório, sem alegar proteção de produção.

## Identidade do artefato e fluxo mínimo

1. Construir a imagem e identificar commit, digest, plataforma e versão do build.
2. Executar **Trivy** sobre exatamente esse artefato, registrando versão do scanner,
   base de vulnerabilidades, horário UTC, cobertura e resultado completo.
3. Gerar SBOM vinculada ao mesmo digest/plataforma, guardar relatórios e avaliar
   política e exceções antes da promoção.
4. Confirmar que o artefato promovido/executado corresponde ao aprovado; não
   reconstruir silenciosamente entre scan e deploy.

Tag `:<commit SHA>` é identificação convencional, não imutabilidade automática:
tags podem ser movidas. O digest identifica conteúdo; para imagem multiplataforma,
registrar se ele é índice ou manifesto e qual plataforma foi efetivamente
construída, examinada e executada. Validação sintática de digest no P0 não prova
nenhum desses vínculos.

## Política proposta e falhas

- **Critical/High bloqueiam promoção**, inclusive achados sem correção disponível.
  Não usar `--ignore-unfixed` para ocultá-los da decisão.
- Scan ausente, falho, incompatível com o digest/plataforma, sem cobertura exigida
  ou além da validade aprovada **bloqueia**. Não converter falha operacional do
  scanner em “zero vulnerabilidades”.
- Preservar findings originais. Classificação de falso positivo exige evidência
  e decisão rastreável; outras severidades também entram no backlog por risco.
- Definir validade dos relatórios e base antes da execução P1. Não existe prazo
  operacional/SLA aprovado por este arquivo nem número exigido pela IRRAH.
- Falha no upload de evidência obrigatória impede concluir a promoção como
  aprovada. Nenhuma dessas etapas está adicionada aos workflows em P0.

## Exceções específicas e temporárias

Uma exceção precisa conter: identificador; **digest + plataforma**; **CVE + pacote
e versão**; workload/ambiente; owner; justificativa e risco residual; controles
compensatórios; aprovador distinto com autoridade identificada; fonte verificável
da aprovação; criação/expiração; prazo de correção e evidência de fechamento.

O gate futuro deve consultar aprovação de fonte confiável, protegida contra
alteração unilateral pelo mesmo PR que solicita a liberação. Um YAML no PR
autodeclarando aprovação não basta. Se a fonte ainda não estiver implementada e
validada, nenhuma exceção deve liberar automaticamente uma promoção.

Matching deve ser exato: exceção para um digest/plataforma/CVE/pacote/versão e
ambiente não cobre outro. Campo ausente, aprovação não verificável ou expiração
bloqueiam; não há wildcard, allowlist permanente nem renovação automática.
Exceção não remove finding do relatório nem desliga globalmente o gate.

## Aceite futuro e retenção

P1 deverá provar: imagem sem achados bloqueantes aprovada; Critical/High com e
sem fix bloqueados; erro de scanner/relatório ausente bloqueados; exceção válida
aplicada somente ao alvo; exceção expirada, adulterada ou de outro digest negada.
Fixar fixtures controladas para regras da política e distinguir seus testes do
scan real da imagem, cujo resultado muda conforme a base de CVEs.

Guardar relatórios JSON, SBOM, decisão, metadados do scanner/build e vínculo
commit/digest/plataforma/execução. Antes de publicar artefatos CI, definir retenção,
acesso e sanitização; localmente usar `/.evidence/`, ignorado. Esses controles de
armazenamento ainda não estão implementados. Nunca incluir credenciais ou
conteúdo de secret. Usar [o formato de evidências](OPERATIONAL-EVIDENCE.md).

SBOM é inventário, não prova de ausência de vulnerabilidades. Assinatura e
proveniência ficam em P2 até existir ameaça/consumidor que justifique verificar
identidade, integridade e origem. Não adicionar ferramentas para produzir
assinaturas que nenhum gate utiliza.
