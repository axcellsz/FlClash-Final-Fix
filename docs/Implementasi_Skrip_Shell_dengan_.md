# Implementasi Skrip Shell `auto_pilot_termux.sh` dengan `shizuku_api`

Skrip `auto_pilot_termux.sh` yang Anda berikan adalah sebuah *daemon* sederhana yang dirancang untuk secara otomatis mereset koneksi internet (dengan men-toggle *Airplane Mode*) jika koneksi terputus.

Karena skrip ini menggunakan logika perulangan (`while true`) dan memerlukan hak istimewa untuk men-toggle *Airplane Mode* (`cmd connectivity`), implementasi terbaik di Flutter adalah dengan mereplikasi logika perulangan di Dart dan menggunakan `shizuku_api.runCommand()` hanya untuk perintah yang membutuhkan hak istimewa.

Berikut adalah panduan implementasi langkah demi langkah.

## 1. Analisis Skrip dan Pemetaan Fungsi

| Fungsi Skrip Shell | Perintah Shell | Implementasi Flutter/Dart | Kebutuhan Shizuku |
| :--- | :--- | :--- | :--- |
| **Cek Koneksi** | `curl ... generate_204` | Menggunakan paket `http` atau `connectivity_plus` di Flutter untuk cek koneksi. | ❌ Tidak |
| **Toggle Airplane Mode** | `cmd connectivity airplane-mode enable` | `shizukuApiPlugin.runCommand('cmd connectivity airplane-mode enable')` | ✅ Ya |
| | `cmd connectivity airplane-mode disable` | `shizukuApiPlugin.runCommand('cmd connectivity airplane-mode disable')` | ✅ Ya |
| **Perulangan** | `while true; do ... sleep $INTERVAL` | Menggunakan `Timer.periodic` di Dart. | ❌ Tidak |

## 2. Persiapan Proyek Flutter

Pastikan Anda sudah menyelesaikan langkah-langkah instalasi dan konfigurasi Android untuk `shizuku_api` seperti yang dijelaskan dalam panduan sebelumnya.

Anda juga memerlukan paket untuk pemeriksaan koneksi internet. Tambahkan `http` atau `connectivity_plus` ke `pubspec.yaml`. Kita akan menggunakan `http` untuk meniru fungsi `curl` secara langsung.

```bash
flutter pub add http
```

## 3. Implementasi Kode Dart

Buat sebuah fungsi yang akan menjalankan logika *auto-pilot* Anda.

### A. Fungsi Cek Koneksi (Menggantikan `check_internet`)

Fungsi ini akan meniru perilaku `curl` dengan mencoba mengakses URL yang sama.

```dart
import 'package:http/http.dart' as http;

Future<bool> checkInternet() async {
  const targetUrl = 'http://connectivitycheck.gstatic.com/generate_204';
  const timeout = Duration(seconds: 5);

  try {
    final response = await http.head(Uri.parse(targetUrl)).timeout(timeout);
    // Skrip shell menganggap 204 atau 200 sebagai sukses
    return response.statusCode == 204 || response.statusCode == 200;
  } catch (e) {
    // Timeout atau error koneksi lainnya
    return false;
  }
}
```

### B. Fungsi Toggle Airplane Mode (Menggantikan `toggle_airplane`)

Fungsi ini menggunakan `shizuku_api` untuk menjalankan perintah sistem Android.

```dart
import 'package:shizuku_api/shizuku_api.dart';

final _shizukuApiPlugin = ShizukuApi();

Future<void> toggleAirplaneMode() async {
  print('   -> [RESET] Toggling Airplane Mode...');
  
  // 1. Enable Airplane Mode
  await _shizukuApiPlugin.runCommand('cmd connectivity airplane-mode enable');
  await Future.delayed(const Duration(seconds: 3)); // sleep 3
  
  // 2. Disable Airplane Mode
  await _shizukuApiPlugin.runCommand('cmd connectivity airplane-mode disable');
  print('   -> [RESET] Done. Waiting for signal...');
  await Future.delayed(const Duration(seconds: 10)); // sleep 10
}
```

### C. Logika Auto-Pilot Utama (Menggantikan `while true`)

Gunakan `Timer.periodic` untuk menjalankan logika perulangan secara berkala.

```dart
import 'dart:async';

void startAutoPilot() async {
  const interval = Duration(seconds: 10); // INTERVAL=10
  
  // 1. Pastikan Shizuku berjalan dan memiliki izin
  bool isRunning = await _shizukuApiPlugin.pingBinder() ?? false;
  if (!isRunning) {
    print('🔴 Layanan Shizuku tidak berjalan. Auto Pilot dibatalkan.');
    return;
  }
  
  bool hasPermission = await _shizukuApiPlugin.checkPermission();
  if (!hasPermission) {
    print('🔴 Izin Shizuku belum diberikan. Meminta izin...');
    hasPermission = await _shizukuApiPlugin.requestPermission();
    if (!hasPermission) {
      print('🔴 Izin ditolak. Auto Pilot dibatalkan.');
      return;
    }
  }
  
  print('--- Auto Pilot Standard Started ---');

  // 2. Mulai perulangan berkala
  Timer.periodic(interval, (timer) async {
    final isConnected = await checkInternet();
    final timestamp = DateTime.now().toString().substring(11, 19); // Format HH:MM:SS

    if (isConnected) {
      // Internet OK
      print('\r[$timestamp] 🟢 Internet OK');
    } else {
      // Connection Lost
      print('\n[$timestamp] 🔴 Connection Lost!');
      await toggleAirplaneMode();
    }
  });
}

// Panggil fungsi ini di initState() atau setelah tombol ditekan
// startAutoPilot();
```

## 4. Kesimpulan Implementasi

Dengan mengadopsi strategi ini, Anda telah berhasil mengimplementasikan logika dari skrip shell Anda ke dalam aplikasi Flutter.

*   **Hak Istimewa:** Diperoleh melalui `shizuku_api.runCommand()` untuk perintah `cmd connectivity`.
*   **Logika:** Diatur oleh Dart/Flutter (`Timer.periodic`, `checkInternet()`).

Pastikan untuk mengelola *state* aplikasi Anda dengan baik, terutama saat memanggil `startAutoPilot()` dan memastikan Anda memiliki cara untuk menghentikan `Timer` jika aplikasi ditutup atau fitur dimatikan.
