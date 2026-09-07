# Phase 13 — AI (optional)

LexPDF keeps AI optional and preserves the offline-first architecture.

## Selected-text actions

PDF text selection exposes **Estudar** in the native selection context menu. The selected text is copied into the study screen without modifying the PDF and can be explained, summarized, converted into flashcards or turned into study questions.

The study screen also accepts an initial action with autorun, so future context-menu shortcuts can invoke a specific action directly without changing the engine contract.

## Offline engine

`LocalStudyEngine` is the default engine. It is deterministic, requires no network, and never sends document text off-device. It supports:

- explanation;
- extractive summary;
- flashcards;
- study questions.

All engines share `AiInputPolicy`, which normalizes whitespace, rejects empty input, caps generated item counts and truncates oversized requests deterministically.

## Optional online engine

`RemoteAiStudyEngine` is enabled only when `LEXPDF_AI_GATEWAY_URL` is configured. Remote processing is therefore opt-in and uses the same bounded request contract as the offline engine.

## Future local model support

`LocalModelRunner` and `LocalModelAiStudyEngine` form the stable adapter boundary for a future on-device model runtime. A model implementation only needs to provide availability detection and return `AiStudyResult`; the PDF reader and study UI do not need to change.

No model binary, API key, or proprietary runtime is bundled in Phase 13.

## Acceptance criteria

1. Selected PDF text can be opened in the study screen.
2. Explain and summarize work fully offline.
3. Flashcards and questions work fully offline.
4. Empty input is rejected and item counts are bounded.
5. Oversized input is bounded before local or remote processing.
6. Online AI remains disabled unless a gateway is explicitly configured.
7. Future local-model runtimes can plug into `LocalModelRunner` without changing the UI contract.
8. Flutter analyze and tests are green.
