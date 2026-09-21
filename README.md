# LexPDF

LexPDF é um workspace multiplataforma, offline-first, para leitura, edição e anotação de PDFs, além de cadernos digitais com suporte avançado a stylus.

## Princípios

- Offline-first: leitura, edição, anotações, cadernos, OCR local, impressão e backup local não dependem de Internet.
- Plataformas de produto e release: Android e Windows.
- PDF + caderno digital no mesmo produto.
- Dados portáveis: exportação e backup integral, sem aprisionamento do usuário.
- Nuvem opcional: Google Drive, OneDrive, Supabase e Cloudflare R2.
- Segurança por padrão: RLS, least privilege, secrets fora do repositório e salvamento atômico local.

## Escopo principal

- Leitor e editor de PDF
- Grifo translúcido com cores configuráveis
- Sublinhado e tachado
- Anotações, comentários e marcadores
- Ink Engine vetorial para stylus
- Cadernos digitais e canvas infinito
- OCR local
- Pesquisa local com SQLite FTS5
- Impressão local e em rede
- Backup local/remoto e restauração
- Importação de conteúdo do Squid quando tecnicamente compatível
- Integração com Google Drive, OneDrive e LexPDF Cloud/R2
- Sincronização opcional
- IA local/offline integrada, com geração online opcional

## Arquitetura

Consulte `ARCHITECTURE.md` e a pasta `docs/`.

## Estratégia de branches

- `main`: linha estável
- `develop`: integração
- `feature/*`: novas funcionalidades
- `fix/*`: correções
- `release/*`: preparação de releases
