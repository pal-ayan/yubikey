# YubiKey Utilities

YubiKey related scripts and tools.

This repository is intended to grow into a collection of YubiKey-related tooling. The current implemented area is FIDO2-backed SSH key management. Future areas may include PIV and other YubiKey applications.

## Why This Exists

YubiKey workflows often span hardware prompts, local key stubs, command-line tools, and service-specific configuration. This repository aims to make those workflows easier to audit, repeat, and explain.

The current FIDO2 SSH module focuses on:

- creating resident OpenSSH `ed25519-sk` keys on a YubiKey,
- restoring resident SSH key stubs onto another machine,
- preserving useful key metadata where OpenSSH and YubiKey behavior allow it,
- documenting PIN, touch, recovery, and local-file behavior clearly.

## Current Features

- [FIDO2 SSH helpers](fido2-ssh/README.md): create and restore resident `ed25519-sk` SSH keys stored on a YubiKey.
- [Generate flow documentation](fido2-ssh/docs/generate-script-flow.md): Mermaid diagram and explanation for creating resident SSH keys.
- [Restore flow documentation](fido2-ssh/docs/restore-script-flow.md): Mermaid diagrams and explanation for recovering resident SSH key stubs and restoring comments.

## Platform Status

The current FIDO2 SSH scripts are designed to be Linux-compatible, but they have only been validated on macOS so far. See the module README for prerequisites, usage, caveats, and validation notes.

## Security Notice

This repository should not contain real YubiKey serial numbers, credential IDs, private keys, public key blobs, PINs, passphrases, tokens, local machine paths, or personal command output. Documentation examples should use placeholders or generic values.

Generated SSH key stubs and common secret file formats are ignored by `.gitignore`, but always review changes before publishing.

## Contributing

Issues and pull requests are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md), especially the safety rules for sanitized logs, YubiKey serial numbers, credential IDs, key material, PINs, and passphrases.

## License

This repository is licensed under the GNU General Public License v3.0. See [LICENSE](LICENSE).
