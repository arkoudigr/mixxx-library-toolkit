#!/bin/bash

DB_PATH="$HOME/.local/share/mixxx/mixxxdb.sqlite"

make_backup() {
    if [ ! -f "$DB_PATH" ]; then return 1; fi
    CURRENT_DATE=$(date +"%Y%m%d_%H%M%S")
    cp "$DB_PATH" "$HOME/mixxxdb_backup_${CURRENT_DATE}.sqlite"
    echo "🔒 Backup created: mixxxdb_backup_${CURRENT_DATE}.sqlite"
    return 0
}

relink_only_playlists() {
    echo "--- ⚡ Fast Relink PLAYLISTS (Linux) ---"
    echo "👉 Drag and drop or enter the NEW FOLDER containing your playlist tracks:"
    read -r NEW_DIR
    if [ ! -d "$NEW_DIR" ]; then echo "❌ Folder does not exist."; return; fi
    make_backup
    sqlite3 "$DB_PATH" "SELECT DISTINCT tl.id, tl.location FROM track_locations tl JOIN PlaylistTracks pt ON tl.id = pt.track_id;" | while read -r line; do
        track_id=$(echo "$line" | cut -d'|' -f1)
        track_path=$(echo "$line" | cut -d'|' -f2)
        filename=$(basename "$track_path")
        if [ ! -f "$track_path" ]; then
            found_path=$(find "$NEW_DIR" -type f -name "$filename" -print -quit)
            if [ -n "$found_path" ]; then
                sqlite3 "$DB_PATH" "PRAGMA foreign_keys = OFF; UPDATE OR IGNORE track_locations SET location = '$found_path' WHERE id = $track_id;"
            fi
        fi
    done
    echo "✅ Fast Playlist Relink completed successfully!"
}

relink_all_library() {
    echo "--- 📁 Universal Relink Entire Library (Linux) ---"
    echo "👉 Drag and drop or enter the NEW FOLDER containing all your music:"
    read -r NEW_DIR
    if [ ! -d "$NEW_DIR" ]; then echo "❌ Folder does not exist."; return; fi
    make_backup
    sqlite3 "$DB_PATH" "SELECT id, location FROM track_locations;" | while read -r line; do
        track_id=$(echo "$line" | cut -d'|' -f1)
        track_path=$(echo "$line" | cut -d'|' -f2)
        filename=$(basename "$track_path")
        if [ ! -f "$track_path" ]; then
            found_path=$(find "$NEW_DIR" -type f -name "$filename" -print -quit)
            if [ -n "$found_path" ]; then
                sqlite3 "$DB_PATH" "PRAGMA foreign_keys = OFF; UPDATE OR IGNORE track_locations SET location = '$found_path' WHERE id = $track_id;"
            fi
        fi
    done
    echo "✅ Universal Library Relink completed successfully!"
}

clean_library() {
    echo "--- 🧹 Clean Missing Tracks & VACUUM (Linux) ---"
    make_backup
    ids_to_delete=()
    while read -r line; do
        track_id=$(echo "$line" | cut -d'|' -f1)
        track_path=$(echo "$line" | cut -d'|' -f2)
        if [ ! -f "$track_path" ]; then 
            echo "❌ Missing from disk: $track_path"
            ids_to_delete+=("$track_id")
        fi
    done < <(sqlite3 "$DB_PATH" "SELECT id, location FROM track_locations;")

    if [ ${#ids_to_delete[@]} -gt 0 ]; then
        echo "--------------------------------------------------"
        read -p "⚠️  Delete ${#ids_to_delete[@]} ghost records from database? [y/N]: " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            comma_separated_ids=$(IFS=,; echo "${ids_to_delete[*]}")
            sqlite3 "$DB_PATH" <<EOF
PRAGMA foreign_keys = OFF;
DELETE FROM track_locations WHERE id IN ($comma_separated_ids);
DELETE FROM library WHERE id NOT IN (SELECT id FROM track_locations);
DELETE FROM PlaylistTracks WHERE track_id NOT IN (SELECT id FROM track_locations);
PRAGMA foreign_keys = ON;
VACUUM;
EOF
            echo "🎉 Database cleaned and compressed successfully!"
        fi
    else
        echo "✨ Library is clean! No missing files found."
    fi
}

export_playlists_m3u8() {
    echo "--- 🎶 Export Playlists to M3U8 (Linux) ---"
    OUTPUT_DIR="$HOME/Desktop/mixxx_playlists_linux"
    mkdir -p "$OUTPUT_DIR"
    playlists=$(sqlite3 "$DB_PATH" "SELECT name FROM Playlists;")
    echo "$playlists" | while read -r playlist; do
        if [ -n "$playlist" ]; then
            echo "#EXTM3U" > "$OUTPUT_DIR/${playlist}.m3u8"
            sqlite3 "$DB_PATH" "SELECT tl.location FROM Playlists p JOIN PlaylistTracks pt ON p.id = pt.playlist_id JOIN track_locations tl ON pt.track_id = tl.id WHERE p.name=\"${playlist}\" ORDER BY pt.position;" >> "$OUTPUT_DIR/${playlist}.m3u8"
            echo "📤 Exported: ${playlist}.m3u8"
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