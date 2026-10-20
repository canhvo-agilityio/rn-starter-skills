// Read Figma's right-hand properties panel as data. Paste the whole file into a browser
// JavaScript tool (built-in browser `javascript_tool`, or Claude in Chrome's equivalent) on an
// open Figma design file. Read-only: it never types into or clicks anything.
//
// After pasting, call:
//   figmaPanel.read()   values for the current selection:
//                       Width/Height, Color (fills, strokes and — for a frame — every
//                       "Selection colors" entry), font family/style/size/line height/letter
//                       spacing, and unlabeled numbers under "?" (corner radius, opacity, …)
//
// The layer list is easier to read with the page-text tool (get_page_text) than from here.
// Panels render lazily: wait ~1 s after changing the selection before reading.
(() => {
  const inRightPanel = (el) => {
    const r = el.getBoundingClientRect();
    return r.width > 0 && r.left > window.innerWidth * 0.62;
  };

  function read() {
    const out = {};
    for (const input of document.querySelectorAll('input')) {
      if (!inRightPanel(input) || input.type === 'checkbox' || input.value === '') continue;
      const label = input.getAttribute('aria-label') || input.placeholder || '?';
      // Figma's plugin search box shows suggested keywords; not design data.
      if (label === '?' && /^[a-z]+$/.test(input.value)) continue;
      (out[label] = out[label] || []).push(input.value);
    }
    if (out.Color) out.Color = [...new Set(out.Color.map((c) => '#' + c.toUpperCase()))];

    // Font family and style are dropdown buttons, not inputs.
    const typo = [...document.querySelectorAll('*')].find(
      (e) => e.children.length === 0 && e.textContent.trim() === 'Typography' && inRightPanel(e),
    );
    if (typo) {
      let block = typo;
      for (let i = 0; i < 4; i++) block = block.parentElement;
      out.typography = block.innerText
        .split('\n')
        .map((s) => s.trim())
        .filter((s) => s && !/^(Typography|Font style|Line height|Letter spacing|Alignment)$/.test(s))
        .slice(0, 3);
    }
    out.nodeId = new URL(location.href).searchParams.get('node-id');
    return out;
  }

  window.figmaPanel = { read };
  return JSON.stringify(read());
})();
