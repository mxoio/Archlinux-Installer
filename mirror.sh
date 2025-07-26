#!/bin/bash

# Arch Linux Mirror Speed Tester
# Optimized for slower connections (20 Mbps and below)
# Tests mirrors and saves results to files for analysis

set -euo pipefail

# Configuration
TEST_FILE="core/os/x86_64/core.db"  # Small file for testing (~150KB)
TIMEOUT=30  # Seconds to wait for each mirror
MAX_TIME=60  # Maximum time for a download test
RESULTS_FILE="mirror_test_results.txt"
BEST_MIRRORS_FILE="best_mirrors.txt"
FAILED_MIRRORS_FILE="failed_mirrors.txt"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$RESULTS_FILE"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$RESULTS_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$RESULTS_FILE"
}

# Comprehensive list of Arch Linux mirrors (UK, EU, and global)
declare -a MIRRORS=(
    # UK Mirrors
    "https://archlinux.uk.mirror.allworldit.com/archlinux/"
    "https://mirrors.ukfast.co.uk/sites/archlinux.org/"
    "https://mirror.bytemark.co.uk/archlinux/"
    "https://www.mirrorservice.org/sites/ftp.archlinux.org/"
    "https://mirrors.manchester.m247.com/arch-linux/"
    "https://archlinux.mirrors.uk2.net/"
    
    # Ireland (close to UK)
    "https://ftp.heanet.ie/mirrors/archlinux/"
    
    # Netherlands (good EU connectivity)
    "https://mirror.lyrahosting.com/archlinux/"
    "https://mirrors.xtom.nl/archlinux/"
    "https://arch.mirror.pcextreme.nl/"
    "https://mirror.nl.leaseweb.net/archlinux/"
    
    # Germany (major EU hub)
    "https://mirror.bethselamin.de/archlinux/"
    "https://mirrors.n-ix.net/archlinux/"
    "https://mirror.dogado.de/archlinux/"
    "https://ftp.gwdg.de/pub/linux/archlinux/"
    "https://mirror.pkgbuild.com/"
    
    # France
    "https://archlinux.mirrors.ovh.net/archlinux/"
    "https://mirror.cyberbits.eu/archlinux/"
    "https://archlinux.mailtunnel.eu/"
    
    # Other EU
    "https://mirror.osbeck.com/archlinux/"  # Sweden
    "https://mirrors.dotsrc.org/archlinux/"  # Denmark
    "https://ftp.acc.umu.se/mirror/archlinux/"  # Sweden
    
    # Global fallbacks
    "https://mirrors.kernel.org/archlinux/"  # US - Kernel.org
    "https://mirror.rackspace.com/archlinux/"  # US - Rackspace
    "https://america.mirror.pkgbuild.com/"  # US - Official
    "https://asia.mirror.pkgbuild.com/"  # Asia - Official
)

# Function to test mirror speed
test_mirror() {
    local mirror_url="$1"
    local test_url="${mirror_url%/}/$TEST_FILE"
    local temp_file="/tmp/mirror_test_$$"
    
    echo -n "Testing: $mirror_url ... "
    
    # Test connectivity first with a quick HEAD request
    if ! curl -s --max-time 10 --head "$test_url" >/dev/null 2>&1; then
        echo -e "${RED}FAILED (unreachable)${NC}"
        echo "FAILED: $mirror_url - Unreachable" >> "$FAILED_MIRRORS_FILE"
        return 1
    fi
    
    # Measure download speed
    local start_time=$(date +%s.%N)
    
    if curl -s --max-time $MAX_TIME --connect-timeout $TIMEOUT \
        -w "%{speed_download},%{time_total},%{http_code}" \
        -o "$temp_file" "$test_url" 2>/dev/null; then
        
        local end_time=$(date +%s.%N)
        local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
        
        # Get curl statistics
        local stats=$(curl -s --max-time $MAX_TIME --connect-timeout $TIMEOUT \
            -w "%{speed_download},%{time_total},%{http_code}" \
            -o /dev/null "$test_url" 2>/dev/null || echo "0,0,0")
        
        local speed=$(echo "$stats" | cut -d',' -f1)
        local time_total=$(echo "$stats" | cut -d',' -f2)
        local http_code=$(echo "$stats" | cut -d',' -f3)
        
        # Convert bytes/sec to Mbps
        local speed_mbps=$(echo "scale=2; $speed * 8 / 1000000" | bc 2>/dev/null || echo "0")
        
        if [[ "$http_code" == "200" ]] && [[ $(echo "$speed > 0" | bc 2>/dev/null || echo 0) == 1 ]]; then
            echo -e "${GREEN}${speed_mbps} Mbps${NC} (${time_total}s)"
            echo "$speed_mbps,$time_total,$mirror_url" >> "${RESULTS_FILE}.csv"
            
            # Check if file was downloaded correctly
            if [[ -f "$temp_file" ]] && [[ -s "$temp_file" ]]; then
                local file_size=$(stat -c%s "$temp_file" 2>/dev/null || echo 0)
                echo "SUCCESS: $mirror_url - Speed: ${speed_mbps} Mbps, Time: ${time_total}s, Size: ${file_size} bytes" >> "$RESULTS_FILE"
                rm -f "$temp_file"
                return 0
            else
                echo -e "${RED}FAILED (incomplete download)${NC}"
                echo "FAILED: $mirror_url - Incomplete download" >> "$FAILED_MIRRORS_FILE"
            fi
        else
            echo -e "${RED}FAILED (HTTP $http_code)${NC}"
            echo "FAILED: $mirror_url - HTTP $http_code" >> "$FAILED_MIRRORS_FILE"
        fi
    else
        echo -e "${RED}FAILED (timeout/error)${NC}"
        echo "FAILED: $mirror_url - Timeout or connection error" >> "$FAILED_MIRRORS_FILE"
    fi
    
    rm -f "$temp_file"
    return 1
}

# Function to analyze results and create best mirrors list
analyze_results() {
    log "Analyzing test results..."
    
    if [[ ! -f "${RESULTS_FILE}.csv" ]]; then
        error "No test results found!"
        return 1
    fi
    
    # Sort by speed (descending) and create best mirrors list
    sort -t',' -k1 -nr "${RESULTS_FILE}.csv" > "${RESULTS_FILE}.sorted"
    
    echo "# Best Arch Linux Mirrors (tested $(date))" > "$BEST_MIRRORS_FILE"
    echo "# Sorted by download speed (fastest first)" >> "$BEST_MIRRORS_FILE"
    echo "# Format: Speed(Mbps), Time(s), Mirror URL" >> "$BEST_MIRRORS_FILE"
    echo "" >> "$BEST_MIRRORS_FILE"
    
    local count=0
    while IFS=',' read -r speed time_total mirror_url; do
        if [[ $count -lt 10 ]]; then  # Top 10 mirrors
            echo "# ${speed} Mbps - ${time_total}s" >> "$BEST_MIRRORS_FILE"
            echo "Server = ${mirror_url}\$repo/os/\$arch" >> "$BEST_MIRRORS_FILE"
            ((count++))
        fi
    done < "${RESULTS_FILE}.sorted"
    
    echo "" >> "$BEST_MIRRORS_FILE"
    echo "# Copy the above servers to /etc/pacman.d/mirrorlist" >> "$BEST_MIRRORS_FILE"
}

# Function to display summary
show_summary() {
    echo ""
    log "=== Mirror Test Summary ==="
    
    if [[ -f "${RESULTS_FILE}.sorted" ]]; then
        echo ""
        echo -e "${BLUE}Top 5 Fastest Mirrors:${NC}"
        head -5 "${RESULTS_FILE}.sorted" | while IFS=',' read -r speed time_total mirror_url; do
            echo "  ${speed} Mbps - $mirror_url"
        done
        
        echo ""
        echo -e "${YELLOW}Your Connection Analysis:${NC}"
        local top_speed=$(head -1 "${RESULTS_FILE}.sorted" | cut -d',' -f1)
        local avg_speed=$(awk -F',' '{sum+=$1; count++} END {printf "%.2f", sum/count}' "${RESULTS_FILE}.sorted")
        
        echo "  Fastest mirror: ${top_speed} Mbps"
        echo "  Average speed: ${avg_speed} Mbps"
        
        if (( $(echo "$top_speed < 5" | bc -l) )); then
            echo -e "  ${RED}⚠️  Your connection seems quite slow${NC}"
            echo "     Consider using fewer parallel downloads in pacman.conf"
        elif (( $(echo "$top_speed > 15" | bc -l) )); then
            echo -e "  ${GREEN}✅ Good connection speeds detected${NC}"
        else
            echo -e "  ${YELLOW}📊 Moderate connection speeds${NC}"
        fi
    fi
    
    local total_mirrors=${#MIRRORS[@]}
    local successful_tests=$(wc -l < "${RESULTS_FILE}.csv" 2>/dev/null || echo 0)
    local failed_tests=$(wc -l < "$FAILED_MIRRORS_FILE" 2>/dev/null || echo 0)
    
    echo ""
    echo -e "${BLUE}Test Statistics:${NC}"
    echo "  Total mirrors tested: $total_mirrors"
    echo "  Successful tests: $successful_tests"
    echo "  Failed tests: $failed_tests"
    
    echo ""
    log "Results saved to:"
    echo "  📄 $RESULTS_FILE - Detailed log"
    echo "  📊 ${RESULTS_FILE}.csv - Raw data"
    echo "  🏆 $BEST_MIRRORS_FILE - Ready-to-use mirrorlist"
    echo "  ❌ $FAILED_MIRRORS_FILE - Failed mirrors"
}

# Main execution
main() {
    clear
    echo -e "${BLUE}Arch Linux Mirror Speed Tester${NC}"
    echo "======================================"
    echo "Testing ${#MIRRORS[@]} mirrors optimized for slower connections..."
    echo "This may take 10-15 minutes depending on your connection."
    echo ""
    
    # Check for required tools
    for tool in curl bc; do
        if ! command -v "$tool" &> /dev/null; then
            error "$tool is required but not installed."
            echo "Install with: pacman -S $tool"
            exit 1
        fi
    done
    
    # Initialize result files
    echo "Mirror Speed Test Results - $(date)" > "$RESULTS_FILE"
    echo "Speed(Mbps),Time(s),Mirror_URL" > "${RESULTS_FILE}.csv"
    echo "Failed Mirrors - $(date)" > "$FAILED_MIRRORS_FILE"
    
    log "Starting mirror speed tests..."
    echo ""
    
    local successful_tests=0
    local total_mirrors=${#MIRRORS[@]}
    local current=0
    
    for mirror in "${MIRRORS[@]}"; do
        ((current++))
        echo -n "[$current/$total_mirrors] "
        
        if test_mirror "$mirror"; then
            ((successful_tests++))
        fi
        
        # Small delay to avoid overwhelming servers
        sleep 1
    done
    
    echo ""
    log "Testing completed. $successful_tests/$total_mirrors mirrors successful."
    
    if [[ $successful_tests -gt 0 ]]; then
        analyze_results
        show_summary
        
        echo ""
        echo -e "${GREEN}✅ Testing complete!${NC}"
        echo ""
        echo -e "${YELLOW}To use the best mirrors:${NC}"
        echo "  sudo cp $BEST_MIRRORS_FILE /etc/pacman.d/mirrorlist"
        echo ""
        echo -e "${YELLOW}For pacman optimization with your connection:${NC}"
        echo "  Edit /etc/pacman.conf and set:"
        if (( $(echo "$(head -1 "${RESULTS_FILE}.sorted" | cut -d',' -f1) < 5" | bc -l 2>/dev/null || echo 0) )); then
            echo "    ParallelDownloads = 3"
        else
            echo "    ParallelDownloads = 5"
        fi
    else
        error "No mirrors were successfully tested!"
        echo "Check your internet connection and try again."
    fi
}

# Run the script
main "$@"
