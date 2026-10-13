#!/bin/bash

# =======================================================================
#           HỆ THỐNG TỰ ĐỘNG CẬP NHẬT TOOLFB (CHO MÁY MAC / macOS)
# =======================================================================

# Đảm bảo thư mục làm việc luôn là thư mục chứa file script này
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR" || exit 1

# Màu sắc hiển thị
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # Không màu

echo ""
echo -e "${CYAN}=======================================================================${NC}"
echo -e "${CYAN}           HỆ THỐNG TỰ ĐỘNG CẬP NHẬT TOOLFB (CHROME EXTENSIONS)        ${NC}"
echo -e "${CYAN}                              DÀNH CHO MACOS                           ${NC}"
echo -e "${CYAN}=======================================================================${NC}"
echo ""

# -------------------------------------------------------------------------
# BƯỚC 1: LẤY THÔNG TIN ĐỊNH DANH MÁY & BẢO TOÀN 100% KHÔNG BỊ MẤT
# -------------------------------------------------------------------------
SAVED_MACHINE_ID=""
SAVED_RAW_GUID=""

SEARCH_PATHS=(
    "device_identity.json"
    "AutoPost/device_identity.json"
    "Sumary/device_identity.json"
    "AutoPost_obfuscated/device_identity.json"
    "Sumary_obfuscated/device_identity.json"
    "extension_auto_poster/device_identity.json"
    "extension_auto_poster_obfuscated/device_identity.json"
)

# 1.1 Tìm mã máy đã lưu trước đó nếu có
for p in "${SEARCH_PATHS[@]}"; do
    if [ -f "$p" ]; then
        SAVED_MACHINE_ID=$(grep -o '"machine_id"[[:space:]]*:[[:space:]]*"[^"]*"' "$p" | head -n 1 | sed -E 's/.*"machine_id"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
        SAVED_RAW_GUID=$(grep -o '"raw_guid"[[:space:]]*:[[:space:]]*"[^"]*"' "$p" | head -n 1 | sed -E 's/.*"raw_guid"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
        if [ -n "$SAVED_MACHINE_ID" ]; then
            break
        fi
    fi
done

# 1.2 Nếu chưa từng lưu, lấy từ Hardware UUID của Mac (IOPlatformUUID)
if [ -z "$SAVED_MACHINE_ID" ]; then
    # Lấy qua ioreg (chuẩn phần cứng Apple Silicon và Intel Mac)
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

# Lưu định danh vào device_identity.json
NOW=$(date +"%Y-%m-%d %H:%M:%S")
cat <<EOF > "device_identity.json"
{
  "raw_guid": "$SAVED_RAW_GUID",
  "machine_id": "$SAVED_MACHINE_ID",
  "updated_at": "$NOW"
}
EOF

# Tự động sao chép mã máy vào Clipboard của Mac (pbcopy)
if command -v pbcopy >/dev/null 2>&1; then
    printf "%s" "$SAVED_MACHINE_ID" | pbcopy
fi

echo -e "   [*] MÃ MÁY CỦA BẠN: ${YELLOW}${SAVED_MACHINE_ID}${NC}"
echo -e "   [V] ĐÃ LƯU ĐỊNH DANH MÁY VÀ COPY VÀO BỘ NHỚ TẠM (CLIPBOARD)!"
echo ""

# -------------------------------------------------------------------------
# BƯỚC 2: TẢI BẢN MỚI NHẤT TỪ NHÁNH RELEASE TRÊN GITHUB
# -------------------------------------------------------------------------
UPDATE_SUCCESS=false

# Cách 2.1: Nếu đang trong Git repo, fetch từ nhánh release
if command -v git >/dev/null 2>&1 && [ -d ".git" ]; then
    echo -e "   [*] Đang kiểm tra bản cập nhật trên Git (nhánh 'release')..."
    if git fetch origin release >/dev/null 2>&1; then
        echo -e "   [V] Đã tìm thấy nhánh 'release' trên GitHub!"
        TARGET_FOLDERS=("AutoPost" "Sumary" "AutoPost_obfuscated" "Sumary_obfuscated" "extension_auto_poster" "extension_auto_poster_obfuscated")
        FOLDERS_TO_CHECKOUT=()
        for f in "${TARGET_FOLDERS[@]}"; do
            if git cat-file -e "origin/release:$f" 2>/dev/null; then
                FOLDERS_TO_CHECKOUT+=("$f")
            fi
        done

        if [ ${#FOLDERS_TO_CHECKOUT[@]} -gt 0 ]; then
            if git checkout --force origin/release -- "${FOLDERS_TO_CHECKOUT[@]}" >/dev/null 2>&1; then
                UPDATE_SUCCESS=true
                echo -e "   [V] Đã đồng bộ mã nguồn 2 extension từ nhánh 'release'!"
            fi
        fi
    fi
fi

# Cách 2.2: Tải zip trực tiếp từ nhánh release của GitHub nếu chưa thành công
if [ "$UPDATE_SUCCESS" = false ]; then
    echo -e "   [*] Đang tải 2 Tool mới nhất từ GitHub..."
    ZIP_URL="https://github.com/Minh2304/ToolFB/archive/refs/heads/release.zip"
    TEMP_DIR=$(mktemp -d 2>/dev/null || echo "/tmp/toolfb_update_$$")
    mkdir -p "$TEMP_DIR"
    TEMP_ZIP="$TEMP_DIR/release.zip"
    TEMP_EXTRACT="$TEMP_DIR/extracted"

    AUTH_HEADER=()
    if [ -n "$GITHUB_TOKEN" ]; then
        AUTH_HEADER=(-H "Authorization: token $GITHUB_TOKEN")
    fi

    if curl -fsSL "${AUTH_HEADER[@]}" "$ZIP_URL" -o "$TEMP_ZIP" 2>/dev/null; then
        mkdir -p "$TEMP_EXTRACT"
        if unzip -q -o "$TEMP_ZIP" -d "$TEMP_EXTRACT" 2>/dev/null; then
            EXTRACTED_ROOT=$(find "$TEMP_EXTRACT" -mindepth 1 -maxdepth 1 -type d | head -n 1)
            if [ -n "$EXTRACTED_ROOT" ]; then
                # Tìm nguồn AutoPost
                SRC_POSTER=""
                for candidate in "$EXTRACTED_ROOT/AutoPost" "$EXTRACTED_ROOT/AutoPost_obfuscated" "$EXTRACTED_ROOT/extension_auto_poster" "$EXTRACTED_ROOT/extension_auto_poster_obfuscated"; do
                    if [ -d "$candidate" ]; then
                        SRC_POSTER="$candidate"
                        break
                    fi
                done

                # Tìm nguồn Sumary
                SRC_SUMARY=""
                for candidate in "$EXTRACTED_ROOT/Sumary" "$EXTRACTED_ROOT/Sumary_obfuscated"; do
                    if [ -d "$candidate" ]; then
                        SRC_SUMARY="$candidate"
                        break
                    fi
                done

                # Copy AutoPost
                if [ -n "$SRC_POSTER" ]; then
                    mkdir -p "AutoPost"
                    cp -R "$SRC_POSTER/"* "AutoPost/"
                    if [ -d "AutoPost_obfuscated" ]; then
                        cp -R "$SRC_POSTER/"* "AutoPost_obfuscated/"
                    fi
                fi

                # Copy Sumary
                if [ -n "$SRC_SUMARY" ]; then
                    mkdir -p "Sumary"
                    cp -R "$SRC_SUMARY/"* "Sumary/"
                    if [ -d "Sumary_obfuscated" ]; then
                        cp -R "$SRC_SUMARY/"* "Sumary_obfuscated/"
                    fi
                fi

                UPDATE_SUCCESS=true
                echo -e "   [V] Đã tải và giải nén 2 Tool về thư mục thành công!"
            fi
        fi
    else
        echo -e "   [!] Không thể tải trực tiếp file zip từ GitHub: $ZIP_URL"
        echo -e "   [i] Gợi ý: Nếu repo đang ở chế độ Private, vui lòng set repository sang Public hoặc thiết lập biến môi trường GITHUB_TOKEN."
    fi

    # Dọn dẹp file tạm
    rm -rf "$TEMP_DIR"
fi

# -------------------------------------------------------------------------
# BƯỚC 3: ĐỒNG BỘ ĐỊNH DANH MÁY VÀO CÁC EXTENSION
# -------------------------------------------------------------------------
RESTORE_FOLDERS=(
    "AutoPost"
    "Sumary"
    "AutoPost_obfuscated"
    "Sumary_obfuscated"
    "extension_auto_poster"
    "extension_auto_poster_obfuscated"
)

SYNCED_LIST=()
for folder in "${RESTORE_FOLDERS[@]}"; do
    if [ -d "$folder" ]; then
        cp -f "device_identity.json" "$folder/device_identity.json"
        SYNCED_LIST+=("$folder")
    fi
done

# -------------------------------------------------------------------------
# BƯỚC 4: HIỂN THỊ KẾT QUẢ VÀ HƯỚNG DẪN SỬ DỤNG TRÊN CHROME MAC
# -------------------------------------------------------------------------
echo ""
echo -e "${GREEN}=======================================================================${NC}"
echo -e "${GREEN}                   KẾT QUẢ CẬP NHẬT TOOLFB (macOS)                    ${NC}"
echo -e "${GREEN}=======================================================================${NC}"
echo ""

if [ "$UPDATE_SUCCESS" = true ]; then
    echo -e "   [V] TRẠNG THÁI: TẢI & CẬP NHẬT 2 TOOL THÀNH CÔNG!"
else
    echo -e "   [!] TRẠNG THÁI: CHƯA TẢI ĐƯỢC BẢN MỚI TỪ GITHUB (KIỂM TRA LẠI KẾT NỐI/REPO)"
fi

echo -e "   [V] ĐÃ ĐỒNG BỘ MÃ MÁY VÀO: ${CYAN}${SYNCED_LIST[*]}${NC}"
echo -e "   [V] MÃ MÁY HIỆN TẠI : ${YELLOW}${SAVED_MACHINE_ID}${NC} (ĐÃ LƯU & CÓ SẴN TRONG CLIPBOARD - BẤM Cmd+V)"
echo ""
echo -e "   -> HƯỚNG DẪN DÙNG TOOL TRÊN TRÌNH DUYỆT CHROME (MAC):"
echo -e "      1. Mở trình duyệt Chrome trên Mac, vào địa chỉ: ${CYAN}chrome://extensions${NC}"
echo -e "      2. Bật công tắc 'Chế độ dành cho nhà phát triển' (Developer mode) ở góc trên bên phải"
echo -e "      3. NẾU LẦN ĐẦU CÀI TOOL:"
echo -e "         - Bấm 'Tải tiện ích đã giải nén' (Load unpacked)"
echo -e "         - Chọn lần lượt 2 thư mục 'AutoPost' và 'Sumary' trong thư mục này"
echo -e "      4. NẾU ĐÃ CÀI VÀ VỪA CẬP NHẬT:"
echo -e "         - Chỉ cần bấm nút 'Tải lại' (biểu tượng mũi tên xoay tròn 🔄) của 2 extension"
echo -e "      5. Mở tiện ích lên, mã máy sẽ được tự động nhận diện để đăng nhập!"
echo -e "${GREEN}=======================================================================${NC}"
echo ""

# Giữ cửa sổ Terminal mở để người dùng xem kết quả (tương tự 'pause' trong .bat)
read -p "Nhấn phím [Enter] để đóng cửa sổ này..." dummy
