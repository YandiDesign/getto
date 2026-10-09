# Prompt: Getto — Download Manager Native untuk macOS

## 1. Peran

Kamu adalah senior macOS engineer sekaligus desainer UI yang berpengalaman dengan Swift, SwiftUI, AppKit, dan Human Interface Guidelines Apple. Tugasmu adalah membangun aplikasi **Getto** dari nol sampai bisa di-build, dijalankan, dan dibagikan sebagai file `.dmg`.

Sebelum menulis kode, buat rencana singkat (struktur proyek, pilihan library, urutan fase). Setelah itu kerjakan fase demi fase dan pastikan tiap fase bisa di-build tanpa error sebelum lanjut.

---

## 2. Ringkasan Produk

**Getto** adalah download manager native macOS yang:

- Mengunduh file dari internet cukup dengan menempel (paste) link.
- Mengunduh video/audio dari YouTube, TikTok, Instagram, X/Twitter, Facebook, Vimeo, dan ribuan situs lain.
- Mendukung torrent (file `.torrent` dan magnet link).
- Datang bersama ekstensi Chrome yang bisa mengirim link atau video langsung ke Getto.
- Tampil dan terasa seperti aplikasi bawaan Apple.

---

## 3. Target Platform dan Batasan Teknis

| Item | Ketentuan |
|---|---|
| Nama aplikasi | **Getto** |
| Bundle ID | `com.getto.app` |
| Arsitektur | **Intel (x86_64)** sebagai target utama. Boleh dibuat universal (x86_64 + arm64) jika tidak menambah kerumitan, tapi Intel wajib jalan sempurna |
| Minimum OS | **macOS 13 Ventura** (`MACOSX_DEPLOYMENT_TARGET = 13.0`) |
| Bahasa | Swift 5.9+ |
| UI | SwiftUI sebagai utama, AppKit hanya untuk hal yang belum didukung SwiftUI di macOS 13 |
| Build | Xcode 15+, bisa di-build lewat `xcodebuild` dari terminal |
| Sandbox | Nonaktif (App Sandbox off) supaya bisa menjalankan binary pendukung dan menulis ke folder pilihan pengguna. Gunakan Hardened Runtime |

**Perhatian kompatibilitas macOS 13** (jangan pakai API yang baru ada di macOS 14+):

- Jangan pakai macro `@Observable`, gunakan `ObservableObject` + `@Published` / `@StateObject`.
- Jangan pakai `SwiftData`, gunakan JSON/`Codable` di Application Support atau Core Data.
- Jangan pakai `.containerBackground`, `ContentUnavailableView`, atau `Inspector`.
- Yang boleh dipakai di macOS 13: `NavigationSplitView`, `Table`, `MenuBarExtra`, `Grid`, `ShareLink`, `.searchable`, `.swipeActions`.
- Gunakan `#available` bila memakai fitur opsional dari OS yang lebih baru.

---

## 4. Fitur Utama

### 4.1 Download Link Langsung (HTTP/HTTPS/FTP)

- Kolom tempel link: tombol **+** di toolbar dan shortcut `⌘N` membuka sheet "Tambah Unduhan".
- Otomatis membaca isi clipboard saat sheet dibuka. Jika berisi URL, langsung isi kolom.
- Mendukung banyak link sekaligus (satu link per baris).
- Mengambil nama file, ukuran, dan tipe dari header server sebelum mulai.
- Download multi-koneksi per file (default 8 segmen, bisa diatur 1–16) agar cepat.
- Pause, resume, cancel, retry otomatis, dan lanjut setelah aplikasi ditutup/dibuka lagi.
- Antrean (queue) dengan batas unduhan bersamaan (default 3).
- Batas kecepatan unduh (global) opsional.
- Dukungan header kustom, cookie, dan basic auth untuk link yang butuh login (opsional, di bagian "Lanjutan").
- Deteksi duplikat dan pilihan: timpa, ganti nama, atau lewati.

### 4.2 Download Video dan Audio (YouTube, TikTok, dll.)

- Gunakan **yt-dlp** sebagai mesin ekstraksi (binary standalone yang dibundel di dalam `.app`, tanpa perlu Python di mesin pengguna).
- Gunakan **ffmpeg** (build x86_64 statis, dibundel) untuk menggabungkan video+audio, konversi ke MP3/M4A, dan embed thumbnail/metadata.
- Saat link video ditempel, tampilkan **pratinjau**: thumbnail, judul, durasi, nama kanal.
- Pilihan kualitas dan format: resolusi (Best, 2160p, 1440p, 1080p, 720p, 480p, 360p), format video (MP4/MKV/WEBM), atau **audio saja** (MP3, M4A, OPUS, FLAC).
- Dukungan **playlist** dan kanal: pilih video mana saja yang ingin diunduh, atau unduh semua.
- Dukungan subtitle (pilih bahasa, embed atau file terpisah `.srt`).
- Untuk TikTok: unduh tanpa watermark bila tersedia dari ekstraktor.
- Fitur "Perbarui mesin" di Pengaturan untuk memperbarui yt-dlp tanpa harus update seluruh aplikasi, karena situs sering berubah.
- Tampilkan progres, kecepatan, ETA, dan fase (mengunduh → menggabungkan → selesai).

### 4.3 Torrent

- Mendukung file `.torrent` (drag & drop, buka dari Finder, atau lewat dialog) dan **magnet link**.
- Daftarkan Getto sebagai handler untuk skema `magnet:` dan tipe file `.torrent` (opsional, lewat toggle di Pengaturan).
- Saat torrent ditambahkan, tampilkan daftar file di dalamnya dengan checkbox agar pengguna bisa memilih file yang diunduh.
- Informasi per torrent: progres, kecepatan unduh/unggah, jumlah seeds/peers, rasio share, ETA.
- Kontrol: pause, resume, hapus (dengan opsi hapus file juga), force recheck.
- Pengaturan torrent: port masuk, batas upload/download, DHT, PEX, enkripsi, batas rasio seeding.
- **Rekomendasi mesin:** gunakan `aria2c` (build x86_64, dibundel) yang dikendalikan lewat JSON-RPC, karena satu binary bisa menangani HTTP multi-koneksi, FTP, dan BitTorrent/magnet sekaligus. Alternatif: `libtorrent-rasterbar` dengan wrapper Swift/C++. Pilih satu, jelaskan alasannya di rencana, dan pastikan bisa berjalan di Intel macOS 13.

### 4.4 Ekstensi Chrome

Buat folder `chrome-extension/` berisi ekstensi **Manifest V3** yang berkomunikasi dengan Getto.

Fitur ekstensi:

- Klik kanan pada link → **"Download dengan Getto"**.
- Klik kanan pada halaman/video → **"Kirim halaman ini ke Getto"**.
- Popup ekstensi: tombol "Kirim tab ini ke Getto", daftar video/media yang terdeteksi di halaman, dan status koneksi ke aplikasi.
- Ikon/tombol mengambang kecil di atas video YouTube/TikTok (opsional, bisa dimatikan).
- Opsi untuk mengambil alih unduhan Chrome (`chrome.downloads`) untuk file di atas ukuran tertentu atau ekstensi tertentu (zip, dmg, pkg, iso, mp4, dll.), dengan daftar pengecualian.
- Kirim juga cookie dan referer situs bila diperlukan agar link yang butuh login tetap bisa diunduh (dengan izin eksplisit dari pengguna).

Cara komunikasi (implementasikan keduanya):

1. **Native Messaging** (utama): sertakan native host kecil (binary Swift atau skrip) di dalam bundle aplikasi, dan buat manifest `com.getto.host.json`. Getto membuat/menulis manifest itu ke `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/` secara otomatis saat pertama dijalankan atau lewat tombol "Pasang integrasi Chrome" di Pengaturan. Dukung juga Chromium, Brave, dan Edge dengan path masing-masing.
2. **URL scheme** (cadangan): `getto://add?url=<encoded-url>` agar tetap berfungsi bila native messaging tidak tersedia.

Di Pengaturan Getto sediakan bagian **"Integrasi Browser"** yang menampilkan: status ekstensi, tombol "Pasang integrasi", tombol "Buka folder ekstensi", dan petunjuk memasang ekstensi lewat `chrome://extensions` → Developer mode → Load unpacked. Jelaskan di README bahwa ID ekstensi perlu dimasukkan ke `allowed_origins` pada manifest native host, dan buat ID yang stabil dengan menyertakan `key` di `manifest.json` ekstensi.

---

## 5. Desain dan Gaya macOS

Aplikasi harus terlihat **native dan khas macOS**, bukan seperti aplikasi web atau port dari platform lain.

**Jendela utama**

- Layout `NavigationSplitView` tiga bagian: **sidebar → daftar unduhan → panel detail** (panel detail bisa disembunyikan).
- Sidebar bergaya macOS (translucent, vibrancy material) dengan ikon SF Symbols:
  - Semua Unduhan
  - Sedang Berjalan
  - Antre
  - Selesai
  - Torrent
  - Video & Audio
  - Gagal
  - Kategori: Dokumen, Arsip, Gambar, Musik, Video, Aplikasi
- Toolbar unified dengan: tambah (+), pause semua, lanjutkan semua, hapus yang selesai, dan kolom cari (`.searchable`).
- Daftar unduhan memakai baris yang rapi: ikon tipe file, nama, progress bar tipis, ukuran, kecepatan, ETA, dan tombol aksi (pause/resume/tampilkan di Finder) yang muncul saat hover.
- Menu konteks klik kanan: Pause, Resume, Salin Link, Buka File, Tampilkan di Finder, Unduh Ulang, Hapus.
- Drag & drop link, teks, file `.torrent` ke jendela atau ikon Dock.

**Elemen khas macOS yang wajib ada**

- **Menu bar extra** (`MenuBarExtra`): ikon kecil dengan ringkasan kecepatan dan daftar unduhan aktif, plus tombol cepat tempel link.
- **Pengaturan** (`⌘,`) dengan jendela `Settings` bergaya tab toolbar: Umum, Unduhan, Video, Torrent, Jaringan, Integrasi Browser, Lanjutan.
- Badge progres di ikon Dock dan bounce saat unduhan selesai.
- **Notifikasi** lewat `UserNotifications` saat selesai/gagal, dengan aksi "Tampilkan di Finder".
- Dukungan **Dark Mode / Light Mode** otomatis, accent color sistem, dan Reduce Motion.
- Dukungan **VoiceOver** (label aksesibilitas), Dynamic ukuran font sistem, dan navigasi keyboard penuh.
- Shortcut keyboard standar: `⌘N` tambah, `⌘V` tempel link, `⌘F` cari, `⌘,` pengaturan, `Space` Quick Look file selesai, `⌫` hapus.
- Animasi halus dan ringan (spring/ease bawaan SwiftUI), tanpa efek berlebihan.
- Ikon aplikasi bergaya macOS (squircle dengan sedikit kedalaman). Buat set ikon lengkap (16–1024 px) di `Assets.xcassets`. Boleh dibuat dengan SVG → PNG atau lewat kode.
- Teks antarmuka berbahasa **Indonesia** dan **Inggris** (gunakan `Localizable.xcstrings` atau `.strings`), mengikuti bahasa sistem.

---

## 6. Arsitektur yang Disarankan

```
Getto/
├── Getto.xcodeproj
├── Getto/
│   ├── App/                  # GettoApp.swift, AppDelegate, URL scheme handler
│   ├── Models/               # DownloadItem, TorrentInfo, MediaInfo, Settings
│   ├── Engines/
│   │   ├── DownloadEngine.swift      # protokol umum
│   │   ├── HTTPEngine / Aria2Engine  # HTTP/FTP + torrent via aria2 RPC
│   │   ├── MediaEngine.swift         # pembungkus yt-dlp + ffmpeg
│   │   └── EngineProcessManager.swift# jalankan/hentikan binary pendukung
│   ├── Services/             # QueueManager, Persistence, Notifications, Clipboard
│   ├── Views/                # Sidebar, DownloadList, DetailPanel, AddSheet, Settings
│   ├── ViewModels/
│   ├── NativeHost/           # target terpisah untuk native messaging host
│   └── Resources/
│       ├── bin/              # yt-dlp, ffmpeg, aria2c (x86_64)
│       ├── Assets.xcassets
│       └── Localizable.xcstrings
├── chrome-extension/
│   ├── manifest.json
│   ├── background.js         # service worker
│   ├── popup.html / popup.js
│   ├── content.js
│   └── icons/
├── scripts/
│   ├── fetch-binaries.sh     # unduh yt-dlp, ffmpeg, aria2c versi x86_64
│   ├── build.sh              # xcodebuild + codesign
│   └── make-dmg.sh           # buat Getto.dmg
└── README.md
```

Ketentuan arsitektur:

- Pisahkan UI dari logika lewat protokol `DownloadEngine` agar mesin bisa diganti.
- Semua proses eksternal dijalankan lewat `Process` dengan **async/await**, parsing output progres secara streaming, dan pembersihan proses saat aplikasi keluar.
- State disimpan ke disk (JSON di `~/Library/Application Support/Getto/`) sehingga antrean dan progres pulih setelah restart.
- Tangani error dengan pesan yang jelas dan bisa ditindaklanjuti (bukan error mentah), misalnya "Video ini privat" atau "Disk penuh", plus tombol Coba Lagi.
- Log debug bisa dibuka lewat menu **Bantuan → Tampilkan Log**.

---

## 7. Keamanan, Privasi, dan Kepatuhan

- Tidak ada telemetri atau pengiriman data ke server pihak ketiga. Tulis ini di README dan layar Tentang.
- Validasi semua URL dan nama file (cegah path traversal, tangani karakter ilegal).
- Pesan dari ekstensi Chrome hanya diterima dari ID ekstensi yang diizinkan.
- Aktifkan Hardened Runtime. Tanda tangani semua binary pendukung di dalam bundle (`codesign --deep` atau satu per satu).
- Saat pertama kali dijalankan, tampilkan catatan singkat: pengguna bertanggung jawab memastikan hak mengunduh konten dan mematuhi ketentuan layanan situs serta hukum hak cipta yang berlaku.
- Jangan menyertakan fitur untuk melewati DRM.

---

## 8. Distribusi

- `scripts/build.sh` menghasilkan `Getto.app` untuk x86_64 dalam konfigurasi Release.
- `scripts/make-dmg.sh` membuat `Getto.dmg` dengan jendela instalasi (ikon app + shortcut ke Applications).
- Tanpa akun Apple Developer, pakai penandatanganan ad-hoc (`codesign -s -`) dan tulis di README cara membuka pertama kali (klik kanan → Buka, atau `xattr -dr com.apple.quarantine /Applications/Getto.app`).
- Jika ada akun Developer, sertakan langkah notarisasi (`notarytool`) sebagai opsional.

---

## 9. Urutan Pengerjaan

1. **Fase 1 — Fondasi:** proyek Xcode, deployment target 13.0, arsitektur, `scripts/fetch-binaries.sh`, jendela kosong dengan sidebar + daftar.
2. **Fase 2 — Download HTTP:** tambah link, antrean, pause/resume, progres, persistensi.
3. **Fase 3 — Video:** integrasi yt-dlp + ffmpeg, pratinjau, pilihan kualitas, playlist.
4. **Fase 4 — Torrent:** file `.torrent`, magnet, pemilihan file, statistik peers.
5. **Fase 5 — Polesan macOS:** menu bar extra, notifikasi, badge Dock, Pengaturan, lokalisasi, aksesibilitas, ikon.
6. **Fase 6 — Ekstensi Chrome:** ekstensi MV3, native host, URL scheme, halaman Integrasi Browser.
7. **Fase 7 — Pengemasan:** build release, DMG, README.

Di akhir setiap fase: jalankan build, perbaiki semua error dan warning, lalu ringkas apa yang sudah selesai.

---

## 10. Kriteria Selesai (Acceptance Criteria)

- [ ] Aplikasi ter-build tanpa error dan berjalan di **macOS 13 pada Mac Intel**.
- [ ] Menempel link file biasa → terunduh dengan progres, pause, dan resume yang berfungsi.
- [ ] Menempel link YouTube → muncul pratinjau, bisa memilih kualitas/audio saja, hasil berupa file yang bisa diputar.
- [ ] Menempel link TikTok → video terunduh.
- [ ] Menambahkan magnet link dan file `.torrent` → bisa memilih file dan mengunduh sampai selesai.
- [ ] Ekstensi Chrome bisa dimuat lewat Load unpacked dan berhasil mengirim link ke Getto yang sedang berjalan maupun yang belum terbuka.
- [ ] Antrean tetap ada setelah aplikasi ditutup dan dibuka lagi.
- [ ] Tampilan mengikuti Dark/Light Mode, memakai SF Symbols, menu bar extra berfungsi, notifikasi muncul.
- [ ] UI tersedia dalam Bahasa Indonesia dan Inggris.
- [ ] `Getto.dmg` berhasil dibuat dan bisa dipasang di Mac lain.
- [ ] README berisi: cara build, cara memasang ekstensi Chrome, cara memperbarui yt-dlp, dan daftar batasan yang diketahui.

---

## 11. Format Jawaban yang Diharapkan

1. Tulis rencana singkat dan daftar keputusan teknis (mesin torrent, cara mendapatkan binary, strategi native messaging).
2. Buat semua file proyek secara lengkap, bukan potongan. Tidak boleh ada placeholder `// TODO` pada fitur inti.
3. Setelah selesai, berikan ringkasan: cara build, cara menjalankan, struktur folder, dan hal yang masih perlu dilakukan manual (misalnya ID ekstensi atau tanda tangan).
4. Bila ada bagian yang tidak bisa dikerjakan atau diuji di lingkungan saat ini (misalnya menjalankan app di macOS), katakan terus terang dan jelaskan cara pengguna mengujinya sendiri.
