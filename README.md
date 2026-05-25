# YubiKey FIDO2 SSH Key Helpers

Small Bash helpers for creating and restoring resident `ed25519-sk` SSH keys on a YubiKey. The scripts are designed around one physical YubiKey at a time and use the YubiKey serial number in SSH application strings and local filenames.

These scripts are Linux-compatible by design, but they have only been validated on macOS so far.

## Scripts

- `generate_fido2_ssh_key_using_yubikey.sh`: creates one resident FIDO2 SSH key on the connected YubiKey.
- `restore_fido2_ssh_keys_from_yubikey.sh`: recovers resident SSH key stubs from the connected YubiKey and installs selected files locally.

Flow diagrams:

- [Generate Script Flow](docs/generate-script-flow.md)
- [Restore Script Flow](docs/restore-script-flow.md)

## Prerequisites

- Bash.
- OpenSSH with FIDO2/security-key support.
- YubiKey Manager CLI: `ykman`.
- A YubiKey with FIDO2 enabled.
- A configured FIDO2 PIN on the YubiKey.
- Exactly one YubiKey connected while either script runs.
- For restore only: `xxd`, used to decode resident user IDs.

macOS notes:

- Install OpenSSH through Homebrew. Apple's bundled OpenSSH may not include the FIDO2 support needed for resident key recovery.
- Typical Homebrew packages are `openssh` and `ykman`.

Linux notes:

- OpenSSH must be built with FIDO2/libfido2 support.
- Your user may need YubiKey udev rules or equivalent device permissions for `ykman` and OpenSSH FIDO access.
- `xxd` may be packaged separately, often through `vim-common` or an equivalent package.

## Output Directory Rules

Both scripts accept an optional output directory:

```bash
./generate_fido2_ssh_key_using_yubikey.sh [output_directory]
./restore_fido2_ssh_keys_from_yubikey.sh [output_directory]
```

If no directory is provided, the scripts use `~/.ssh`, but that directory must already exist. They will not create it silently.

The output directory must:

- exist,
- be writable,
- be owned by the current user,
- not be writable by group or others.

Use `.` to write into the current directory.

## Generate Usage

Make the script executable:

```bash
chmod +x generate_fido2_ssh_key_using_yubikey.sh
```

Run with the default `~/.ssh` output directory:

```bash
./generate_fido2_ssh_key_using_yubikey.sh
```

Or write to a chosen directory:

```bash
./generate_fido2_ssh_key_using_yubikey.sh .
./generate_fido2_ssh_key_using_yubikey.sh /path/to/output-directory
```

The script will:

- verify exactly one YubiKey is connected,
- prompt for a key suffix,
- prompt for an optional resident user ID,
- reject unsafe suffix/user ID values,
- check for local filename conflicts,
- check the YubiKey for an existing credential with the same SSH application string,
- generate a resident `ed25519-sk` SSH key.

The suffix and resident user ID allow letters, numbers, `.`, `_`, `@`, `+`, and `-`, up to 31 characters. They cannot contain whitespace, slashes, commas, or path separators.

If a resident user ID is provided, the script also uses it as the local SSH public key comment and appends it to the generated local filename to match OpenSSH recovery behavior.

## Restore Usage

Make the script executable:

```bash
chmod +x restore_fido2_ssh_keys_from_yubikey.sh
```

Run with the default `~/.ssh` output directory:

```bash
./restore_fido2_ssh_keys_from_yubikey.sh
```

Or restore to a chosen directory:

```bash
./restore_fido2_ssh_keys_from_yubikey.sh .
./restore_fido2_ssh_keys_from_yubikey.sh /path/to/output-directory
```

The script will:

- verify exactly one YubiKey is connected,
- run `ssh-keygen -K` in a temporary directory,
- list recovered SSH key stubs,
- let you install all, selected keys, or none,
- refuse to overwrite symlinks or non-regular files,
- read resident credential metadata with `ykman`,
- optionally update local SSH key comments from resident user IDs.

When updating comments, you can choose all, selected key numbers, none, or enter numbers directly when prompted.

## Caveats

- Only resident SSH keys can be restored from the YubiKey.
- Existing credentials are not deleted by these scripts.
- The restore script can restore local key stubs, but custom SSH comments are only recoverable when the key was created with a non-empty resident user ID.
- If metadata matching is ambiguous, restore skips comment restoration for that key instead of guessing.
- OpenSSH may show the first recovered filename when asking for the local key-stub passphrase during restore. That prompt protects recovered local files, not a single YubiKey credential.
- The restore script uses a temporary directory and removes it on normal exit and common interrupt signals. It cannot clean up after `SIGKILL`, power loss, or a hard crash.
- PATH hardening is not implemented yet. Run these scripts from a trusted shell environment.
- Linux support is intended, but current validation has only been performed on macOS.

## Typical Key Roles

For a single YubiKey, useful suffixes and resident user IDs might be:

- `servers` for SSH access to servers or personal machines,
- `github_auth` or `github-auth` for GitHub SSH authentication,
- `github_sign` or `github-sign` for Git commit signing.

Use one naming style consistently. The scripts allow both `_` and `-`.

## Exit Behavior

The scripts return non-zero on validation errors, unsafe output paths, duplicate credentials, failed key generation, selected restore install failures, metadata parsing errors, and selected comment-update failures.

User-chosen no-op paths, such as selecting no keys to restore or choosing not to update comments, exit successfully.
