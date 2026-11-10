import { bridge } from "./bridge.js";
import { icon, symbolIcon } from "./icons.js";

const params = new URLSearchParams(location.search);
const forcedTheme = params.get("theme");
if (forcedTheme === "light" || forcedTheme === "dark") {
  document.documentElement.dataset.theme = forcedTheme;
}

const els = {
  root: document.getElementById("root"),
  boot: document.getElementById("boot"),
  sidebar: document.getElementById("sidebar"),
  content: document.getElementById("content"),
  toast: document.getElementById("toast-host"),
  sheet: document.getElementById("sheet-host")
};

const state = {
  data: null,
  view: "system",
  selected: "",
  filter: "all",
  query: "",
  systemReveal: false,
  revealedSystem: new Set(),
  sheet: null,
  dialog: null,
  saveState: "saved",
  busy: false,
  revealed: new Set(),
  // Plaintext of secrets the user has asked to see. The host keeps secrets
  // masked on the wire, so each value is fetched once and kept for the session.
  plain: {},
  mcpClient: "generic"
};

const TINT_NAMES = { aurora: "极光", ocean: "海洋", ember: "余烬", orchid: "兰紫", lime: "青柠", slate: "石墨" };

let backendKind = "demo";
let hostKind = "demo";

/* ---------------- helpers ---------------- */

function esc(value) {
  const text = value === null || value === undefined ? "" : String(value);
  let out = "";
  for (let i = 0; i < text.length; i++) {
    const ch = text.charAt(i);
    if (ch === "&") out += "&amp;";
    else if (ch === "<") out += "&lt;";
    else if (ch === ">") out += "&gt;";
    else if (ch === '"') out += "&quot;";
    else if (ch === "'") out += "&#39;";
    else out += ch;
  }
  return out;
}

function tintStyle(tint) {
  const name = TINT_NAMES[tint] ? tint : "aurora";
  return "background:linear-gradient(140deg,var(--tint-" + name + "-1),var(--tint-" + name + "-2))";
}

function fmtRelative(iso) {
  if (!iso || iso.indexOf("0001-") === 0) return "—";
  const time = Date.parse(iso);
  if (isNaN(time)) return "—";
  const minutes = Math.max(0, Math.round((Date.now() - time) / 60000));
  if (minutes < 1) return "刚刚";
  if (minutes < 60) return minutes + " 分钟前";
  const hours = Math.round(minutes / 60);
  if (hours < 24) return hours + " 小时前";
  const days = Math.round(hours / 24);
  if (days < 30) return days + " 天前";
  return new Date(time).toLocaleDateString();
}

function countEnabled(profile) {
  return profile.variables.filter(function (v) { return v.enabled; }).length;
}

function currentProfile() {
  if (!state.data) return null;
  return state.data.profiles.find(function (p) { return p.id === state.selected; }) || null;
}

function kindLabel(kind) {
  if (kind === "expand") return "可展开";
  if (kind === "path") return "路径";
  return "文本";
}

function resultLabel(code) {
  const map = {
    "up-to-date": "已是最新",
    "not-modified": "无变化",
    "check-failed": "检查失败",
    "unsigned-build": "当前版本未签名"
  };
  if (!code) return "";
  if (code.indexOf("update-available:") === 0) return "发现新版本 " + code.slice(18);
  return map[code] || code;
}

function fmtBytes(bytes) {
  const size = Number(bytes) || 0;
  if (size < 1024) return size + " B";
  if (size < 1024 * 1024) return (size / 1024).toFixed(1) + " KB";
  return (size / (1024 * 1024)).toFixed(1) + " MB";
}

/* ---------------- toast ---------------- */

function toast(message, isError) {
  if (!message) return;
  const node = document.createElement("div");
  node.className = "toast" + (isError ? " error" : "");
  node.innerHTML = icon(isError ? "x" : "check", 13) + "<span>" + esc(message) + "</span>";
  els.toast.appendChild(node);
  setTimeout(function () { node.remove(); }, 3800);
}

/* ---------------- sidebar ---------------- */

function sidebarHTML() {
  const data = state.data;
  const active = data.profiles.find(function (p) { return p.active; });
  let html = '<div class="sidebar-drag" aria-hidden="true"></div>';
  html += '<header class="brand">'
    + '<span class="brand-mark">' + icon("box", 19) + '</span>'
    + '<span style="min-width:0">'
    + '<div class="brand-title">EnvBox</div>'
    + '<div class="brand-sub"><span class="dot' + (active ? '' : ' idle') + '"></span>'
    + esc(active ? active.name : "环境配置管理") + '</div>'
    + '</span></header>';

  html += '<div class="nav" id="nav"><div class="selection-pill" id="selection-pill"></div>';
  html += '<button class="system-row' + (state.view === "system" ? " active" : "") + '" data-act="view:system">'
    + '<span class="tile">' + icon("terminal", 15) + '</span>'
    + '<span style="min-width:0">'
    + '<div class="row-title">系统环境</div>'
    + '<div class="row-sub">实时快照</div>'
    + '</span>'
    + '<span class="count-pill">' + data.system.length + '</span>'
    + '</button>';

  html += '<div class="section-head">'
    + '<span class="section-label">Profiles</span>'
    + '<span class="section-count">' + data.profiles.length + '</span>'
    + '<button class="icon-btn" data-act="new-profile" title="新建配置">' + icon("plus", 12) + '</button>'
    + '</div>';

  html += '<div class="profile-list">' + data.profiles.map(profileRowHTML).join("") + '</div>';

  html += '</div>';
  html += '<footer class="sidebar-foot">'
    + saveStateHTML()
    + '<button class="icon-btn" data-act="view:settings" title="设置">' + icon("gear", 13) + '</button>'
    + '</footer>';
  return html;
}

// The footer must describe the store, not decorate it: "saved" tracks whether the
// last write reached the vault, and the count is the live applied key list.
function saveStateHTML() {
  const applied = (state.data.appliedKeys || []).length;
  const failed = state.saveState === "failed";
  const title = failed ? "未保存" : "已保存";
  const sub = failed
    ? "上一次改动没有写进配置库"
    : (applied ? applied + " 个变量已写入本机" : "尚未应用到本机");
  return '<span class="save-state' + (failed ? " failed" : "") + '" title="' + esc(sub) + '">'
    + '<span class="ico">' + icon(failed ? "x" : "check", 13) + '</span>'
    + '<span><div>' + esc(title) + '</div><div class="sub">' + esc(sub) + '</div></span></span>';
}

function profileRowHTML(profile) {
  const selected = state.view === "profiles" && state.selected === profile.id;
  return '<button class="profile-row' + (selected ? " active" : "") + '" data-act="select" data-id="' + esc(profile.id) + '">'
    + '<span class="profile-tile" style="' + tintStyle(profile.tint) + '">' + symbolIcon(profile.symbol, 15) + '</span>'
    + '<span class="profile-copy">'
    + '<div class="row-title">' + esc(profile.name) + '</div>'
    + '<div class="profile-meta">' + countEnabled(profile) + ' 启用 · ' + profile.variables.length + ' 变量</div>'
    + '</span>'
    + (profile.active ? '<span class="profile-flag">' + icon("check", 9) + '</span>' : '')
    + '</button>';
}

/* ---------------- shared blocks ---------------- */

function statCard(iconName, background, color, value, label, small) {
  return '<div class="stat">'
    + '<span class="stat-ico" style="background:' + background + ';color:' + color + '">' + icon(iconName, 16) + '</span>'
    + '<span><div class="stat-value' + (small ? " small" : "") + '">' + esc(value) + '</div>'
    + '<div class="stat-label">' + esc(label) + '</div></span>'
    + '</div>';
}

function chipsHTML(options) {
  return '<div class="chips">' + options.map(function (option) {
    return '<button class="chip' + (state.filter === option.value ? " active" : "") + '" data-act="filter" data-value="' + option.value + '">' + esc(option.label) + '</button>';
  }).join("") + '</div>';
}

function searchHTML(placeholder) {
  return '<div class="search">' + icon("search", 14)
    + '<input id="search-input" data-role="search" type="text" placeholder="' + esc(placeholder) + '" value="' + esc(state.query) + '" spellcheck="false" autocomplete="off"></div>';
}

function panelHead(title, count, right) {
  return '<div class="panel-head"><h3>' + esc(title) + '</h3>'
    + '<span class="count" data-list-count>' + count + '</span>'
    + '<span class="right" data-list-meta>' + esc(right) + '</span></div>';
}

/* ---------------- profile view ---------------- */

function profileHTML() {
  const profile = currentProfile();
  if (!profile) {
    return '<div class="crumb">Profiles</div>'
      + '<div class="panel"><div class="empty"><strong>还没有配置</strong>点击侧栏的 + 新建一个配置，或先在系统环境里选中变量保存。</div></div>';
  }
  const enabled = countEnabled(profile);
  const secrets = profile.variables.filter(function (v) { return v.secret; }).length;
  const tintName = TINT_NAMES[profile.tint] || "极光";

  let html = '<div class="crumb">Profile · ' + esc(tintName) + '</div>';
  html += '<div class="page-head">'
    + '<span class="page-tile" style="' + tintStyle(profile.tint) + '">' + symbolIcon(profile.symbol, 23) + '</span>'
    + '<div class="head-copy">'
    + '<h1>' + esc(profile.name)
    + (profile.active ? '<span class="pill on"><span class="dot"></span>当前已启用</span>' : '<span class="pill off">未启用</span>')
    + '</h1>'
    + '<div class="page-sub">' + esc(profile.note || "未填写备注") + '</div>'
    + '</div>'
    + '<div class="page-actions">'
    + '<button class="btn icon-only" data-act="edit-profile" title="编辑名称与备注">' + icon("pencil", 15) + '</button>'
    + '<button class="btn icon-only" data-act="duplicate-profile" data-id="' + esc(profile.id) + '" title="复制配置">' + icon("copy", 15) + '</button>'
    + '<button class="btn icon-only" data-act="export-profile" data-id="' + esc(profile.id) + '" title="导出此配置">' + icon("download", 15) + '</button>'
    + '<button class="btn icon-only" data-act="delete-profile" title="删除配置">' + icon("trash", 15) + '</button>'
    + (profile.active
      ? '<button class="btn" data-act="apply" data-id="' + esc(profile.id) + '">' + icon("refresh", 13) + '重新应用</button>'
      : '<button class="btn primary" data-act="apply" data-id="' + esc(profile.id) + '">' + icon("check", 13) + '应用到本机</button>')
    + '</div></div>';

  html += '<div class="stats">'
    + statCard("check", "rgba(89,237,199,.16)", "#0f9c77", enabled + "/" + profile.variables.length, "已启用变量")
    + statCard("lock", "rgba(255,184,89,.16)", "#b4761f", String(secrets), "敏感变量")
    + statCard("refresh", "rgba(71,194,230,.16)", "#1a86a8", fmtRelative(profile.updatedAt), "最后修改", true)
    + '</div>';

  html += '<div class="toolbar">' + searchHTML("搜索变量名、值或备注")
    + chipsHTML([{ value: "all", label: "全部" }, { value: "enabled", label: "已启用" }, { value: "disabled", label: "已停用" }, { value: "sensitive", label: "敏感" }])
    + '<div class="toolbar-right"><button class="btn" data-act="add-variable">' + icon("plus", 13) + '添加变量</button></div>'
    + '</div>';

  html += '<div class="panel">' + panelHead("变量", profile.variables.length, enabled + " 已启用")
    + '<div class="rows" data-list>' + variableRowsHTML(profile) + '</div></div>';
  return html;
}

function visibleVariables(profile) {
  const query = state.query.trim().toLowerCase();
  return profile.variables.filter(function (variable) {
    const haystack = (variable.key + " " + variable.value + " " + variable.note).toLowerCase();
    const matches = !query || haystack.indexOf(query) >= 0;
    const filter = state.filter;
    let pass = true;
    if (filter === "enabled") pass = variable.enabled;
    else if (filter === "disabled") pass = !variable.enabled;
    else if (filter === "sensitive") pass = variable.secret;
    return matches && pass;
  });
}

function variableRowsHTML(profile) {
  if (!profile.variables.length) {
    return '<div class="empty"><strong>还没有变量</strong>点右上角的「添加变量」添加第一条。</div>';
  }
  const rows = visibleVariables(profile);
  if (!rows.length) return '<div class="empty">没有匹配的变量</div>';
  return rows.map(function (variable) { return variableRowHTML(variable); }).join("");
}

function variableRowHTML(variable) {
  const masked = variable.secret && !state.revealed.has(variable.id);
  const shown = masked ? "••••••••" : plainOf(variable);
  return '<div class="vrow' + (variable.enabled ? "" : " disabled") + '">'
    + '<button class="switch' + (variable.enabled ? " on" : "") + '" data-act="toggle" data-vid="' + esc(variable.id) + '" role="switch" aria-checked="' + (variable.enabled ? "true" : "false") + '" aria-label="启用 ' + esc(variable.key) + '"></button>'
    + '<div style="min-width:0">'
    + '<div class="vkey"><span class="vlock">' + (variable.secret ? icon("lock", 11) : "") + '</span>' + esc(variable.key) + '</div>'
    + (variable.note ? '<div class="vnote">' + esc(variable.note) + '</div>' : '')
    + '</div>'
    + '<div class="vval' + (masked ? " masked" : "") + '">' + esc(shown) + '</div>'
    + '<div class="vacts">'
    + (variable.secret ? '<button class="icon-btn" data-act="reveal" data-vid="' + esc(variable.id) + '" title="' + (masked ? "显示" : "隐藏") + '">' + icon(masked ? "eye" : "eyeOff", 13) + '</button>' : "")
    + '<button class="icon-btn" data-act="copy-key" data-vid="' + esc(variable.id) + '" title="复制变量名">' + icon("tag", 13) + '</button>'
    + '<button class="icon-btn" data-act="copy-value" data-vid="' + esc(variable.id) + '" title="复制值">' + icon("copy", 13) + '</button>'
    + '<button class="icon-btn" data-act="edit" data-vid="' + esc(variable.id) + '" title="编辑">' + icon("pencil", 13) + '</button>'
    + '</div></div>';
}

/* ---------------- system view ---------------- */

function systemHTML() {
  const data = state.data;
  const applied = data.system.filter(function (v) { return v.applied; }).length;
  const sensitive = data.system.filter(function (v) { return v.sensitive; }).length;

  let html = '<div class="crumb">System</div>';
  html += '<div class="page-head">'
    + '<span class="page-tile" style="background:linear-gradient(140deg,var(--brand-aqua),var(--brand-indigo))">' + icon("terminal", 23) + '</span>'
    + '<div class="head-copy"><h1>系统环境</h1>'
    + '<div class="page-sub">当前用户的环境变量，来源标为 EnvBox 的是当前配置写入的。</div></div>'
    + '<div class="page-actions"><button class="btn" data-act="refresh">' + icon("refresh", 13) + '刷新</button></div>'
    + '</div>';

  html += '<div class="stats">'
    + statCard("layers", "rgba(71,194,230,.16)", "#1a86a8", String(data.system.length), "变量总数")
    + statCard("box", "rgba(89,237,199,.16)", "#0f9c77", String(applied), "EnvBox 写入")
    + statCard("lock", "rgba(255,184,89,.16)", "#b4761f", String(sensitive), "敏感值")
    + '</div>';

  html += '<div class="toolbar">' + searchHTML("搜索变量名")
    + chipsHTML([{ value: "all", label: "全部" }, { value: "sensitive", label: "敏感" }, { value: "applied", label: "EnvBox" }])
    + '<div class="toolbar-right"><button class="btn ' + (state.systemReveal ? "" : "ghost") + '" data-act="toggle-system-reveal">' + icon(state.systemReveal ? "eyeOff" : "eye", 13) + (state.systemReveal ? "隐藏敏感值" : "显示敏感值") + '</button></div>'
    + '</div>';

  html += '<div class="panel">' + panelHead("变量", data.system.length, applied + " 个来自 EnvBox")
    + '<div class="rows" data-list>' + systemRowsHTML() + '</div></div>';
  return html;
}

function visibleSystem() {
  const query = state.query.trim().toLowerCase();
  return state.data.system.filter(function (variable) {
    const matches = !query || variable.key.toLowerCase().indexOf(query) >= 0;
    let pass = true;
    if (state.filter === "sensitive") pass = variable.sensitive;
    else if (state.filter === "applied") pass = variable.applied;
    return matches && pass;
  });
}

function systemRowsHTML() {
  const rows = visibleSystem();
  if (!rows.length) return '<div class="empty">没有匹配的变量</div>';
  return rows.map(function (variable) {
    // macOS conceals each sensitive row on its own as well as all at once.
    const hidden = variable.sensitive && !state.systemReveal && !state.revealedSystem.has(variable.key);
    const key = esc(variable.key);
    return '<div class="srow">'
      + '<div class="vkey"><span class="vlock">' + (variable.sensitive ? icon("lock", 11) : "") + '</span>' + esc(variable.key) + '</div>'
      + '<div class="vval' + (hidden ? " masked" : "") + '">' + esc(hidden ? "••••••••" : variable.value) + '</div>'
      + '<div><span class="badge">' + kindLabel(variable.kind) + '</span></div>'
      + '<div><span class="badge' + (variable.applied ? " envbox" : "") + '">' + (variable.applied ? "EnvBox" : "用户") + '</span></div>'
      + '<div class="vacts">'
      + (variable.sensitive ? '<button class="icon-btn" data-act="reveal-system" data-key="' + key + '" title="' + (hidden ? "显示值" : "隐藏值") + '">' + icon(hidden ? "eye" : "eyeOff", 13) + '</button>' : "")
      + '<button class="icon-btn" data-act="copy-key" data-scope="system" data-key="' + key + '" title="复制变量名">' + icon("tag", 13) + '</button>'
      + '<button class="icon-btn" data-act="copy-value" data-scope="system" data-key="' + key + '" title="复制值">' + icon("copy", 13) + '</button>'
      + '</div>'
      + '</div>';
  }).join("");
}

/* ---------------- settings view ---------------- */

function settingsHTML() {
  const data = state.data;
  const settings = data.settings;
  const update = data.update;
  const shell = data.shell;
  const mcp = data.mcp;

  let html = '<div class="crumb">Settings</div>';
  html += '<div class="page-head">'
    + '<span class="page-tile" style="background:linear-gradient(140deg,var(--brand-violet),var(--brand-indigo))">' + icon("gear", 23) + '</span>'
    + '<div class="head-copy"><h1>设置</h1><div class="page-sub">启动、Shell 集成、MCP 与更新。</div></div>'
    + '</div>';

  html += '<div class="settings-grid">';

  html += '<div class="panel"><div class="panel-head"><h3>常规</h3></div>'
    + settingRow("开机启动 EnvBox", "登录后自动在后台运行，菜单栏常驻。", switchHTML("autostart", data.autostart.enabled))
    + settingRow("自动检查更新", "只访问 GitHub Releases，可随时关闭。", selectHTML("check", settings.check, [["off", "关闭"], ["daily", "每天"], ["weekly", "每周"]]))
    + '</div>';

  html += '<div class="panel"><div class="panel-head"><h3>Shell 集成</h3></div>'
    + settingRow(shell.installed ? "已安装" : "未安装",
      shell.installed ? esc(shell.profilePath) : "启用后新开的终端会自动加载当前配置。",
      '<button class="btn' + (shell.installed ? " danger" : "") + '" data-act="' + (shell.installed ? "shell-uninstall" : "shell-install") + '">'
      + (shell.installed ? "移除" : "安装") + '</button>')
    + '</div>';

  html += '<div class="panel"><div class="panel-head"><h3>MCP</h3></div>'
    + settingRow("启用 MCP 服务器", "让 Claude、Cursor 等客户端读取配置库。", switchHTML("mcp-enabled", mcp.enabled))
    + (mcp.enabled
      ? mcpWiringHTML() + settingRow("允许读取明文", "关闭时 env_reveal 只返回掩码。", switchHTML("mcp-reveal", mcp.allowReveal))
      : "")
    + '</div>';

  const meta = [];
  if (settings.lastCheckAt) meta.push("上次检查 " + fmtRelative(settings.lastCheckAt));
  if (settings.lastResult) meta.push("结果 " + resultLabel(settings.lastResult));
  html += '<div class="panel"><div class="panel-head"><h3>更新</h3><span class="right">当前 ' + esc(update.current) + (update.available ? " → " + esc(update.available) : "") + '</span></div>'
    + settingRow("检查与安装", meta.length ? esc(meta.join(" · ")) : "尚未检查过。",
      (update.available ? '<button class="btn" data-act="update-download">下载</button>' : "")
      + '<button class="btn" data-act="update-check">检查</button>'
      + '<button class="btn primary" data-act="update-install"' + (update.canInstall ? "" : " disabled") + '>安装并重启</button>')
    + settingRow("更新通道", update.signing ? "此版本可自动安装更新。" : "此版本需手动下载安装包。",
      '<a class="btn ghost" href="' + esc(update.htmlUrl) + '" target="_blank" rel="noreferrer">发布页</a>')
    + '</div>';

  html += '<div class="panel"><div class="panel-head"><h3>数据</h3></div>'
    + settingRow("加密导入", "读取其他平台导出的 .envbox。重名配置自动改名，不会覆盖现有配置。", '<button class="btn" data-act="import">导入 .envbox</button>')
    + settingRow("加密导出", "使用独立密码保护的可移植 .envbox 文件。", '<button class="btn" data-act="export">导出全部配置</button>')
    + settingRow("配置库位置", "AES-256-GCM 加密，密钥由系统钥匙串/DPAPI 保护。", '<span class="setting-value">仅本机</span>')
    + '</div>';

  html += '</div>';
  return html;
}

function settingRow(title, description, control) {
  return '<div class="setting"><div><div class="setting-title">' + esc(title) + '</div>'
    + '<div class="setting-desc">' + description + '</div></div>'
    + '<div style="display:flex;align-items:center;gap:8px">' + control + '</div></div>';
}

// mcpWiringHTML mirrors the macOS settings card: pick a client, see the exact
// config, copy it, or copy a prompt that makes an agent wire itself up.
function mcpWiringHTML() {
  const clients = (state.data && state.data.mcpClients) || [];
  if (!clients.length) return "";
  const client = clients.find(function (item) { return item.id === state.mcpClient; }) || clients[0];
  return '<div class="setting wide"><div>'
    + '<div class="setting-title">客户端接入</div>'
    + '<div class="setting-desc">选中客户端后复制配置；提示词交给 agent，让它自己接上。</div>'
    + '<div class="chips" style="margin-top:10px">'
    + clients.map(function (item) {
      return '<button class="chip' + (item.id === client.id ? " active" : "") + '" data-act="mcp-client" data-value="' + esc(item.id) + '">' + esc(item.name) + '</button>';
    }).join("")
    + '</div>'
    + '<pre class="snippet">' + esc(client.snippet) + '</pre>'
    + '<div class="cmd-row">'
    + '<button class="btn primary" data-act="mcp-copy-snippet">' + icon("copy", 13) + esc(client.snippetLabel) + '</button>'
    + '<button class="btn" data-act="mcp-copy-prompt">' + icon("sparkles", 13) + '复制提示词</button>'
    + '</div>'
    + '</div></div>';
}

function currentMCPClient() {
  const clients = (state.data && state.data.mcpClients) || [];
  return clients.find(function (item) { return item.id === state.mcpClient; }) || clients[0] || null;
}

function switchHTML(act, on) {
  return '<button class="switch' + (on ? " on" : "") + '" data-act="' + act + '" role="switch" aria-checked="' + (on ? "true" : "false") + '"></button>';
}

function selectHTML(role, value, options) {
  return '<select class="select" name="' + role + '" data-role="' + role + '">' + options.map(function (pair) {
    return '<option value="' + pair[0] + '"' + (pair[0] === value ? " selected" : "") + '>' + pair[1] + '</option>';
  }).join("") + '</select>';
}

/* ---------------- sheet ---------------- */

function sheetHTML() {
  const sheet = state.sheet;
  if (!sheet) return "";
  if (sheet.kind === "profile") return profileSheetHTML(sheet);
  if (sheet.kind !== "variable") return "";
  const draft = sheet.draft;
  return '<div class="sheet-backdrop" data-act="sheet-backdrop"><div class="sheet" data-sheet="1">'
    + '<div class="sheet-head"><h2>' + (sheet.index < 0 ? "添加变量" : "编辑变量") + '</h2>'
    + '<p>敏感变量的值会加密保存，列表里默认遮盖。</p></div>'
    + '<div class="sheet-body">'
    + fieldHTML("变量名", '<input id="f-key" type="text" value="' + esc(draft.key) + '" placeholder="API_BASE_URL" spellcheck="false" autocomplete="off">')
    + fieldHTML("值", '<input id="f-value" type="text" value="' + esc(draft.value) + '" placeholder="https://…" spellcheck="false" autocomplete="off">')
    + fieldHTML("备注", '<input id="f-note" type="text" value="' + esc(draft.note) + '" placeholder="可选" autocomplete="off">')
    + '<label class="checkrow"><input id="f-enabled" type="checkbox" ' + (draft.enabled ? "checked" : "") + '> 启用这个变量</label>'
    + '<label class="checkrow"><input id="f-secret" type="checkbox" ' + (draft.secret ? "checked" : "") + '> 标记为敏感值</label>'
    + '</div>'
    + '<div class="sheet-foot"><button class="btn ghost" data-act="close-sheet">取消</button>'
    + '<button class="btn primary" data-act="sheet-save">保存</button></div>'
    + '</div></div>';
}

function fieldHTML(label, control) {
  return '<div class="field"><label>' + esc(label) + '</label>' + control + '</div>';
}

function fieldError(text) {
  return '<div class="field-error" data-sheet-error hidden>' + esc(text) + '</div>';
}

function profileSheetHTML(sheet) {
  const draft = sheet.draft;
  const creating = sheet.mode === "create";
  return '<div class="sheet-backdrop" data-act="sheet-backdrop"><div class="sheet sheet-narrow" data-sheet="1">'
    + '<div class="sheet-head"><h2>' + (creating ? "新建配置" : "编辑配置") + '</h2>'
    + '<p>' + (creating ? "配置是一组环境变量，应用这个配置时会整组写入。" : "改名或改备注不会动已经写入本机的变量。") + '</p></div>'
    + '<div class="sheet-body">'
    + fieldHTML("名称", '<input id="f-name" type="text" maxlength="60" value="' + esc(draft.name) + '" placeholder="例如 本地开发" spellcheck="false" autocomplete="off">')
    + fieldHTML("备注", '<input id="f-note" type="text" maxlength="500" value="' + esc(draft.note) + '" placeholder="可选" autocomplete="off">')
    + fieldError("")
    + '</div>'
    + '<div class="sheet-foot"><button class="btn ghost" data-act="close-sheet">取消</button>'
    + '<button class="btn primary" data-act="sheet-save">' + (creating ? "创建" : "保存") + '</button></div>'
    + '</div></div>';
}

/* ---------------- dialog ---------------- */

// window.confirm renders the WebView2 chrome dialog ("wails.localhost 显示"),
// which shares nothing with the app shell. Everything modal goes through here.
function dialogHTML() {
  const dialog = state.dialog;
  if (!dialog) return "";
  const password = dialog.kind === "password";
  return '<div class="sheet-backdrop dialog-backdrop" data-act="dialog-backdrop">'
    + '<div class="dialog" data-dialog="1" role="dialog" aria-modal="true">'
    + '<div class="dialog-head">'
    + '<span class="dialog-icon' + (dialog.danger ? " danger" : "") + '">' + icon(dialog.danger ? "trash" : "shield", 16) + '</span>'
    + '<div><h2>' + esc(dialog.title) + '</h2>'
    + (dialog.message ? '<p>' + esc(dialog.message) + '</p>' : '')
    + '</div></div>'
    + (password
      ? '<div class="dialog-body">' + fieldHTML(dialog.label, '<input id="f-passphrase" type="password" autocomplete="off" placeholder="至少 8 位">')
        + '<div class="field-error" data-dialog-error hidden></div></div>'
      : '')
    + '<div class="dialog-foot">'
    + '<button class="btn ghost" data-act="dialog-cancel">' + esc(dialog.cancelLabel) + '</button>'
    + '<button class="btn ' + (dialog.danger ? "danger solid" : "primary") + '" data-act="dialog-confirm">' + esc(dialog.confirmLabel) + '</button>'
    + '</div></div></div>';
}

function openDialog(dialog) {
  return new Promise(function (resolve) {
    state.dialog = Object.assign({ cancelLabel: "取消", confirmLabel: "确定" }, dialog, { resolve: resolve });
    render();
    const target = document.getElementById("f-passphrase")
      || document.querySelector('[data-act="dialog-confirm"]');
    if (target) target.focus();
  });
}

async function askConfirm(options) {
  const answer = await openDialog({
    kind: "confirm",
    title: options.title,
    message: options.message || "",
    confirmLabel: options.confirmLabel,
    danger: Boolean(options.danger)
  });
  return answer === true;
}

async function askPassword(options) {
  const answer = await openDialog({
    kind: "password",
    title: options.title,
    message: options.message || "",
    label: options.label || "密码",
    confirmLabel: options.confirmLabel
  });
  return typeof answer === "string" ? answer : "";
}

function settleDialog(value) {
  const dialog = state.dialog;
  state.dialog = null;
  render();
  if (dialog && dialog.resolve) dialog.resolve(value);
}

function showError(selector, message) {
  const box = document.querySelector(selector);
  if (!box) {
    toast(message, true);
    return;
  }
  box.textContent = message;
  box.hidden = false;
}

function submitDialog() {
  const dialog = state.dialog;
  if (!dialog) return;
  if (dialog.kind === "password") {
    const input = document.getElementById("f-passphrase");
    const value = input ? input.value : "";
    if (value.length < 8) {
      showError("[data-dialog-error]", "密码至少 8 位");
      if (input) input.focus();
      return;
    }
    settleDialog(value);
    return;
  }
  settleDialog(true);
}

/* ---------------- render ---------------- */

let selectionState = null;

// The selection highlight is one element shared by the system row and every
// profile row, so switching between them slides the same pill instead of
// swapping two differently styled backgrounds. Mirrors the macOS
// matchedGeometryEffect behaviour.
function positionSelection() {
  const nav = document.getElementById("nav");
  const pill = document.getElementById("selection-pill");
  if (!nav || !pill) return;
  const row = nav.querySelector(".system-row.active, .profile-row.active");
  if (!row) {
    pill.classList.remove("visible");
    if (selectionState) selectionState.visible = false;
    return;
  }
  const top = row.offsetTop;
  const height = row.offsetHeight;
  if (selectionState && selectionState.visible) {
    pill.style.transition = "none";
    pill.style.top = selectionState.top + "px";
    pill.style.height = selectionState.height + "px";
    void pill.offsetHeight;
    pill.style.transition = "";
  }
  pill.style.top = top + "px";
  pill.style.height = height + "px";
  pill.classList.add("visible");
  selectionState = { top: top, height: height, visible: true };
}

function render() {
  if (!state.data) return;
  els.boot.hidden = true;
  els.root.hidden = false;
  const previousNav = document.getElementById("nav");
  const scrollTop = previousNav ? previousNav.scrollTop : 0;
  els.sidebar.innerHTML = sidebarHTML();
  const nav = document.getElementById("nav");
  if (nav) nav.scrollTop = scrollTop;
  positionSelection();
  els.content.innerHTML = state.view === "system" ? systemHTML() : state.view === "settings" ? settingsHTML() : profileHTML();
  els.sheet.innerHTML = dialogHTML() + sheetHTML();
}

function refreshList() {
  const list = document.querySelector("[data-list]");
  if (!list) return;
  if (state.view === "system") {
    list.innerHTML = systemRowsHTML();
    return;
  }
  const profile = currentProfile();
  if (!profile) return;
  list.innerHTML = variableRowsHTML(profile);
  const counter = document.querySelector("[data-list-count]");
  if (counter) counter.textContent = String(visibleVariables(profile).length);
}

/* ---------------- actions ---------------- */

// Actions that write the vault; everything else is read-only or machine state.
const PERSIST_ACTIONS = {
  "save-profile": 1, "delete-profile": 1, "duplicate-profile": 1, "save-settings": 1,
  "set-autostart": 1, "set-mcp": 1, "shell-install": 1, "shell-uninstall": 1,
  "export": 1, "import": 1
};

function isPersistence(action) {
  return Boolean(PERSIST_ACTIONS[action]);
}

async function run(action, payload) {
  if (state.busy) return null;
  state.busy = true;
  document.body.style.cursor = "progress";
  try {
    const result = await bridge.dispatch(action, payload || null);
    if (isPersistence(action)) state.saveState = (!result || result.ok === false) ? "failed" : "saved";
    if (result && result.state) state.data = result.state;
    if (result && result.message) toast(result.message, result.ok === false);
    if (!result || result.ok === false) return result;
    if (!state.data.profiles.some(function (p) { return p.id === state.selected; })) {
      const active = state.data.profiles.find(function (p) { return p.active; });
      state.selected = active ? active.id : (state.data.profiles[0] ? state.data.profiles[0].id : "");
      if (!state.selected) state.view = "system";
    }
    return result;
  } catch (error) {
    if (isPersistence(action)) state.saveState = "failed";
    toast(error.message || String(error), true);
    return null;
  } finally {
    state.busy = false;
    document.body.style.cursor = "";
    render();
  }
}

// selectProfile switches to the profile view with one profile selected; actions
// that create a profile (duplicate, import) use it to land on the new one.
function selectProfile(id) {
  if (!id) return;
  state.selected = id;
  state.view = "profiles";
  state.query = "";
  state.filter = "all";
  render();
}

// plainOf returns the value to render: secrets keep the mask until the user
// asks for them, then the fetched plaintext is used from then on.
function plainOf(variable) {
  if (!variable) return "";
  if (!variable.secret) return variable.value;
  const cached = state.plain[variable.id];
  return cached === undefined ? variable.value : cached;
}

// plainValue resolves a secret to its real text. The host answers "reveal" with
// one value so /api/state can stay masked; the answer is cached for the session.
async function plainValue(variable) {
  if (!variable) throw new Error("变量不存在");
  if (!variable.secret) return variable.value;
  const cached = state.plain[variable.id];
  if (cached !== undefined) return cached;
  const result = await bridge.dispatch("reveal", { id: variable.id });
  if (!result || result.ok === false) throw new Error((result && result.message) || "无法读取明文");
  state.plain[variable.id] = result.value;
  return result.value;
}

// copyValue goes through the host so a secret carries the clipboard formats that
// keep it out of history and cloud sync, and disappears 45 s later.
async function copyValue(text, sensitive, message) {
  const flags = Boolean(sensitive);
  const result = await bridge.dispatch("copy", { value: text, sensitive: flags }).catch(function () { return null; });
  if (result && result.ok !== false) {
    toast(message || result.message || "已复制");
    return;
  }
  try {
    await navigator.clipboard.writeText(text);
    toast(message || (flags ? "已复制，请尽快粘贴" : "已复制"));
  } catch (error) {
    const area = document.createElement("textarea");
    area.value = text;
    document.body.appendChild(area);
    area.select();
    try { document.execCommand("copy"); toast("已复制"); } catch (inner) { toast("复制失败", true); }
    area.remove();
  }
}

// clipboardSubject returns what a row's copy buttons act on: a profile variable
// (whose value may still need revealing) or a live system variable.
function clipboardSubject(target) {
  if ((target.getAttribute("data-scope") || "") === "system") {
    const key = target.getAttribute("data-key") || "";
    const variable = (state.data.system || []).find(function (item) { return item.key === key; });
    return variable ? { key: variable.key, value: variable.value, sensitive: variable.sensitive } : null;
  }
  const variable = variableById(target.getAttribute("data-vid"));
  return variable ? { key: variable.key, variable: variable, sensitive: variable.secret } : null;
}

function variableById(id) {
  const profile = currentProfile();
  if (!profile) return null;
  return profile.variables.find(function (v) { return v.id === id; }) || null;
}

function saveProfile() {
  const profile = currentProfile();
  if (!profile) return null;
  return run("save-profile", { profile: profile });
}

const TINT_CYCLE = ["ocean", "aurora", "ember", "orchid", "lime", "slate"];

// New profiles get the least-used tint so the sidebar stays readable instead of
// turning into six identical blue rows.
function nextTint() {
  const used = {};
  state.data.profiles.forEach(function (profile) { used[profile.tint] = (used[profile.tint] || 0) + 1; });
  let best = TINT_CYCLE[0];
  let bestCount = Infinity;
  TINT_CYCLE.forEach(function (tint) {
    const count = used[tint] || 0;
    if (count < bestCount) { bestCount = count; best = tint; }
  });
  return best;
}

async function persistSheet() {
  const sheet = state.sheet;
  if (!sheet) return;
  if (sheet.kind === "profile") { await persistProfileSheet(sheet); return; }
  await persistVariableSheet(sheet);
}

// Persists before closing: a rejected name (empty, duplicate) leaves the sheet
// open with the typed text intact instead of dropping the edit on the floor.
async function persistProfileSheet(sheet) {
  const nameInput = document.getElementById("f-name");
  const noteInput = document.getElementById("f-note");
  if (!nameInput) return;
  const name = nameInput.value.trim();
  const note = noteInput ? noteInput.value.trim() : "";
  if (!name) {
    showError("[data-sheet-error]", "名称不能为空");
    nameInput.focus();
    return;
  }
  const creating = sheet.mode === "create";
  const clash = state.data.profiles.some(function (profile) {
    return profile.id !== sheet.draft.id && profile.name.trim().toLowerCase() === name.toLowerCase();
  });
  if (clash) {
    showError("[data-sheet-error]", "已有同名配置");
    nameInput.focus();
    return;
  }

  const profile = currentProfile();
  const request = {
    id: creating ? "" : sheet.draft.id,
    name: name,
    note: note,
    tint: creating ? sheet.draft.tint : (profile ? profile.tint : sheet.draft.tint),
    symbol: creating ? sheet.draft.symbol : (profile ? profile.symbol : sheet.draft.symbol),
    variables: creating || !profile ? [] : profile.variables
  };
  sheet.draft.name = name;
  sheet.draft.note = note;

  const result = await run("save-profile", { profile: request });
  if (!result || result.ok === false) return;
  state.sheet = null;
  state.query = "";
  state.filter = "all";
  if (creating) {
    const created = state.data.profiles.find(function (profile) {
      return profile.name.trim().toLowerCase() === name.toLowerCase();
    });
    if (created) { state.selected = created.id; state.view = "profiles"; }
  }
  render();
}

async function persistVariableSheet(sheet) {
  const profile = currentProfile();
  if (!profile) return;
  const keyInput = document.getElementById("f-key");
  const valueInput = document.getElementById("f-value");
  const noteInput = document.getElementById("f-note");
  const enabledInput = document.getElementById("f-enabled");
  const secretInput = document.getElementById("f-secret");
  if (!keyInput || !valueInput) return;

  const key = keyInput.value.trim();
  const value = valueInput.value;
  const note = noteInput ? noteInput.value.trim() : "";
  const enabled = enabledInput ? enabledInput.checked : true;
  const secret = secretInput ? secretInput.checked : false;
  if (!key) {
    showError("[data-sheet-error]", "变量名不能为空");
    keyInput.focus();
    return;
  }
  if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) {
    showError("[data-sheet-error]", "变量名只能用字母、数字和下划线，且不能以数字开头");
    keyInput.focus();
    return;
  }

  // Work on a copy so a rejected save leaves the visible profile untouched.
  const next = {
    id: profile.id, name: profile.name, note: profile.note,
    tint: profile.tint, symbol: profile.symbol,
    variables: profile.variables.map(function (variable) { return Object.assign({}, variable); })
  };
  if (sheet.index < 0) {
    const duplicate = next.variables.some(function (variable) {
      return variable.key.trim().toUpperCase() === key.toUpperCase();
    });
    if (duplicate) {
      showError("[data-sheet-error]", "已有同名变量");
      keyInput.focus();
      return;
    }
    next.variables.push({ id: "", key: key, value: value, note: note, enabled: enabled, secret: secret, masked: false });
  } else {
    const variable = next.variables.find(function (item) { return item.id === sheet.draft.id; });
    if (!variable) return;
    variable.key = key;
    variable.value = value;
    variable.note = note;
    variable.enabled = enabled;
    variable.secret = secret;
  }

  sheet.draft = { id: sheet.draft.id, key: key, value: value, note: note, enabled: enabled, secret: secret };
  const result = await run("save-profile", { profile: next });
  if (!result || result.ok === false) return;
  if (secret && sheet.draft.id) state.plain[sheet.draft.id] = value;
  state.sheet = null;
  render();
}

async function applyProfile(id) {
  await run("apply", { id: id });
}

document.addEventListener("click", async function (event) {
  const target = event.target.closest("[data-act]");
  if (!target) return;
  const act = target.getAttribute("data-act");

  if (act === "window-minimise" || act === "window-toggle-maximise" || act === "window-close") {
    if (backendKind !== "http") {
      toast("演示模式下窗口按钮不可用");
      return;
    }
    await bridge.dispatch(act, null);
    return;
  }

  // Backdrops and their buttons are separate actions: the old shared guard
  // swallowed the in-panel 取消 button, and dropping it let clicks inside the
  // panel close the panel. Each side now has its own handler.
  if (act === "dialog-cancel") {
    settleDialog(state.dialog && state.dialog.kind === "password" ? "" : false);
    return;
  }

  if (act === "dialog-backdrop") {
    if (event.target.closest("[data-dialog]")) return;
    settleDialog(state.dialog && state.dialog.kind === "password" ? "" : false);
    return;
  }

  if (act === "dialog-confirm") {
    submitDialog();
    return;
  }

  if (act === "close-sheet") {
    state.sheet = null;
    render();
    return;
  }

  if (act === "sheet-backdrop") {
    if (event.target.closest("[data-sheet]")) return;
    state.sheet = null;
    render();
    return;
  }

  if (act === "view:system") { state.view = "system"; state.query = ""; state.filter = "all"; render(); return; }
  if (act === "view:settings") { state.view = "settings"; state.query = ""; state.filter = "all"; render(); return; }

  if (act === "select") {
    state.selected = target.getAttribute("data-id");
    state.view = "profiles";
    state.query = "";
    state.filter = "all";
    render();
    return;
  }

  if (act === "new-profile") {
    if (state.data.profiles.length >= 100) { toast("配置数量已达上限", true); return; }
    state.sheet = {
      kind: "profile", mode: "create",
      draft: { id: "", name: "", note: "", tint: nextTint(), symbol: "cloud.fill" }
    };
    render();
    const input = document.getElementById("f-name");
    if (input) input.focus();
    return;
  }

  if (act === "edit-profile") {
    const profile = currentProfile();
    if (!profile) return;
    state.sheet = {
      kind: "profile", mode: "edit",
      draft: { id: profile.id, name: profile.name, note: profile.note, tint: profile.tint, symbol: profile.symbol }
    };
    render();
    const input = document.getElementById("f-name");
    if (input) { input.focus(); input.select(); }
    return;
  }

  if (act === "filter") {
    state.filter = target.getAttribute("data-value");
    render();
    return;
  }

  if (act === "toggle") {
    const variable = variableById(target.getAttribute("data-vid"));
    if (!variable) return;
    variable.enabled = !variable.enabled;
    await saveProfile();
    return;
  }

  if (act === "reveal") {
    const id = target.getAttribute("data-vid");
    if (state.revealed.has(id)) {
      state.revealed.delete(id);
      render();
      return;
    }
    const variable = variableById(id);
    try {
      await plainValue(variable);
      state.revealed.add(id);
    } catch (error) {
      toast(error.message, true);
    }
    render();
    return;
  }

  if (act === "copy-key" || act === "copy-value") {
    const subject = clipboardSubject(target);
    if (!subject) return;
    try {
      if (act === "copy-key") {
        await copyValue(subject.key, false, "已复制变量名");
      } else if (subject.variable) {
        await copyValue(await plainValue(subject.variable), subject.sensitive);
      } else {
        await copyValue(subject.value, subject.sensitive);
      }
    } catch (error) {
      toast(error.message, true);
    }
    return;
  }

  if (act === "reveal-system") {
    const key = target.getAttribute("data-key") || "";
    if (state.revealedSystem.has(key)) state.revealedSystem.delete(key);
    else state.revealedSystem.add(key);
    render();
    return;
  }

  if (act === "edit") {
    const variable = variableById(target.getAttribute("data-vid"));
    if (!variable) return;
    let value = variable.value;
    if (variable.secret) {
      // Editing needs the real text, not the mask the list view carries.
      try {
        value = await plainValue(variable);
      } catch (error) {
        toast(error.message, true);
        return;
      }
    }
    state.sheet = { kind: "variable", index: 1, draft: { id: variable.id, key: variable.key, value: value, note: variable.note, enabled: variable.enabled, secret: variable.secret } };
    render();
    const input = document.getElementById("f-key");
    if (input) input.focus();
    return;
  }

  if (act === "add-variable") {
    state.sheet = { kind: "variable", index: -1, draft: { id: "", key: "", value: "", note: "", enabled: true, secret: false } };
    render();
    const input = document.getElementById("f-key");
    if (input) input.focus();
    return;
  }

  if (act === "sheet-save") {
    await persistSheet();
    return;
  }

  if (act === "apply") {
    await applyProfile(target.getAttribute("data-id"));
    return;
  }

  if (act === "delete-profile") {
    const profile = currentProfile();
    if (!profile) return;
    const total = profile.variables.length;
    const confirmed = await askConfirm({
      title: "删除「" + profile.name + "」？",
      message: profile.active
        ? "这个配置正在本机生效。删除会先把已写入的变量从系统中移除，再永久删除配置，无法撤销。"
        : "配置和其中的 " + total + " 个变量会被永久删除，无法撤销。",
      confirmLabel: "删除",
      danger: true
    });
    if (!confirmed) return;
    await run("delete-profile", { id: profile.id });
    return;
  }

  if (act === "duplicate-profile") {
    const result = await run("duplicate-profile", { id: target.getAttribute("data-id") });
    if (result && result.focus) selectProfile(result.focus);
    return;
  }

  if (act === "export-profile") {
    const profile = currentProfile();
    if (!profile) return;
    const passphrase = await askPassword({
      title: "导出「" + profile.name + "」",
      message: "只导出这一个配置。文件用这个密码加密，导入时需要同一个密码。",
      label: "密码（至少 8 位）",
      confirmLabel: "导出"
    });
    if (!passphrase) return;
    await run("export", { passphrase: passphrase, ids: [profile.id] });
    return;
  }

  if (act === "import") {
    // The host owns the file: the page only learns its name and size.
    const picked = await run("import-pick");
    if (!picked || picked.ok === false || !picked.pick) return;
    const passphrase = await askPassword({
      title: "导入 " + picked.pick.name,
      message: fmtBytes(picked.pick.bytes) + "。输入导出时设置的密码；重名配置会自动改名。",
      label: "密码（至少 8 位）",
      confirmLabel: "导入"
    });
    if (!passphrase) return;
    const result = await run("import", { passphrase: passphrase });
    if (result && result.focus) selectProfile(result.focus);
    return;
  }

  if (act === "refresh") {
    try {
      state.data = await bridge.state();
      render();
      toast("已刷新系统环境");
    } catch (error) {
      toast(error.message, true);
    }
    return;
  }

  if (act === "toggle-system-reveal") {
    state.systemReveal = !state.systemReveal;
    render();
    return;
  }

  if (act === "autostart") {
    await run("set-autostart", { enabled: !state.data.autostart.enabled });
    return;
  }

  if (act === "mcp-enabled") {
    await run("set-mcp", { enabled: !state.data.mcp.enabled, allowReveal: state.data.mcp.allowReveal });
    return;
  }

  if (act === "mcp-reveal") {
    await run("set-mcp", { enabled: state.data.mcp.enabled, allowReveal: !state.data.mcp.allowReveal });
    return;
  }

  if (act === "shell-install") { await run("shell-install"); return; }
  if (act === "shell-uninstall") { await run("shell-uninstall"); return; }
  if (act === "update-check") { await run("update-check"); return; }
  if (act === "update-download") { await run("update-download"); return; }
  if (act === "update-install") { await run("update-install"); return; }

  if (act === "mcp-client") {
    state.mcpClient = target.getAttribute("data-value") || "generic";
    render();
    return;
  }

  if (act === "mcp-copy-snippet" || act === "mcp-copy-prompt") {
    const client = currentMCPClient();
    if (!client) return;
    await copyValue(act === "mcp-copy-prompt" ? client.prompt : client.snippet, false);
    return;
  }

  if (act === "export") {
    const passphrase = await askPassword({
      title: "导出全部配置",
      message: "导出的 .envbox 文件用这个密码加密，导入时需要同一个密码。密码不会被保存。",
      label: "密码（至少 8 位）",
      confirmLabel: "导出"
    });
    if (!passphrase) return;
    await run("export", { passphrase: passphrase });
    return;
  }
});

document.addEventListener("input", function (event) {
  const input = event.target;
  if (!input) return;
  if (input.closest("[data-sheet]") || input.closest("[data-dialog]")) {
    const box = input.closest("[data-sheet]") ? document.querySelector("[data-sheet-error]") : document.querySelector("[data-dialog-error]");
    if (box) box.hidden = true;
  }
  if (input.getAttribute("data-role") !== "search") return;
  state.query = input.value;
  refreshList();
});

document.addEventListener("change", function (event) {
  const select = event.target;
  if (!select || select.getAttribute("data-role") !== "check") return;
  run("save-settings", { check: select.value });
});

document.addEventListener("keydown", function (event) {
  if (event.key === "Escape" && state.dialog) {
    event.preventDefault();
    settleDialog(state.dialog.kind === "password" ? "" : false);
    return;
  }
  if (event.key === "Enter" && state.dialog) {
    event.preventDefault();
    submitDialog();
    return;
  }
  if (event.key === "Enter" && state.sheet && event.target.closest("[data-sheet]")) {
    event.preventDefault();
    const save = document.querySelector('[data-act="sheet-save"]');
    if (save) save.click();
    return;
  }
  if (event.key === "Escape" && state.sheet) {
    state.sheet = null;
    render();
  }
});

/* ---------------- boot ---------------- */

function mountTitlebar() {
  const bar = document.getElementById("titlebar");
  if (!bar || bar.dataset.mounted) return;
  bar.dataset.mounted = "1";
  bar.innerHTML = '<div class="tb-controls" style="--wails-draggable: no-drag">'
    + '<button class="tb-btn" data-act="window-minimise" title="最小化" aria-label="最小化">' + icon("winMin", 11) + '</button>'
    + '<button class="tb-btn" data-act="window-toggle-maximise" title="最大化" aria-label="最大化">' + icon("winMax", 11) + '</button>'
    + '<button class="tb-btn close" data-act="window-close" title="关闭" aria-label="关闭">' + icon("winClose", 11) + '</button>'
    + '</div>';
  bar.addEventListener("dblclick", function (event) {
    if (backendKind !== "http" || event.target.closest(".tb-btn")) return;
    bridge.dispatch("window-toggle-maximise", null);
  });
}

async function start() {
  try {
    mountTitlebar();
    backendKind = await bridge.kind();
    const isWebView2 = !!(window.chrome && window.chrome.webview) || location.hostname === "wails.localhost";
    hostKind = params.get("host") || (isWebView2 || backendKind === "http" ? "win" : backendKind === "native" ? "mac" : "demo");
    document.body.dataset.host = hostKind;
    const data = await bridge.state();
    state.data = data;
    const requested = params.get("view");
    if (requested === "system" || requested === "settings" || requested === "profiles") state.view = requested;
    const active = data.profiles.find(function (p) { return p.active; });
    state.selected = data.activeId || (active ? active.id : "") || (data.profiles[0] ? data.profiles[0].id : "");
    render();
    if (params.get("view") === "profiles" && !data.profiles.some(function (p) { return p.id === state.selected; }) && data.profiles[0]) {
      state.selected = data.profiles[0].id;
      render();
    }
    window.__envboxReady = true;
  } catch (error) {
    els.boot.textContent = "载入失败：" + (error && error.message ? error.message : error);
  }
}

start();
