# Cermin

Mirror layar iPhone ke **jendela biasa** di Mac: bisa digeser, di-resize, dan dibuat *always on top*. iPhone tetap bisa dipakai di tangan, Mac tidak fullscreen. Tanpa watermark, gratis, offline. Spesifikasi lengkap ada di [PRD.md](PRD.md), desain di [design/](design/).

| Cara | Di iPhone | Syarat |
|---|---|---|
| **USB** (utama) | tidak perlu install apa pun | kabel data, ketuk *Percayai* sekali |
| **Wireless / AirPlay** | tidak perlu install apa pun | Wi-Fi sama + UxPlay terpasang di Mac (lihat di bawah) |

## Build & jalankan

Cukup Command Line Tools (Xcode tidak wajib).

```bash
./scripts/build.sh --test --run   # unit test, build build/Cermin.app, lalu buka
```

Supaya **Buka saat login** berfungsi, pindahkan `build/Cermin.app` ke `/Applications`.
Karena app ditandatangani ad-hoc, macOS akan meminta izin Kamera lagi setiap kali app di-build ulang.

## Wireless (AirPlay) — sekali saja

```bash
./scripts/install-uxplay.sh
```

Script ini memasang `cmake pkgconf libplist openssl@3 gstreamer` lewat Homebrew, lalu mem-build [UxPlay](https://github.com/FDH2/UxPlay) 1.74 (commit `534e2cc`, dikunci) ke `~/Library/Application Support/Cermin/bin/uxplay`. Setelah itu buka **Pengaturan → Wireless → Aktifkan wireless**.

> **Jangan pakai UxPlay v1.73.7** (rilis resmi terakhir / versi Homebrew). Pairing kodenya menolak iOS 27 (`client_proof_len 20 invalid`), sehingga iPhone meminta kode terus-menerus. Kalau sudah terlanjur pasang versi lama, jalankan ulang script ini.

- Matikan **AirPlay Receiver bawaan** (Pengaturan Sistem → Umum → AirDrop & Handoff). Kalau tidak, iPhone melihat dua tujuan, dan yang bawaan selalu fullscreen.
- Cermin memakai port 7300–7302 dan 5600 (lokal). Kalau firewall aktif, izinkan koneksi masuk untuk `uxplay`.
- Kode cukup dimasukkan sekali per iPhone. Cermin menyimpan identitas AirPlay-nya (`uxplay.pem` dan ID perangkat) supaya iPhone tetap mengenali Mac setelah restart.
- Mode P2P (tanpa Wi-Fi yang sama) masih eksperimental.
- UxPlay berlisensi **GPL-3.0**. Aman untuk dipakai sendiri; kalau Cermin + UxPlay dibagikan, source code wajib dibuka.

## Shortcut

| Aksi | Shortcut |
|---|---|
| Privacy Curtain (global, bisa diganti) | ⌃⌥⌘P |
| Screenshot (PNG resolusi asli, juga ke clipboard) | ⌘S |
| Selalu di atas | ⌘T |
| Ukuran 50% / 75% / 100% / Fit | ⌘1 – ⌘4 |
| Sembunyikan/tampilkan jendela | ⌥⌘M |

Sebelum meeting telemedicine: nyalakan **Focus Mode** di iPhone, pakai data pasien dummy, dan coba hotkey curtain sekali.

## Struktur

```
Sources/CerminCore/   logika murni + unit test: state machine, ukuran jendela, RTP/H.264, log UxPlay, register perangkat
Sources/Cermin/       app: Capture/ (USB, AirPlay) · Render/ · Window/ · Features/ · UI/ · App/
Tests/                swift test
scripts/              build.sh · install-uxplay.sh · make-icon.swift
```

## Tes

- `swift test` menjalankan unit test logika murni (state machine, ukuran/rotasi jendela, depacketizer RTP, parser log UxPlay, argumen UxPlay, register perangkat tepercaya, hotkey).
- Build debug punya dua alat bantu:
  - `.build/debug/Cermin --snapshot /tmp/shots` merender semua layar (light/dark) ke PNG.
  - `CERMIN_UXPLAY=<script> CERMIN_LOG=1 .build/debug/Cermin` menjalankan app dengan uxplay palsu dan mencetak state tiap detik. Dengan ini jalur wireless (PIN → izin → decode H.264 → rotasi → putus) bisa dites tanpa iPhone. Tambahkan `CERMIN_AUTOANSWER=approve|deny` untuk menjawab prompt Izinkan/Tolak otomatis.
- Tes yang butuh perangkat asli ada di checklist [PRD.md §Bagian 5](PRD.md).

## Lisensi

Kode Cermin: [MIT](LICENSE). UxPlay (dipakai untuk mode wireless) tidak ikut di repo ini; script hanya mengunduh dan mem-build-nya. Lisensi UxPlay adalah GPL-3.0.
