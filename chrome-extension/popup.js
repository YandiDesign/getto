// Popup Getto: kirim tab, daftar media, tempel manual, pengaturan, salin ID.
const toastEl = document.getElementById("toast");
let toastTimer = null;
let gettoEnabled = true;

function toast(msg, kind) {
  toastEl.textContent = msg;
  toastEl.className = "show" + (kind ? " " + kind : "");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { toastEl.className = ""; }, 3500);
}

function guardEnabled() {
  if (!gettoEnabled) {
    toast("Getto nonaktif — nyalakan dulu untuk mengirim.", "err");
    return false;
  }
  return true;
}

// ---------- master switch ----------
const enabledChk = document.getElementById("enabledChk");
chrome.storage.sync.get({ gettoEnabled: true }, (cfg) => {
  gettoEnabled = cfg.gettoEnabled !== false;
  enabledChk.checked = gettoEnabled;
});
enabledChk.onchange = () => {
  gettoEnabled = enabledChk.checked;
  chrome.storage.sync.set({ gettoEnabled }, () => {
    toast(gettoEnabled ? "Getto aktif ✓" : "Getto nonaktif — Chrome download manual", "ok");
  });
};

// ---------- kirim tab aktif ----------
document.getElementById("sendTabBtn").onclick = () => {
  if (!guardEnabled()) return;
  chrome.runtime.sendMessage({ type: "send-tab" }, (r) => {
    if (chrome.runtime.lastError) { toast("Gagal: " + chrome.runtime.lastError.message, "err"); return; }
    if (r && r.fallback) { toast("Terkirim via cadangan — perbaiki koneksi native.", "err"); return; }
    const extra = r && r.cookiesSent ? " + cookies ✓" : "";
    toast(r && r.ok ? "Terkirim ke Getto ✓" + extra : "Gagal: " + ((r && (r.message || r.error)) || "?"), r && r.ok ? "ok" : "err");
  });
};

// ---------- status koneksi saat dibuka ----------
chrome.runtime.sendMessage({ type: "ping-host" }, (r) => {
  if (chrome.runtime.lastError || !r || !r.ok) {
    toast("Getto belum terhubung — pengiriman lewat cadangan.", "err");
  }
});

// ---------- daftar media ----------
function extOf(u) {
  try {
    const p = new URL(u).pathname.split("/").pop() || "";
    const m = p.match(/\.([a-z0-9]{2,5})$/i);
    return m ? m[1].toUpperCase() : "";
  } catch { return ""; }
}
function hostOf(u) {
  try { return new URL(u).hostname.replace(/^www\./, ""); } catch { return ""; }
}
function fileNameOf(u) {
  try {
    const p = decodeURIComponent(new URL(u).pathname.split("/").pop() || "");
    return p || u.slice(0, 48);
  } catch { return u.slice(0, 48); }
}

function sendUrl(u) {
  if (!guardEnabled()) return;
  chrome.runtime.sendMessage({ type: "send-url", url: u }, (r) => {
    if (chrome.runtime.lastError) { toast("Gagal: " + chrome.runtime.lastError.message, "err"); return; }
    if (r && r.fallback) { toast("Terkirim via cadangan — perbaiki koneksi native.", "err"); return; }
    const extra = r && r.cookiesSent ? " + cookies ✓" : "";
    toast(r && r.ok ? "Terkirim ke Getto ✓" + extra : "Gagal: " + ((r && (r.message || r.error)) || "?"), r && r.ok ? "ok" : "err");
  });
}

function renderMedia(list) {
  const box = document.getElementById("mediaList");
  document.getElementById("mediaCount").textContent = list.length;
  box.innerHTML = "";
  if (!list.length) {
    const d = document.createElement("div");
    d.className = "empty";
    d.textContent = "Tidak ada media terdeteksi di halaman ini.";
    box.appendChild(d);
    return;
  }
  list.slice(0, 10).forEach((item, i) => {
    const u = typeof item === "string" ? item : item.url;
    const poster = (item && item.poster) || "";
    const kind = (item && item.kind) || (/(\.mp4|\.webm|\.mov|\.mkv|\.m3u8)($|[?#])/i.test(u) ? "video" : "file");
    const row = document.createElement("div");
    row.className = "mrow";
    const tw = document.createElement("div");
    tw.className = "thumbwrap";
    if (poster) {
      const img = document.createElement("img");
      img.className = "thumb";
      img.src = poster;
      img.onerror = () => { img.replaceWith(iconBox(kind)); };
      tw.appendChild(img);
    } else {
      tw.appendChild(iconBox(kind));
    }
    if (kind === "video") {
      const pb = document.createElement("span");
      pb.className = "playbadge";
      pb.textContent = "▶";
      tw.appendChild(pb);
    }
    const info = document.createElement("div");
    info.className = "minfo";
    const t = document.createElement("b");
    t.textContent = (item && item.title) || fileNameOf(u);
    t.title = u;
    const meta = document.createElement("span");
    const ext = extOf(u) || (kind === "video" ? "VIDEO" : "FILE");
    meta.textContent = ext + (hostOf(u) ? " • " + hostOf(u) : "");
    info.appendChild(t);
    info.appendChild(meta);
    const btn = document.createElement("button");
    btn.className = "btn " + (i === 0 ? "btn-primary" : "btn-outline");
    btn.innerHTML = "⬇ Unduh";
    btn.onclick = () => sendUrl(u);
    row.appendChild(tw);
    row.appendChild(info);
    row.appendChild(btn);
    box.appendChild(row);
  });
}

function iconBox(kind) {
  const d = document.createElement("div");
  d.className = "thumbicon";
  d.textContent = kind === "video" ? "🎬" : (kind === "image" ? "🖼" : "📄");
  return d;
}

chrome.tabs.query({ active: true, lastFocusedWindow: true }, (tabs) => {
  const id = tabs && tabs[0] && tabs[0].id;
  if (!id) { renderMedia([]); return; }
  chrome.tabs.sendMessage(id, { type: "list-media" }, (list) => {
    if (chrome.runtime.lastError || !list) { renderMedia([]); return; }
    renderMedia(list);
  });
});

// ---------- ciutkan daftar ----------
document.getElementById("collapseBtn").onclick = (e) => {
  const box = document.getElementById("mediaList");
  box.classList.toggle("hidden");
  e.currentTarget.textContent = box.classList.contains("hidden") ? "▸" : "▾";
};

// ---------- tempel manual: buka sheet tanpa dialog bila app berjalan ----------
// (Sheet otomatis mengisi dari clipboard; app yang membacanya.)
document.getElementById("pasteBtn").onclick = () => {
  if (!guardEnabled()) return;
  chrome.runtime.sendMessage({ type: "open-sheet" }, (r) => {
    if (chrome.runtime.lastError || !r || !r.ok) {
      toast("Gagal membuka Getto", "err");
    } else if (!r.fallback) {
      toast("Membuka Getto…", "ok");
    }
  });
};

// ---------- pengaturan (gear) ----------
const settingsCard = document.getElementById("settingsCard");
const takeoverChk = document.getElementById("takeoverChk");
document.getElementById("gearBtn").onclick = () => {
  settingsCard.classList.toggle("open");
};
chrome.storage.sync.get({ takeover: true }, (cfg) => {
  takeoverChk.checked = cfg.takeover !== false;
});
takeoverChk.onchange = () => {
  chrome.storage.sync.set({ takeover: takeoverChk.checked }, () => {
    toast(takeoverChk.checked ? "Pengambilalihan aktif ✓" : "Pengambilalihan mati", "ok");
  });
};

// ---------- salin ID ekstensi (pin) ----------
document.getElementById("copyIdBtn").onclick = async () => {
  const id = chrome.runtime.id || "";
  try {
    await navigator.clipboard.writeText(id);
    toast("ID tersalin — tempel di Getto → Browser ✓", "ok");
  } catch {
    toast("ID: " + id, "");
  }
};

// ---------- log diagnosis ----------
const logCard = document.getElementById("logCard");
const logPre = document.getElementById("logPre");
document.getElementById("logBtn").onclick = () => {
  const open = logCard.classList.toggle("open");
  if (open) refreshLog();
};
document.getElementById("copyLogBtn").onclick = async () => {
  try {
    await navigator.clipboard.writeText(logPre.textContent || "");
    toast("Log tersalin ✓", "ok");
  } catch {
    toast("Gagal menyalin log", "err");
  }
};
document.getElementById("clearLogBtn").onclick = () => {
  chrome.runtime.sendMessage({ type: "clear-log" }, () => refreshLog());
};
function refreshLog() {
  logPre.textContent = "Memuat…";
  chrome.runtime.sendMessage({ type: "get-log" }, (r) => {
    if (chrome.runtime.lastError || !r || !r.ok) {
      logPre.textContent = "Log tidak tersedia: " + ((r && r.error) || (chrome.runtime.lastError || {}).message || "?");
      return;
    }
    const list = r.log || [];
    logPre.textContent = list.length
      ? list.map((e) => `${e.t || ""} [${e.type || ""}] ${e.detail || ""}`).join("\n")
      : "(belum ada kejadian — coba kirim link lalu buka lagi)";
  });
}
