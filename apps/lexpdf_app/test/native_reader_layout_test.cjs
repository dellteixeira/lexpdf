const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

const source = fs.readFileSync(path.join(__dirname,
  '../android/app/src/main/kotlin/com/lexpdf/lexpdf_app/NativePdfReaderActivity.kt'), 'utf8');
const helper = source.match(/function balancePageVerticalSpace\(\) \{[\s\S]*?\n\}/)?.[0];
assert.ok(helper, 'Exercise the actual embedded viewer layout helper');

function layout(height, pageHeight, mode = 'page', padding = 12) {
  const context = {
    stage: { clientHeight: height },
    pageHost: { style: { height: `${pageHeight}px` } },
    readerViewMode: mode,
    document: { getElementById: () => ({}) },
    getComputedStyle: () => ({ paddingTop: `${padding}px`, paddingBottom: `${padding}px` }),
  };
  vm.runInNewContext(`${helper}\nbalancePageVerticalSpace();`, context);
  return Number.parseFloat(context.pageHost.style.marginTop);
}

test('tablet page leaves equal space above and below, with no footer reservation', () => {
  const inset = layout(1490, 1262);
  assert.equal(inset, 102);
  assert.equal(12 + inset, 1490 - 1262 - 12 - inset);
});

test('hiding the 48 dp toolbar redistributes the added height equally', () => {
  assert.equal(layout(1490, 1262) - layout(1442, 1262), 24);
});

test('zoomed and landscape pages retain a reachable top edge', () => {
  assert.equal(layout(1490, 2524), 0);
  assert.equal(layout(600, 1262), 0);
  assert.equal(layout(1490, 1466), 0);
});

test('continuous modes preserve top alignment', () => {
  assert.equal(layout(1490, 1262, 'continuous_vertical'), 0);
  assert.equal(layout(1490, 1262, 'continuous_horizontal'), 0);
});

test('reader margins and unloaded pages do not introduce stale offsets', () => {
  assert.equal(layout(1490, 1262, 'page', 36), 78);
  assert.equal(layout(1490, 0), 0);
});

function memoryContext() {
  const names = ['releasePreviewCanvas', 'clearVirtualPageWindow',
    'releaseBackgroundPage', 'retryMemoryRender', 'trimReaderMemory'];
  const functions = names.map(name => {
    const body = source.match(new RegExp(`function ${name}\\([^)]*\\) \\{[\\s\\S]*?\\n\\}`))?.[0];
    assert.ok(body, name);
    return body;
  }).join('\n');
  const timers = [];
  const renders = [];
  const context = {
    readerBackgrounded: false, memoryPressureActive: false,
    renderPixelBudget: 8000000, memoryRenderTimer: 0, readerNeedsRepaint: false,
    virtualWindowGeneration: 1, virtualPageWindow: new Map(), virtualPreviewTasks: new Set(),
    renderTask: null, pageRenderInProgress: false, pinchStartDistance: 0, singleTouchActive: false,
    pdf: {}, pageNumber: 585, canvas: { width: 2000, height: 3000 },
    setTimeout: callback => { timers.push(callback); return timers.length; },
    renderPage: (page, preserve) => { renders.push({ page, preserve }); },
  };
  vm.createContext(context);
  vm.runInContext(functions, context);
  return { context, timers, renders };
}

test('memory pressure frees previews, cancels speculative work and lowers the budget', () => {
  const { context, timers, renders } = memoryContext();
  const preview = { width: 1000, height: 1500 };
  let cancelled = false;
  context.virtualPageWindow.set('586', { canvas: preview });
  context.virtualPreviewTasks.add({ cancel: () => { cancelled = true; } });
  context.trimReaderMemory(true, false);
  assert.equal(cancelled, true);
  assert.equal(preview.width * preview.height, 0);
  assert.equal(context.virtualPageWindow.size, 0);
  assert.equal(context.renderPixelBudget, 2000000);
  timers.shift()();
  assert.deepEqual(renders, [{ page: 585, preserve: true }]);
});

test('memory rerender waits for pinch, touch and active rendering without changing the page', () => {
  const { context, timers, renders } = memoryContext();
  context.pinchStartDistance = 120;
  context.trimReaderMemory(true, false);
  timers.shift()();
  assert.equal(renders.length, 0);
  context.pinchStartDistance = 0;
  context.singleTouchActive = true;
  timers.shift()();
  assert.equal(renders.length, 0);
  context.singleTouchActive = false;
  context.renderTask = {};
  timers.shift()();
  assert.equal(renders.length, 0);
  context.renderTask = null;
  context.pageRenderInProgress = true;
  timers.shift()();
  assert.equal(renders.length, 0);
  context.pageRenderInProgress = false;
  timers.shift()();
  assert.deepEqual(renders, [{ page: 585, preserve: true }]);
});

test('backgrounding frees the page buffer and returning repaints the same page', () => {
  const { context, timers, renders } = memoryContext();
  context.trimReaderMemory(false, true);
  assert.equal(context.canvas.width * context.canvas.height, 0);
  assert.equal(context.renderPixelBudget, 8000000);
  assert.equal(renders.length, 0);
  context.trimReaderMemory(false, false);
  timers.shift()();
  assert.deepEqual(renders, [{ page: 585, preserve: true }]);
});

test('background cleanup never resizes a canvas while rendering into it', () => {
  const { context } = memoryContext();
  context.renderTask = {};
  context.trimReaderMemory(false, true);
  assert.equal(context.canvas.width * context.canvas.height, 6000000);
  context.renderTask = null;
  context.releaseBackgroundPage();
  assert.equal(context.canvas.width * context.canvas.height, 0);
});

test('memory checks do not rerender a page already below the pixel budget', () => {
  const { context, timers, renders } = memoryContext();
  context.canvas = { width: 1000, height: 1500 };
  context.trimReaderMemory(true, false);
  context.trimReaderMemory(true, false);
  assert.equal(timers.length, 1);
  timers.shift()();
  assert.equal(renders.length, 0);
});

test('a delayed render frame cannot discard the repaint needed after backgrounding', async () => {
  const { context, timers, renders } = memoryContext();
  const frames = [];
  const render = source.match(/async function renderPage\([^)]*\) \{[\s\S]*?\n\}/)?.[0];
  assert.ok(render);
  const page = {
    getViewport: () => ({ width: 1000, height: 1500 }),
    render: () => ({ promise: Promise.resolve() }), cleanup: () => {},
  };
  Object.assign(context, {
    pdf: { numPages: 1267, getPage: async () => page },
    renderToken: 0, scale: 1, smartFitWidthEnabled: false,
    promoteVirtualPreview: () => false,
    loading: { style: {} }, canvas: { width: 0, height: 0, style: {} }, ctx: {},
    window: { devicePixelRatio: 2 },
    renderSelectableTextLayer: async () => {}, renderTextMarkups: () => {},
    paintSearchHighlights: async () => {}, stage: {},
    requestAnimationFrame: callback => frames.push(callback),
    settleMetrics: () => {}, scheduleVirtualPageWindow: () => {},
    LexPdfBridge: { pageChanged: () => {}, rendered: () => {},
      error: message => { throw new Error(message); } },
  });
  vm.runInContext(render, context);
  await context.renderPage(585, true);
  context.trimReaderMemory(false, true);
  assert.equal(context.readerNeedsRepaint, true);
  context.trimReaderMemory(false, false);
  frames.shift()();
  assert.equal(context.readerNeedsRepaint, true);
  context.renderPage = (page, preserve) => renders.push({ page, preserve });
  timers.shift()();
  assert.deepEqual(renders, [{ page: 585, preserve: true }]);
});
