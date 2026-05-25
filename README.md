# Description
A menu-driven Bash &amp; PowerShell toolkit for Mixxx DJ software. Easily fix broken file paths (relink), clean missing duplicate tracks from the database, and mass export playlists to M3U8. Supports macOS, Linux, and Windows.


# Mixxx Library Toolkit

A powerful, menu-driven command-line utility designed to maintain, repair, and optimize your Mixxx DJ software database (`mixxxdb.sqlite`). Whether you moved your music library to a new folder, switched operating systems, or ended up with thousands of duplicate "missing" tracks due to a bad rescan, this toolkit helps you recover your library and playlists in seconds.

Currently available for **macOS**, **Linux** (Bash scripts), and **Windows** (PowerShell).

---

## 🚀 Features & Menu Options

### 1️⃣ Fast Relink PLAYLISTS
* **What it does:** Scans **only** the tracks that belong to your existing Mixxx playlists and matches them against a new directory.
* **Why use it:** If you moved your music to a new folder/drive and your playlists appear empty or red, this option quickly relinks them without wasting time scanning your entire multi-gigabyte library.

### 2️⃣ Universal Relink LIBRARY
* **What it does:** Performs a deep scan of every single track registered in your Mixxx library. It automatically searches your new music directory by filename and updates the database paths.
* **Why use it:** Perfect for migrating your entire music collection to a new drive, a different folder structure, or a new computer while preserving all your precious BPM, Key, Hotcues, Cues, and Play counts.

### 3️⃣ Clean Missing Tracks & VACUUM
* **What it does:** Cross-references the Mixxx database with your actual hard drive. It identifies "ghost" tracks (files that no longer exist at the specified path), safely removes them in bulk while bypassing restrictive Foreign Key locks, and runs a database `VACUUM` to compress the file.
* **Why use it:** Shrinks bloated database files (e.g., from 175MB down to 55MB), speeds up Mixxx search functionality, and permanently eliminates annoying duplicate/missing entries from your screen.

### 4️⃣ Export Playlists to M3U8
* **What it does:** Mass exports all your Mixxx playlists into standard `.m3u8` files on your Desktop.
* **Why use it:** Creates a clean backup of your playlists that can be imported into other media players (like VLC) or other DJ software. The Windows version automatically fixes forward/backward slashes so the playlists work flawlessly natively.

### 5️⃣ Quick Backup
* **What it does:** Instantly creates a time-stamped backup copy of your `mixxxdb.sqlite` on your Desktop before any modification.
* **Why use it:** Safety first! If anything goes wrong, you can restore your library to its exact previous state with a single copy-paste.

---

## 🛠️ Requirements

* **Mixxx** installed on your system.
* **SQLite3 CLI** installed and available in your system's PATH.
  * *macOS/Linux:* Usually pre-installed.
  * *Windows:* Requires `sqlite3.exe` downloaded from the official SQLite website.

---

## 💻 How to Use

### macOS & Linux
1. Download the script (`mixxx_toolkit.sh` or `mixxx_toolkit_linux.sh`).
2. Open your Terminal and navigate to the script's folder.
3. Make it executable:
```bash
   chmod +x mixxx_toolkit.sh
```
4. Run the script:
```bash
   ./mixxx_toolkit.sh
```

### windows (PowerShell)
1. Download mixxx_toolkit_windows.ps1
2. Open PowerShell as an Administrator and allow script execution if needed:
```powershell
   Set-ExecutionPolicy RemoteSigned -Scope Process
```
3. Run teh script:
```powershell
   .\mixxx_toolkit_windows.ps1
```

### 🤝 Contributing
Feel free to fork this repository, open issues, or submit pull requests with improvements, bug fixes, or new features!

Developed with passion for DJs who want to keep their libraries lightweight and bulletproof.
