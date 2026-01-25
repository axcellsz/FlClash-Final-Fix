# Panduan Penggunaan Plugin Flutter `shizuku_api`

Plugin `shizuku_api` adalah sebuah plugin Flutter yang memungkinkan aplikasi Anda untuk berinteraksi dengan **Shizuku API** pada perangkat Android. Shizuku adalah layanan yang memungkinkan aplikasi biasa untuk menjalankan perintah *shell* dengan hak istimewa (seperti `adb shell`) tanpa memerlukan akses *root* penuh, asalkan layanan Shizuku sudah diaktifkan dan berjalan di perangkat [1].

Berikut adalah panduan langkah demi langkah untuk menginstal, mengkonfigurasi, dan menggunakan plugin ini dalam proyek Flutter Anda.

## 1. Prasyarat

Sebelum menggunakan plugin ini, ada dua prasyarat utama yang harus dipenuhi:

1.  **Aplikasi Shizuku Terinstal dan Berjalan**: Aplikasi Shizuku harus sudah terinstal dan layanan Shizuku harus sudah diaktifkan pada perangkat Android target.
2.  **Minimum SDK**: Proyek Android Anda harus memiliki `minSdk` minimal **24** (Android 7.0 Nougat) atau lebih tinggi.

## 2. Instalasi

Tambahkan plugin `shizuku_api` ke proyek Flutter Anda dengan menjalankan perintah berikut di terminal proyek:

```bash
flutter pub add shizuku_api
```

Atau, tambahkan secara manual ke file `pubspec.yaml` Anda:

```yaml
dependencies:
  flutter:
    sdk: flutter
  shizuku_api: ^1.2.2 # Gunakan versi terbaru yang tersedia
```

Setelah itu, jalankan `flutter pub get` untuk mengunduh paket.

## 3. Konfigurasi Android

Plugin ini memerlukan konfigurasi tambahan pada level Android untuk dapat berinteraksi dengan layanan Shizuku.

### A. Konfigurasi `AndroidManifest.xml`

Tambahkan tag `<provider>` berikut di dalam tag `<application>` pada file `android/app/src/main/AndroidManifest.xml`:

```xml
<application>
    <provider
        android:name="rikka.shizuku.ShizukuProvider"
        android:authorities="${applicationId}.shizuku"
        android:multiprocess="false"
        android:enabled="true"
        android:exported="true"
        android:permission="android.permission.INTERACT_ACROSS_USERS_FULL" />
</application>
```

**Catatan**: Pastikan Anda menempatkan kode ini di dalam tag `<application>`.

### B. Konfigurasi `build.gradle`

Pastikan `minSdkVersion` di file `android/app/build.gradle` (atau `android/local.properties` jika Anda menggunakan *Flutter module*) diatur ke 24 atau lebih tinggi.

```groovy
android {
    defaultConfig {
        // ...
        minSdkVersion 24 // Pastikan nilainya 24 atau lebih tinggi
        // ...
    }
}
```

## 4. Penggunaan (Usage)

Setelah instalasi dan konfigurasi selesai, Anda dapat mulai menggunakan API Shizuku dalam kode Dart/Flutter Anda.

### A. Inisialisasi Plugin

Pertama, inisialisasi plugin:

```dart
import 'package:shizuku_api/shizuku_api.dart';

final _shizukuApiPlugin = ShizukuApi();
```

### B. Memeriksa Status Shizuku

Langkah pertama yang sangat penting adalah memeriksa apakah *binder* Shizuku sedang berjalan. Ini memastikan bahwa layanan Shizuku aktif dan dapat dihubungi.

```dart
Future<bool> isShizukuRunning() async {
  bool isBinderRunning = await _shizukuApiPlugin.pingBinder() ?? false;
  return isBinderRunning;
}
```

### C. Memeriksa dan Meminta Izin (Permission)

Aplikasi Anda memerlukan izin dari pengguna melalui aplikasi Shizuku untuk dapat menjalankan perintah.

#### 1. Memeriksa Izin

Fungsi ini akan mengembalikan `true` jika izin sudah diberikan sebelumnya, atau `false` jika izin belum pernah diminta atau ditolak.

```dart
Future<bool> checkShizukuPermission() async {
  bool checkPermission = await _shizukuApiPlugin.checkPermission();
  print('Izin Shizuku sudah diberikan: $checkPermission');
  return checkPermission;
}
```

#### 2. Meminta Izin

Fungsi ini akan memicu *popup* permintaan izin Shizuku kepada pengguna.

```dart
Future<bool> requestShizukuPermission() async {
  // Akan memicu popup Shizuku
  bool requestPermission = await _shizukuApiPlugin.requestPermission();
  print('Izin Shizuku diberikan: $requestPermission');
  return requestPermission;
}
```

### D. Menjalankan Perintah Shell

Setelah Anda memastikan Shizuku berjalan dan izin telah diberikan, Anda dapat menjalankan perintah *shell* (perintah `adb shell`) dengan hak istimewa.

```dart
Future<void> runAdbCommand(String command) async {
  try {
    // Contoh: Menghapus aplikasi sistem (bloatware) untuk user 0
    // PERHATIAN: Gunakan dengan sangat hati-hati!
    // String command = 'pm uninstall --user 0 com.android.chrome'; 
    
    await _shizukuApiPlugin.runCommand(command);
    print('Perintah berhasil dijalankan: $command');
  } catch (e) {
    print('Gagal menjalankan perintah: $e');
  }
}
```

**Peringatan Penting**: Perintah yang dijalankan melalui Shizuku memiliki hak istimewa yang tinggi. **Gunakan fitur ini dengan sangat hati-hati** karena kesalahan dalam perintah dapat menyebabkan kerusakan pada sistem operasi perangkat Android.

## 5. Alur Penggunaan yang Direkomendasikan

Dalam aplikasi Anda, alur penggunaan yang disarankan adalah sebagai berikut:

1.  Panggil `pingBinder()` untuk memastikan layanan Shizuku berjalan.
2.  Jika Shizuku berjalan, panggil `checkPermission()` untuk melihat apakah izin sudah ada.
3.  Jika izin belum ada, panggil `requestPermission()` untuk meminta izin kepada pengguna.
4.  Jika izin diberikan, Anda dapat memanggil `runCommand()` untuk menjalankan perintah *shell* yang diperlukan.

| Langkah | Fungsi | Tujuan |
| :--- | :--- | :--- |
| 1 | `pingBinder()` | Memastikan layanan Shizuku aktif. |
| 2 | `checkPermission()` | Memeriksa apakah izin sudah diberikan. |
| 3 | `requestPermission()` | Meminta izin dari pengguna jika belum ada. |
| 4 | `runCommand(command)` | Menjalankan perintah *shell* dengan hak istimewa. |

## Referensi

[1] shizuku\_api | Flutter package - pub.dev. (n.d.). *pub.dev*. [https://pub.dev/packages/shizuku\_api](https://pub.dev/packages/shizuku_api)
