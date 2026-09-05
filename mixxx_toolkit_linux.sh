#!/bin/bash

DB_PATH=""
KNOWN_DB_LOCATIONS=(
    "$HOME/.local/share/mixxx/mixxxdb.sqlite"                              # Native install (modern XDG)
    "$HOME/.mixxx/mixxxdb.sqlite"                                          # Native install (legacy)
    "$HOME/.var/app/org.mixxx.Mixxx/.mixxx/mixxxdb.sqlite"                 # Flatpak (legacy home)
    "$HOME/.var/app/org.mixxx.Mixxx/data/mixxx/mixxxdb.sqlite"             # Flatpak (modern XDG data)
    "$HOME/.var/app/org.mixxx.Mixxx/.local/share/mixxx/mixxxdb.sqlite"     # Flatpak (XDG)
    "$HOME/snap/mixxx/current/.mixxx/mixxxdb.sqlite"                       # Snap (legacy)
    "$HOME/snap/mixxx/current/.local/share/mixxx/mixxxdb.sqlite"           # Snap (modern XDG)
)

find_db() {
    if [ -n "$1" ] && [ -f "$1" ]; then
        DB_PATH="$1"
        echo "📂 Using database from argument: $DB_PATH"
        return 0
    fi
    if [ -n "$MIXXX_DB" ] && [ -f "$MIXXX_DB" ]; then
        DB_PATH="$MIXXX_DB"
        echo "📂 Using database from MIXXX_DB: $DB_PATH"
        return 0
    fi
    found=()
    for db in "${KNOWN_DB_LOCATIONS[@]}"; do
        [ -f "$db" ] && found+=("$db")
    done
    case ${#found[@]} in
        0)
            echo "❌ mixxxdb.sqlite not found in any known location."
            echo "   Pass it as an argument: $0 /path/to/mixxxdb.sqlite"
            echo "   or set the MIXXX_DB environment variable."
            exit 1
            ;;
        1)
            DB_PATH="${found[0]}"
            echo "📂 Found database: $DB_PATH"
            return 0
            ;;
        *)
            echo "❓ Multiple Mixxx databases found — which one does your Mixxx actually use?"
            i=1
            for db in "${found[@]}"; do
                size=$(stat -c %s "$db")
                size_h=$(numfmt --to=iec "$size" 2>/dev/null || echo "$size bytes")
                mtime=$(stat -c '%.19y' "$db" | cut -d' ' -f1-2)
                desc=""
                case "$db" in
                    *"/org.mixxx.Mixxx/.mixxx/"*) desc="Flatpak install (legacy .mixxx)" ;;
                    *"/org.mixxx.Mixxx/data/"*) desc="Flatpak install" ;;
                    *"/org.mixxx.Mixxx/.local/share/"*) desc="Flatpak install (XDG)" ;;
                    *"/snap/"*) desc="Snap install" ;;
                    *"/.local/share/"*) desc="Native install" ;;
                    *"/.mixxx/"*) desc="Native install (legacy)" ;;
                esac
                printf '  %d) %s  (%s, modified %s)  — %s\n' "$i" "$db" "$size_h" "$mtime" "${desc:-unknown}"
                i=$((i + 1))
            done
            read -p "  Choose 1-${#found[@]} [1]: " pick
            pick=${pick:-1}
            if [[ "$pick" =~ ^[0-9]+$ ]] && [ "$pick" -ge 1 ] && [ "$pick" -le "${#found[@]}" ]; then
                DB_PATH="${found[$((pick - 1))]}"
                echo "📂 Using database: $DB_PATH"
                return 0
            else
                echo "❌ Invalid choice."
                exit 1
            fi
            ;;
    esac
}

find_db "$1"

make_backup() {
    if [ ! -f "$DB_PATH" ]; then return 1; fi
    CURRENT_DATE=$(date +"%Y%m%d_%H%M%S")
    cp "$DB_PATH" "$HOME/mixxxdb_backup_${CURRENT_DATE}.sqlite"
    echo "🔒 Backup created: mixxxdb_backup_${CURRENT_DATE}.sqlite"
    return 0
}

ask_old_root() {
    hint=$(sqlite3 "$DB_PATH" "SELECT location FROM track_locations WHERE substr(location,1,1)='/' LIMIT 3000;" \
        | while read -r p; do dirname "$p"; done \
        | awk -F/ '{
            if (NR==1) { n=NF; for (i=2;i<=NF;i++) pre[i]=$i }
            else {
                if (NF<n) n=NF
                for (i=2;i<=n;i++) if (pre[i] != $i) { n=i-1; break }
            }
            if (n<=1) exit
          }
          END { s=""; if (n>1) for (i=2;i<=n;i++) s=s "/" pre[i]; print s }')
    if [ -n "$hint" ]; then
        sample_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM (SELECT location FROM track_locations WHERE location LIKE '$hint/%' LIMIT 3000);")
        ext=$(sqlite3 "$DB_PATH" "SELECT location FROM track_locations WHERE location LIKE '$hint/%' LIMIT 3000;" \
            | awk -v p="$hint/" 'index($0,p)==1{sub(p,""); split($0,a,"/"); if (a[1]!="") print a[1]}' \
            | sort | uniq -c | sort -rn | head -n1)
        ext_freq=$(echo "$ext" | awk '{print $1}')
        ext_name=$(echo "$ext" | awk '{print $2}')
        if [ -n "$ext_name" ] && [ "$ext_freq" -ge $((sample_count * 7 / 10)) ] 2>/dev/null; then
            hint="$hint/$ext_name"
        fi
    fi
    if [ -n "$hint" ]; then
        read -p "👴 OLD ROOT the DB paths start with [Enter = $hint, or 'skip' = filename-only]: " OLD_ROOT
        if [ -z "$OLD_ROOT" ]; then OLD_ROOT="$hint"; fi
    else
        read -p "👴 OLD ROOT the DB paths start with (or 'skip' = filename-only): " OLD_ROOT
    fi
    if [ "$OLD_ROOT" = "skip" ]; then OLD_ROOT=""; fi
    OLD_ROOT="${OLD_ROOT%/}"
}

check_pairing() {
    [ -n "$OLD_ROOT" ] || return 0
    try=0; ok=0
    while read -r p; do
        case "$p" in
            "$OLD_ROOT"/*)
                rel="${p#"$OLD_ROOT"/}"
                if [ -f "$NEW_DIR/$rel" ]; then ok=$((ok + 1)); fi
                try=$((try + 1))
                ;;
        esac
        [ "$try" -ge 20 ] && break
    done < <(sqlite3 "$DB_PATH" "SELECT location FROM track_locations WHERE location LIKE '$OLD_ROOT/%' LIMIT 100;")
    if [ "$try" -ge 5 ] && [ "$ok" -eq 0 ]; then
        echo "⚠️  Pairing check: none of $try sample paths exist via structure."
        echo "   Old root and new folder must pair as prefixes, e.g.:"
        echo "   $OLD_ROOT/Album/track.mp3  →  $NEW_DIR/Album/track.mp3"
        echo "   If your new folder is $NEW_DIR, the old root should usually end in the same folder name (e.g. .../Music)."
        echo ""
    fi
}

relink_tracks() {
    local select_sql="$1" count_sql="$2" label="$3"
    local tmp sqlfile total current match_count apply_status apply_out
    local track_id track_path filename found_path rel
    local structure_hit=0 basename_hit=0

    total=$(sqlite3 "$DB_PATH" "$count_sql")

    check_pairing

    echo "🗂️  Indexing filenames in $NEW_DIR (single pass)..."
    declare -A name_index
    while IFS= read -r -d '' p; do
        b=${p##*/}
        if [ -z "${name_index[$b]:-}" ]; then
            name_index["$b"]="$p"
        fi
    done < <(find "$NEW_DIR" -type f -print0)
    echo "   Indexed ${#name_index[@]} unique filenames."

    tmp=$(mktemp)
    current=0
    while IFS='|' read -r track_id track_path; do
        current=$((current + 1))
        if [ $((current % 500)) -eq 0 ] || [ "$current" -eq 1 ]; then
            printf '\r\033[K🔍 Scanning %d / %d tracks...' "$current" "$total" >&2
        fi

        if [ -n "$OLD_ROOT" ] && [[ "$track_path" == "$OLD_ROOT"/* ]]; then
            rel="${track_path#"$OLD_ROOT"/}"
            if [ -f "$NEW_DIR/$rel" ]; then
                printf '%s|%s\n' "$track_id" "$NEW_DIR/$rel"
                structure_hit=$((structure_hit + 1))
                continue
            fi
        fi

        if [ ! -f "$track_path" ]; then
            filename=${track_path##*/}
            found_path=${name_index["$filename"]:-}
            if [ -n "$found_path" ]; then
                printf '%s|%s\n' "$track_id" "$found_path"
                basename_hit=$((basename_hit + 1))
            fi
        fi
    done < <(sqlite3 "$DB_PATH" "$select_sql") > "$tmp"
    printf '\r\033[K' >&2

    match_count=$(wc -l < "$tmp")
    if [ "$match_count" -eq 0 ]; then
        rm -f "$tmp"
        echo "⚠️  No matches found. Check the new folder and the old root you entered."
        return
    fi
    echo "✅ Matches: $match_count / $total (structure: $structure_hit, by filename: $basename_hit). Applying..."

    sqlfile=$(mktemp)
    {
        echo ".bail on"
        echo "PRAGMA foreign_keys = OFF;"
        echo "PRAGMA busy_timeout = 10000;"
        echo "BEGIN IMMEDIATE;"
        echo "CREATE TEMP TABLE relink_targets(id INTEGER PRIMARY KEY, new_loc TEXT);"
        while IFS='|' read -r track_id found_path; do
            escaped_path="${found_path//\'/\'\'}"
            printf "INSERT INTO relink_targets VALUES (%s, '%s');\n" "$track_id" "$escaped_path"
        done < "$tmp"
        echo "UPDATE OR IGNORE track_locations SET location = (SELECT rt.new_loc FROM relink_targets rt WHERE rt.id = track_locations.id) WHERE id IN (SELECT id FROM relink_targets);"
        echo "SELECT changes();"
        echo "DROP TABLE relink_targets;"
        echo "COMMIT;"
    } > "$sqlfile"

    apply_out=$(sqlite3 "$DB_PATH" < "$sqlfile")
    apply_status=$?
    rm -f "$sqlfile" "$tmp"

    if [ "$apply_status" -ne 0 ]; then
        echo "❌ Error applying updates (sqlite3 exit $apply_status). Nothing was committed."
    else
        relinked=$(printf '%s\n' "$apply_out" | tail -n1)
        echo "✅ $label: $relinked tracks relinked."
    fi
}

relink_only_playlists() {
    echo "--- ⚡ Fast Relink PLAYLISTS (Linux) ---"
    echo "👉 Drag and drop or enter the NEW FOLDER containing your playlist tracks:"
    read -r NEW_DIR
    if [ ! -d "$NEW_DIR" ]; then echo "❌ Folder does not exist."; return; fi
    ask_old_root
    make_backup
    relink_tracks \
        "SELECT DISTINCT tl.id, tl.location FROM track_locations tl JOIN PlaylistTracks pt ON tl.id = pt.track_id;" \
        "SELECT COUNT(DISTINCT tl.id) FROM track_locations tl JOIN PlaylistTracks pt ON tl.id = pt.track_id;" \
        "Fast Playlist Relink"
}

relink_all_library() {
    echo "--- 📁 Universal Relink Entire Library (Linux) ---"
    echo "👉 Drag and drop or enter the NEW FOLDER containing all your music:"
    read -r NEW_DIR
    if [ ! -d "$NEW_DIR" ]; then echo "❌ Folder does not exist."; return; fi
    ask_old_root
    make_backup
    relink_tracks \
        "SELECT id, location FROM track_locations;" \
        "SELECT COUNT(*) FROM track_locations;" \
        "Universal Library Relink"
}

clean_library() {
    echo "--- 🧹 Clean Missing Tracks & VACUUM (Linux) ---"
    total=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM track_locations;")
    ids_to_delete=()
    while IFS='|' read -r track_id track_path; do
        if [ ! -f "$track_path" ]; then
            echo "❌ Missing from disk: $track_path"
            ids_to_delete+=("$track_id")
        fi
    done < <(sqlite3 "$DB_PATH" "SELECT id, location FROM track_locations;")

    missing=${#ids_to_delete[@]}
    if [ "$missing" -eq 0 ]; then
        echo "✨ Library is clean! No missing files found."
        return
    fi
    if [ "$total" -gt 0 ]; then pct=$((missing * 100 / total)); else pct=100; fi
    echo "--------------------------------------------------"
    echo "⚠️  $missing of $total paths are missing ($pct% of your library)."
    if [ "$pct" -ge 25 ]; then
        echo "   That is a LOT of missing files. Did you relink the library first (option 2)?"
        echo "   If the files were MOVED (not deleted), cleaning now will permanently erase"
        echo "   them from Mixxx: playlists, cues, ratings, play counts and history."
        echo "   Mixxx's own 'Purge deleted tracks' is safer; this option HARD-deletes records."
    fi
    read -p "🗑️  Hard-delete these $missing records? Type 'yes': " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Aborted. No changes made."
        return
    fi
    make_backup
    comma_separated_ids=$(IFS=,; echo "${ids_to_delete[*]}")
    sqlite3 "$DB_PATH" <<EOF
PRAGMA foreign_keys = OFF;
DELETE FROM cues WHERE track_id IN ($comma_separated_ids);
DELETE FROM crate_tracks WHERE track_id IN ($comma_separated_ids);
DELETE FROM PlaylistTracks WHERE track_id IN ($comma_separated_ids);
DELETE FROM library WHERE id IN ($comma_separated_ids);
DELETE FROM track_locations WHERE id IN ($comma_separated_ids);
VACUUM;
EOF
    echo "🎉 Database cleaned and compressed successfully!"
}

export_playlists_m3u8() {
    echo "--- 🎶 Export Playlists to M3U8 (Linux) ---"
    if command -v xdg-user-dir >/dev/null 2>&1; then
        DESKTOP_DIR=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")
    else
        DESKTOP_DIR="$HOME/Desktop"
    fi
    OUTPUT_DIR="${DESKTOP_DIR:-$HOME/Desktop}/mixxx_playlists_linux"
    mkdir -p "$OUTPUT_DIR"
    sqlite3 "$DB_PATH" "SELECT name FROM Playlists;" | while read -r playlist; do
        if [ -n "$playlist" ]; then
            safe_name=$(printf '%s' "$playlist" | tr '/\\' '--')
            echo "#EXTM3U" > "$OUTPUT_DIR/${safe_name}.m3u8"
            sqlite3 "$DB_PATH" "SELECT tl.location FROM Playlists p JOIN PlaylistTracks pt ON p.id = pt.playlist_id JOIN track_locations tl ON pt.track_id = tl.id WHERE p.name=\"${playlist//\"/\"\"}\" ORDER BY pt.position;" >> "$OUTPUT_DIR/${safe_name}.m3u8"
            echo "📤 Exported: ${safe_name}.m3u8"
        fi
    done
    echo "✅ Playlists exported to 'mixxx_playlists_linux' folder on your Desktop!"
}

while true; do
    echo "=========================================================="
    echo "                MIXXX LIBRARY TOOLKIT                     "
    echo "=========================================================="
    echo "1) ⚡ Fast Relink PLAYLISTS"
    echo "2) 📁 Universal Relink LIBRARY"
    echo "3) 🧹 Clean Missing Tracks & VACUUM"
    echo "4) 🎶 Export Playlists to M3U8"
    echo "5) 💾 Quick Backup"
    echo "6) ❌ Exit"
    read -p "Please select an action [1-6]: " choice
    case $choice in
        1) relink_only_playlists ;;
        2) relink_all_library ;;
        3) clean_library ;;
        4) export_playlists_m3u8 ;;
        5) make_backup ;;
        6) echo "Goodbye!"; exit 0 ;;
        *) echo "❌ Invalid option. Please try again." ;;
    esac
done