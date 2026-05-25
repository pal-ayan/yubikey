#!/bin/bash

umask 077

usage() {
    echo "Usage: $0 [output_directory]"
    echo ""
    echo "If output_directory is omitted, ~/.ssh must already exist."
    echo "Use '.' to generate the key into the current directory."
}

trim() {
    printf "%s" "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

parse_csv_line() {
    local line="$1"
    local field=""
    local char
    local next
    local i
    local len=${#line}
    local in_quotes=0

    CSV_FIELDS=()

    for ((i = 0; i < len; i++)); do
        char="${line:i:1}"

        if [ "$in_quotes" -eq 1 ]; then
            if [ "$char" = '"' ]; then
                next="${line:i+1:1}"
                if [ "$next" = '"' ]; then
                    field="${field}\""
                    i=$((i + 1))
                else
                    in_quotes=0
                fi
            else
                field="${field}${char}"
            fi
        else
            case "$char" in
                '"')
                    in_quotes=1
                    ;;
                ',')
                    CSV_FIELDS+=("$field")
                    field=""
                    ;;
                *)
                    field="${field}${char}"
                    ;;
            esac
        fi
    done

    if [ "$in_quotes" -eq 1 ]; then
        return 1
    fi

    CSV_FIELDS+=("$field")
    return 0
}

is_safe_label() {
    [[ "$1" =~ ^[A-Za-z0-9._@+-]{1,31}$ ]]
}

validate_output_directory() {
    local dir="$1"
    local dir_info
    local dir_mode
    local dir_owner
    local current_uid

    if [ ! -w "$dir" ]; then
        echo "Error: Output directory is not writable: $dir"
        exit 1
    fi

    dir_info=$(ls -ldn "$dir") || {
        echo "Error: Could not inspect output directory: $dir"
        exit 1
    }

    dir_mode=$(printf "%s\n" "$dir_info" | awk '{print $1}')
    dir_owner=$(printf "%s\n" "$dir_info" | awk '{print $3}')
    current_uid=$(id -u)

    if [ "$dir_owner" != "$current_uid" ]; then
        echo "Error: Output directory must be owned by the current user: $dir"
        exit 1
    fi

    if [ "${dir_mode:5:1}" = "w" ] || [ "${dir_mode:8:1}" = "w" ]; then
        echo "Error: Output directory must not be writable by group or others: $dir"
        echo "Fix permissions with: chmod go-w \"$dir\""
        exit 1
    fi
}

require_single_yubikey() {
    local ykman_output
    local serials
    local count

    if ! ykman_output=$(ykman list); then
        echo "Error: Could not list connected YubiKeys."
        exit 1
    fi

    serials=$(printf "%s\n" "$ykman_output" | sed -n 's/.*Serial: \([0-9][0-9]*\).*/\1/p')
    count=$(printf "%s\n" "$serials" | sed '/^$/d' | wc -l | tr -d ' ')

    if [ "$count" -eq 0 ]; then
        echo "Error: No YubiKey found. Please plug in exactly one YubiKey."
        exit 1
    fi

    if [ "$count" -gt 1 ]; then
        echo "Error: Multiple YubiKeys detected. Please plug in only one YubiKey at a time."
        printf "%s\n" "$serials" | sed '/^$/d; s/^/  Serial: /'
        exit 1
    fi

    SERIAL=$(printf "%s\n" "$serials" | sed '/^$/d' | head -n 1)
}

if [ "$#" -gt 1 ]; then
    usage
    exit 1
fi

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

if [ -n "${1:-}" ]; then
    SSH_DIR="$1"
else
    SSH_DIR="$HOME/.ssh"
    if [ ! -d "$SSH_DIR" ]; then
        echo "Error: Default SSH directory does not exist: $SSH_DIR"
        echo "Create it first with: mkdir -m 700 ~/.ssh"
        echo "Or provide an output directory, for example: $0 ."
        exit 1
    fi
fi

if [ ! -d "$SSH_DIR" ]; then
    echo "Error: Output directory does not exist: $SSH_DIR"
    echo "Create it first or provide a different output directory."
    exit 1
fi

SSH_DIR=$(cd "$SSH_DIR" && pwd -P) || {
    echo "Error: Could not resolve output directory."
    exit 1
}

validate_output_directory "$SSH_DIR"

# 1. Ensure required commands are installed
if ! command -v ssh-keygen &> /dev/null; then
    echo "Error: ssh-keygen is not installed."
    exit 1
fi

if ! command -v ykman &> /dev/null; then
    echo "Error: ykman (YubiKey Manager) is not installed."
    exit 1
fi

# 2. Require exactly one connected YubiKey and capture its serial number
require_single_yubikey

echo "Detected YubiKey with Serial: $SERIAL"
echo "----------------------------------------"

# 3. Prompt user for a suffix
read -p "Enter a suffix for this key (e.g., work, github) [Leave empty for none]: " SUFFIX
SUFFIX=$(trim "$SUFFIX")

if [ -n "$SUFFIX" ] && ! is_safe_label "$SUFFIX"; then
    echo "❌ Error: Suffix can only contain letters, numbers, dot, underscore, at-sign, plus, and hyphen."
    echo "❌ Error: Suffix must be 31 characters or fewer and cannot contain spaces, slashes, commas, or path separators."
    exit 1
fi

# 4. Format the Application String based on input
if [ -z "$SUFFIX" ]; then
    APP_STRING="ssh:yk_${SERIAL}"
    FILE_NAME_BASE="id_ed25519_sk_rk_yk_${SERIAL}"
else
    APP_STRING="ssh:yk_${SERIAL}_${SUFFIX}"
    FILE_NAME_BASE="id_ed25519_sk_rk_yk_${SERIAL}_${SUFFIX}"
fi

# 5. Prompt user for an optional resident user ID
read -p "Enter resident user ID / public key comment (e.g., servers, github-auth) [Leave empty for none]: " RESIDENT_USER_ID
RESIDENT_USER_ID=$(trim "$RESIDENT_USER_ID")

if [ -n "$RESIDENT_USER_ID" ]; then
    if ! is_safe_label "$RESIDENT_USER_ID"; then
        echo "❌ Error: Resident user ID can only contain letters, numbers, dot, underscore, at-sign, plus, and hyphen."
        echo "❌ Error: Resident user ID must be 31 characters or fewer and cannot contain spaces, slashes, commas, or path separators."
        exit 1
    fi

    KEY_COMMENT="$RESIDENT_USER_ID"
    FILE_NAME="${FILE_NAME_BASE}_${RESIDENT_USER_ID}"
else
    KEY_COMMENT="$APP_STRING"
    FILE_NAME="$FILE_NAME_BASE"
fi

TARGET_FILE="$SSH_DIR/$FILE_NAME"

echo ""
echo "Target Application String : $APP_STRING"
echo "Target Output Directory   : $SSH_DIR"
echo "Target Local File         : $TARGET_FILE"
echo "Resident User ID         : ${RESIDENT_USER_ID:-<not set>}"
echo "Public Key Comment        : $KEY_COMMENT"
echo "----------------------------------------"

# 6. Check 1: Do local files already exist?
if [ -e "$TARGET_FILE" ] || [ -L "$TARGET_FILE" ] || [ -e "${TARGET_FILE}.pub" ] || [ -L "${TARGET_FILE}.pub" ]; then
    echo "❌ Error: Local SSH key files for '$FILE_NAME' already exist in $SSH_DIR"
    echo "Aborting to prevent accidental overwrite."
    exit 1
fi

# 7. Check 2: Does the key already exist on the YubiKey?
echo "Checking YubiKey for existing keys..."
echo "Next prompt comes from ykman:"
echo "  When you see 'Enter your PIN:', type your FIDO2 PIN and press Enter."
echo "  If the YubiKey flashes, touch the gold contact."

# Capture the existing credentials from the FIDO2 applet
if ! EXISTING_CREDS=$(ykman fido credentials list --csv); then
    echo ""
    echo "❌ Error: Could not check existing FIDO2 credentials on the YubiKey."
    echo "Aborting because duplicate-key validation could not be completed."
    exit 1
fi

DUPLICATE_FOUND=0
while IFS= read -r csv_line; do
    if ! parse_csv_line "$csv_line"; then
        echo ""
        echo "❌ Error: Could not parse ykman CSV output while checking existing credentials."
        echo "Aborting because duplicate-key validation could not be completed safely."
        exit 1
    fi

    if [ "${CSV_FIELDS[0]:-}" = "credential_id" ]; then
        continue
    fi

    if [ "${CSV_FIELDS[1]:-}" = "$APP_STRING" ]; then
        DUPLICATE_FOUND=1
        break
    fi
done <<< "$EXISTING_CREDS"

if [ "$DUPLICATE_FOUND" -eq 1 ]; then
    echo ""
    echo "❌ Error: A key with the application string '$APP_STRING' already exists on this YubiKey."
    echo "Aborting to prevent duplicate credentials."
    exit 1
fi

echo ""
echo "✅ Validation passed. No conflicts found."
echo "Generating FIDO2 SSH Key..."
echo "Next prompts come from ssh-keygen/OpenSSH:"
echo "  If you see 'You may need to touch your authenticator', touch the YubiKey."
echo "  When you see 'Enter PIN for authenticator:', type your FIDO2 PIN and press Enter."
echo "  Touch the YubiKey again if OpenSSH asks for another touch."
echo "  The passphrase prompt is for the local SSH key file; press Enter twice for no passphrase."
echo "----------------------------------------"

# 8. Generate the SSH key
SSH_KEYGEN_OPTIONS=(-O resident -O application="$APP_STRING" -O verify-required)
if [ -n "$RESIDENT_USER_ID" ]; then
    SSH_KEYGEN_OPTIONS+=(-O user="$RESIDENT_USER_ID")
fi

# 9. Generate and confirm completion
if ssh-keygen -t ed25519-sk "${SSH_KEYGEN_OPTIONS[@]}" -C "$KEY_COMMENT" -f "$TARGET_FILE"; then
    echo ""
    echo "✅ Successfully generated key for YubiKey $SERIAL"
    echo "🔑 Public key to upload to servers: ${TARGET_FILE}.pub"
else
    echo "❌ Error: Key generation failed."
    exit 1
fi
