# Security Policy

## Supported Versions

This repository is early-stage and does not currently publish versioned releases.

Security fixes apply to the default branch, `main`, until versioned releases are introduced.

## Reporting A Vulnerability

Do not open a public issue for vulnerabilities or security-sensitive reports.

Use GitHub private vulnerability reporting:

https://github.com/pal-ayan/yubikey/security/advisories/new

Include:

- a clear summary of the issue,
- affected script, module, or documentation path,
- sanitized reproduction steps,
- expected impact,
- relevant environment details.

Do not include:

- FIDO2 PINs, PIV PINs, passphrases, tokens, or recovery codes,
- private keys, generated SSH key stubs, certificates with private material, or public key blobs tied to a real account,
- real YubiKey serial numbers,
- credential IDs, resident key IDs, or unsanitized `ykman` output,
- local absolute home paths or other personal machine identifiers,
- exploit details that would let someone attack users before a fix is available.

## Public Issues

Use public issues only for non-sensitive bugs, documentation problems, feature requests, or high-level security questions that do not disclose exploitable details.

If you are unsure whether a report is sensitive, use private vulnerability reporting.

## Scope

In scope:

- scripts and tooling in this repository,
- documentation that could cause unsafe YubiKey, SSH, FIDO2, or future module behavior,
- workflows that could expose secrets, private key material, credential identifiers, or sensitive device metadata.

Out of scope:

- vulnerabilities in YubiKey firmware, OpenSSH, `ykman`, operating systems, GitHub, or other upstream dependencies,
- lost or compromised personal credentials,
- reports based only on social engineering or physical access without a repo-specific issue.

## Response Expectations

This is a personal open-source project. I will review valid private reports as availability allows.

For confirmed issues, I will aim to:

- acknowledge the report,
- assess impact,
- prepare a fix or documentation update,
- publish the fix before discussing sensitive details publicly.
