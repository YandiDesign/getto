# Getto — Download Manager Native untuk macOS

Getto adalah download manager native untuk macOS (**universal: Intel x86_64
dan Apple Silicon arm64**, macOS 13+). Prinsipnya sederhana: **tempel link →
terunduh**, dengan tampilan dan perilaku khas aplikasi bawaan Apple.

**Privasi:** tidak ada telemetri atau pengiriman data ke server pihak ketiga.

---

## Daftar Isi

- [Fitur utama](#fitur-utama)
- [Cara memakai](#cara-memakai)
- [Jendela utama](#jendela-utama)
- [Pengaturan](#pengaturan)
- [Ekstensi Chrome](#ekstensi-chrome)
- [Pintasan keyboard](#pintasan-keyboard)
- [Troubleshooting](#troubleshooting)
- [Untuk developer](#untuk-developer)
- [Batasan yang diketahui](#batasan-yang-diketahui)
- [Lisensi](#lisensi)

---

## Fitur utama

### 1. Download file langsung (HTTP/HTTPS/FTP)
- Tempel satu atau banyak link sekaligus (satu link per baris).
- Nama file, ukuran, dan tipe dideteksi otomatis dari server sebelum mulai.
- **Multi-koneksi** per file (default 8 segmen, bisa 1–16) agar cepat.
- **Pause, resume, retry**, dan unduhan lanjut otomatis setelah aplikasi
  ditutup/dibuka lagi.
- **Antrean** dengan batas unduhan bersamaan + batas kecepatan global opsional.
- Dukungan header kustom, cookie, dan basic auth (bagian *Lanjutan*) untuk
  link yang butuh login.
- Deteksi file duplikat: timpa, ganti nama otomatis, atau lewati.

### 2. Download video & audio (YouTube, TikTok, Instagram, X, Facebook, Vimeo, …)
- Mesin ekstraksi **yt-dlp** + **ffmpeg** dibundel di dalam aplikasi
  (tanpa perlu Python/instal tambahan).
- **Pratinjau** otomatis: thumbnail besar, judul, kanal, durasi.
- Pilihan kualitas (Terbaik s.d. 360p), format (MP4/MKV/WEBM), atau
  **audio saja** (MP3/M4A/OPUS/FLAC).
- Pilihan **codec H.264 (kompatibel)** agar hasil bisa diputar dan
  di-Quick Look di Mac Intel (kualitas Best/4K YouTube umumnya AV1).
- Playlist/kanal, subtitle (embed atau `.srt` terpisah), embed
  thumbnail & metadata.
- Tombol **Perbarui mesin yt-dlp** di Pengaturan (situs video sering berubah;
  tanpa perlu update aplikasi).

### 3. Torrent & magnet link
- Buka file `.torrent` (drag & drop / dialog / dari Finder) dan magnet link.
- Pilih file di dalam torrent (checkbox) sebelum mengunduh.
- Statistik live: progres, kecepatan unduh/unggah, seeds/peers, rasio, ETA.
- Kontrol pause, resume, hapus (+opsi hapus file), dan pengaturan lanjutan
  (port, batas upload/download, DHT, PEX, enkripsi, rasio seeding).

### 4. Mode lambat 🐢 (1 KB/s)
- Tombol kura-kura di toolbar (atau menu *Unduhan*, `⌥⌘L`).
- Membatasi **semua** unduhan menjadi 1 KB/s secara realtime — unduhan tetap
  jalan tapi sangat lemot. Berguna sebagai "pause semu" untuk server yang
  tidak mendukung pause/resume.
- Berlaku langsung tanpa restart unduhan (video dilanjutkan otomatis dari
  `.part`).

### 5. Matikan komputer otomatis
- Pengaturan → Umum → **"Matikan komputer saat semua unduhan selesai"**,
  atau tombol power ⏻ di toolbar.
- Komputer dimatikan **60 detik** setelah semua unduhan selesai/gagal,
  didahului notifikasi. Menambah unduhan baru membatalkan jadwal.
- Butuh izin **Aksesibilitas** sekali
  (Pengaturan Sistem → Privasi & Keamanan → Aksesibilitas).

### 6. Pengalaman khas macOS
- Tiga kolom: sidebar → daftar kartu kaca → panel info (atau tampilan awal).
- Mode daftar **dan grid**, sortir (terbaru, terlama, A–Z, Z–A, ukuran),
  pencarian instan.
- **Quick Look**: klik file lalu tekan **Space**; atau klik kanan → Quick Look.
- **Menu bar extra**: ringkasan kecepatan + unduhan aktif + tempel cepat.
- Badge progres di Dock, notifikasi selesai/gagal (dengan aksi
  *Tampilkan di Finder*), Dark/Light Mode + tampilan manual
  (sistem/terang/gelap), VoiceOver dan navigasi keyboard penuh.
- **Dua bahasa**: Indonesia & Inggris — mengikuti sistem, atau dikunci di
  Pengaturan → Umum → Bahasa.

---

## Cara memakai

1. Klik **+** (atau `⌘N`) — isi clipboard otomatis terbaca.
2. Tempel link (boleh banyak, satu per baris) → untuk video muncul pratinjau
   + pilihan kualitas/format → klik **Unduh**.
3. Pantau progres di kartu (bar, ukuran, kecepatan, ETA).
4. Klik kartu untuk melihat detail kanan: statistik, aksi
   (Finder/Buka/Quick Look/Coba Lagi), dan sumber
   (situs web, link berkas, file lokal — semuanya bisa diklik).
5. Klik kanan kartu untuk menu lengkap; seret file `.torrent`/link ke
   jendela atau ikon Dock.

---

## Jendela utama

| Area | Isi |
|---|---|
| Sidebar | Semua Unduhan, Sedang Berjalan, Selesai, Torrent, Video & Audio, Gagal + Kategori (Dokumen, Arsip, Gambar, Musik, Video, Aplikasi). Angka = jumlah item. |
| Tengah | Kolom cari, judul + ringkasan, toggle daftar/grid, kartu unduhan (pause/resume sekali klik, menu `…` di tepi). |
| Kanan | Toolbar (+, tempel-cepat, mode lambat, shutdown otomatis, pengaturan, tampilan), panel info item terpilih, atau tampilan awal (ikon, tombol Tempel Link, kartu kecepatan live + grafik). |

---

## Pengaturan (`⌘,`)

| Tab | Isi |
|---|---|
| Umum | Folder unduhan, tampilan, **bahasa**, notifikasi selesai/gagal, **shutdown otomatis**, catatan privasi. |
| Unduhan | Unduhan bersamaan, segmen per file, batas kecepatan global, perilaku duplikat. |
| Video | Kualitas/format/codec/audio default, perbarui yt-dlp. |
| Torrent | Port, batas unduh/unggah, DHT, PEX, enkripsi, rasio seeding, handler magnet/`.torrent`. |
| Jaringan | Cookie, username/password basic auth. |
| Browser | Status ekstensi, ID ekstensi, pasang integrasi, buka folder ekstensi. |
| Lanjutan | Tampilkan log, reset antrean, info keamanan bundle. |

---

## Ekstensi Chrome

1. Buka `chrome://extensions` → nyalakan **Developer mode** → **Load unpacked**
   → pilih folder `chrome-extension/`.
2. Klik ikon puzzle 🧩 → pin 📌 Getto. Salin **ID ekstensi**.
3. Getto → **Pengaturan (`⌘,`) → Browser** → tempel ID → **Pasang integrasi**
   (status harus *Terpasang*).
4. Uji: klik ikon Getto → **"Terhubung ke Getto ✓"** → klik kanan link →
   **Download dengan Getto**.

Tanpa native messaging, pengiriman tetap jalan via URL scheme
`getto://add?url=<encoded-url>`. Kalau error: `forbidden` berarti ID salah
(ulangi langkah 3); `not found` berarti klik Pasang integrasi lagi, dan ulangi
setiap aplikasi pindah folder.

Urutan jalur pengiriman ekstensi (otomatis, tercatat di Log popup):
native messaging → HTTP lokal `127.0.0.1:17842` (perlu app berjalan;
tanpa dialog, tanpa manifest) → URL scheme (selalu memicu dialog "open
with" — itu keamanan browser). Kalau popup menampilkan dialog terus,
berarti dua jalur pertama gagal — buka Log di popup, salin, dan periksa
baris `native-error`/`http-error`.

### Cookie & login otomatis

Ekstensi membaca cookie + referer situs aktif (`chrome.cookies`,
butuh izin eksplisit saat instal) dan mengirimnya ke aplikasi. Aplikasi
meneruskannya sebagai header HTTP (`Cookie`/`Referer`) ke aria2 maupun
yt-dlp — jadi link yang butuh login (milikmu, saat kamu login di Chrome)
tetap bisa diunduh Getto. Cookie tersimpan per-item di antrean lokal dan
tidak dikirim ke mana pun selain situs tujuannya. Cara cek: kirim link dari
Chrome → unduhan yang tadinya 401/403/private menjadi jalan.

### User-Agent asli ikut terkirim (penting untuk situs ketat)

Cookie sesi tidak cukup sendiri: situs seperti Cloudflare mengikat
`cf_clearance` pada **User-Agent + client hint** browser yang menerbitkannya.
Kalau pemunduh memakai UA generik, situs membalas *“Access denied”* /
*“you may need login/cookies”* walau cookie sudah benar.

Karena itu ekstensi mengirim profil browser aslinya bersama cookie:
`User-Agent`, `Accept`, `Accept-Language`, dan `Sec-CH-UA` /
`Sec-CH-UA-Mobile` / `Sec-CH-UA-Platform`. Semuanya diteruskan apa adanya ke
aria2 dan yt-dlp per-item. Tautan yang butuh login tidak perlu UA generik —
link yang sama bisa gagal di browser dan sukses di Getto (atau sebaliknya).

Kalau muncul “Situs memverifikasi browser (Cloudflare)”: buka tautan itu di
browser sampai verifikasi selesai, lalu kirim ulang dari browser (klik kanan →
Download dengan Getto). Cookie dan UA yang baru ikut terkirim. Getto
mendeteksi halaman verifikasi tersebut secara otomatis (status 403/503/429
+ penanda Cloudflare) dan tidak menyimpannya sebagai file unduhan.

Untuk link yang **ditempel manual**, cookie tidak bisa diambil dari browser
oleh Getto — pakai **Pengaturan → Video → Cookie browser otomatis**
(`--cookies-from-browser`, sekali izin Keychain), atau isi cookie manual di
**Pengaturan → Jaringan → Cookie**.

---

## Pintasan keyboard

| Pintasan | Aksi |
|---|---|
| `⌘N` | Tambah unduhan |
| `⌘F` | Cari |
| `⌘,` | Pengaturan |
| `Space` | Quick Look file selesai yang dipilih |
| `Esc` | Tutup panel detail (kembali ke tampilan awal) |
| `⌥⌘P` / `⌥⌘R` | Jeda / lanjutkan semua |
| `⌥⌘L` | Mode lambat on/off |
| `⇧⌘D` | Tampilkan/sembunyikan panel detail |

---

## Troubleshooting

- **Ikon Dock tidak ikut berubah** (cache ikon macOS): lepas tile lama dari
  Dock, lalu:
  ```bash
  touch /Applications/Getto.app && killall Dock
  ```
- **Tombol pengaturan toolbar tidak membuka apa-apa**: pakai `⌘,` (selalu
  bisa). Tombol toolbar memakai selector `showSettingsWindow:` (Ventura+).
- **Pratinjau Space tidak muncul untuk video AV1** (YouTube Best/4K di Intel):
  pilih Codec H.264 saat mengunduh, atau buka dengan IINA/VLC.
- **YouTube minta verifikasi anti-bot**: tunggu sebentar lalu coba lagi, atau
  isi cookie login di Pengaturan → Jaringan.
- **Membuka pertama kali** (ad-hoc sign, tanpa akun Developer): klik kanan
  `Getto.app` → **Buka**, atau:
  ```bash
  xattr -dr com.apple.quarantine /Applications/Getto.app
  ```

---

## Untuk developer

### Persyaratan

- Mac Intel (x86_64) **atau** Apple Silicon (arm64), macOS 13+.
- Xcode 14.3+ (Swift 5.8, deployment target 13.0).
- Koneksi internet (mengambil binary pendukung saat build).

### Universal (Intel + Apple Silicon)

- `Getto` dan `GettoNativeHost` dibangun universal (`ARCHS = arm64 x86_64`,
  `lipo`-verified). Tanpa Rosetta.
- Helper binary dibundel **per-arch** di `Getto/Resources/bin/{x86_64,arm64}/`
  dan dipilih otomatis sesuai slice yang berjalan (`#if arch()`):
  | Helper | x86_64 | arm64 |
  |---|---|---|
  | yt-dlp | universal (satu file) | universal (satu file) |
  | ffmpeg | evermeet static 6.1 | osxexperts static 8.0 |
  | aria2c | conda-forge + 10 dylib | conda-forge + 10 dylib |
- `scripts/fetch-binaries.sh` mengisi kedua arch; `scripts/build.sh`
  membangun universal penuh.
- Slice ARM **terverifikasi struktur** (Mach-O arm64, rpath `@loader_path`,
  codesign) di mesin Intel; uji jalan pertama di Mac Apple Silicon akan
  mengonfirmasi runtime ARM.

### Cara build

```bash
# 1. Ambil binary pendukung (kedua arch)
bash scripts/fetch-binaries.sh

# 2. Build Release universal + codesign ad-hoc
bash scripts/build.sh
# hasil: build/Getto.app

# 3. Buat DMG
bash scripts/make-dmg.sh
# hasil: build/Getto.dmg
```

Build manual:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project Getto.xcodeproj -scheme Getto -configuration Release build
```

Jika punya akun Apple Developer, ganti `CODE_SIGN_IDENTITY` dan jalankan
notarisasi (`notarytool`) sebelum distribusi.

### Arsitektur kode

```
Getto/            # App, Models, Engines, Services, Views, ViewModels, NativeHost, Resources
chrome-extension/ # ekstensi MV3 (background, popup, content, icons)
scripts/          # fetch-binaries.sh, build.sh, make-dmg.sh
```

- Protokol `DownloadEngine` memisahkan UI dari mesin unduh.
- Satu mesin `aria2c` via JSON-RPC untuk HTTP/FTP/Torrent/magnet
  (alternatif libtorrent ditolak karena butuh wrapper C++).
- `MediaEngine` membungkus yt-dlp + ffmpeg (pratinjau, kualitas, playlist,
  subtitle, limit-rate, embed metadata).
- State JSON di `~/Library/Application Support/Getto/` (antrean pulih
  setelah restart); debug via menu Bantuan → Tampilkan Log.
- Lihat rencana awal di `prompt.md`.

---

## Batasan yang diketahui

- Binary `aria2c` tidak punya rilis resmi static macOS; diambil dari
  conda-forge (atau build dari source — butuh clang).
- Notarisasi Apple butuh akun Developer (opsional).
- Tanpa fitur melewati DRM. Pengguna bertanggung jawab atas hak mengunduh
  konten dan kepatuhan pada ketentuan layanan situs & hukum hak cipta.
- Mac Intel tidak bisa memutar/preview video **AV1** (YouTube Best/4K) lewat
  Quick Look/QuickTime — pilih **Codec H.264** atau buka dengan IINA/VLC.

---

## Lisensi

Kode Getto (Swift, JavaScript, skrip build) berlisensi **MIT** — lihat
[LICENSE](LICENSE).

Binary pendukung yang di-bundle saat distribusi (`aria2c`, `ffmpeg`, `yt-dlp`)
berlisensi berlainan: **yt-dlp** = Unlicense (domain publik), **aria2c** dan
**ffmpeg** = GPL-2.0-or-later. Inventaris lengkap + cara memenuhi kewajiban
GPL ada di [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Binary tersebut
dijalankan sebagai proses terpisah (bukan di-link), jadi kode Getto tetap MIT.

### Penggunaan yang bertanggung jawab

Getto adalah alat teknis: ia mengunduh apa pun URL yang kamu berikan. Getto
tidak menyediakan akses ke konten berhak-cipta, **tidak menyediakan tautan
atau daftar menuju konten tertentu**, dan tidak memuat konten apa pun —
semuanya berasal dari URL yang kamu sendiri tempel atau klik.

Kamu bertanggung jawab penuh atas:

- **Memegang hak** atas konten yang kamu unduh (karya sendiri, berlisensi,
  atau dengan izin).
- **Menaati ketentuan layanan** situs asal. Mengunduh dari YouTube, TikTok,
  Instagram, X, atau Facebook secara automate melanggar ToS situs tersebut
  bagi sebagian besar pengguna.
- **Menaati hukum hak cipta** di yurisdiksi kamu. Getto sengaja tidak
  menyediakan fitur untuk melewati DRM, menangkap stream terproteksi, atau
  membongkar proteksi apa pun.

Penyalahgunaan untuk mengunduh konten tanpa hak bukan tanggung jawab Getto
maupun penulisnya.

**Tanpa DRM, tanpa pembongkolan proteksi, tanpa bypass.** Hanya unduhan
konvensional dari URL.
