#!/bin/bash

# =======================================================================
#           HỆ THỐNG TỰ ĐỘNG CẬP NHẬT TOOLFB (CHO MÁY MAC / macOS)
# =======================================================================

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# Đảm bảo thư mục làm việc luôn là thư mục chứa file script này
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR" || exit 1

# Màu sắc hiển thị
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
RED='\033[0;31m'
NC='\033[0m' # Không màu

echo ""
echo -e "${CYAN}=======================================================================${NC}"
echo -e "${CYAN}           HỆ THỐNG TỰ ĐỘNG CẬP NHẬT TOOLFB (CHROME EXTENSIONS)        ${NC}"
echo -e "${CYAN}                        DÀNH CHO MACBOOK / MACOS                       ${NC}"
echo -e "${CYAN}=======================================================================${NC}"
echo ""

# -------------------------------------------------------------------------
# BƯỚC 1: LẤY THÔNG TIN ĐỊNH DANH MÁY & BẢO TOÀN 100% KHÔNG BỊ MẤT
# -------------------------------------------------------------------------
SAVED_MACHINE_ID=""
SAVED_RAW_GUID=""

SEARCH_PATHS=(
    "$DIR/device_identity.json"
    "$DIR/AutoPost/device_identity.json"
    "$DIR/Sumary/device_identity.json"
    "$DIR/PostVideo/device_identity.json"
    "$DIR/GenImage/device_identity.json"
    "$DIR/AutoPost_obfuscated/device_identity.json"
    "$DIR/Sumary_obfuscated/device_identity.json"
    "$DIR/PostVideo_obfuscated/device_identity.json"
    "$DIR/GenImage_obfuscated/device_identity.json"
    "$DIR/extension_auto_poster/device_identity.json"
    "$DIR/extension_auto_poster_obfuscated/device_identity.json"
)

# Quét thêm bất kỳ thư mục con nào có chứa device_identity.json
for subId in "$DIR"/*/device_identity.json; do
    if [ -f "$subId" ]; then
        SEARCH_PATHS+=("$subId")
    fi
done

# 1.1 Tìm mã máy đã lưu trước đó nếu có
for p in "${SEARCH_PATHS[@]}"; do
    if [ -f "$p" ]; then
        CAND_ID=$(grep -o '"machine_id"[[:space:]]*:[[:space:]]*"[^"]*"' "$p" 2>/dev/null | head -n 1 | sed -E 's/.*"machine_id"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
        CAND_GUID=$(grep -o '"raw_guid"[[:space:]]*:[[:space:]]*"[^"]*"' "$p" 2>/dev/null | head -n 1 | sed -E 's/.*"raw_guid"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
        if [[ "$CAND_ID" == PC-MAC-* ]] || [[ "$CAND_ID" == PC-WIN-* ]]; then
            SAVED_MACHINE_ID="$CAND_ID"
            SAVED_RAW_GUID="$CAND_GUID"
            break
        fi
    fi
done

# 1.2 Nếu chưa từng lưu, lấy từ Hardware UUID của MacBook (IOPlatformUUID)
if [ -z "$SAVED_MACHINE_ID" ]; then
    # Lấy qua ioreg (chuẩn phần cứng Apple Silicon M1/M2/M3/M4 và Intel Mac)
    SAVED_RAW_GUID=$(ioreg -rd1 -c IOPlatformExpertDevice 2>/dev/null | awk -F'"' '/IOPlatformUUID/ {print $4}')

    # Dự phòng 1: qua system_profiler
    if [ -z "$SAVED_RAW_GUID" ]; then
        SAVED_RAW_GUID=$(system_profiler SPHardwareDataType 2>/dev/null | awk '/Hardware UUID/ {print $3}')
    fi

    # Dự phòng 2: qua uuidgen
    if [ -z "$SAVED_RAW_GUID" ]; then
        SAVED_RAW_GUID=$(uuidgen 2>/dev/null)
    fi

    # Dự phòng 3: tạo chuỗi ngẫu nhiên
    if [ -z "$SAVED_RAW_GUID" ]; then
        SAVED_RAW_GUID=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 32)
    fi

    CLEAN=$(echo "$SAVED_RAW_GUID" | tr -cd '[:alnum:]' | tr '[:lower:]' '[:upper:]')
    while [ ${#CLEAN} -lt 12 ]; do
        CLEAN="${CLEAN}0"
    done

    P1=${CLEAN:0:4}
    P2=${CLEAN:4:4}
    P3=${CLEAN:8:4}
    SAVED_MACHINE_ID="PC-MAC-${P1}-${P2}-${P3}"
fi

# Lưu định danh vào device_identity.json (UTF-8 không BOM)
NOW=$(date +"%Y-%m-%d %H:%M:%S")
cat <<EOF > "$DIR/device_identity.json"
{
  "machine_id": "$SAVED_MACHINE_ID",
  "raw_guid": "$SAVED_RAW_GUID",
  "updated_at": "$NOW"
}
EOF

# Tự động sao chép mã máy vào Clipboard của Mac (pbcopy)
if command -v pbcopy >/dev/null 2>&1; then
    printf "%s" "$SAVED_MACHINE_ID" | pbcopy 2>/dev/null
fi

echo -e "   [*] MÃ MÁY CỦA BẠN: ${YELLOW}${SAVED_MACHINE_ID}${NC}"
echo -e "   ${GREEN}[V] ĐÃ LƯU ĐỊNH DANH MÁY VÀ COPY VÀO BỘ NHỚ TẠM (CLIPBOARD)!${NC}"
echo ""

# -------------------------------------------------------------------------
# BƯỚC 2: TẢI TẤT CẢ EXTENSION ĐƯỢC RELEASE TỪ GITHUB (NHÁNH 'release')
# -------------------------------------------------------------------------
UPDATE_SUCCESS=false
DOWNLOADED_EXTENSIONS=()

# Cách 2.1: Nếu đang trong Git repo, fetch từ nhánh release và lấy tất cả thư mục Extension
if command -v git >/dev/null 2>&1 && [ -d "$DIR/.git" ]; then
    echo -e "   ${CYAN}[*] Đang kiểm tra bản cập nhật trên Git (nhánh 'release')...${NC}"
    if git fetch origin release >/dev/null 2>&1; then
        echo -e "   ${GREEN}[V] Đã tìm thấy nhánh 'release' trên GitHub!${NC}"

        TARGET_FOLDERS=("AutoPost" "Sumary" "PostVideo" "GenImage" "AutoPost_obfuscated" "Sumary_obfuscated" "PostVideo_obfuscated" "GenImage_obfuscated")

        # Tự động quét thêm tất cả các thư mục trên nhánh origin/release
        REMOTE_DIRS=$(git ls-tree -d --name-only origin/release 2>/dev/null)
        if [ -n "$REMOTE_DIRS" ]; then
            while IFS= read -r rd; do
                rd_clean=$(echo "$rd" | tr -d '\r' | xargs)
                if [ -n "$rd_clean" ]; then
                    already_in=false
                    for existing in "${TARGET_FOLDERS[@]}"; do
                        if [ "$existing" = "$rd_clean" ]; then
                            already_in=true
                            break
                        fi
                    done
                    if [ "$already_in" = false ]; then
                        TARGET_FOLDERS+=("$rd_clean")
                    fi
                fi
            done <<< "$REMOTE_DIRS"
        fi

        FOLDERS_TO_CHECKOUT=()
        HAS_GENIMAGE=false
        for f in "${TARGET_FOLDERS[@]}"; do
            if git cat-file -e "origin/release:$f" 2>/dev/null; then
                FOLDERS_TO_CHECKOUT+=("$f")
                if [ "$f" = "GenImage" ]; then
                    HAS_GENIMAGE=true
                fi
            fi
        done

        if [ ${#FOLDERS_TO_CHECKOUT[@]} -gt 0 ] && [ "$HAS_GENIMAGE" = true ]; then
            if git checkout --force origin/release -- "${FOLDERS_TO_CHECKOUT[@]}" >/dev/null 2>&1; then
                UPDATE_SUCCESS=true
                for f in "${FOLDERS_TO_CHECKOUT[@]}"; do
                    if [[ "$f" != *_obfuscated ]] && [ -f "$DIR/$f/manifest.json" ]; then
                        DOWNLOADED_EXTENSIONS+=("$f")
                    fi
                done
                echo -e "   ${GREEN}[V] Đã đồng bộ tất cả Extension (${DOWNLOADED_EXTENSIONS[*]}) từ nhánh 'release'!${NC}"
            fi
        fi
    fi
fi

# Cách 2.2: Tải gói nén ZIP trực tiếp từ nhánh release trên GitHub (hoạt động cho mọi máy khách hàng)
if [ "$UPDATE_SUCCESS" = false ]; then
    echo -e "   ${CYAN}[*] Đang tải toàn bộ Extension mới nhất từ GitHub Release...${NC}"
    ZIP_URL="https://github.com/Minh2304/ToolFB/archive/refs/heads/release.zip"
    TEMP_DIR=$(mktemp -d 2>/dev/null || echo "/tmp/toolfb_update_$$")
    mkdir -p "$TEMP_DIR"
    TEMP_ZIP="$TEMP_DIR/ToolFB_release_update.zip"
    TEMP_EXTRACT="$TEMP_DIR/extracted"

    AUTH_HEADER=()
    if [ -n "$GITHUB_TOKEN" ]; then
        AUTH_HEADER=(-H "Authorization: token $GITHUB_TOKEN")
    fi

    if curl -fsSL --connect-timeout 20 --max-time 60 "${AUTH_HEADER[@]}" "$ZIP_URL" -o "$TEMP_ZIP" 2>/dev/null; then
        mkdir -p "$TEMP_EXTRACT"
        EXTRACT_OK=false
        if command -v unzip >/dev/null 2>&1 && unzip -q -o "$TEMP_ZIP" -d "$TEMP_EXTRACT" 2>/dev/null; then
            EXTRACT_OK=true
        elif command -v ditto >/dev/null 2>&1 && ditto -x -k "$TEMP_ZIP" "$TEMP_EXTRACT" 2>/dev/null; then
            EXTRACT_OK=true
        fi

        if [ "$EXTRACT_OK" = true ]; then
            EXTRACTED_ROOT=$(find "$TEMP_EXTRACT" -mindepth 1 -maxdepth 1 -type d | head -n 1)
            if [ -n "$EXTRACTED_ROOT" ] && [ -d "$EXTRACTED_ROOT" ]; then
                # 1. Sao chép 4 bộ công cụ chuẩn (AutoPost, Sumary, PostVideo, GenImage)
                copy_ext_pair() {
                    local ext_name="$1"
                    shift
                    local src_found=""
                    for cand in "$@"; do
                        if [ -d "$EXTRACTED_ROOT/$cand" ]; then
                            src_found="$EXTRACTED_ROOT/$cand"
                            break
                        fi
                    done
                    if [ -n "$src_found" ]; then
                        mkdir -p "$DIR/$ext_name"
                        cp -Rf "$src_found/"* "$DIR/$ext_name/" 2>/dev/null
                        if [ -d "$DIR/${ext_name}_obfuscated" ]; then
                            cp -Rf "$src_found/"* "$DIR/${ext_name}_obfuscated/" 2>/dev/null
                        fi
                    fi
                }

                copy_ext_pair "AutoPost" "AutoPost" "AutoPost_obfuscated" "extension_auto_poster" "extension_auto_poster_obfuscated"
                copy_ext_pair "Sumary" "Sumary" "Sumary_obfuscated"
                copy_ext_pair "PostVideo" "PostVideo" "PostVideo_obfuscated"
                copy_ext_pair "GenImage" "GenImage" "GenImage_obfuscated"

                # 2. Tự động quét và tải TẤT CẢ các thư mục Extension có chứa manifest.json trong bản phát hành
                for dirPath in "$EXTRACTED_ROOT"/*/; do
                    [ -d "$dirPath" ] || continue
                    dirName=$(basename "$dirPath")
                    if [ -f "$dirPath/manifest.json" ] && [[ "$dirName" != *_obfuscated ]]; then
                        mkdir -p "$DIR/$dirName"
                        cp -Rf "$dirPath"* "$DIR/$dirName/" 2>/dev/null
                        already_recorded=false
                        for item in "${DOWNLOADED_EXTENSIONS[@]}"; do
                            if [ "$item" = "$dirName" ]; then
                                already_recorded=true
                                break
                            fi
                        done
                        if [ "$already_recorded" = false ]; then
                            DOWNLOADED_EXTENSIONS+=("$dirName")
                        fi
                    fi
                done

                # 3. Cập nhật các file script công cụ nếu có trong bản release
                for updFile in "Update.bat" "Update.ps1"; do
                    if [ -f "$EXTRACTED_ROOT/$updFile" ]; then
                        cp -f "$EXTRACTED_ROOT/$updFile" "$DIR/$updFile" 2>/dev/null
                    fi
                done

                UPDATE_SUCCESS=true
                echo -e "   ${GREEN}[V] Đã tải và giải nén thành công toàn bộ ${#DOWNLOADED_EXTENSIONS[@]} Extension (${DOWNLOADED_EXTENSIONS[*]})!${NC}"
            fi
        fi
    else
        echo -e "   ${RED}[!] Lỗi khi tải trực tiếp từ GitHub: $ZIP_URL${NC}"
        echo -e "   ${YELLOW}[i] Vui lòng kiểm tra kết nối mạng Internet trên máy Mac của bạn.${NC}"
    fi

    # Dọn dẹp thư mục tạm
    rm -rf "$TEMP_DIR" 2>/dev/null
fi

# -------------------------------------------------------------------------
# BƯỚC 3: ĐỒNG BỘ ĐỊNH DANH MÁY VÀO TẤT CẢ EXTENSION ĐỂ CHROME TỰ NHẬN DIỆN
# -------------------------------------------------------------------------
RESTORE_FOLDERS=(
    "AutoPost"
    "Sumary"
    "PostVideo"
    "GenImage"
    "AutoPost_obfuscated"
    "Sumary_obfuscated"
    "PostVideo_obfuscated"
    "GenImage_obfuscated"
    "extension_auto_poster"
    "extension_auto_poster_obfuscated"
)

SYNCED_LIST=()
MAIN_EXT_LIST=()

for dirPath in "$DIR"/*/; do
    [ -d "$dirPath" ] || continue
    folderName=$(basename "$dirPath")

    is_target=false
    if [ -f "$dirPath/manifest.json" ]; then
        is_target=true
    else
        for rf in "${RESTORE_FOLDERS[@]}"; do
            if [ "$rf" = "$folderName" ]; then
                is_target=true
                break
            fi
        done
    fi

    if [ "$is_target" = true ]; then
        cp -f "$DIR/device_identity.json" "$dirPath/device_identity.json" 2>/dev/null
        SYNCED_LIST+=("$folderName")
        if [[ "$folderName" != *_obfuscated ]] && [ -f "$dirPath/manifest.json" ]; then
            MAIN_EXT_LIST+=("$folderName")
        fi
    fi
done

# -------------------------------------------------------------------------
# BƯỚC 4: ĐĂNG KÝ NATIVE MESSAGING HOST CHO GENIMAGE TRÊN MACOS (MỞ FINDER)
# -------------------------------------------------------------------------
compute_chrome_ext_id_utf8() {
    local target_path="$1"
    local hex_hash
    hex_hash=$(printf "%s" "$target_path" | shasum -a 256 2>/dev/null | awk '{print $1}' | cut -c1-32)
    if [ -z "$hex_hash" ]; then
        return
    fi
    echo "$hex_hash" | tr '0123456789abcdef' 'abcdefghijklmnop'
}

if [ -d "$DIR/GenImage" ]; then
    NATIVE_SH="$DIR/GenImage/native_host.sh"
    if [ -f "$NATIVE_SH" ]; then
        chmod +x "$NATIVE_SH" 2>/dev/null
        chmod +x "$DIR/GenImage/native_host.cjs" 2>/dev/null

        CAND_PATHS=(
            "$DIR/GenImage"
            "$DIR/GenImage_obfuscated"
        )

        # Thêm đường dẫn thực tế đã phân giải symlink (ví dụ /private/var/... trên macOS)
        REAL_GENIMAGE=$(cd "$DIR/GenImage" 2>/dev/null && pwd -P)
        if [ -n "$REAL_GENIMAGE" ] && [ "$REAL_GENIMAGE" != "$DIR/GenImage" ]; then
            CAND_PATHS+=("$REAL_GENIMAGE")
        fi

        # Quét thêm đường dẫn thực tế trong Preferences của Chrome / Brave / Edge / Cốc Cốc trên Mac
        BROWSER_SUPPORT_DIRS=(
            "$HOME/Library/Application Support/Google/Chrome"
            "$HOME/Library/Application Support/BraveSoftware/Brave-Browser"
            "$HOME/Library/Application Support/Microsoft Edge"
            "$HOME/Library/Application Support/CocCoc/Browser"
            "$HOME/Library/Application Support/Chromium"
        )

        for bdir in "${BROWSER_SUPPORT_DIRS[@]}"; do
            if [ -d "$bdir" ]; then
                while IFS= read -r prefFile; do
                    [ -f "$prefFile" ] || continue
                    if grep -q "GenImage" "$prefFile" 2>/dev/null; then
                        while IFS= read -r matchedPath; do
                            cleanPath=$(echo "$matchedPath" | sed -E 's/.*"path"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' | sed 's#\\/#/#g')
                            if [ -n "$cleanPath" ]; then
                                CAND_PATHS+=("$cleanPath")
                            fi
                        done < <(grep -o '"path"[[:space:]]*:[[:space:]]*"[^"]*GenImage[^"]*"' "$prefFile" 2>/dev/null)
                    fi
                done < <(find "$bdir" -maxdepth 3 \( -name "Preferences" -o -name "Secure Preferences" \) 2>/dev/null)
            fi
        done

        Origins_JSON=""
        SEEN_IDS="|"
        for cp_item in "${CAND_PATHS[@]}"; do
            clean_cp="${cp_item%/}"
            [ -n "$clean_cp" ] || continue
            ext_id=$(compute_chrome_ext_id_utf8 "$clean_cp")
            if [ -n "$ext_id" ] && [[ "$SEEN_IDS" != *"|$ext_id|"* ]]; then
                SEEN_IDS="${SEEN_IDS}${ext_id}|"
                if [ -n "$Origins_JSON" ]; then
                    Origins_JSON="${Origins_JSON},
    \"chrome-extension://${ext_id}/\""
                else
                    Origins_JSON="    \"chrome-extension://${ext_id}/\""
                fi
            fi
        done

        NM_MANIFEST_PATH="$DIR/GenImage/com.toolfb.genimage.json"
        cat <<EOF > "$NM_MANIFEST_PATH"
{
  "name": "com.toolfb.genimage",
  "description": "GenImage macOS Finder & Windows Explorer Native Host",
  "path": "$NATIVE_SH",
  "type": "stdio",
  "allowed_origins": [
$Origins_JSON
  ]
}
EOF

        # Đăng ký file manifest vào thư mục NativeMessagingHosts của tất cả trình duyệt Chromium trên macOS
        MAC_NM_DIRS=(
            "$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
            "$HOME/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts"
            "$HOME/Library/Application Support/Microsoft Edge/NativeMessagingHosts"
            "$HOME/Library/Application Support/CocCoc/Browser/NativeMessagingHosts"
            "$HOME/Library/Application Support/Chromium/NativeMessagingHosts"
        )
        for nm_dir in "${MAC_NM_DIRS[@]}"; do
            parent_browser_dir=$(dirname "$nm_dir")
            if [ -d "$parent_browser_dir" ]; then
                mkdir -p "$nm_dir" 2>/dev/null
                cp -f "$NM_MANIFEST_PATH" "$nm_dir/com.toolfb.genimage.json" 2>/dev/null
            fi
        done
    fi
fi

# Gỡ cờ cách ly Gatekeeper của macOS (nếu có) và đảm bảo quyền thực thi cho các file .command / .sh
chmod +x "$DIR/Update.command" "$DIR/Update.sh" 2>/dev/null
if command -v xattr >/dev/null 2>&1; then
    xattr -cr "$DIR" 2>/dev/null
fi

# -------------------------------------------------------------------------
# BƯỚC 5: HIỂN THỊ KẾT QUẢ VÀ HƯỚNG DẪN SỬ DỤNG TRÊN CHROME MACBOOK
# -------------------------------------------------------------------------
echo ""
echo -e "${GREEN}=======================================================================${NC}"
echo -e "${GREEN}                   KẾT QUẢ CẬP NHẬT TOOLFB (macOS)                    ${NC}"
echo -e "${GREEN}=======================================================================${NC}"
echo ""

if [ "$UPDATE_SUCCESS" = true ]; then
    echo -e "   ${GREEN}[V] TRẠNG THÁI: TẢI & CẬP NHẬT BỘ ${#MAIN_EXT_LIST[@]} TOOL THÀNH CÔNG!${NC}"
else
    echo -e "   ${YELLOW}[!] TRẠNG THÁI: CHƯA TẢI ĐƯỢC BẢN MỚI TỪ GITHUB (KIỂM TRA KẾT NỐI)${NC}"
fi

echo -e "   ${CYAN}[V] ĐÃ ĐỒNG BỘ MÃ MÁY VÀO: ${SYNCED_LIST[*]}${NC}"
echo -e "   ${WHITE}[V] MÃ MÁY HIỆN TẠI : ${YELLOW}${SAVED_MACHINE_ID} (ĐÃ LƯU VÀ CÓ SẴN TRONG CLIPBOARD - BẤM Cmd+V)${NC}"
echo ""
echo -e "   ${CYAN}-> HƯỚNG DẪN DÙNG TOOL TRÊN TRÌNH DUYỆT CHROME (MACBOOK):${NC}"
echo -e "      1. Mở trình duyệt Chrome, vào địa chỉ: ${WHITE}chrome://extensions${NC}"
echo -e "      2. Bật công tắc ${WHITE}'Chế độ dành cho nhà phát triển' (Developer mode)${NC}"
echo -e "      3. Bấm ${YELLOW}'Tải tiện ích đã giải nén' (Load unpacked)${NC}"
echo -e "         -> Chọn lần lượt các thư mục: ${WHITE}${MAIN_EXT_LIST[*]}${NC}"
echo -e "      4. ${GREEN}Nếu đã cài trước đó, chỉ cần bấm nút 'Tải lại' (Reload 🔄) trên từng extension!${NC}"
echo -e "${GREEN}=======================================================================${NC}"
echo ""

# Giữ cửa sổ Terminal mở khi người dùng nhấp đúp vào Update.command trên Finder
if [ -t 0 ]; then
    read -r -p "Nhấn phím [Enter] để đóng cửa sổ này..." dummy
fi
