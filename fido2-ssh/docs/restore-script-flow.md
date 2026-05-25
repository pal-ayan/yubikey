# Restore Script Flow

This document explains what `restore_fido2_ssh_keys_from_yubikey.sh` does without requiring you to read the script directly. The script recovers resident SSH key stubs from one connected YubiKey, installs selected files into an output directory, and can update local key comments from resident user ID metadata.

## Main Flow

```mermaid
flowchart TD
    Start([Start]) --> Args{Help requested?}
    Args -->|yes| Usage[Print usage and exit]
    Args -->|no| Deps[Check ssh-keygen, ykman, and xxd]

    Deps --> DepsOk{Dependencies found?}
    DepsOk -->|no| DepError[Print missing dependency and exit]
    DepsOk -->|yes| Output[Resolve output directory]

    Output --> ValidateDir{Output directory valid?}
    ValidateDir -->|no| DirError[Print error and exit]
    ValidateDir -->|yes| ListKeys[Run ykman list]

    ListKeys --> KeyCount{Connected YubiKeys}
    KeyCount -->|zero| NoKey[Print no YubiKey error and exit]
    KeyCount -->|multiple| MultiKey[Print multiple YubiKeys error and exit]
    KeyCount -->|one| Serial[Extract YubiKey serial number]

    Serial --> TempDir[Create temporary restore directory]
    TempDir --> Trap[Install cleanup traps]
    Trap --> Recover[Run ssh-keygen -K inside temporary directory]

    Recover --> OpenSshPrompts[OpenSSH may prompt for PIN, touch, and local passphrase]
    OpenSshPrompts --> RecoverOk{Recovery succeeded?}
    RecoverOk -->|no| RecoverError[Print recovery error, clean up temp directory, exit non-zero]
    RecoverOk -->|yes| Discover[Find recovered private key stubs]

    Discover --> AnyKeys{Any recovered keys?}
    AnyKeys -->|no| NoKeys[Print no keys found, clean up, exit]
    AnyKeys -->|yes| Status[List each recovered key and local install status]

    Status --> AllNew{All recovered keys are new locally?}
    AllNew -->|yes| AutoSelect[Select all recovered keys]
    AllNew -->|no| InstallPrompt[Prompt for all, selected numbers, none, or direct numbers]

    InstallPrompt --> Selection{Any keys selected?}
    AutoSelect --> Install
    Selection -->|no| NoInstall[Clean up and exit]
    Selection -->|yes| Install[Install selected non-blocked private and public files]

    Install --> InstalledAny{Any selected keys installed?}
    InstalledAny -->|no| InstallFailed[Clean up and exit with failure if selected installs failed]
    InstalledAny -->|yes| Metadata[Read YubiKey resident credential metadata with ykman CSV]

    Metadata --> MetadataOk{Metadata readable and parseable?}
    MetadataOk -->|no| MetadataError[Report metadata error and exit non-zero after cleanup]
    MetadataOk -->|yes| Match[Match installed keys to resident metadata]

    Match --> Candidates{Any unambiguous comment candidates?}
    Candidates -->|no| DoneNoComments[Clean up and exit with current status]
    Candidates -->|yes| CommentPrompt[Prompt for all, selected numbers, none, or direct numbers]

    CommentPrompt --> CommentSelection{Any comment updates selected?}
    CommentSelection -->|no| DoneNoUpdate[Clean up and exit with current status]
    CommentSelection -->|yes| UpdateComments[Run ssh-keygen -c -C for selected keys]

    UpdateComments --> UpdateOk{All selected comments updated?}
    UpdateOk -->|no| UpdateFailed[Clean up and exit non-zero]
    UpdateOk -->|yes| Success[Clean up and exit successfully]
```

## Install Selection

The restore script first downloads all recoverable resident SSH key stubs into a temporary directory. It then lets you choose which recovered files should be installed into the output directory.

Each recovered key is classified as:

- `new`: no matching local private or public file exists.
- `exists`: a matching local private or public file already exists.
- `blocked`: the matching local file is a symlink or another non-regular file, so the script refuses to overwrite it.

If every recovered key is new, all keys are selected automatically. If any local conflict exists, the script asks whether to install all, selected keys, none, or a direct numeric list.

## Metadata Matching

```mermaid
flowchart TD
    Installed[Installed local key] --> ParseName[Read recovered filename]
    ParseName --> MetadataRows[Compare against parsed YubiKey SSH credential metadata]
    MetadataRows --> Count{Number of possible metadata matches}

    Count -->|zero| NoMatch[No comment restoration for this key]
    Count -->|one| OneMatch[Use resident user ID as comment candidate]
    Count -->|multiple| Ambiguous[Skip comment restoration and report ambiguity]

    OneMatch --> SafeComment{Decoded user ID is safe and non-empty?}
    SafeComment -->|no| NoCandidate[No comment candidate]
    SafeComment -->|yes| Candidate[Offer key for comment update]
```

The script does not guess when metadata is ambiguous. Ambiguity can happen if different resident credentials can produce the same recovered filename shape after combining suffix and resident user ID.

## Comment Restoration

OpenSSH recovery writes public key comments based on the resident credential application string. If a key was originally created with a resident user ID, this script can decode that user ID from the YubiKey metadata and apply it as the local SSH key comment.

Comment updates are optional. You can update all offered keys, selected key numbers, no keys, or enter numbers directly at the prompt.

## Temporary Directory Cleanup

Recovered files are first written to a temporary directory created with restrictive permissions. The script removes that directory on normal exit and common interrupt signals.

The temporary directory cannot be cleaned automatically after `SIGKILL`, power loss, or a hard crash. In that case, remove leftover `yk-ssh-restore.*` directories from your system temporary directory after confirming they are not from a running restore.

## Exit Status

The script exits non-zero for validation errors, dependency failures, unsafe output paths, failed recovery, selected install failures, metadata parse errors, ambiguous metadata that blocks requested comment restoration, and selected comment-update failures.

User-chosen no-op paths, such as selecting no keys to install or declining comment updates, exit successfully.
