Sjtech Panel - Sistem Otentikasi yang Ditingkatkan
VersiLisensi

Sistem panel manajemen hosting dengan otentikasi yang aman dan fitur keamanan enterprise-level.

📋 Ringkasan
Sjtech Panel adalah solusi manajemen hosting lengkap dengan sistem otentikasi yang ditingkatkan. Proyek ini menyediakan dashboard modern, manajemen website, keamanan enterprise-level, dan antarmuka pengguna yang responsif.

✨ Fitur Utama
🔒 Keamanan
Persyaratan Kompleksitas Password: Password minimal 8 karakter dengan kombinasi huruf besar, huruf kecil, angka, dan karakter spesial
Mekanisme Penguncian Akun: Penguncian otomatis setelah 5 kali percobaan login gagal (15 menit)
Rate Limiting: Pembatasan 10 permintaan per detik untuk endpoint otentikasi
Header Keamanan: Implementasi header keamanan lengkap (X-Frame-Options, CSP, dll)
Validasi Input: Sanitasi input untuk mencegah serangan XSS dan SQL injection
📊 Dashboard
Statistik sistem real-time (CPU, Memory, Disk Usage)
Grafik dan visualisasi data
Kartu statistik yang informatif
Monitoring kinerja server
🔐 Sistem Otentikasi
Login dan registrasi pengguna
Manajemen profil (update nama dan password)
Session management yang aman
Protected routes untuk akses dashboard
🌐 Manajemen Hosting
Manajemen website dan domain
DNS management dengan Bind9
FTP accounts management
Database management
💻 Persyaratan Sistem
OS: Debian 11/12 atau Ubuntu 20.04/22.04
Web Server: Nginx
Database: MySQL/MariaDB
Runtime: Node.js 18+
Certificate: Let's Encrypt SSL
DNS: Bind9
Memory: Minimal 2GB RAM
Storage: Minimal 20GB disk space
🚀 Instalasi
Langkah 1: Clone Repository
git clone https://github.com/jayaputra212/sjtech-panel/blob/main/install.sh sjtech-panel
Langkah 2: Jalankan Skrip Instalasi
bash

chmod +x install.sh
./install.sh
Langkah 3: Konfigurasi Domain
Masukkan domain Anda saat diminta
Pastikan DNS sudah diatur ke IP server
⚙️ Konfigurasi
File Konfigurasi
config/database.js - Konfigurasi database
config/nginx.conf - Konfigurasi Nginx
config/ssl.conf - Konfigurasi SSL
Variabel Lingkungan
DOMAIN - Domain panel Anda
PM2_APP_NAME - Nama aplikasi PM2
📖 Penggunaan
Login
Buka browser dan akses domain Anda
Masukkan email dan password
Akses dashboard setelah login berhasil
Registrasi
Klik "Register" di halaman login
Isi form registrasi
Konfirmasi email (jika diimplementasikan)
