#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}ℹ️  INFO:${NC} $1"
}

log_success() {
    echo -e "${GREEN} ✅ SUCCESS:${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠️  WARNING:${NC} $1"
}

log_error() {
    echo -e "${RED}❌ ERROR:${NC} $1"
}

log_processing() {
    echo -e "${CYAN}🔄  PROCESSING:${NC} $1"
}

show_progress() {
    local current="$1"
    local total="$2"
    local width=50
    local percent=$((current * 100 / total))
    local completed=$((current * width / total))
    local remaining=$((width - completed))

    local progress_bar="["
    for ((i=0; i<completed; i++)); do
        progress_bar+="█"
    done
    for ((i=0; i<remaining; i++)); do
        progress_bar+="░"
    done
    progress_bar+="]"

    printf "\r${CYAN}📊  Progress: ${GREEN}%s${CYAN} ${YELLOW}%3d%%${NC} (%d/%d files)" \
        "$progress_bar" "$percent" "$current" "$total"
}

show_help() {
    echo -e "${CYAN}📖 Usage: $0 -d DIRECTORY -u URL -p PASSWORD -U USER -D DATABASE -t TABLE -P PROJECT${NC}"
    echo "Combine JSON test result files into a single temporary file and send to ClickHouse"
    echo ""
    echo -e "${YELLOW}Required Options:${NC}"
    echo "  --dir                 Allure results search directory"
    echo "  --url                 ClickHouse server URL"
    echo "  -p                    ClickHouse password"
    echo "  -u,                   ClickHouse username"
    echo "  -d,                   ClickHouse database name"
    echo "  -t                    ClickHouse table name"
    echo "  --project             Project name"
    echo "  -h                    Show this help message"
    echo ""
    echo -e "${GREEN}Example:${NC}"
    echo "  $0 --dir ./test-results --url http://localhost:8123 -p clickhouse_password -u admin -d default -t test_results -project MyProject"
    echo ""
    echo -e "${RED}Note: All parameters are required!${NC}"
    echo -e "${YELLOW}Output: Temporary file path will be printed at the end${NC}"
}

SEARCH_DIR=""
CLICKHOUSE_URL=""
CLICKHOUSE_PASSWORD=""
CLICKHOUSE_USER=""
CLICKHOUSE_DATABASE=""
CLICKHOUSE_TABLE=""
PROJECT_NAME=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --dir)
            SEARCH_DIR="$2"
            shift 2
            ;;
        --url)
            CLICKHOUSE_URL="$2"
            shift 2
            ;;
        -p)
            CLICKHOUSE_PASSWORD="$2"
            shift 2
            ;;
        -u)
            CLICKHOUSE_USER="$2"
            shift 2
            ;;
        -d)
            CLICKHOUSE_DATABASE="$2"
            shift 2
            ;;
        -t)
            CLICKHOUSE_TABLE="$2"
            shift 2
            ;;
        --project)
            PROJECT_NAME="$2"
            shift 2
            ;;
        -h)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

MISSING_PARAMS=()
[[ -z "$SEARCH_DIR" ]] && MISSING_PARAMS+=("--dir")
[[ -z "$CLICKHOUSE_URL" ]] && MISSING_PARAMS+=("--url")
[[ -z "$CLICKHOUSE_PASSWORD" ]] && MISSING_PARAMS+=("--p")
[[ -z "$CLICKHOUSE_USER" ]] && MISSING_PARAMS+=("-u")
[[ -z "$CLICKHOUSE_DATABASE" ]] && MISSING_PARAMS+=("-d")
[[ -z "$CLICKHOUSE_TABLE" ]] && MISSING_PARAMS+=("-t")
[[ -z "$PROJECT_NAME" ]] && MISSING_PARAMS+=("--project")

if [[ ${#MISSING_PARAMS[@]} -gt 0 ]]; then
    log_error "Missing required parameters: ${MISSING_PARAMS[*]}"
    echo ""
    show_help
    exit 1
fi

if [[ ! -d "$SEARCH_DIR" ]]; then
    log_error "Search directory '$SEARCH_DIR' does not exist"
    exit 1
fi

log_info "Starting JSON files merge process"
log_info "Search directory: $SEARCH_DIR"

FOUND_FILES=0

TEMP_FILE=$(mktemp)
log_info "Temporary file created: $TEMP_FILE"

log_processing "Scanning for JSON files matching pattern '*result.json'..."
mapfile -t json_files < <(find "$SEARCH_DIR" -type f -name "*result.json")
TOTAL_FILES="${#json_files[@]}"

if [[ $TOTAL_FILES -eq 0 ]]; then
    log_error "No files found matching pattern '*result.json' in $SEARCH_DIR"
    rm -f "$TEMP_FILE"
    exit 1
fi

log_info "Found $TOTAL_FILES files to process"
echo ""

CURRENT_FILE=0
CURRENT_TIME=$(TZ=UTC date "+%Y-%m-%d %H:%M:%S")

for file in "${json_files[@]}"; do
    ((CURRENT_FILE++))
    ((FOUND_FILES++))

    show_progress "$CURRENT_FILE" "$TOTAL_FILES"

    if sed '0,/{/s//{"project":"'"${PROJECT_NAME}"'","upload_time":"'"${CURRENT_TIME}"'",/' "$file" >> "$TEMP_FILE" 2>/dev/null; then
        echo "" >> "$TEMP_FILE"
    else
        log_error "Failed to add file: $file"
    fi
done

echo ""
echo ""

log_info "File processing completed"
echo ""
echo -e "${CYAN}=========================================${NC}"

echo ""

if [[ -f "$TEMP_FILE" && -s "$TEMP_FILE" ]]; then
    FILE_SIZE=$(wc -c < "$TEMP_FILE")
    LINES_COUNT=$(wc -l < "$TEMP_FILE")

    echo -e "${CYAN}📁 TEMPORARY FILE INFORMATION${NC}"
    echo -e "File: ${GREEN}$TEMP_FILE${NC}"
    echo -e "Size: ${BLUE}$FILE_SIZE bytes${NC}"
    echo -e "Lines: ${BLUE}$LINES_COUNT${NC}"
else
    log_error "Temporary file was not created or is empty"
    exit 1
fi

echo ""
log_success "Merge process completed successfully! 🎉"
echo -e "${GREEN}All test results have been merged into temporary file:${NC}"
echo -e "${GREEN}📄 $TEMP_FILE${NC}"
echo ""

echo -e "${CYAN}=========================================${NC}"
log_processing "Sending data to ClickHouse..."

log_info "ClickHouse URL: $CLICKHOUSE_URL"
log_info "ClickHouse database: $CLICKHOUSE_DATABASE"
log_info "ClickHouse table: $CLICKHOUSE_TABLE"
log_info "ClickHouse user: $CLICKHOUSE_USER"
log_info "Project name: $PROJECT_NAME"
echo -e "${CYAN}=========================================${NC}"

FULL_URL="${CLICKHOUSE_URL}/?database=${CLICKHOUSE_DATABASE}&user=${CLICKHOUSE_USER}&password=${CLICKHOUSE_PASSWORD}&query=INSERT%20INTO%20${CLICKHOUSE_TABLE}%20FORMAT%20JSONEachRow"

if response_code=$(curl -X POST -w "%{http_code}" -s -o /dev/null "$FULL_URL" --data-binary @"$TEMP_FILE"); then
    if [ "$response_code" -ge 200 ] && [ "$response_code" -lt 300 ]; then
        log_success "Data successfully sent to ClickHouse table: $CLICKHOUSE_TABLE"
    else
        log_error "Failed to send data to ClickHouse. HTTP status code: $response_code"
        log_warning "Temporary file preserved for debugging: $TEMP_FILE"
        exit 1
    fi
else
    log_error "Network error when sending data to ClickHouse"
    log_warning "Temporary file preserved for debugging: $TEMP_FILE"
    exit 1
fi

log_processing "Cleaning up temporary file..."
rm -f "$TEMP_FILE"
log_success "Temporary file removed: $TEMP_FILE"