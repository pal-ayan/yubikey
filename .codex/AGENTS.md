# Repository Guidelines

This repo contains Bash helpers for creating and restoring resident FIDO2 SSH keys on a YubiKey. Treat it as a future public GitHub repository.

## Security And Privacy

- Do not commit personally identifiable information, real YubiKey serial numbers, real credential IDs, email addresses, usernames, local absolute home paths, public key blobs, private key files, passphrases, PINs, tokens, or command output containing any of those values.
- Use placeholders in docs, for example `<serial>`, `<output-directory>`, `<user-id>`, and `<application-string>`.
- Keep generated SSH key stubs and secret material out of the repo. The `.gitignore` intentionally excludes common generated key and secret file patterns.
- Do not make scripts collect, store, echo, or log FIDO2 PINs or local key passphrases. Those prompts should remain owned by `ykman` or `ssh-keygen`.
- Before considering work ready for publication, scan for obvious sensitive material with `rg` patterns for names, emails, long hex strings, key markers, local paths, and large numeric identifiers.

## Script Behavior

- Both scripts should allow exactly one connected YubiKey. Zero or multiple connected YubiKeys must be a clear error.
- Both scripts should remain compatible with macOS and Linux. Linux compatibility is intended, but macOS is the only validated platform until explicit Linux testing is performed.
- If no output directory is provided, default to `~/.ssh`, but do not create it silently. The directory must already exist.
- Output directories must be owned by the current user, writable, and not writable by group or others.
- Preserve symlink and non-regular-file protections. Do not overwrite symlinks or unusual filesystem objects.
- Preserve non-zero exits for real failures: validation errors, dependency failures, unsafe paths, failed generation, selected install failures, metadata parsing failures, ambiguous metadata that blocks requested restoration, and selected comment update failures.
- User-chosen no-op paths, such as declining restore installs or comment updates, may exit successfully.
- Avoid guessing when metadata is ambiguous. Report ambiguity and skip the unsafe action.

## Bash Style

- Use Bash features deliberately and keep scripts readable for users who may audit them before running.
- Quote variable expansions unless there is a specific reason not to.
- Use arrays for command construction, especially when passing user-provided values to `ssh-keygen`.
- Validate all user-controlled labels before using them in filenames, application strings, comments, or command options.
- Keep CSV parsing CSV-aware. Do not replace the parser with simple `awk -F,`, `cut -d,`, or `IFS=, read` logic.
- Do not introduce destructive commands or automatic deletion of YubiKey credentials.
- Keep temporary files restricted and clean them up with traps where practical.

## Documentation

- Keep `README.md` focused on prerequisites, usage, output directory rules, caveats, and platform support.
- Do not embed the full scripts into documentation.
- Keep script logic explanations in separate Markdown files under `docs/` with Mermaid diagrams.
- Documentation examples must use placeholders or generic values, not real terminal output copied from a user machine.
- Maintain the caveat that Linux support is intended but only validated on macOS until that changes.

## Validation

Run these lightweight checks after script changes:

```bash
bash -n generate_fido2_ssh_key_using_yubikey.sh
bash -n restore_fido2_ssh_keys_from_yubikey.sh
```

Run publication-safety scans after doc or example changes:

```bash
rg --hidden -n -i 'BEGIN .*PRIVATE KEY|OPENSSH PRIVATE KEY|ssh-rsa|sk-ssh|token|api[_-]?key|secret|password' .
rg --hidden -n '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' .
rg --hidden -n '[A-Fa-f0-9]{32,}' .
rg --hidden -n '[0-9]{8,}' .
```

Only run hardware-touching commands such as `ykman fido credentials list`, `ssh-keygen -K`, or the generation script itself when the user explicitly wants an interactive hardware test.
