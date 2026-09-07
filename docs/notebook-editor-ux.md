# Notebook editor UX

The notebook editor now exposes a safer, more discoverable desktop/mobile interaction model:

- page zoom controls (decrease, percentage, increase, fit page);
- pointer/select mode that does not draw or erase and enables object selection/move/resize;
- dedicated text insertion action using Flutter's text input, supporting physical and virtual keyboards;
- grouped toolbar sections inspired by desktop document editors;
- always-visible horizontal scrollbar for toolbar overflow;
- existing lasso remains available for ink-stroke selection and transformation.

The implementation is validated by Flutter analysis and contract tests for zoom, pointer mode, text input, and toolbar overflow.
