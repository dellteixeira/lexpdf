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
