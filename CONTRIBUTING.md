# Contributing

Thanks for considering a contribution.

This repository contains security-sensitive YubiKey workflows. Contributions are welcome, but reports, examples, tests, and documentation must avoid exposing private data or hardware identifiers.

## Ways To Contribute

- Report bugs with sanitized reproduction steps.
- Improve documentation, diagrams, caveats, and platform notes.
- Add validation for Linux environments.
- Improve existing FIDO2 SSH scripts without weakening safety checks.
- Propose new YubiKey modules, such as PIV, OATH, or other workflows.

## Before Opening An Issue

Use the issue templates. They are designed to collect useful details while discouraging accidental disclosure of secrets.

Do not include:

- real YubiKey serial numbers,
- credential IDs or resident key IDs,
- private keys, generated SSH key stubs, certificates with private material, or account-linked public key blobs,
- FIDO2 PINs, PIV PINs, passphrases, tokens, recovery codes, or management keys,
- unsanitized `ykman`, `ssh-keygen`, or shell output,
- local absolute home paths or personal machine identifiers.

Use placeholders such as `<serial>`, `<credential-id>`, `<output-directory>`, `<user-id>`, and `<application-string>`.

## Security Reports

Do not open a public issue for vulnerabilities or security-sensitive reports.

Use GitHub private vulnerability reporting:

https://github.com/pal-ayan/yubikey/security/advisories/new

See [SECURITY.md](SECURITY.md) for scope and reporting expectations.

## Pull Request Guidelines

- Keep changes focused.
- Match the existing Bash style and module layout.
- Keep module-specific files inside the module directory, for example `fido2-ssh/`.
- Update the root README when adding, renaming, or removing modules.
- Update module READMEs and module-local `docs/` when behavior changes.
- Update `.github/ISSUE_TEMPLATE/` dropdown options when modules are added, renamed, or removed.
- Do not add generated key stubs, real command output, local machine paths, or personal identifiers.
- Keep new scripts and documentation compatible with GPL-3.0.

## Validation

Run the lightweight checks that apply to your change.

For the current FIDO2 SSH module:

```bash
bash -n fido2-ssh/generate_fido2_ssh_key_using_yubikey.sh
bash -n fido2-ssh/restore_fido2_ssh_keys_from_yubikey.sh
```

Before publishing examples or terminal output, run a sensitive-content scan:

```bash
rg --hidden -n -i 'BEGIN .*PRIVATE KEY|OPENSSH PRIVATE KEY|ssh-rsa|sk-ssh|token|api[_-]?key|secret|password' . --glob '!/.git/**'
rg --hidden -n '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' . --glob '!/.git/**'
rg --hidden -n '[A-Fa-f0-9]{32,}' . --glob '!/.git/**'
rg --hidden -n '[0-9]{8,}' . --glob '!/.git/**'
```

Some matches may be expected in safety documentation, but real secrets, personal identifiers, serials, credential IDs, or key material must not be committed.

## Hardware Tests

Commands such as `ykman fido credentials list`, `ssh-keygen -K`, or key-generation scripts may prompt for a PIN or YubiKey touch.

Only run hardware-touching tests when you intentionally want to test with a connected YubiKey. Never paste PINs, passphrases, private key material, or unsanitized credential output into an issue or pull request.

## Code Of Conduct

Participation in this project is covered by [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
