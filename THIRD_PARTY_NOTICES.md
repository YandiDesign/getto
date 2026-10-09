# Notices Lisensi Party Ketiga

Getto sendiri berlisensi **MIT** (lihat [LICENSE](LICENSE)). Dokumen ini
menginventarisasi **binary pendukung** yang di-bundle di dalam `Getto.app` saat
distribusi, beserta lisensinya dan ketentuan dissemination masing-masing.

> **Binary pendukung TIDAK disimpan di repository ini.** Repo hanya berisi
> source. `scripts/fetch-binaries.sh` yang mengunduhnya (~230 MB) — terlalu
> besar untuk git dan bukan bagian dari source.

---

## 1. Inventaris komponen

Status di bawah diverifikasi langsung dari binary hasil unduhan
(`ffmpeg -version`, `aria2c --version`, dan string konfigurasi di dalam file).

| Komponen | Versi | Sumber | Lisensi | Salinan GPL? |
|---|---|---|---|---|
| yt-dlp | 2026.08.19 | github.com/yt-dlp/yt-dlp (PyInstaller, universal) | **Unlicense** (domain publik) | Tidak |
| ffmpeg (x86_64) | 6.1 "tessus" | evermeet.cx (`--enable-gpl --enable-version3`) | **GPL-2.0-or-later** | **Ya** |
| ffmpeg (arm64) | 8.0 | osxexperts.net (`--enable-gpl`) | **GPL-2.0-or-later** | **Ya** |
| aria2c + libaria2 | 1.37.0 | conda-forge (`osx-64`, `osx-arm64`) | **GPL-2.0-or-later** | **Ya** |
| libcrypto.3 / libssl.3 | OpenSSL 3.x | conda-forge | **Apache-2.0** | Tidak |
| libxml2 | 2.15.2+ | conda-forge | **MIT** | Tidak |
| libssh2 | 1.11.1 | conda-forge | **BSD-3-Clause** | Tidak |
| c-ares | 1.34.6 | conda-forge | **MIT** | Tidak |
| GMP | 6.3.0 | conda-forge | **LGPL-3.0-or-later** | Tidak |
| zlib | 1.3.2 | conda-forge | **Zlib** | Tidak |
| sqlite3 | 3.53.0 | conda-forge / sistem | **Public Domain** | Tidak |
| libc++ | — | conda-forge | **Apache-2.0 WITH LLVM-exception** | Tidak |

### Bukti verifikasi

```
$ Getto/Resources/bin/x86_64/ffmpeg -version | grep configuration
configuration: ... --enable-gpl ... --enable-version3 --pkg-config-flags=--static

$ strings Getto/Resources/bin/arm64/ffmpeg | grep -o '\-\-enable-gpl'
--enable-gpl

$ Getto/Resources/bin/x86_64/aria2c --version
This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.
```

---

## 2. Mengapa kode Getto tetap boleh MIT

Getto **tidak meng-link** pustaka GPL. `aria2c`, `ffmpeg`, dan `yt-dlp`
dijalankan sebagai **proses terpisah** (subprocess) dan berkomunikasi lewat
stdin/stdout/argumen baris perintah. Secara lisensi GPL ini disebut *mere
aggregation* — GPL tidak berlaku ke kode Getto.

> **Batasnya:** selama pemanggilan tetap lewat **proses terpisah + CLI**.
> Kalau suatu saat Getto meng-*link* `libaria2` atau `libav*` sebagai
> pustaka statis/dinamis di dalam binary Getto, Getto **wajib** menjadi
> GPL-2.0-or-later. Aturan ini berlaku untuk Getto maupun fork apa pun.

---

## 3. Kewajiban GPL yang sudah dipenuhi

Mendistribusikan binary GPL berarti wajib:

1. **Menyertakan teks lisensi** — ada di `Getto/Resources/licenses/`, otomatis
   ikut ke dalam `.app` sebagai resource bundle.
2. **Menyertakan Corresponding Source** — lihat §4.
3. **Menyatakan perubahan** — Getto tidak mempatch binary mana pun; binary
   dipakai apa adanya. Tidak ada modifikasi yang perlu disclose.

### Teks lisensi yang disertakan

| File | Lisensi |
|---|---|
| `Getto/Resources/licenses/GPL-2.0.txt` | GNU GPL v2 (aria2, ffmpeg) |
| `Getto/Resources/licenses/GPL-3.0.txt` | GNU GPL v3 (ffmpeg Intel punya `--enable-version3`) |
| `Getto/Resources/licenses/LGPL-2.1.txt` | LGPL v2.1+ (pustaka bawaan ffmpeg) |
| `Getto/Resources/licenses/LGPL-3.0.txt` | LGPL v3 (GMP) |
| `Getto/Resources/licenses/Apache-2.0.txt` | Apache 2.0 (OpenSSL, libc++) |
| `Getto/Resources/licenses/Unlicense.txt` | yt-dlp |

---

## 4. Corresponding Source (pemenuhan GPL-2 §3)

Karena Getto memakai **build statis pihak ketiga tanpa patch**, Corresponding
Source = source upstream persis pada versi yang dipakai + konfigurasi build
(yang sudah tercantum di atas). Semuanya tersedia bebas di server upstream:

| Komponen | Corresponding Source |
|---|---|
| aria2 1.37.0 | https://github.com/aria2/aria2/releases/tag/release-1.37.0 |
| ffmpeg 6.1 (x86_64) | https://ffmpeg.org/releases/ffmpeg-6.1.tar.xz + flag `configuration` di atas |
| ffmpeg 8.0 (arm64) | https://ffmpeg.org/releases/ (tag 8.0) + flag `configuration` di atas |
| yt-dlp 2026.08.19 | https://github.com/yt-dlp/yt-dlp/tree/2026.08.19 |
| libaria2 + dylib lain | source package conda-forge, channel `conda-forge`, subdir `osx-64` / `osx-arm64` |

**Tidak ada patch** yang diterapkan Getto ke binary mana pun. Selain menautkan
sumber di atas, rilis binary Getto harus menyertakan file ini
(`THIRD_PARTY_NOTICES.md` + folder `licenses/`) di dalam DMG.

---

## 5. Lisensi kode Getto sendiri

Tidak ada kode yang disalin dari proyek pihak ketiga. Seluruh
`Getto/**/*.swift` dan `chrome-extension/*.js` ditulis orisinal — tidak ada
header lisensi pihak ketiga yang perlu diatribusikan.

- **yt-dlp** dipanggil sebagai executable (`yt-dlp --dump-json ...`), bukan
  lewat import Python — tidak ada kode Python yang ikut.
- **aria2** dipanggil lewat JSON-RPC ke `aria2c` — tidak ada libtorrent.

---

## 6. Ekstensi Chrome

Kode ekstensi (`chrome-extension/`) ikut berlisensi MIT. Key publik di
`manifest.json` (`"key"`) sengaja dipublikasikan agar ID ekstensi
`0n9n3m074864m7mlo9n519nll233ok3l` tetap stabil. **Private key-nya
(`getto-extension-key.pem`) tidak boleh di-commit** dan sudah masuk
`.gitignore`.

---

## 7. Merek & aset

Nama "Getto", logo, dan ikon aplikasi milik penulis proyek dan tidak
diberikan lisensi lewat lisensi MIT.