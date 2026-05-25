#!/bin/bash

umask 077

if ! command -v ssh-keygen &> /dev/null; then
    echo "Error: ssh-keygen is not installed."
    exit 1
fi

if ! command -v ykman &> /dev/null; then
    echo "Error: ykman (YubiKey Manager) is not installed."
    exit 1
fi

if ! command -v xxd &> /dev/null; then
    echo "Error: xxd is not installed. It is required to decode FIDO2 user IDs."
    exit 1
fi

usage() {
    echo "Usage: $0 [output_directory]"
    echo ""
    echo "If output_directory is omitted, ~/.ssh must already exist."
    echo "Use '.' to install recovered keys into the current directory."
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

is_all_zero_hex() {
    local value="$1"
    [ -n "$value" ] && [[ "$value" =~ ^0+$ ]]
}

is_safe_comment() {
    [[ "$1" =~ ^[A-Za-z0-9._@+-]{1,31}$ ]]
}

hex_to_text() {
    local value="$1"

    while [[ "$value" == *00 ]]; do
        value="${value%00}"
    done

    printf "%s" "$value" | xxd -r -p 2>/dev/null
}

discover_recovered_key_files() {
    local candidate

    RECOVERED_KEY_FILES=()

    for candidate in "$TMP_DIR"/id_*_sk_rk_*; do
        if [ ! -f "$candidate" ]; then
            continue
        fi

        if [[ "$candidate" == *.pub ]]; then
            continue
        fi

        RECOVERED_KEY_FILES+=("$candidate")
    done
}

get_target_status() {
    local source_key="$1"
    local file_name
    local target_key
    local target_pub

    file_name="${source_key##*/}"
    target_key="$SSH_DIR/$file_name"
    target_pub="${target_key}.pub"
    TARGET_STATUS="new"

    if [ -L "$target_key" ] || [ -L "$target_pub" ]; then
        TARGET_STATUS="blocked: symlinked local file"
        return 2
    fi

    if { [ -e "$target_key" ] && [ ! -f "$target_key" ]; } || { [ -e "$target_pub" ] && [ ! -f "$target_pub" ]; }; then
        TARGET_STATUS="blocked: non-regular local file"
        return 2
    fi

    if [ -e "$target_key" ] || [ -e "$target_pub" ]; then
        TARGET_STATUS="exists"
        return 1
    fi

    return 0
}

add_selected_recovered_key() {
    local selected="$1"
    local index
    local key_file
    local file_name

    selected=$(trim "$selected")
    if [[ ! "$selected" =~ ^[0-9]+$ ]]; then
        echo "Skipping invalid selection: $selected"
        RESTORE_EXIT_STATUS=1
        return
    fi

    index=$((selected - 1))
    if [ "$index" -lt 0 ] || [ "$index" -ge "${#RECOVERED_KEY_FILES[@]}" ]; then
        echo "Skipping out-of-range selection: $selected"
        RESTORE_EXIT_STATUS=1
        return
    fi

    if [[ "$SELECTED_RECOVERED_INDEXES" == *" $index "* ]]; then
        return
    fi

    key_file="${RECOVERED_KEY_FILES[$index]}"
    file_name="${key_file##*/}"

    if ! get_target_status "$key_file"; then
        if [ "$TARGET_STATUS" != "exists" ]; then
            echo "Skipping $file_name: $TARGET_STATUS"
            RESTORE_EXIT_STATUS=1
            return
        fi
    fi

    SELECTED_RECOVERED_KEY_FILES+=("$key_file")
    SELECTED_RECOVERED_INDEXES="${SELECTED_RECOVERED_INDEXES}${index} "
}

select_recovered_keys_to_install() {
    local i
    local key_file
    local file_name
    local status
    local has_existing_or_blocked=0
    local install_choice
    local selection
    local selected

    SELECTED_RECOVERED_KEY_FILES=()
    SELECTED_RECOVERED_INDEXES=" "

    echo ""
    echo "Recovered SSH keys:"
    for ((i = 0; i < ${#RECOVERED_KEY_FILES[@]}; i++)); do
        key_file="${RECOVERED_KEY_FILES[$i]}"
        file_name="${key_file##*/}"
        get_target_status "$key_file"
        status="$TARGET_STATUS"

        if [ "$status" != "new" ]; then
            has_existing_or_blocked=1
        fi

        printf "  %d. %s [%s]\n" "$((i + 1))" "$file_name" "$status"
    done

    if [ "$has_existing_or_blocked" -eq 0 ]; then
        SELECTED_RECOVERED_KEY_FILES=("${RECOVERED_KEY_FILES[@]}")
        return
    fi

    echo ""
    echo "Choosing all installs every non-blocked key above and overwrites files marked [exists]."
    read -p "Install recovered keys? [a]ll/[s]elect/[n]one: " install_choice
    install_choice=$(trim "$install_choice")

    case "$install_choice" in
        a|A|all|ALL)
            for key_file in "${RECOVERED_KEY_FILES[@]}"; do
                file_name="${key_file##*/}"
                if ! get_target_status "$key_file"; then
                    if [ "$TARGET_STATUS" != "exists" ]; then
                        echo "Skipping $file_name: $TARGET_STATUS"
                        RESTORE_EXIT_STATUS=1
                        continue
                    fi
                fi

                SELECTED_RECOVERED_KEY_FILES+=("$key_file")
            done
            ;;
        s|S|select|SELECT)
            read -p "Enter key numbers to install, separated by commas: " selection
            selection=$(trim "$selection")
            ;;
        n|N|no|NO|"")
            echo "No recovered SSH keys selected for install."
            exit 0
            ;;
        *)
            if [[ "$install_choice" =~ ^[0-9][0-9,[:space:]]*$ ]]; then
                selection="$install_choice"
            else
                echo "Invalid choice. No recovered SSH keys installed."
                exit 1
            fi
            ;;
    esac

    if [ -n "${selection:-}" ]; then
        IFS=',' read -ra SELECTED_NUMBERS <<< "$selection"
        for selected in "${SELECTED_NUMBERS[@]}"; do
            add_selected_recovered_key "$selected"
        done
    fi

    if [ ${#SELECTED_RECOVERED_KEY_FILES[@]} -eq 0 ]; then
        echo "No installable recovered SSH keys were selected."
        exit "$RESTORE_EXIT_STATUS"
    fi
}

metadata_for_key_file() {
    local file_name="$1"
    local i
    local rp_id
    local comment
    local key_name
    local candidate
    local match_count=0
    local matched_rp_id=""
    local matched_comment=""

    COMMENT_FOR_KEY=""
    RP_ID_FOR_KEY=""
    METADATA_MATCH_STATUS="none"

    for ((i = 0; i < ${#META_RP_IDS[@]}; i++)); do
        rp_id="${META_RP_IDS[$i]}"
        comment="${META_COMMENTS[$i]}"
        key_name="${rp_id#ssh:}"

        for candidate in "id_ed25519_sk_rk_${key_name}" "id_ecdsa_sk_rk_${key_name}"; do
            if [ "$file_name" = "$candidate" ]; then
                match_count=$((match_count + 1))
                matched_rp_id="$rp_id"
                matched_comment="$comment"
                break
            fi

            if [ -n "$comment" ] && [ "$file_name" = "${candidate}_${comment}" ]; then
                match_count=$((match_count + 1))
                matched_rp_id="$rp_id"
                matched_comment="$comment"
                break
            fi
        done
    done

    if [ "$match_count" -eq 0 ]; then
        return 1
    fi

    if [ "$match_count" -gt 1 ]; then
        METADATA_MATCH_STATUS="ambiguous"
        return 2
    fi

    COMMENT_FOR_KEY="$matched_comment"
    RP_ID_FOR_KEY="$matched_rp_id"
    METADATA_MATCH_STATUS="matched"
    return 0
}

install_recovered_key() {
    local source_key="$1"
    local file_name
    local target_key
    local source_pub
    local target_pub

    INSTALLED_KEY_FILE=""
    file_name="${source_key##*/}"
    target_key="$SSH_DIR/$file_name"
    source_pub="${source_key}.pub"
    target_pub="${target_key}.pub"

    if [ -L "$target_key" ] || [ -L "$target_pub" ]; then
        echo ""
        echo "Warning: Refusing to overwrite symlinked key files for $file_name in $SSH_DIR."
        echo "Remove the symlink manually if you really want to replace this key."
        return 1
    fi

    if { [ -e "$target_key" ] && [ ! -f "$target_key" ]; } || { [ -e "$target_pub" ] && [ ! -f "$target_pub" ]; }; then
        echo ""
        echo "Warning: Refusing to overwrite non-regular key files for $file_name in $SSH_DIR."
        echo "Move or remove the existing path manually if you really want to replace this key."
        return 1
    fi

    if ! cp -p "$source_key" "$target_key"; then
        echo "Warning: Could not install $target_key"
        return 1
    fi

    if [ -f "$source_pub" ]; then
        if ! cp -p "$source_pub" "$target_pub"; then
            echo "Warning: Could not install $target_pub"
            return 1
        fi
    else
        echo "Warning: No public key file was recovered for $file_name"
    fi

    INSTALLED_KEY_FILE="$target_key"
    echo "Installed $target_key"
    return 0
}

update_comment() {
    local key_file="$1"
    local comment="$2"

    echo ""
    echo "Updating comment for $key_file -> $comment"
    echo "If prompted, enter the local key file passphrase for $key_file."
    if ssh-keygen -c -C "$comment" -f "$key_file"; then
        echo "Updated $key_file"
    else
        echo "Warning: Could not update comment for $key_file"
        return 1
    fi
}

update_selected_comments() {
    local selection="$1"
    local selected
    local index

    selection=$(trim "$selection")

    if [ -z "$selection" ]; then
        echo "No keys selected."
        exit "$RESTORE_EXIT_STATUS"
    fi

    IFS=',' read -ra SELECTED_NUMBERS <<< "$selection"
    for selected in "${SELECTED_NUMBERS[@]}"; do
        selected=$(trim "$selected")
        if [[ ! "$selected" =~ ^[0-9]+$ ]]; then
            echo "Skipping invalid selection: $selected"
            COMMENT_UPDATE_FAILED=1
            continue
        fi

        index=$((selected - 1))
        if [ "$index" -lt 0 ] || [ "$index" -ge "${#KEY_FILES[@]}" ]; then
            echo "Skipping out-of-range selection: $selected"
            COMMENT_UPDATE_FAILED=1
            continue
        fi

        if ! update_comment "${KEY_FILES[$index]}" "${KEY_COMMENTS[$index]}"; then
            COMMENT_UPDATE_FAILED=1
        fi
    done
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
require_single_yubikey

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/yk-ssh-restore.XXXXXX")

if [ -z "$TMP_DIR" ] || [ ! -d "$TMP_DIR" ]; then
    echo "Error: Could not create temporary recovery directory."
    exit 1
fi

cleanup() {
    rm -rf "$TMP_DIR"
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

cd "$TMP_DIR" || {
    echo "Error: Could not enter temporary recovery directory."
    exit 1
}

echo "Recovering resident SSH keys from the YubiKey into a temporary directory."
echo "Detected YubiKey with Serial: $SERIAL"
echo "Recovered keys will be installed into $SSH_DIR after download."
echo "Next prompts come from ssh-keygen/OpenSSH:"
echo "  When you see 'Enter PIN for authenticator:', type your FIDO2 PIN and press Enter."
echo "  If prompted for a passphrase, it is for the recovered local SSH key stub."
echo "  OpenSSH may show the first recovered filename while applying that passphrase to this recovery run."
echo "----------------------------------------"

if ! ssh-keygen -K; then
    echo ""
    echo "Error: ssh-keygen -K failed."
    exit 1
fi

KEY_FILES=()
KEY_COMMENTS=()
KEY_RP_IDS=()
META_RP_IDS=()
META_COMMENTS=()
RECOVERED_KEY_FILES=()
SELECTED_RECOVERED_KEY_FILES=()
SELECTED_RECOVERED_INDEXES=""
INSTALLED_KEY_FILES=()
INSTALLED_FILE_NAMES=()
INSTALLED_COUNT=0
INSTALL_FAILED=0
METADATA_PARSE_FAILED=0
COMMENT_UPDATE_FAILED=0
RESTORE_EXIT_STATUS=0

discover_recovered_key_files

if [ ${#RECOVERED_KEY_FILES[@]} -eq 0 ]; then
    echo ""
    echo "No resident SSH key files were recovered by ssh-keygen -K."
    exit 0
fi

select_recovered_keys_to_install

for key_file in "${SELECTED_RECOVERED_KEY_FILES[@]}"; do
    file_name="${key_file##*/}"

    if ! install_recovered_key "$key_file"; then
        INSTALL_FAILED=1
        continue
    fi

    INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
    INSTALLED_KEY_FILES+=("$INSTALLED_KEY_FILE")
    INSTALLED_FILE_NAMES+=("$file_name")
done

if [ "$INSTALLED_COUNT" -eq 0 ]; then
    echo ""
    echo "No recovered SSH keys were installed."
    exit 1
fi

if [ "$INSTALL_FAILED" -eq 1 ]; then
    RESTORE_EXIT_STATUS=1
fi

echo ""
echo "Reading YubiKey resident credential metadata for comment restoration..."
echo "Next prompt comes from ykman:"
echo "  When you see 'Enter your PIN:', type your FIDO2 PIN and press Enter."

if ! CREDS_CSV=$(ykman fido credentials list --csv); then
    echo ""
    echo "Warning: Could not read FIDO2 credential metadata from the YubiKey."
    echo "Recovered SSH keys were installed, but comments were not restored."
    exit 1
fi

while IFS= read -r csv_line; do
    comment=""

    if ! parse_csv_line "$csv_line"; then
        echo "Warning: Could not parse a ykman CSV row; comment restoration metadata may be incomplete."
        METADATA_PARSE_FAILED=1
        continue
    fi

    credential_id="${CSV_FIELDS[0]:-}"
    rp_id="${CSV_FIELDS[1]:-}"
    user_id="${CSV_FIELDS[4]:-}"

    if [ "$credential_id" = "credential_id" ]; then
        continue
    fi

    rp_id=$(trim "$rp_id")
    user_id=$(trim "$user_id")

    if [[ "$rp_id" != ssh:* ]]; then
        continue
    fi

    if [ -n "$user_id" ] && ! is_all_zero_hex "$user_id"; then
        comment=$(hex_to_text "$user_id")
        if ! is_safe_comment "$comment"; then
            echo "Skipping comment restoration metadata for $rp_id: decoded user_id '$comment' is not a safe comment value."
            comment=""
        fi
    fi

    META_RP_IDS+=("$rp_id")
    META_COMMENTS+=("$comment")
done <<< "$CREDS_CSV"

if [ "$METADATA_PARSE_FAILED" -eq 1 ]; then
    RESTORE_EXIT_STATUS=1
fi

for ((i = 0; i < ${#INSTALLED_KEY_FILES[@]}; i++)); do
    INSTALLED_KEY_FILE="${INSTALLED_KEY_FILES[$i]}"
    file_name="${INSTALLED_FILE_NAMES[$i]}"

    metadata_for_key_file "$file_name"
    metadata_status=$?
    if [ "$metadata_status" -eq 1 ]; then
        echo "No YubiKey metadata match found for $file_name; comment restoration is unavailable for this key."
        continue
    fi

    if [ "$metadata_status" -eq 2 ]; then
        echo "Ambiguous YubiKey metadata match found for $file_name; skipping comment restoration for this key."
        RESTORE_EXIT_STATUS=1
        continue
    fi

    if [ -z "$COMMENT_FOR_KEY" ]; then
        echo "No resident user ID stored for $RP_ID_FOR_KEY; comment restoration is unavailable for this key."
        continue
    fi

    KEY_FILES+=("$INSTALLED_KEY_FILE")
    KEY_COMMENTS+=("$COMMENT_FOR_KEY")
    KEY_RP_IDS+=("$RP_ID_FOR_KEY")
done

if [ ${#KEY_FILES[@]} -eq 0 ]; then
    echo ""
    echo "Installed recovered SSH keys, but none had unambiguous non-empty resident user IDs for comment restoration."
    echo "Existing keys created without -O user have all-zero user IDs and cannot provide a comment to restore."
    exit "$RESTORE_EXIT_STATUS"
fi

echo ""
echo "Installed SSH keys with comment metadata:"
for ((i = 0; i < ${#KEY_FILES[@]}; i++)); do
    printf "  %d. %s -> %s (%s)\n" "$((i + 1))" "${KEY_FILES[$i]}" "${KEY_COMMENTS[$i]}" "${KEY_RP_IDS[$i]}"
done

echo ""
read -p "Update local SSH key comments from resident user IDs? [a]ll/[s]elect/[n]one: " UPDATE_CHOICE
UPDATE_CHOICE=$(trim "$UPDATE_CHOICE")

case "$UPDATE_CHOICE" in
    a|A|all|ALL)
        for ((i = 0; i < ${#KEY_FILES[@]}; i++)); do
            if ! update_comment "${KEY_FILES[$i]}" "${KEY_COMMENTS[$i]}"; then
                COMMENT_UPDATE_FAILED=1
            fi
        done
        ;;
    s|S|select|SELECT)
        read -p "Enter key numbers to update, separated by commas: " SELECTION
        update_selected_comments "$SELECTION"
        ;;
    n|N|no|NO|"")
        echo "No comments updated."
        ;;
    *)
        if [[ "$UPDATE_CHOICE" =~ ^[0-9][0-9,[:space:]]*$ ]]; then
            update_selected_comments "$UPDATE_CHOICE"
        else
            echo "Invalid choice. No comments updated."
            exit 1
        fi
        ;;
esac

if [ "$COMMENT_UPDATE_FAILED" -eq 1 ]; then
    RESTORE_EXIT_STATUS=1
fi

exit "$RESTORE_EXIT_STATUS"
