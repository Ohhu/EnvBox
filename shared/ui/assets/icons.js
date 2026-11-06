// Inline icon set shared by macOS (WKWebView) and Windows (WebView2).
// SF Symbols are macOS-only and not redistributable, so the shared UI ships its own
// 24x24 stroke glyphs that follow the same optical weight.

const PATHS = {
  box: '<path d="M21 8.4 12 3 3 8.4v7.2L12 21l9-5.4V8.4Z"/><path d="M3.4 8.6 12 13.6l8.6-5"/><path d="M12 13.6V21"/>',
  terminal: '<path d="m5 7.5 5 4.5-5 4.5"/><path d="M13 16.5h6"/>',
  cloud: '<path d="M17.3 18.5a4.3 4.3 0 0 0 .3-8.6 6 6 0 0 0-11.4-1 4 4 0 0 0 .8 9.6h10.3Z"/>',
  flame: '<path d="M12 3c.7 3.6 3.6 4.7 3.6 8a3.6 3.6 0 0 1-7.2 0c0-1.7.8-2.7 1.5-3.7.4 1 .8 1.7 1.6 2.3C11 7.7 11 5.4 12 3Z"/>',
  hammer: '<path d="m13.5 4.5 6 6-2.8 2.8-6-6 2.8-2.8Z"/><path d="m10.2 8.3 4 4L6.7 20 3 18.3l7.2-10Z"/>',
  braces: '<path d="M8.5 4C6.5 4 5.5 5 5.5 7v3c0 2-1 2-2 2 1 0 2 0 2 2v3c0 2 1 3 3 3"/><path d="M15.5 4c2 0 3 1 3 3v3c0 2 1 2 2 2-1 0-2 0-2 2v3c0 2-1 3-3 3"/>',
  leaf: '<path d="M4 20C4 11.5 9.8 5.5 20 4.5 19 15 13 21 5 21"/><path d="M4.6 19.4C7 13.6 11 10.2 15.6 8.4"/>',
  sparkles: '<path d="m12 3 1.7 5.1L19 10l-5.3 1.9L12 17l-1.7-5.1L5 10l5.3-1.9L12 3Z"/><path d="M18.5 15.5l.8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8.8-2.2Z"/>',
  layers: '<path d="m12 3 9 4.8-9 4.8-9-4.8L12 3Z"/><path d="m3 12.6 9 4.8 9-4.8"/><path d="m3 17.2 9 4.8 9-4.8"/>',
  wrench: '<path d="M15 4.5a4.2 4.2 0 0 0 4.5 6.6L13 17.6 6.4 11 12.9 4.5a4.2 4.2 0 0 1 2.1 0Z"/><path d="m6.4 11-2 2a2.8 2.8 0 1 0 4 4l2-2"/>',
  plus: '<path d="M12 5v14"/><path d="M5 12h14"/>',
  minus: '<path d="M5 12h14"/>',
  search: '<circle cx="11" cy="11" r="6.5"/><path d="m20 20-3.6-3.6"/>',
  gear: '<circle cx="12" cy="12" r="3"/><path d="M19.4 14.6a1.7 1.7 0 0 0 .4 1.9l.1.1a2 2 0 1 1-2.9 2.8l-.1-.1a1.7 1.7 0 0 0-1.9-.3 1.7 1.7 0 0 0-1 1.6V21a2 2 0 1 1-4 0v-.4a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.9.3l-.1.1a2 2 0 1 1-2.8-2.9l.1-.1a1.7 1.7 0 0 0 .3-1.9 1.7 1.7 0 0 0-1.6-1H3a2 2 0 1 1 0-4h.4a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.9l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.9.3H9.4a1.7 1.7 0 0 0 1-1.6V3a2 2 0 1 1 4 0v.4a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.9-.3l.1-.1a2 2 0 1 1 2.9 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.9v.2a1.7 1.7 0 0 0 1.6 1H21a2 2 0 1 1 0 4h-.4a1.7 1.7 0 0 0-1.2 1Z"/>',
  copy: '<rect x="9" y="9" width="11" height="11" rx="2.2"/><path d="M5.6 15H5a1.8 1.8 0 0 1-1.8-1.8V5A1.8 1.8 0 0 1 5 3.2h8.2A1.8 1.8 0 0 1 15 5v.6"/>',
  pencil: '<path d="M12 20h9"/><path d="M16.4 3.6a2.1 2.1 0 0 1 3 3L7.4 18.6 3.6 20l1.4-3.8L16.4 3.6Z"/>',
  eye: '<path d="M2.5 12S6 5.8 12 5.8 21.5 12 21.5 12 18 18.2 12 18.2 2.5 12 2.5 12Z"/><circle cx="12" cy="12" r="2.6"/>',
  eyeOff: '<path d="M3 3l18 18"/><path d="M10.6 6.1A9.8 9.8 0 0 1 12 5.8c6 0 9.5 6.2 9.5 6.2a17 17 0 0 1-3.4 4.1"/><path d="M6.3 7.9A17 17 0 0 0 2.5 12S6 18.2 12 18.2c1.4 0 2.6-.3 3.7-.8"/>',
  check: '<path d="m4.5 12.5 5 5L20 6.8"/>',
  x: '<path d="m6 6 12 12"/><path d="m18 6-12 12"/>',
  dots: '<circle cx="6" cy="12" r="1.4"/><circle cx="12" cy="12" r="1.4"/><circle cx="18" cy="12" r="1.4"/>',
  trash: '<path d="M4 7h16"/><path d="M9.5 7V4.8h5V7"/><path d="m6.4 7 1 13.2h9.2L17.6 7"/>',
  refresh: '<path d="M20 11.5A8 8 0 1 0 18.9 16"/><path d="M20 5v6.5h-6.5"/>',
  download: '<path d="M12 4v11"/><path d="m8 11.5 4 4 4-4"/><path d="M5 20h14"/>',
  shield: '<path d="M12 3 5 6v6c0 4.2 3 7.4 7 9 4-1.6 7-4.8 7-9V6l-7-3Z"/>',
  lock: '<rect x="4.8" y="11" width="14.4" height="9.2" rx="2.2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
  external: '<path d="M14 4h6v6"/><path d="M20 4 11 13"/><path d="M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/>',
  chevronRight: '<path d="m9 5 7 7-7 7"/>',
  sliders: '<path d="M4 8h10"/><path d="M18 8h2"/><circle cx="16" cy="8" r="2"/><path d="M4 16h4"/><path d="M12 16h8"/><circle cx="10" cy="16" r="2"/>',
  winMin: '<path d="M4 12h16"/>',
  winMax: '<rect x="5" y="5" width="14" height="14" rx="1.6"/>',
  winRestore: '<rect x="4" y="9" width="11" height="11" rx="1.6"/><path d="M8 9V5.6A1.6 1.6 0 0 1 9.6 4h8.8A1.6 1.6 0 0 1 20 5.6v8.8a1.6 1.6 0 0 1-1.6 1.6H15"/>',
  winClose: '<path d="m5 5 14 14"/><path d="m19 5-14 14"/>',
  command: '<path d="M9 6.5A2.5 2.5 0 1 0 6.5 9H9V6.5Z"/><path d="M15 6.5A2.5 2.5 0 1 1 17.5 9H15V6.5Z"/><path d="M9 17.5A2.5 2.5 0 1 1 6.5 15H9v2.5Z"/><path d="M15 17.5a2.5 2.5 0 1 0 2.5-2.5H15v2.5Z"/><rect x="9" y="9" width="6" height="6" rx="1"/>'
};

export function icon(name, size) {
  const body = PATHS[name] || PATHS.box;
  const px = size || 16;
  return '<svg viewBox="0 0 24 24" width="' + px + '" height="' + px + '" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + body + '</svg>';
}

export const SYMBOL_MAP = {
  "shippingbox.fill": "box",
  "hammer.fill": "hammer",
  "terminal.fill": "terminal",
  "curlybraces": "braces",
  "swift": "command",
  "leaf.fill": "leaf",
  "flame.fill": "flame",
  "cloud.fill": "cloud",
  "cylinder.split.1x2.fill": "layers",
  "sparkles": "sparkles"
};

export function symbolIcon(symbol, size) {
  return icon(SYMBOL_MAP[symbol] || "box", size || 15);
}
