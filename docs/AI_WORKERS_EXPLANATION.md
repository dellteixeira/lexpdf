# LexPDF — explicação de seleção com Workers AI

## Fluxo

`seleção PDF -> Explicar com IA -> Cloudflare Worker -> Workers AI`

O APK nunca contém chave privada do provedor. O Worker autentica o usuário pelo token Supabase já usado pelo LexPDF e aplica quota no servidor.

## Níveis

- **Rápida**: 1 crédito, resposta curta, modelo primário GLM-4.7-Flash.
- **Detalhada**: 2 créditos, modelo primário Gemma 4 26B.
- **Aprofundada**: 4 créditos, resposta mais longa e estruturada, modelo primário Gemma 4 26B.

Se o modelo primário falhar, o Worker tenta automaticamente o outro modelo.

## Limites padrão

- 240 créditos por usuário/dia (UTC).
- 12 solicitações por minuto por usuário.
- 12.000 caracteres por seleção.
- Rápida: até 350 tokens de saída.
- Detalhada: até 800 tokens.
- Aprofundada: até 1.400 tokens.

Os créditos são um mecanismo interno de proteção do LexPDF e não representam diretamente Neurons da Cloudflare.

## Segurança e confiabilidade

O prompt obriga a distinguir o conteúdo apoiado pelo trecho de informação complementar, não inventar jurisprudência/legislação atual e declarar contexto insuficiente. Como todo modelo generativo pode errar, informações críticas devem ser confirmadas em fonte oficial.

## Runtime

O `wrangler.toml` declara o binding `AI`. A quota usa a função Supabase `consume_ai_daily_quota`, acessível apenas ao `service_role`; `SUPABASE_SECRET_KEY` permanece segredo do Worker e nunca é compilado no aplicativo.
