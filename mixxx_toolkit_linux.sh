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
    while IFS= read -r -d '' k && IFS= read -r -d '' p; do
        if [ -z "${name_index[$k]:-}" ]; then
            name_index["$k"]="$p"
        fi
    done < <(find "$NEW_DIR" -type f -print0 | python3 -c '
import sys, unicodedata
for raw in sys.stdin.buffer.read().split(b"\0"):
    if not raw: continue
    p = raw.decode("utf-8", "surrogateescape")
    b = p.rsplit("/", 1)[-1]
    sys.stdout.buffer.write((unicodedata.normalize("NFC", b) + "\0" + p + "\0").encode("utf-8", "surrogateescape"))
')
    echo "   Indexed ${#name_index[@]} unique filenames."

    tmp=$(mktemp)
    current=0
    while IFS='|' read -r track_id norm_basename track_path; do
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
            found_path=${name_index["$norm_basename"]:-}
            if [ -n "$found_path" ]; then
                printf '%s|%s\n' "$track_id" "$found_path"
                basename_hit=$((basename_hit + 1))
            fi
        fi
    done < <(sqlite3 "$DB_PATH" "$select_sql" | python3 -c '
import sys, unicodedata
for line in sys.stdin:
    line = line.rstrip("\n")
    if not line: continue
    tid, _, p = line.partition("|")
    b = p.rsplit("/", 1)[-1]
    print(tid + "|" + unicodedata.normalize("NFC", b) + "|" + p)
') > "$tmp"
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

find_moved_tracks() {
    echo "--- 🔎 Find Moved/Renamed Tracks (Linux) ---"
    echo "👉 Drag and drop or enter the folder to search for orphaned files:"
    read -r NEW_DIR
    if [ ! -d "$NEW_DIR" ]; then echo "❌ Folder does not exist."; return; fi

    orphans=$(sqlite3 "$DB_PATH" "SELECT id, location FROM track_locations WHERE location LIKE '/Users/%' AND fs_deleted = 0;")
    if [ -z "$orphans" ]; then
        echo "✨ No orphaned tracks found — nothing to relocate."
        return
    fi
    orphan_ids=()
    while IFS='|' read -r oid old_loc; do
        orphan_ids+=("$oid")
    done <<< "$orphans"
    em=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM track_locations WHERE location LIKE '/Users/%';")
    echo "   Found ${#orphan_ids[@]} orphaned tracks (of $em still pointing to macOS)."

    echo "🗂️  Indexing filenames under $NEW_DIR (single pass)..."
    declare -A fs_index
    while IFS= read -r -d '' k && IFS= read -r -d '' p; do
        if [ -z "${fs_index[$k]:-}" ]; then
            fs_index["$k"]="$p"
        fi
    done < <(find "$NEW_DIR" -type f -print0 | python3 -c '
import sys, unicodedata
for raw in sys.stdin.buffer.read().split(b"\0"):
    if not raw: continue
    p = raw.decode("utf-8", "surrogateescape")
    b = p.rsplit("/", 1)[-1]
    sys.stdout.buffer.write((unicodedata.normalize("NFC", b) + "\0" + p + "\0").encode("utf-8", "surrogateescape"))
')
    echo "   Indexed ${#fs_index[@]} unique filenames."

    tmp=$(mktemp)
    declare -A orphan_freq
    while IFS='|' read -r _ norm_basename; do
        orphan_freq["$norm_basename"]=$(( ${orphan_freq["$norm_basename"]:-0} + 1 ))
    done < <(sqlite3 "$DB_PATH" "SELECT id, location FROM track_locations WHERE location LIKE '/Users/%' AND fs_deleted = 0;" | python3 -c '
import sys, unicodedata
for line in sys.stdin:
    line = line.rstrip("\n")
    if not line: continue
    tid, _, p = line.partition("|")
    print(tid + "|" + unicodedata.normalize("NFC", p.rsplit("/", 1)[-1]))
')
    dup_skip=0
    while IFS='|' read -r oid norm_basename; do
        [ "${orphan_freq[$norm_basename]}" -gt 1 ] && continue
        found=${fs_index[$norm_basename]:-}
        if [ -n "$found" ]; then
            exists=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM track_locations WHERE location = '${found//\'/\'\'}';")
            if [ "$exists" -eq 0 ]; then
                printf '%s|%s\n' "$oid" "$found"
            else
                dup_skip=$((dup_skip + 1))
            fi
        fi
    done < <(sqlite3 "$DB_PATH" "SELECT id, location FROM track_locations WHERE location LIKE '/Users/%' AND fs_deleted = 0;" | python3 -c '
import sys, unicodedata
for line in sys.stdin:
    line = line.rstrip("\n")
    if not line: continue
    tid, _, p = line.partition("|")
    print(tid + "|" + unicodedata.normalize("NFC", p.rsplit("/", 1)[-1]))
') > "$tmp"

    match_count=$(wc -l < "$tmp")
    echo "✅ Filesystem matches by filename: $match_count / ${#orphan_ids[@]} orphans (skipped $dup_skip already-present duplicates)."
    if [ "$match_count" -eq 0 ]; then
        rm -f "$tmp"
        echo "   No files found. They may have been renamed or truly deleted."
        return
    fi

    echo "--------------------------------------------------"
    echo "Proposed re-points (unambiguous filename matches only):"
    while IFS='|' read -r oid nloc; do
        printf '  [%s] -> %s\n' "$oid" "$nloc"
    done < "$tmp"
    read -p "🗑️  Apply these $match_count re-points? Type 'yes': " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Aborted. No changes made."
        rm -f "$tmp"
        return
    fi
    make_backup

    sqlfile=$(mktemp)
    {
        echo ".bail on"
        echo "PRAGMA foreign_keys = OFF;"
        echo "PRAGMA busy_timeout = 10000;"
        echo "BEGIN IMMEDIATE;"
        echo "CREATE TEMP TABLE relink_targets(id INTEGER PRIMARY KEY, new_loc TEXT);"
        while IFS='|' read -r oid nloc; do
            escaped="${nloc//\'/\'\'}"
            printf "INSERT INTO relink_targets VALUES (%s, '%s');\n" "$oid" "$escaped"
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
        echo "✅ Find Moved/Renamed: $relinked tracks re-pointed."
    fi
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
    missing=0
    ids_to_delete=()
    while IFS='|' read -r track_id track_path; do
        if [ ! -f "$track_path" ]; then
            echo "❌ Missing from disk: $track_path"
            ids_to_delete+=("$track_id")
            missing=$((missing + 1))
        fi
    done < <(sqlite3 "$DB_PATH" "SELECT id, location FROM track_locations;")

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

    comma_separated_ids=$(IFS=,; echo "${ids_to_delete[*]}")

    merge_map=""
    if [ "$missing" -gt 0 ]; then
        merge_map=$(sqlite3 "$DB_PATH" "
            SELECT o.id || '|' || l.id
            FROM track_locations o
            JOIN track_locations l
              ON l.filename = o.filename
             AND l.location LIKE '/home/brain/%'
             AND o.filesize = l.filesize
             AND o.filesize > 0
             AND o.id <> l.id
            WHERE o.id IN ($comma_separated_ids)
            GROUP BY o.id
            HAVING COUNT(*) = 1
            UNION ALL
            SELECT o.id || '|' || l.id
            FROM track_locations o
            JOIN track_locations l
              ON l.location LIKE '/home/brain/%'
             AND o.filesize = l.filesize
             AND o.filesize > 0
             AND o.id <> l.id
             AND lower(substr(l.location,-4)) = lower(substr(o.location,-4))
            JOIN library lo ON lo.id = o.id
            JOIN library ll ON ll.id = l.id
            WHERE ABS(ll.duration - lo.duration) < 0.5
              AND o.id IN ($comma_separated_ids)
              AND o.id NOT IN (
                  SELECT o2.id FROM track_locations o2
                  JOIN track_locations l2
                    ON l2.filename = o2.filename
                   AND l2.location LIKE '/home/brain/%'
                   AND o2.filesize = l2.filesize
                   AND o2.filesize > 0
                   AND o2.id <> l2.id
                  GROUP BY o2.id
                  HAVING COUNT(*) = 1
              )
            GROUP BY o.id
            HAVING COUNT(*) = 1;")
    fi
    merge_count=0
    if [ -n "$merge_map" ]; then
        merge_count=$(printf '%s\n' "$merge_map" | wc -l)
        echo "   Of those, $merge_count are duplicates of a surviving copy (same file, possibly renamed)."
        echo "   Their cues, rating, play count and crate membership will be MERGED into the"
        echo "   surviving copy before the orphan row is removed."
    fi

    read -p "🗑️  Hard-delete these $missing records? Type 'yes': " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Aborted. No changes made."
        return
    fi
    make_backup
    sqlite3 "$DB_PATH" <<EOF
PRAGMA foreign_keys = OFF;
BEGIN IMMEDIATE;
CREATE TEMP TABLE merge_pairs(orphan_id INTEGER PRIMARY KEY, keep_id INTEGER);
$( [ -n "$merge_map" ] && printf '%s\n' "$merge_map" | while IFS='|' read -r oid kid; do printf "INSERT OR IGNORE INTO merge_pairs VALUES (%s, %s);\n" "$oid" "$kid"; done )
UPDATE cues SET track_id = (SELECT keep_id FROM merge_pairs WHERE orphan_id = cues.track_id)
  WHERE track_id IN (SELECT orphan_id FROM merge_pairs);
UPDATE track_analysis SET track_id = (SELECT keep_id FROM merge_pairs WHERE orphan_id = track_analysis.track_id)
  WHERE track_id IN (SELECT orphan_id FROM merge_pairs);
INSERT OR IGNORE INTO crate_tracks (crate_id, track_id)
  SELECT ct.crate_id, mp.keep_id FROM crate_tracks ct JOIN merge_pairs mp ON ct.track_id = mp.orphan_id;
INSERT OR IGNORE INTO PlaylistTracks (playlist_id, track_id, position, pl_datetime_added)
  SELECT pt.playlist_id, mp.keep_id, pt.position, pt.pl_datetime_added
  FROM PlaylistTracks pt JOIN merge_pairs mp ON pt.track_id = mp.orphan_id
  WHERE NOT EXISTS (SELECT 1 FROM PlaylistTracks pt2
                    WHERE pt2.playlist_id = pt.playlist_id AND pt2.track_id = mp.keep_id);
DELETE FROM cues WHERE track_id IN ($comma_separated_ids);
DELETE FROM track_analysis WHERE track_id IN ($comma_separated_ids);
DELETE FROM crate_tracks WHERE track_id IN ($comma_separated_ids);
DELETE FROM PlaylistTracks WHERE track_id IN ($comma_separated_ids);
DELETE FROM library WHERE id IN ($comma_separated_ids);
DELETE FROM track_locations WHERE id IN ($comma_separated_ids);
DROP TABLE merge_pairs;
COMMIT;
VACUUM;
EOF
    echo "🎉 Database cleaned and compressed successfully!"
    [ "$merge_count" -gt 0 ] && echo "   Merged history of $merge_count duplicates into their surviving copies."
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
    echo "6) 🔎 Find Moved/Renamed Tracks"
    echo "7) ❌ Exit"
    read -p "Please select an action [1-7]: " choice || break
    case $choice in
        1) relink_only_playlists ;;
        2) relink_all_library ;;
        3) clean_library ;;
        4) export_playlists_m3u8 ;;
        5) make_backup ;;
        6) find_moved_tracks ;;
        7) echo "Goodbye!"; exit 0 ;;
        *) echo "❌ Invalid option. Please try again." ;;
    esac
done