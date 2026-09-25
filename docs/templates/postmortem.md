# Post-mortem (blameless)

> Template para documentação pós-incidente. Preencher com fatos verificados e
> distinguir hipótese de evidência confirmada. Não substitui registro operacional
> em tempo real (timeline do incidente).

## Resumo

<!-- O que aconteceu, em poucas frases, para leitores executivos e técnicos. -->

## Metadados

| Campo | Valor |
| --- | --- |
| Data do incidente | |
| Severidade | |
| Duração (detecção → recuperação estável) | |
| Serviços afetados | |
| Incident Commander | |
| Autores deste documento | |

## Impacto

<!-- Impacto técnico e percebido pelo cliente, sem inventar números de negócio. -->

- **Experiência do serviço:**
- **Funcionalidades dependentes (ex.: webhooks WhatsApp, integrações ERP):**
- **Escopo geográfico / tenants / lojas (se conhecido):**
- **Dados ou mensagens:** descrever somente o que for verificável; não estimar volume financeiro ou conversões.

## Detecção

- **Como foi detectado:** (alerta Grafana/Slack, cliente, monitoramento interno, etc.)
- **Sinal inicial:**
- **Atraso entre início do impacto e detecção (se estimável):**
- **Lacunas de observabilidade que dificultaram detecção:**

## Timeline

Registrar eventos com timestamp (UTC ou fuso acordado), autor quando relevante, e **fato vs. ação vs. hipótese**.

| Horário | Evento |
| --- | --- |
| | Alerta crítico recebido |
| | Incident Commander designado |
| | |
| | Mitigação aplicada |
| | Serviço considerado estável |
| | Encerramento formal do incidente |

## Resposta

- **Participantes e papéis:**
- **Comunicação:** (Slack, status page, stakeholders internos)
- **Escalonamentos:** (plataforma, banco de dados, aplicação, ERP)

## Mitigação

<!-- Ações tomadas para reduzir impacto antes/durante confirmação da causa raiz. -->

- **O que foi feito:**
- **Risco/reversibilidade:**
- **Evidências que sustentaram a decisão:**

## Recuperação

- **Critérios observáveis usados para declarar estabilização:**
- **Janela de observação pós-mitigação:**
- **Validações realizadas:** (métricas, smoke, traces amostrais)

## Causa raiz

<!-- Explicação técnica da causa confirmada. Se ainda incerta, declarar explicitamente. -->

## Fatores contribuintes

Pergunta orientadora (blameless):

> Quais condições técnicas, processuais ou organizacionais permitiram que essa
> falha ocorresse ou tivesse esse impacto?

- **Técnicos:**
- **Processuais:**
- **Organizacionais / capacity / sazonalidade:**

## O que funcionou

-

## O que não funcionou

-

## Observabilidade durante o incidente

- **Métricas:** o que foi útil / o que faltou
- **Logs:** correlação por request/trace ID
- **Traces (Jaeger):** gaps de propagação ou instrumentação
- **Possível evolução futura (somente se lacuna observada):** padronização via OpenTelemetry para context propagation — **não obrigatório**

## Ações corretivas

| ID | Ação | Owner | Prioridade | Prazo | Critério de conclusão | Follow-up |
| --- | --- | --- | --- | --- | --- | --- |
| | | | | | | |

Organize mentalmente por horizonte:

- **Curto prazo:** estabilização e recorrência imediata
- **Médio prazo:** capacidade, queries, pooling, alertas, dashboards, runbooks, testes
- **Longo prazo:** arquitetura, capacity planning, resiliência — **somente se justificado pela causa raiz confirmada**

## Aprendizados

-

## Aprovações e revisão

| Papel | Nome | Data |
| --- | --- | --- |
| Revisão técnica | | |
| Revisão SRE/Plataforma | | |
