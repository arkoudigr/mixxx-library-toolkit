$DB_PATH = "$env:USERPROFILE\AppData\Local\Mixxx\mixxxdb.sqlite"
$DESKTOP = [Environment]::GetFolderPath('Desktop')

function Make-Backup {
    if (Test-Path $DB_PATH) {
        $date = Get-Date -Format "yyyyMMdd_HHmmss"
        $backupPath = "$DESKTOP\mixxxdb_backup_$date.sqlite"
        Copy-Item $DB_PATH $backupPath
        Write-Host "🔒 Backup created on Desktop!" -ForegroundColor Green
    }
}

function Relink-Playlists {
    Write-Host "--- ⚡ Fast Relink PLAYLISTS (Windows) ---"
    $newDir = (Read-Host "👉 Drag and drop or enter the NEW FOLDER containing your playlist tracks").Trim('"')
    if (-not (Test-Path $newDir)) { Write-Host "❌ Folder does not exist." -ForegroundColor Red; return }
    Make-Backup
    
    $tracks = sqlite3 $DB_PATH "SELECT DISTINCT tl.id, tl.location FROM track_locations tl JOIN PlaylistTracks pt ON tl.id = pt.track_id;"
    foreach ($track in $tracks) {
        if ($track -match "(.+)\|(.+)") {
            $id = $Matches[1]; $path = $Matches[2]
            $filename = Split-Path $path -Leaf
            if (-not (Test-Path $path)) {
                $found = Get-ChildItem -Path $newDir -Filter $filename -Recurse -File | Select-Object -First 1
                if ($found) {
                    $newPath = $found.FullName.Replace("\", "/")
                    sqlite3 $DB_PATH "PRAGMA foreign_keys = OFF; UPDATE OR IGNORE track_locations SET location = '$newPath' WHERE id = $id;"
                }
            }
        }
    }
    Write-Host "✅ Fast Playlist Relink completed successfully!" -ForegroundColor Green
}

function Relink-Library {
    Write-Host "--- 📁 Universal Relink Entire Library (Windows) ---"
    $newDir = (Read-Host "👉 Drag and drop or enter the NEW FOLDER containing all your music").Trim('"')
    if (-not (Test-Path $newDir)) { Write-Host "❌ Folder does not exist." -ForegroundColor Red; return }
    Make-Backup
    
    $tracks = sqlite3 $DB_PATH "SELECT id, location FROM track_locations;"
    foreach ($track in $tracks) {
        if ($track -match "(.+)\|(.+)") {
            $id = $Matches[1]; $path = $Matches[2]
            $filename = Split-Path $path -Leaf
            if (-not (Test-Path $path)) {
                $found = Get-ChildItem -Path $newDir -Filter $filename -Recurse -File | Select-Object -First 1
                if ($found) {
                    $newPath = $found.FullName.Replace("\", "/")
                    sqlite3 $DB_PATH "PRAGMA foreign_keys = OFF; UPDATE OR IGNORE track_locations SET location = '$newPath' WHERE id = $id;"
                }
            }
        }
    }
    Write-Host "✅ Universal Library Relink completed successfully!" -ForegroundColor Green
}

function Clean-Library {
    Write-Host "--- 🧹 Clean Missing Tracks & VACUUM (Windows) ---"
    Make-Backup
    $tracks = sqlite3 $DB_PATH "SELECT id, location FROM track_locations;"
    $toDelete = @()
    foreach ($track in $tracks) {
        if ($track -match "(.+)\|(.+)") {
            $id = $Matches[1]; $path = $Matches[2]
            if (-not (Test-Path $path)) { 
                Write-Host "❌ Missing from disk: $path" -ForegroundColor Red
                $toDelete += $id 
            }
        }
    }
    if ($toDelete.Count -gt 0) {
        Write-Host "--------------------------------------------------"
        $confirm = Read-Host "⚠️  Delete $($toDelete.Count) ghost records from database? [y/N]"
        if ($confirm -eq 'y' -or $confirm -eq 'Y') {
            $ids = $toDelete -join ","
            sqlite3 $DB_PATH "PRAGMA foreign_keys = OFF; DELETE FROM track_locations WHERE id IN ($ids); DELETE FROM library WHERE id NOT IN (SELECT id FROM track_locations); DELETE FROM PlaylistTracks WHERE track_id NOT IN (SELECT id FROM track_locations); PRAGMA foreign_keys = ON; VACUUM;"
            Write-Host "🎉 Database cleaned and compressed successfully!" -ForegroundColor Green
        }
    } else {
        Write-Host "✨ Library is clean! No missing files found." -ForegroundColor Green
    }
}

function Export-Playlists {
    Write-Host "--- 🎶 Export Playlists to M3U8 (Windows) ---"
    $outDir = "$DESKTOP\mixxx_playlists_windows"
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    
    $playlists = sqlite3 $DB_PATH "SELECT name FROM Playlists;"
    foreach ($playlist in $playlists) {
        if ($playlist) {
            $outFile = "$outDir\$playlist.m3u8"
            "#EXTM3U" | Out-File -FilePath $outFile -Encoding utf8
            $paths = sqlite3 $DB_PATH "SELECT tl.location FROM Playlists p JOIN PlaylistTracks pt ON p.id = pt.playlist_id JOIN track_locations tl ON pt.track_id = tl.id WHERE p.name=""$playlist"" ORDER BY pt.position;"
            foreach ($path in $paths) {
                if ($path) {
                    $winPath = $path.Replace("/", "\")
                    $winPath | Out-File -FilePath $outFile -Append -Encoding utf8
                }
            }
            Write-Host "📤 Exported: $playlist.m3u8" -ForegroundColor Cyan
        }
    }
    Write-Host "✅ Playlists exported to 'mixxx_playlists_windows' folder on your Desktop!" -ForegroundColor Green
}

while ($true) {
    Write-Host "`n==========================================================" -ForegroundColor Yellow
    Write-Host "          MIXXX LIBRARY TOOLKIT v4.0 (WINDOWS)            " -ForegroundColor Yellow
    Write-Host "==========================================================" -ForegroundColor Yellow
    Write-Host "1) ⚡ Fast Relink PLAYLISTS"
    Write-Host "2) 📁 Universal Relink LIBRARY"
    Write-Host "3) 🧹 Clean Missing Tracks & VACUUM"
    Write-Host "4) 🎶 Export Playlists to M3U8"
    Write-Host "5) 💾 Quick Backup"
    Write-Host "6) ❌ Exit"
    $choice = Read-Host "Please select an action [1-6]"
    switch ($choice) {
        "1" { Relink-Playlists }
        "2" { Relink-Library }
        "3" { Clean-Library }
        "4" { Export-Playlists }
        "5" { Make-Backup }
        "6" { Write-Host "Goodbye!"; exit }
        default { Write-Host "❌ Invalid option. Please try again." -ForegroundColor Red }
    }
}