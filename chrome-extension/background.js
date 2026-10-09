// Service worker: context menu, takeover downloads, Native Messaging + fallback URL scheme.
const HOST = "com.getto.host";
const TAKEOVER_EXTS = ["zip", "dmg", "pkg", "iso", "mp4", "mkv", "webm"];
const TAKEOVER_MIN_BYTES = 50 * 1024 * 1024;
const LOG_KEY = "getto.log";
const LOG_MAX = 120;

// ---------- log ringkas (untuk diagnosis, bisa disalin dari popup) ----------
async function logEvent(type, detail) {
  try {
    const entry = { t: new Date().toISOString(), type, detail: String(detail || "").slice(0, 300) };
    const cfg = await chrome.storage.local.get({ [LOG_KEY]: [] }).catch(() => ({}));
    const list = cfg[LOG_KEY] || [];
    list.push(entry);
    while (list.length > LOG_MAX) list.shift();
    await chrome.storage.local.set({ [LOG_KEY]: list }).catch(() => {});
  } catch {}
}

// ---------- kirim native messaging yang aman di konteks apa pun ----------
// (di content script / worker tertentu API bisa tidak ada → jangan TypeError,
// kembalikan error terstruktur agar fallback berjalan rapi)
function nativeSend(message) {
  try {
    if (chrome.runtime && typeof chrome.runtime.sendNativeMessage === "function") {
      return chrome.runtime.sendNativeMessage(HOST, message);
    }
  } catch (e) {
    return Promise.reject(e);
  }
  return Promise.reject(new Error("native messaging tidak tersedia di konteks ini"));
}

// ---------- jalur HTTP lokal (tanpa dialog, tanpa manifest) ----------
// App mendengarkan di 127.0.0.1:17842 bila sedang berjalan.
const LOCAL_HTTP = "http://127.0.0.1:17842";

async function httpSend(path, payload) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 8000);
  try {
    const res = await fetch(LOCAL_HTTP + path, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload || {}),
      signal: ctrl.signal
    });
    if (!res.ok) throw new Error("http " + res.status);
    return await res.json();
  } finally {
    clearTimeout(timer);
  }
}

async function httpPing() {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 4000);
  try {
    const res = await fetch(LOCAL_HTTP + "/ping", { signal: ctrl.signal });
    if (!res.ok) throw new Error("http " + res.status);
    return await res.json();
  } finally {
    clearTimeout(timer);
  }
}

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({ id: "getto-link", title: "Download dengan Getto", contexts: ["link"] });
  chrome.contextMenus.create({ id: "getto-page", title: "Kirim halaman ini ke Getto", contexts: ["page", "video"] });
});

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  const url = info.linkUrl || info.pageUrl;
  if (url) await sendToGetto(url, tab);
});

async function getCookies(url) {
  try {
    const list = await chrome.cookies.getAll({ url });
    return list.map(c => `${c.name}=${c.value}`).join("; ");
  } catch { return ""; }
}

// ---------- profil browser nyata (WAJIB menyertai cookie) ----------
// Cookie sesi situs (terutama `cf_clearance` Cloudflare) hanya sah bila
// request berikutnya memakai User-Agent + client hint yang SAMA dengan browser
// yang menerbitkannya. Kalau aria2 memakai UA generik, situs membalas
// "access denied" walau cookie sudah benar. Jadi kirim UA asli.
async function browserProfile() {
  const nav = (typeof navigator !== "undefined") ? navigator : {};
  const ua = nav.userAgent || "";
  const langs = (nav.languages && nav.languages.length ? nav.languages : [nav.language || "en"])
    .slice(0, 3).join(",");
  const hints = {};
  const uad = nav.userAgentData;
  if (uad && uad.brands && uad.brands.length) {
    hints["Sec-CH-UA"] = uad.brands
      .map((b) => `"${b.brand}";v="${b.version}"`).join(", ");
    hints["Sec-CH-UA-Mobile"] = uad.mobile ? "?1" : "?0";
    if (uad.platform) hints["Sec-CH-UA-Platform"] = `"${uad.platform}"`;
  }
  return {
    userAgent: ua,
    accept: "*/*",
    acceptLanguage: langs,
    hints: hints
  };
}

async function sendToGetto(url, tab) {
  const enabled = await chrome.storage.sync.get({ gettoEnabled: true })
    .then((c) => c.gettoEnabled !== false).catch(() => true);
  if (!enabled) return { ok: false, message: "Getto nonaktif" };
  const [cookies, profile] = await Promise.all([
    getCookies(url).catch(() => ""),
    browserProfile().catch(() => ({}))
  ]);
  const payload = { action: "add", url, cookies, referer: tab?.url || "", profile };
  const idInfo = cookies ? " [+cookies+ua]" : " [+ua]";
  // 1) Native messaging (bisa membangunkan app yang tutup).
  try {
    const resp = await nativeSend(payload);
    if (!resp || resp.ok === false) throw new Error(resp?.message || "native host gagal");
    logEvent("native-ok", url + idInfo);
    return { ...resp, transport: "native", cookiesSent: !!cookies };
  } catch (e) {
    logEvent("native-error", String((e && e.message) || e));
  }
  // 2) HTTP lokal (tanpa dialog, tanpa manifest — app harus berjalan).
  try {
    const resp = await httpSend("/add", payload);
    if (!resp || resp.ok === false) throw new Error(resp?.message || "http gagal");
    logEvent("http-ok", url + idInfo);
    return { ...resp, transport: "http", cookiesSent: !!cookies };
  } catch (e) {
    logEvent("http-error", String((e && e.message) || e));
  }
  // 3) Cadangan terakhir: URL scheme (selalu memicu dialog "open with" —
  // itu keamanan browser, tidak bisa dimatikan dari kode).
  await chrome.tabs.create({ url: "getto://add?url=" + encodeURIComponent(url) });
  logEvent("fallback-used", url);
  return { ok: true, fallback: true, transport: "scheme" };
}

// Alihkan unduhan Chrome besar / ekstensi tertentu ke Getto.
chrome.downloads.onCreated.addListener(async (item) => {
  const cfg = await chrome.storage.sync.get({ takeover: true, gettoEnabled: true, minBytes: TAKEOVER_MIN_BYTES });
  if (cfg.gettoEnabled === false) return; // Getto dimatikan: biarkan Chrome download manual
  if (!cfg.takeover || !item.url || item.url.startsWith("blob:")) return;
  const ext = (item.filename?.split(".").pop() || "").toLowerCase();
  const big = (item.fileSize || 0) >= (cfg.minBytes || TAKEOVER_MIN_BYTES);
  if (TAKEOVER_EXTS.includes(ext) || big) {
    logEvent("takeover", (item.filename || "") + " <- " + item.url);
    try {
      await chrome.downloads.cancel(item.id);
      await chrome.downloads.erase({ id: item.id });
    } catch {}
    const tabs = await chrome.tabs.query({ active: true, lastFocusedWindow: true }).catch(() => []);
    await sendToGetto(item.url, tabs[0]);
  }
});

// Dipanggil popup.js: kirim tab aktif / URL tertentu + cek status koneksi.
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg?.type === "send-tab") {
    chrome.tabs.query({ active: true, lastFocusedWindow: true }).then(async (tabs) => {
      const r = await sendToGetto(tabs[0]?.url || "", tabs[0]);
      sendResponse(r);
    });
    return true;
  }
  if (msg?.type === "send-url" && msg.url) {
    chrome.tabs.query({ active: true, lastFocusedWindow: true }).then(async (tabs) => {
      const r = await sendToGetto(msg.url, tabs[0]);
      sendResponse(r);
    });
    return true;
  }
  if (msg?.type === "ping-host") {
    // Coba native dulu, lalu HTTP lokal. Laporkan transport yang berhasil.
    nativeSend({ action: "ping" }).then(
      (r) => { logEvent("ping-ok", "native"); sendResponse({ ok: true, transport: "native", r }); },
      async () => {
        try {
          const r = await httpPing();
          logEvent("ping-ok", "http");
          sendResponse({ ok: true, transport: "http", r });
        } catch (e) {
          const err = String((e && e.message) || e);
          logEvent("ping-error", err);
          sendResponse({ ok: false, error: err });
        }
      }
    );
    return true;
  }
  if (msg?.type === "open-sheet") {
    // Buka sheet Tambah tanpa dialog: via HTTP bila app berjalan.
    httpSend("/open-sheet", {}).then(
      () => sendResponse({ ok: true, transport: "http" }),
      async () => {
        await chrome.tabs.create({ url: "getto://add" });
        logEvent("fallback-used", "open-sheet");
        sendResponse({ ok: true, fallback: true, transport: "scheme" });
      }
    );
    return true;
  }
  if (msg?.type === "get-log") {
    chrome.storage.local.get({ [LOG_KEY]: [] }).then(
      (cfg) => sendResponse({ ok: true, log: cfg[LOG_KEY] || [] }),
      (e) => sendResponse({ ok: false, error: String(e) })
    );
    return true;
  }
  if (msg?.type === "clear-log") {
    chrome.storage.local.set({ [LOG_KEY]: [] }).then(
      () => sendResponse({ ok: true }),
      (e) => sendResponse({ ok: false, error: String(e) })
    );
    return true;
  }
});
