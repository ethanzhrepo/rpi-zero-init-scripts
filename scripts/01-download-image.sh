#!/bin/bash
# Download and verify Raspberry Pi OS image
# Returns: Path to verified image file

set -euo pipefail

# Get project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source libraries
source "$PROJECT_ROOT/scripts/lib/common.sh"

# ==============================================================================
# Configuration
# ==============================================================================
BASE_URL="https://downloads.raspberrypi.org/raspios_lite_armhf/images"
CACHE_DIR="$PROJECT_ROOT/cache/images"
VERSION="${RPI_OS_VERSION:-latest}"

# ==============================================================================
# Functions
# ==============================================================================

# Resolve "latest" to actual version
resolve_latest_version() {
    log_info "Resolving latest Raspberry Pi OS version..."

    local index_url="${BASE_URL}/"
    local versions

    # Download directory listing
    versions=$(curl -s "$index_url" | grep -oE 'raspios_lite_armhf-[0-9]{4}-[0-9]{2}-[0-9]{2}' | sed 's/raspios_lite_armhf-//' | sort -r)

    if [[ -z "$versions" ]]; then
        log_error "Failed to fetch version list from $index_url"
        return 1
    fi

    # Get the most recent version
    local latest_version
    latest_version=$(echo "$versions" | head -n1)

    log_info "Latest version: $latest_version"
    echo "$latest_version"
}

# Get download URL for version
get_download_url() {
    local version="$1"
    local version_dir="raspios_lite_armhf-${version}"
    local dir_url="${BASE_URL}/${version_dir}/"

    log_debug "Fetching file list from: $dir_url"

    # Fetch directory listing and find the .img.xz file
    local filename
    filename=$(curl -s "$dir_url" | grep -oE "${version}-raspios-[a-z]+-armhf-lite\.img\.xz" | head -n1)

    if [[ -z "$filename" ]]; then
        log_error "Failed to find image file in directory: $dir_url"
        return 1
    fi

    log_debug "Found image filename: $filename"

    # Construct full URL
    local image_url="${BASE_URL}/${version_dir}/${filename}"
    echo "$image_url"
}

# Check if image is already cached
check_cache() {
    local version="$1"
    local cached_image="$CACHE_DIR/raspios-${version}.img"

    if [[ -f "$cached_image" ]]; then
        log_success "Found cached image: $cached_image"
        echo "$cached_image"
        return 0
    fi

    return 1
}

# Download file with progress
download_file() {
    local url="$1"
    local output="$2"

    log_info "Downloading: $url"
    log_info "Output: $output"

    # Create temporary file
    local temp_file="${output}.tmp"

    # Download with curl (supports resume)
    if ! curl -L -C - -o "$temp_file" --progress-bar "$url"; then
        log_error "Download failed"
        rm -f "$temp_file"
        return 1
    fi

    # Move to final location
    mv "$temp_file" "$output"
    log_success "Download complete"

    return 0
}

# Calculate SHA256 checksum for a file
calculate_checksum() {
    local file="$1"

    if command_exists shasum; then
        shasum -a 256 "$file" | awk '{print $1}'
        return 0
    fi

    if command_exists sha256sum; then
        sha256sum "$file" | awk '{print $1}'
        return 0
    fi

    log_error "No SHA256 checksum tool found (shasum or sha256sum)"
    return 1
}

# Verify SHA256 checksum
verify_checksum() {
    local file="$1"
    local checksum_file="$2"

    log_info "Verifying checksum..."

    # Extract checksum from file
    local expected_checksum
    expected_checksum=$(awk '{print $1}' "$checksum_file")

    if [[ -z "$expected_checksum" ]]; then
        log_error "Failed to read checksum from $checksum_file"
        return 1
    fi

    # Calculate actual checksum
    log_debug "Expected: $expected_checksum"
    log_info "Calculating SHA256 checksum (this may take a moment)..."

    local actual_checksum
    if ! actual_checksum=$(calculate_checksum "$file"); then
        return 1
    fi

    log_debug "Actual: $actual_checksum"

    # Compare
    if [[ "$expected_checksum" != "$actual_checksum" ]]; then
        log_error "Checksum mismatch!"
        log_error "Expected: $expected_checksum"
        log_error "Actual:   $actual_checksum"
        return 1
    fi

    log_success "Checksum verification passed"
    return 0
}

# Extract .xz file
extract_xz() {
    local xz_file="$1"
    local output_file="$2"

    log_info "Extracting image..."
    log_info "This may take several minutes..."

    # Extract to temporary file first
    local temp_file="${output_file}.tmp"

    if command_exists unxz; then
        if ! unxz -c "$xz_file" > "$temp_file"; then
            log_error "Extraction failed"
            rm -f "$temp_file"
            return 1
        fi
    elif command_exists xz; then
        if ! xz -dc "$xz_file" > "$temp_file"; then
            log_error "Extraction failed"
            rm -f "$temp_file"
            return 1
        fi
    else
        log_error "xz/unxz command not found"
        log_error "Install with: brew install xz (macOS) or apt install xz-utils (Linux)"
        return 1
    fi

    if [[ ! -f "$temp_file" ]]; then
        log_error "Extraction failed"
        rm -f "$temp_file"
        return 1
    fi

    # Move to final location
    mv "$temp_file" "$output_file"
    log_success "Extraction complete"

    return 0
}

# Check available disk space
check_disk_space() {
    local required_bytes="$1"
    local available_bytes

    available_bytes=$(get_free_space "$CACHE_DIR")

    local required_gb=$((required_bytes / 1073741824))
    local available_gb=$((available_bytes / 1073741824))

    log_debug "Required: ${required_gb}GB, Available: ${available_gb}GB"

    if [[ $available_bytes -lt $required_bytes ]]; then
        log_error "Insufficient disk space"
        log_error "Required: ${required_gb}GB"
        log_error "Available: ${available_gb}GB"
        return 1
    fi

    return 0
}

# Main download and verification process
download_and_verify() {
    local version="$1"
    local download_url
    local xz_file
    local sha_file
    local img_file

    # Get download URL
    download_url=$(get_download_url "$version")
    sha_url="${download_url}.sha256"

    # Create filenames
    local filename
    filename=$(basename "$download_url")
    xz_file="$CACHE_DIR/${filename}"
    sha_file="${xz_file}.sha256"
    img_file="$CACHE_DIR/raspios-${version}.img"

    log_info "Image version: $version"

    # Check disk space (need about 3GB for compressed + extracted image)
    if ! check_disk_space 3221225472; then
        return 1
    fi

    # Download compressed image
    if [[ ! -f "$xz_file" ]]; then
        if ! download_file "$download_url" "$xz_file"; then
            return 1
        fi
    else
        log_info "Using cached compressed file: $xz_file"
    fi

    # Download checksum
    if [[ ! -f "$sha_file" ]]; then
        log_info "Downloading checksum..."
        if ! curl -s -L -o "$sha_file" "$sha_url"; then
            log_error "Failed to download checksum"
            return 1
        fi
    fi

    # Verify checksum of compressed file
    if ! verify_checksum "$xz_file" "$sha_file"; then
        log_error "Checksum verification failed, removing corrupted file"
        rm -f "$xz_file"
        return 1
    fi

    # Extract image
    if [[ ! -f "$img_file" ]]; then
        if ! extract_xz "$xz_file" "$img_file"; then
            return 1
        fi
    else
        log_info "Using cached extracted image: $img_file"
    fi

    # Clean up compressed file to save space (optional)
    if [[ "${KEEP_CACHED_IMAGES:-true}" != "true" ]]; then
        log_info "Removing compressed file to save space..."
        rm -f "$xz_file" "$sha_file"
    fi

    # Return path to image
    echo "$img_file"
    return 0
}

# ==============================================================================
# Main
# ==============================================================================

main() {
    log_step "Download Raspberry Pi OS Image"

    # Ensure cache directory exists
    ensure_dir "$CACHE_DIR"

    # Resolve version
    local version="$VERSION"
    if [[ "$version" == "latest" ]]; then
        version=$(resolve_latest_version) || exit 1
    fi

    # Check if already cached
    local cached_image
    if cached_image=$(check_cache "$version"); then
        echo "$cached_image"
        exit 0
    fi

    # Download and verify
    local image_path
    if ! image_path=$(download_and_verify "$version"); then
        log_error "Failed to download and verify image"
        exit 1
    fi

    log_success "Image ready: $image_path"
    echo "$image_path"
}

main "$@"
