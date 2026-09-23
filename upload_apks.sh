#!/usr/bin/env sh

# Default parameters
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APK_FOLDER="$SCRIPT_DIR"
REPO="nullcpy/apks"

# Parse arguments (supports positional and named flags like -ApkFolder / --apk-folder / -Repo / --repo)
positional_index=0
while [ $# -gt 0 ]; do
    case "$1" in
        -ApkFolder|--apk-folder|-folder|-f)
            APK_FOLDER="$2"
            shift 2
            ;;
        -Repo|--repo|-r)
            REPO="$2"
            shift 2
            ;;
        -*)
            printf "\033[0;31m[-] Unknown option: %s\033[0m\n" "$1"
            exit 1
            ;;
        *)
            if [ "$positional_index" -eq 0 ]; then
                APK_FOLDER="$1"
            elif [ "$positional_index" -eq 1 ]; then
                REPO="$1"
            fi
            positional_index=$((positional_index + 1))
            shift
            ;;
    esac
done

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Ensure gh CLI is installed
if ! command -v gh >/dev/null 2>&1; then
    printf "${RED}[-] Error: GitHub CLI ('gh') is not installed or not in PATH.${NC}\n"
    printf "${YELLOW}    Install it via your package manager or from https://cli.github.com${NC}\n"
    exit 1
fi

# Ensure gh CLI is authenticated
if ! gh auth status >/dev/null 2>&1; then
    printf "${RED}[-] Error: GitHub CLI is not authenticated.${NC}\n"
    printf "${YELLOW}    Please run 'gh auth login' to log into your GitHub account.${NC}\n"
    exit 1
fi

# Ensure target folder exists
if [ ! -d "$APK_FOLDER" ]; then
    printf "${RED}[-] Error: Folder '%s' does not exist.${NC}\n" "$APK_FOLDER"
    exit 1
fi

ORIGINAL_PWD="$(pwd)"
cd "$APK_FOLDER" || exit 1

# Cleanup function to restore directory on exit
cleanup() {
    cd "$ORIGINAL_PWD" || true
}
trap cleanup EXIT INT TERM

# Find all .apk, .apkm, and .xapk files
# Using find to locate files matching the patterns
MATCHING_FILES=$(find . -type f \( -name "*.apk" -o -name "*.apkm" -o -name "*.xapk" \))

if [ -z "$MATCHING_FILES" ]; then
    printf "${YELLOW}[!] No .apk, .apkm, or .xapk files found in '%s'.${NC}\n" "$APK_FOLDER"
    exit 0
fi

TOTAL_COUNT=$(printf "%s\n" "$MATCHING_FILES" | grep -c -v '^$')
printf "${GREEN}[+] Found %s APK(s) to process for repository '%s'.${NC}\n" "$TOTAL_COUNT" "$REPO"

# Process each file line-by-line
printf "%s\n" "$MATCHING_FILES" | while IFS= read -r apk_path; do
    [ -z "$apk_path" ] && continue

    file_name="$(basename "$apk_path")"

    # Ensure proper naming format: <package_name>-<version>[-<version_code>]-<arch>.<ext>
    case "$file_name" in
        -*|*[!-]*"-")
            # If starts with '-' or invalid
            ;;
    esac

    case "$file_name" in
        *-*)
            case "$file_name" in
                -*)
                    printf "${YELLOW}[-] Skipping '%s': file name does not follow '<pkg_name>-<version>...<ext>' convention.${NC}\n" "$file_name"
                    continue
                    ;;
            esac
            ;;
        *)
            printf "${YELLOW}[-] Skipping '%s': file name does not follow '<pkg_name>-<version>...<ext>' convention.${NC}\n" "$file_name"
            continue
            ;;
    esac

    # Extract package name (everything before the first '-')
    package_name="${file_name%%-*}"

    case "$package_name" in
        *.*)
            ;;
        *)
            printf "${YELLOW}[-] Skipping '%s': '%s' does not look like a valid Android package name (e.g. com.example.app).${NC}\n" "$file_name" "$package_name"
            continue
            ;;
    esac

    printf "=================================================\n"
    printf "[*] Processing: %s\n" "$file_name"
    printf "[*] Package / Tag: %s\n" "$package_name"

    # Check if the release (tag) already exists on GitHub
    if gh release view "$package_name" --repo "$REPO" >/dev/null 2>&1; then
        printf "${CYAN}[+] Release '%s' exists. Uploading asset...${NC}\n" "$package_name"
        # --clobber allows overwriting if the same exact file name already exists in the release
        if gh release upload "$package_name" "$apk_path" --repo "$REPO" --clobber; then
            printf "${GREEN}[+] Successfully uploaded %s to '%s'.${NC}\n" "$file_name" "$package_name"
            rm -f "$apk_path"
            printf "${GRAY}[*] Removed %s from local folder.${NC}\n" "$file_name"
        else
            printf "${RED}[-] Failed to upload %s to '%s'.${NC}\n" "$file_name" "$package_name"
        fi
    else
        printf "${YELLOW}[+] Release '%s' does not exist. Creating and uploading...${NC}\n" "$package_name"
        # Create a new release and upload the file at the same time
        if gh release create "$package_name" "$apk_path" --repo "$REPO" --title "$package_name" --notes " "; then
            printf "${GREEN}[+] Successfully created release '%s' and uploaded %s.${NC}\n" "$package_name" "$file_name"
            rm -f "$apk_path"
            printf "${GRAY}[*] Removed %s from local folder.${NC}\n" "$file_name"
        else
            printf "${RED}[-] Failed to create release '%s'.${NC}\n" "$package_name"
        fi
    fi
done

printf "=================================================\n"
printf "${GREEN}[+] All done!${NC}\n"
