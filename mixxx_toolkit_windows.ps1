[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$DB_PATH = "$env:USERPROFILE\AppData\Local\Mixxx\mixxxdb.sqlite"
$DESKTOP = "$env:USERPROFILE\Desktop"

$fso = New-Object -ComObject Scripting.FileSystemObject

function Make-Backup {
    if ($fso.FileExists($DB_PATH)) {
        $date = Get-Date -Format "yyyyMMdd_HHmmss"
        $backupPath = "$DESKTOP\mixxxdb_backup_$date.sqlite"
        Copy-Item -LiteralPath $DB_PATH -Destination $backupPath -Force
        Write-Host "🔒 Backup created on Desktop!" -ForegroundColor Green
    }
}

function Relink-Playlists {
    Write-Host "--- ⚡ Fast Relink PLAYLISTS (Windows) ---"
    $newDir = (Read-Host "👉 Drag and drop or enter the NEW FOLDER containing your playlist tracks").Trim('"')
    if (-not ($fso.FolderExists($newDir))) { Write-Host "❌ Folder does not exist." -ForegroundColor Red; return }
    Make-Backup
    
    $querySelect = "SELECT DISTINCT tl.id, tl.location FROM track_locations tl JOIN PlaylistTracks pt ON tl.id = pt.track_id;"
    $tracks = sqlite3 $DB_PATH $querySelect
    
    foreach ($track in $tracks) {
        if ($track -match "(.+)\|(.+)") {
            $id = $Matches[1]; $path = $Matches[2]
            $filename = Split-Path $path -Leaf
            $winPath = $path.Replace("/", "\")
            if (-not ($fso.FileExists($winPath))) {
                $found = Get-ChildItem -Path $newDir -Filter $filename -Recurse -File | Select-Object -First 1
                if ($found) {
                    $newPath = $found.FullName.Replace("\", "/")
                    $queryUpdate = "PRAGMA foreign_keys = OFF; UPDATE OR IGNORE track_locations SET location = '$newPath' WHERE id = $id;"
                    sqlite3 $DB_PATH $queryUpdate
                }
            }
        }
    }
    Write-Host "✅ Fast Playlist Relink completed successfully!" -ForegroundColor Green
}

function Relink-Library {
    Write-Host "--- 📁 Universal Relink Entire Library (Windows) ---"
    $newDir = (Read-Host "👉 Drag and drop or enter the NEW FOLDER containing all your music").Trim('"')
    if (-not ($fso.FolderExists($newDir))) { Write-Host "❌ Folder does not exist." -ForegroundColor Red; return }
    Make-Backup
    
    $querySelect = "SELECT id, location FROM track_locations;"
    $tracks = sqlite3 $DB_PATH $querySelect
    
    foreach ($track in $tracks) {
        if ($track -match "(.+)\|(.+)") {
            $id = $Matches[1]; $path = $Matches[2]
            $filename = Split-Path $path -Leaf
            $winPath = $path.Replace("/", "\")
            if (-not ($fso.FileExists($winPath))) {
                $found = Get-ChildItem -Path $newDir -Filter $filename -Recurse -File | Select-Object -First 1
                if ($found) {
                    $newPath = $found.FullName.Replace("\", "/")
                    $queryUpdate = "PRAGMA foreign_keys = OFF; UPDATE OR IGNORE track_locations SET location = '$newPath' WHERE id = $id;"
                    sqlite3 $DB_PATH $queryUpdate
                }
            }
        }
    }
    Write-Host "✅ Universal Library Relink completed successfully!" -ForegroundColor Green
}

function Clean-Library {
    Write-Host "--- 🧹 Clean Missing Tracks & VACUUM (Windows) ---"
    Make-Backup
    
    $querySelect = "SELECT id, location FROM track_locations;"
    $tracks = sqlite3 $DB_PATH $querySelect
    $toDelete = @()
    
    foreach ($track in $tracks) {
        if ($track -match "(.+)\|(.+)") {
            $id = $Matches[1]; $path = $Matches[2]
            $winPath = $path.Replace("/", "\")
            
            if (-not ($fso.FileExists($winPath))) { 
                $filename = Split-Path $winPath -Leaf
                $parentDir = Split-Path $winPath -Parent
                
                # ΕΛΕΓΧΟΣ: Περιέχει το όνομα χαρακτήρες εκτός ASCII (τόνους, ñ, ελληνικά, κλπ.);
                # Το [^\x00-\x7F] πιάνει τα πάντα εκτός από απλά αγγλικά γράμματα/νούμερα
                $hasSpecialChars = $filename -match "[^\x00-\x7F]"
                
                if ($hasSpecialChars -and ($fso.FolderExists($parentDir))) {
                    # Παίρνουμε τους πρώτους 4 χαρακτήρες (π.χ. "09.Ο") για να κάνουμε match στον φάκελο
                    $prefix = if ($filename.Length -gt 4) { $filename.Substring(0, 4) } else { $filename }
                    $fileExistsUnderAlternativeName = $false
                    
                    $files = Get-ChildItem -LiteralPath $parentDir -File
                    foreach ($f in $files) {
                        # Αν στον φάκελο υπάρχει αρχείο με το ίδιο track number/ξεκίνημα, το θεωρούμε False Positive
                        if ($f.Name.StartsWith($prefix)) {
                            $fileExistsUnderAlternativeName = $true
                            break
                        }
                    }
                    
                    if ($fileExistsUnderAlternativeName) {
                        Write-Host "✨ Safe Match (Unicode/Tone issue bypassed): $filename" -ForegroundColor Cyan
                        continue # Το σώζουμε, δεν πάει για διαγραφή!
                    }
                }
                
                Write-Host "❌ Missing from disk: $winPath" -ForegroundColor Red
                $toDelete += $id 
            }
        }
    }
    if ($toDelete.Count -gt 0) {
        Write-Host "--------------------------------------------------"
        $confirm = Read-Host "⚠️  Delete $($toDelete.Count) ghost records from database? [y/N]"
        if ($confirm -eq 'y' -or $confirm -eq 'Y') {
            $ids = $toDelete -join ","
            $queryClean = "PRAGMA foreign_keys = OFF; DELETE FROM track_locations WHERE id IN ($ids); DELETE FROM library WHERE id NOT IN (SELECT id FROM track_locations); DELETE FROM PlaylistTracks WHERE track_id NOT IN (SELECT id FROM track_locations); PRAGMA foreign_keys = ON; REINDEX; VACUUM;"
            sqlite3 $DB_PATH $queryClean
            Write-Host "🎉 Database cleaned, reindexed and compressed successfully!" -ForegroundColor Green
        }
    } else {
        Write-Host "✨ Library is clean! No missing files found." -ForegroundColor Green
    }
}

function Export-Playlists {
    Write-Host "--- 🎶 Export Playlists to M3U8 (Hybrid Fix) ---"
    $outDir = "$DESKTOP\mixxx_playlists_windows"
    
    if (-not ($fso.FolderExists($outDir))) {
        New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    }
    
    # 1. Παίρνουμε τα ονόματα των playlists σε καθαρό string array
    $playlists = sqlite3 $DB_PATH "SELECT name FROM Playlists;"
    $utf8NoBOM = New-Object System.Text.UTF8Encoding($false)
    
    foreach ($playlist in $playlists) {
        if ($playlist) {
            $safePlaylistName = $playlist -replace '[\\/:*?"<>|]', '_'
            $outFile = "$outDir\$safePlaylistName.m3u8"
            
            # Προετοιμασία της λίστας εγγραφής
            $m3uLines = [System.Collections.Generic.List[string]]::new()
            $m3uLines.Add("#EXTM3U")
            
            # 2. Τρέχουμε το query περνώντας τις ρυθμίσεις της SQLite απευθείας με -cmd (Χωρίς αρχεία!)
            $query = "SELECT tl.location FROM Playlists p JOIN PlaylistTracks pt ON p.id = pt.playlist_id JOIN track_locations tl ON pt.track_id = tl.id WHERE p.name='$playlist' ORDER BY pt.position;"
            $rawPaths = sqlite3 -cmd ".headers off" -cmd ".mode list" $DB_PATH $query
            
            foreach ($path in $rawPaths) {
                if ($path) {
                    # Μετατροπή slashes σε Windows style (\)
                    $winPath = $path.Replace("/", "\")
                    
                    # Εξαναγκασμός σε Normalization Form C για να ενωθεί ο "σπασμένος" τόνος (NFD -> NFC)
                    # Αυτό θα μετατρέψει το "i" + "╠ü" στο κανονικό "í" που καταλαβαίνει το Notepad!
                    $normalizedPath = $winPath.Normalize([System.Text.NormalizationForm]::FormC)
                    
                    # Επιπλέον ασφάλεια: Αν για οποιοδήποτε λόγο η κονσόλα κράτησε τα ωμά raw bytes του Mojibake
                    $cleanPath = $normalizedPath `
                        -replace "i╠ü", "í" `
                        -replace "o╠ü", "ó" `
                        -replace "a╠ü", "á" `
                        -replace "e╠ü", "é" `
                        -replace "u╠ü", "ú" `
                        -replace "n╠â", "ñ" `
                        -replace "I╠ü", "Í" `
                        -replace "A╠ü", "Á"

                    $m3uLines.Add($cleanPath)
                }
            }
            
            # 3. Γράφουμε το αρχείο σε 100% καθαρό UTF-8 ΧΩΡΙΣ BOM
            [System.IO.File]::WriteAllLines($outFile, $m3uLines, $utf8NoBOM)
            Write-Host "📤 Exported: $safePlaylistName.m3u8 (Clean UTF-8)" -ForegroundColor Cyan
        }
    }
    Write-Host "`n✅ All playlists exported flawlessly to 'mixxx_playlists_windows' on your Desktop!" -ForegroundColor Green
}

while ($true) {
    Write-Host "`n==========================================================" -ForegroundColor Yellow
    Write-Host "            MIXXX LIBRARY TOOLKIT    (WINDOWS)            " -ForegroundColor Yellow
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
