// Content script: hanya deteksi media untuk popup (tanpa tombol melayang agar tidak mengganggu tampilan web).
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg?.type === "list-media") {
    const seen = new Set();
    const out = [];
    const push = (url, poster, title, kind) => {
      if (!url || seen.has(url)) return;
      seen.add(url);
      out.push({ url, poster: poster || "", title: title || "", kind });
    };
    document.querySelectorAll("video").forEach((v) => {
      const src = v.currentSrc || v.src || (v.querySelector("source") || {}).src || "";
      if (src) push(src, v.poster || "", document.title || "", "video");
    });
    document.querySelectorAll("img").forEach((img) => {
      const src = img.currentSrc || img.src || "";
      if (src && (img.naturalWidth || 0) >= 120)
        push(src, src, img.alt || document.title || "", "image");
    });
    document.querySelectorAll("a[href]").forEach((el) => {
      const u = el.href || "";
      if (/(\.mp4|\.webm|\.mov|\.mkv|\.mp3|\.zip|\.pdf|\.dmg|\.pkg|\.iso)($|[?#])/i.test(u))
        push(u, "", (el.textContent || "").trim().slice(0, 80) || document.title || "", "file");
    });
    push(location.href, "", document.title || "", "video");
    sendResponse(out.slice(0, 20));
  }
});
