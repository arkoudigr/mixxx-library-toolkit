#!/bin/bash

# Global database localization (Normal & Sandbox)
PATH_NORMAL="$HOME/Library/Application Support/Mixxx/mixxxdb.sqlite"
PATH_SANDBOX="$HOME/Library/Containers/org.mixxx.mixxx/Data/Library/Application Support/Mixxx/mixxxdb.sqlite"

if [ -f "$PATH_SANDBOX" ]; then
    DB_PATH="$PATH_SANDBOX"
elif [ -f "$PATH_NORMAL" ]; then
    DB_PATH="$PATH_NORMAL"
else
    DB_PATH=""
fi

make_backup() {
    if [ ! -f "$DB_PATH" ]; then
        echo "❌ Database not found."
        return 1
    fi
    CURRENT_DATE=$(date +"%Y%m%d_%H%M%S")
    BACKUP_FULL_PATH="$HOME/Desktop/mixxxdb_backup_${CURRENT_DATE}.sqlite"
    cp "$DB_PATH" "$BACKUP_FULL_PATH"
    echo "🔒 Automatic backup created on Desktop: mixxxdb_backup_${CURRENT_DATE}.sqlite"
    return 0
}

# ---------------------------------------------------------------------
# TOOL 1: FAST RELINK PLAYLISTS
# ---------------------------------------------------------------------
relink_only_playlists() {
    echo ""
    echo "--- ⚡ Tool: Quick Relink ONLY for Playlists ---"
    if [ -z "$DB_PATH" ]; then
        echo "👉 Drag and drop the mixxxdb.sqlite file here and press Enter:"
        read -r DB_PATH
        DB_PATH="${DB_PATH%\"}"; DB_PATH="${DB_PATH#\"}"
    fi

    echo "👉 Drag and drop the NEW FOLDER containing the playlist files:"
    read -r NEW_DIR
    NEW_DIR="${NEW_DIR%\"}"; NEW_DIR="${NEW_DIR#\"}"

    if [ ! -d "$NEW_DIR" ]; then
        echo "❌ The folder does not exist. Canceling."
        return
    fi

    make_backup
    echo "🔄 Quick scan ONLY of tracks that belong to playlists..."

    sqlite3 "$DB_PATH" "SELECT DISTINCT tl.id, tl.location FROM track_locations tl JOIN PlaylistTracks pt ON tl.id = pt.track_id;" | while read -r line; do
        if [ -n "$line" ]; then
            track_id=$(echo "$line" | cut -d'|' -f1)
            track_path=$(echo "$line" | cut -d'|' -f2)
            filename=$(basename "$track_path")

            if [ ! -f "$track_path" ]; then
                found_path=$(find "$NEW_DIR" -type f -name "$filename" -print -quit)
                if [ -n "$found_path" ]; then
                    echo "🔗 Link to playlist track: $filename"
                    sqlite3 "$DB_PATH" "PRAGMA foreign_keys = OFF; UPDATE OR IGNORE track_locations SET location = '$found_path' WHERE id = $track_id;"
                fi
            fi
        fi
    done
    echo "✅ Quick Relink of Playlists completed!"
}

# ---------------------------------------------------------------------
# TOOL 2: UNIVERSAL RELINK LIBRARY
# ---------------------------------------------------------------------
relink_all_library() {
    echo ""
    echo "--- 📁 Tool: Global Relink of the entire Library ---"
    if [ -z "$DB_PATH" ]; then
        echo "👉 Drag and drop the mixxxdb.sqlite file here and press Enter:"
        read -r DB_PATH
        DB_PATH="${DB_PATH%\"}"; DB_PATH="${DB_PATH#\"}"
    fi

    echo "👉 Drag and drop the NEW FOLDER containing the playlist files:"
    read -r NEW_DIR
    NEW_DIR="${NEW_DIR%\"}"; NEW_DIR="${NEW_DIR#\"}"

    if [ ! -d "$NEW_DIR" ]; then
        echo "❌ The folder does not exist. Canceling."
        return
    fi

    make_backup
    echo "🔄 Scanning the entire database (this will take longer)..."

    sqlite3 "$DB_PATH" "SELECT id, location FROM track_locations;" | while read -r line; do
        if [ -n "$line" ]; then
            track_id=$(echo "$line" | cut -d'|' -f1)
            track_path=$(echo "$line" | cut -d'|' -f2)
            filename=$(basename "$track_path")

            if [ ! -f "$track_path" ]; then
                found_path=$(find "$NEW_DIR" -type f -name "$filename" -print -quit)
                if [ -n "$found_path" ]; then
                    echo "🔗 Fixed: $filename"
                    sqlite3 "$DB_PATH" "PRAGMA foreign_keys = OFF; UPDATE OR IGNORE track_locations SET location = '$found_path' WHERE id = $track_id;"
                fi
            fi
        fi
    done
    echo "✅ Library Relink was successfully completed!"
}

# ---------------------------------------------------------------------
# TOOL 3: REAL MISSING TRACKS CLEANING (SCAN & DELETE)
# ---------------------------------------------------------------------
clean_library() {
    echo ""
    echo "--- 🧹 Tool: Cleaning Missing Tracks & VACUUM ---"
    if [ -z "$DB_PATH" ]; then
        echo "👉 Drag and drop the mixxxdb.sqlite file here and press Enter:"
        read -r DB_PATH
        DB_PATH="${DB_PATH%\"}"; DB_PATH="${DB_PATH#\"}"
    fi

    make_backup
    echo "⚡ Starting actual file check on disk..."
    ids_to_delete=()

    # We check if the path that the database says actually exists on your hard drive.
    while read -r line; do
        if [ -n "$line" ]; then
            track_id=$(echo "$line" | cut -d'|' -f1)
            track_path=$(echo "$line" | cut -d'|' -f2)
            
            if [ ! -f "$track_path" ]; then
                echo "❌ Missing from the hard disk: $track_path"
                ids_to_delete+=("$track_id")
            fi
        fi
    done < <(sqlite3 "$DB_PATH" "SELECT id, location FROM track_locations;")

    if [ ${#ids_to_delete[@]} -gt 0 ]; then
        echo "--------------------------------------------------"
        echo "🔎 Found ${#ids_to_delete[@]} dead records (that don't exist anywhere)."
        read -p "⚠️  Do you want me to proceed with deleting them from the database?[y/N]: " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            comma_separated_ids=$(IFS=,; echo "${ids_to_delete[*]}")
            
            sqlite3 "$DB_PATH" <<EOF
PRAGMA foreign_keys = OFF;
DELETE FROM track_locations WHERE id IN ($comma_separated_ids);
DELETE FROM library WHERE id NOT IN (SELECT id FROM track_locations);
DELETE FROM PlaylistTracks WHERE track_id NOT IN (SELECT id FROM track_locations);
DELETE FROM crate_tracks WHERE track_id NOT IN (SELECT id FROM track_locations) AND EXISTS (SELECT 1 FROM sqlite_master WHERE type='table' AND name='crate_tracks');
PRAGMA foreign_keys = ON;
VACUUM;
EOF
            echo "🎉 The library was cleaned and the base was compressed with VACUUM!"
        else
            echo "❌ The deletion was canceled."
        fi
    else
        echo "✨ All files are normally present on the disk!"
    fi
}

# ---------------------------------------------------------------------
# TOOL 4: EXPORT PLAYLISTS TO M3U8
# ---------------------------------------------------------------------
export_playlists_m3u8() {
    echo ""
    echo "--- 🎶 Tool: Export Playlists to M3U8 ---"
    if [ -z "$DB_PATH" ]; then
        echo "👉 Drag and drop the mixxxdb.sqlite file here and press Enter:"
        read -r DB_PATH
        DB_PATH="${DB_PATH%\"}"; DB_PATH="${DB_PATH#\"}"
    fi

    mkdir -p ~/Desktop/mixxx_playlists
    playlists=$(sqlite3 "$DB_PATH" "SELECT name FROM Playlists;")

    echo "$playlists" | while read -r playlist; do
        if [ -n "$playlist" ]; then
            echo "#EXTM3U" > "$HOME/Desktop/mixxx_playlists/${playlist}.m3u8"
            paths=$(sqlite3 "$DB_PATH" "SELECT track_locations.location FROM Playlists JOIN PlaylistTracks ON Playlists.id = PlaylistTracks.playlist_id JOIN track_locations ON PlaylistTracks.track_id = track_locations.id WHERE Playlists.name=\"${playlist}\" ORDER BY PlaylistTracks.position;")
            echo "$paths" | while read -r track_path; do
                if [ -n "$track_path" ]; then
                    echo "$track_path" >> "$HOME/Desktop/mixxx_playlists/${playlist}.m3u8"
                fi
            done
            echo "📤 The list was extracted: ${playlist}.m3u8"
        fi
    done
    echo "✅ The lists were saved in the 'mixxx_playlists' folder on the Desktop!"
}

# ---------------------------------------------------------------------
# MAIN APPLICATION MENU
# ---------------------------------------------------------------------
while true; do
    echo "▗▖  ▗▖▗▄▄▄▖▗▖  ▗▖▗▖  ▗▖▗▖  ▗▖    ▗▖   ▗▄▄▄▖▗▄▄▖ ▗▄▄▖  ▗▄▖ ▗▄▄▖▗▖  ▗▖    ";
    echo "▐▛▚▞▜▌  █   ▝▚▞▘  ▝▚▞▘  ▝▚▞▘     ▐▌     █  ▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌▝▚▞▘     ";
    echo "▐▌  ▐▌  █    ▐▌    ▐▌    ▐▌      ▐▌     █  ▐▛▀▚▖▐▛▀▚▖▐▛▀▜▌▐▛▀▚▖ ▐▌      ";
    echo "▐▌  ▐▌▗▄█▄▖▗▞▘▝▚▖▗▞▘▝▚▖▗▞▘▝▚▖    ▐▙▄▄▖▗▄█▄▖▐▙▄▞▘▐▌ ▐▌▐▌ ▐▌▐▌ ▐▌ ▐▌      ";
    echo "                                                                        ";
    echo "                                                                        ";
    echo "                                                                        ";
    echo "                ▗▄▄▄▖▗▄▖  ▗▄▖ ▗▖   ▗▖ ▗▖▗▄▄▄▖▗▄▄▄▖                      ";
    echo "                  █ ▐▌ ▐▌▐▌ ▐▌▐▌   ▐▌▗▞▘  █    █                        ";
    echo "                  █ ▐▌ ▐▌▐▌ ▐▌▐▌   ▐▛▚▖   █    █                        ";
    echo "                  █ ▝▚▄▞▘▝▚▄▞▘▐▙▄▄▖▐▌ ▐▌▗▄█▄▖  █                        ";
    echo "                                                                        ";
    echo "                                                                        ";
    echo "                                                                        ";
    echo "========================================================================"
    echo "                       MIXXX LIBRARY TOOLKIT                            "
    echo "========================================================================"
    if [ -n "$DB_PATH" ]; then
        echo " 🎯 Found dbase: Sandbox/Mixxx/mixxxdb.sqlite"
    else
        echo " ⚠️  No dbase was automatically detected."
    fi
    echo "========================================================================"
    echo "1) ⚡ Fast Relink PLAYLISTS (Correction of playlists ONLY)"
    echo "2) 📁 Universal Relink LIBRARY (Fix the entire library)"
    echo "3) 🧹 Clean Missing Tracks (Real Cleaning & VACUUM)"
    echo "4) 🎶 Export Playlists (Export all lists to M3U8)"
    echo "5) 💾 Quick Backup"
    echo "6) ❌ Exit"
    echo "========================================================================="
    read -p "Please select an action [1-6]: " menu_choice

    case $menu_choice in
        1) relink_only_playlists ;;
        2) relink_all_library ;;
        3) clean_library ;;
        4) export_playlists_m3u8 ;;
        5) make_backup ;;
        6) echo "Good luck with your mixes! Goodbye."; exit 0 ;;
        *) echo "❌ Invalid selection. Please try again." ;;
    esac
    echo ""
done