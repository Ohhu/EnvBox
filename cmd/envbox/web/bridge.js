// Transport layer: one frontend, three hosts.
//   native  — macOS WKWebView, messages answered by WebUIBridge.swift
//   http    — Windows Wails v3 (/api/state, /api/dispatch)
//   demo    — no backend, in-memory data for previews and screenshots
//
// The native host replies by calling window.__envboxReply(id, jsonString).

import { DemoBackend } from "./mock.js";

const params = new URLSearchParams(location.search);
const forcedDemo = params.get("demo") === "1";
const pending = new Map();
let seq = 0;

window.__envboxReply = function (id, body) {
  const entry = pending.get(id);
  if (!entry) return;
  pending.delete(id);
  try {
    entry.resolve(typeof body === "string" ? JSON.parse(body) : body);
  } catch (error) {
    entry.reject(new Error("原生桥返回的不是合法 JSON"));
  }
};

function nativeHandler() {
  return window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.envbox;
}

function postNative(message) {
  return new Promise(function (resolve, reject) {
    const id = "m" + ++seq;
    pending.set(id, { resolve: resolve, reject: reject });
    message.id = id;
    nativeHandler().postMessage(message);
    setTimeout(function () {
      if (!pending.has(id)) return;
      pending.delete(id);
      reject(new Error("原生桥没有响应"));
    }, 30000);
  });
}

async function httpState() {
  const response = await fetch("/api/state");
  const payload = await response.json();
  if (!payload || payload.ok === false) throw new Error((payload && payload.message) || "读取状态失败");
  return payload.state || payload;
}

async function httpDispatch(action, payload) {
  const response = await fetch("/api/dispatch", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ action: action, payload: payload ? JSON.stringify(payload) : "" })
  });
  return response.json();
}

let backend = null;

async function resolveBackend() {
  if (backend) return backend;
  if (forcedDemo) {
    backend = new DemoBackend();
    return backend;
  }
  if (nativeHandler()) {
    backend = {
      kind: "native",
      state: function () {
        return postNative({ kind: "state" }).then(function (envelope) {
          if (envelope && envelope.ok === false) throw new Error(envelope.message || "读取状态失败");
          return envelope && envelope.state ? envelope.state : envelope;
        });
      },
      dispatch: function (action, payload) {
        return postNative({ kind: "dispatch", action: action, payload: payload ? JSON.stringify(payload) : "" });
      }
    };
    return backend;
  }
  try {
    await httpState();
    backend = { kind: "http", state: httpState, dispatch: httpDispatch };
  } catch (error) {
    // Plain browser preview without a running Wails host.
    backend = new DemoBackend();
  }
  return backend;
}

export const bridge = {
  async kind() {
    return (await resolveBackend()).kind;
  },
  async state() {
    return (await resolveBackend()).state();
  },
  async dispatch(action, payload) {
    return (await resolveBackend()).dispatch(action, payload);
  }
};
