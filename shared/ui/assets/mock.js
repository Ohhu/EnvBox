// Demo backend used by index.html?demo=1.
// It mirrors the Go/Swift state contract so the same frontend can be previewed
// in a plain browser without either backend running.

function nowISO() { return new Date().toISOString(); }

function makeVariable(id, key, value, options) {
  const extra = options || {};
  return {
    id: id,
    key: key,
    value: value,
    enabled: extra.enabled !== false,
    secret: Boolean(extra.secret),
    masked: Boolean(extra.secret),
    note: extra.note || ""
  };
}

function demoState() {
  return {
    version: "1.4.0",
    channel: "stable",
    installed: true,
    activeId: "p1",
    appliedKeys: ["API_BASE_URL", "DATABASE_URL", "FEATURE_FLAGS", "HTTP_PROXY", "LOG_LEVEL", "NODE_ENV", "REDIS_URL", "SENTRY_DSN"],
    profiles: [
      {
        id: "p1",
        name: "本地开发",
        note: "本地 API、调试日志与开发数据库",
        tint: "aurora",
        symbol: "shippingbox.fill",
        active: true,
        updatedAt: new Date(Date.now() - 7 * 60 * 1000).toISOString(),
        variables: [
          makeVariable("v1", "API_BASE_URL", "https://api.staging.envbox.dev/v2"),
          makeVariable("v2", "DATABASE_URL", "postgres://envbox:devpass@127.0.0.1:5432/envbox", { secret: true, note: "本地 Docker" }),
          makeVariable("v3", "FEATURE_FLAGS", "new-editor,fast-sync,command-palette"),
          makeVariable("v4", "HTTP_PROXY", "http://127.0.0.1:6152"),
          makeVariable("v5", "LEGACY_MODE", "1", { enabled: false, note: "仅旧项目使用" }),
          makeVariable("v6", "LOG_LEVEL", "debug"),
          makeVariable("v7", "NODE_ENV", "development"),
          makeVariable("v8", "REDIS_URL", "redis://127.0.0.1:6379/0", { secret: true }),
          makeVariable("v9", "SENTRY_DSN", "https://8f2c1a@o0.ingest.sentry.io/4501", { secret: true })
        ]
      },
      {
        id: "p2",
        name: "预发布",
        note: "staging 集群与灰度开关",
        tint: "ocean",
        symbol: "cloud.fill",
        active: false,
        updatedAt: new Date(Date.now() - 3 * 3600 * 1000).toISOString(),
        variables: [
          makeVariable("w1", "API_BASE_URL", "https://api.staging.envbox.dev/v2"),
          makeVariable("w2", "FLAGS_ENDPOINT", "https://flags.staging.envbox.dev"),
          makeVariable("w3", "LOG_LEVEL", "info"),
          makeVariable("w4", "SENTRY_ENV", "staging"),
          makeVariable("w5", "DATABASE_URL", "postgres://envbox@db.staging.internal:5432/envbox", { secret: true })
        ]
      },
      {
        id: "p3",
        name: "生产排障",
        note: "只读诊断用，勿写入业务流量",
        tint: "ember",
        symbol: "flame.fill",
        active: false,
        updatedAt: new Date(Date.now() - 26 * 3600 * 1000).toISOString(),
        variables: [
          makeVariable("x1", "API_BASE_URL", "https://api.envbox.dev"),
          makeVariable("x2", "LOG_LEVEL", "warn"),
          makeVariable("x3", "NODE_ENV", "production"),
          makeVariable("x4", "HTTP_PROXY", ""),
          makeVariable("x5", "SENTRY_DSN", "https://c91b2f@o0.ingest.sentry.io/4502", { secret: true })
        ]
      }
    ],
    system: [
      { key: "API_BASE_URL", value: "https://api.staging.envbox.dev/v2", kind: "string", sensitive: false, applied: true },
      { key: "DATABASE_URL", value: "postgres://envbox:devpass@127.0.0.1:5432/envbox", kind: "string", sensitive: true, applied: true },
      { key: "EDITOR", value: "code --wait", kind: "string", sensitive: false, applied: false },
      { key: "FEATURE_FLAGS", value: "new-editor,fast-sync,command-palette", kind: "string", sensitive: false, applied: true },
      { key: "GOPATH", value: "C:\\Users\\dev\\go", kind: "path", sensitive: false, applied: false },
      { key: "HOME", value: "C:\\Users\\dev", kind: "path", sensitive: false, applied: false },
      { key: "HTTP_PROXY", value: "http://127.0.0.1:6152", kind: "string", sensitive: false, applied: true },
      { key: "JAVA_HOME", value: "C:\\Program Files\\Java\\jdk-21", kind: "path", sensitive: false, applied: false },
      { key: "LANG", value: "zh_CN.UTF-8", kind: "string", sensitive: false, applied: false },
      { key: "LOG_LEVEL", value: "debug", kind: "string", sensitive: false, applied: true },
      { key: "NODE_ENV", value: "development", kind: "string", sensitive: false, applied: true },
      { key: "NODE_OPTIONS", value: "--max-old-space-size=4096", kind: "string", sensitive: false, applied: false },
      { key: "PATH", value: "%USERPROFILE%\\bin;%APPDATA%\\npm;C:\\Program Files\\nodejs", kind: "expand", sensitive: false, applied: false },
      { key: "PNPM_HOME", value: "%LOCALAPPDATA%\\pnpm", kind: "expand", sensitive: false, applied: false },
      { key: "REDIS_URL", value: "redis://127.0.0.1:6379/0", kind: "string", sensitive: true, applied: true },
      { key: "SHELL", value: "C:\\Program Files\\PowerShell\\7\\pwsh.exe", kind: "path", sensitive: false, applied: false },
      { key: "SSH_AUTH_SOCK", value: "\\\\.\\pipe\\openssh-ssh-agent", kind: "string", sensitive: false, applied: false },
      { key: "TERM", value: "xterm-256color", kind: "string", sensitive: false, applied: false }
    ],
    settings: { check: "daily", skippedVersion: "", lastCheckAt: "2026-11-05T07:30:00Z", lastResult: "up-to-date" },
    update: { current: "1.4.0", available: "", signing: true, canInstall: false, notes: "", pending: "", htmlUrl: "https://github.com/Ohhu/EnvBox/releases" },
    shell: { installed: true, profilePath: "%USERPROFILE%\\Documents\\PowerShell\\Microsoft.PowerShell_profile.ps1" },
    autostart: { enabled: true },
    mcp: { enabled: true, allowReveal: false },
    mcpCommand: "envbox.exe mcp --stdio",
    warning: ""
  };
}

export class DemoBackend {
  constructor() {
    this.data = demoState();
    this.kind = "demo";
  }

  async state() {
    return structuredClone(this.data);
  }

  async dispatch(action, payload) {
    const data = this.data;
    const profile = payload && payload.id ? data.profiles.find(function (p) { return p.id === payload.id; }) : null;
    let message = "已保存";
    let ok = true;

    if (action === "apply" && profile) {
      data.profiles.forEach(function (item) { item.active = false; });
      profile.active = true;
      data.activeId = profile.id;
      data.appliedKeys = profile.variables.filter(function (v) { return v.enabled; }).map(function (v) { return v.key; });
      message = "已应用 " + profile.name + "（" + data.appliedKeys.length + " 个变量）";
    } else if (action === "deactivate") {
      data.profiles.forEach(function (item) { item.active = false; });
      data.activeId = "";
      data.appliedKeys = [];
      message = "已移除全部变量";
    } else if (action === "save-profile" && payload && payload.profile) {
      const incoming = payload.profile;
      const name = String(incoming.name || "").trim();
      const duplicate = data.profiles.some(function (p) {
        return p.id !== incoming.id && p.name.trim().toLowerCase() === name.toLowerCase();
      });
      if (!name) {
        ok = false;
        message = "配置名不能为空";
      } else if (duplicate) {
        ok = false;
        message = "配置名重复：" + name;
      } else {
        const index = data.profiles.findIndex(function (p) { return p.id === incoming.id; });
        const copy = structuredClone(incoming);
        copy.name = name;
        copy.updatedAt = nowISO();
        if (index >= 0) {
          copy.active = data.profiles[index].active;
          data.profiles[index] = copy;
        } else {
          copy.id = "p" + Date.now().toString(36);
          copy.active = false;
          data.profiles.push(copy);
        }
        message = "配置已保存";
      }
    } else if (action === "delete-profile" && payload) {
      data.profiles = data.profiles.filter(function (p) { return p.id !== payload.id; });
      if (data.activeId === payload.id) { data.activeId = ""; data.appliedKeys = []; }
      message = "配置已删除";
    } else if (action === "save-settings" && payload) {
      if (payload.check) data.settings.check = payload.check;
      message = "设置已保存";
    } else if (action === "set-autostart" && payload) {
      data.autostart.enabled = Boolean(payload.enabled);
      message = payload.enabled ? "已开启开机启动" : "已关闭开机启动";
    } else if (action === "shell-install") {
      data.shell.installed = true;
      message = "Shell 集成已安装";
    } else if (action === "shell-uninstall") {
      data.shell.installed = false;
      message = "Shell 集成已移除";
    } else if (action === "set-mcp" && payload) {
      data.mcp.enabled = Boolean(payload.enabled);
      data.mcp.allowReveal = Boolean(payload.allowReveal);
      message = "MCP 设置已更新";
    } else if (action === "update-check") {
      data.settings.lastCheckAt = nowISO();
      data.settings.lastResult = "up-to-date";
      message = "已是最新版本";
    } else if (action === "update-download") {
      message = "演示模式下不下载安装包";
      ok = false;
    } else if (action === "update-install") {
      message = "演示模式下不执行安装";
      ok = false;
    } else if (action === "export") {
      message = "演示模式下不生成导出文件";
      ok = false;
    } else if (action) {
      message = "演示模式不支持：" + action;
      ok = false;
    }

    return { ok: ok, message: message, state: structuredClone(this.data) };
  }
}
