# Security Policy

## Supported versions

Only the latest release is supported with security fixes.

## Reporting a vulnerability

Please do not open a public issue for a vulnerability that could expose secrets or allow code execution.

Use GitHub's private vulnerability reporting on
[Ohhu/EnvBox](https://github.com/Ohhu/EnvBox/security/advisories/new), or contact the maintainer through
the GitHub profile. Include reproduction steps, affected version and impact. We aim to acknowledge within
72 hours and to publish a coordinated fix within 90 days.

## Design and threat model

EnvBox manages secrets that are often present in a developer's shell. The design assumes:

- The macOS user account is trusted.
- The operating system, Keychain and code signing chain are trusted.
- A compromised user session or malware with the user's privileges is out of scope.
- Environment variables are inherently visible to processes that inherit them; EnvBox cannot hide values
  from the applications that receive them.

### Local vault

- Document: JSON envelope with format, version, Keychain key ID and ciphertext.
- Encryption: AES-256-GCM with a fresh random nonce for every save. Authenticated additional data:
  `EnvBox.Vault.v1`.
- Key: 32 random bytes generated with `SecRandomCopyBytes`, stored as a generic password in the login
  Keychain, non-synchronizing, accessible only while the device is unlocked and only on this device.
- Keychain access is scoped to the EnvBox service and account. The key is never written to app data or logs.
- If Keychain access is denied, saving fails closed. EnvBox never writes a plaintext fallback. Ad-hoc builds may
  prompt again after an update because their code signature changes; production distribution should use Developer ID.
- File permissions: containing directory `0700`, vault `0600`. Writes are atomic.
- If the Keychain item is lost, the vault cannot be decrypted. EnvBox refuses to silently replace the key
  because doing so would destroy existing configurations.
- Imported or malformed vaults fail closed and are never overwritten while locked.

### Portable exports

- PBKDF2-HMAC-SHA256 with 600,000 iterations and a fresh 16-byte salt.
- AES-256-GCM with authenticated additional data `EnvBox.Export.v1`.
- The password is never stored. A lost password cannot be recovered.
- Envelope header fields that affect interpretation (format, version, KDF, iteration count and salt) are
  bound into the AES-GCM AAD and cannot be changed undetected. `createdAt` is advisory metadata only.
- Tampering with authenticated header fields results in decryption failure.
- Import validates format version, KDF, iteration bounds, salt size, sealed size, schema, profile count,
  total variable count and every variable before merging. Files are read with a hard 20 MB bound and the
  decrypted aggregate value payload is capped at 8 MB.
- Imports always create new profiles and regenerate internal IDs; they cannot overwrite an existing profile.

### Shell and launchd

- Applied values are written through `/bin/sh` using POSIX single-quote escaping after strict key validation
  (`[A-Za-z_][A-Za-z0-9_]*`). Values cannot inject shell syntax or command substitution.
- Environment variable names and values are validated for length, NUL bytes and duplicates.
- `launchctl` is invoked with fixed, absolute paths.
- Reading the environment starts the user's login Zsh, which executes their own startup files. This is
  opt-in configurable and never evaluates variable values.
- The activation script `~/.envbox/active.zsh` is only written when Shell integration is installed. It is
  required to be plaintext for shells to read it, is created with directory mode `0700` and file mode
  `0600`, and contains a warning comment. Removing integration deletes it. Applying a profile while
  integration is disabled does not create a plaintext activation file.
- Shell integration is opt-in. EnvBox only edits a delimited block in `~/.zshrc`, preserves the rest of the
  file, resolves symlinked dotfiles, and never changes unrelated content.
- Before rewriting `.zshrc`, EnvBox checks that the file did not change after it was read, refuses to edit
  malformed/unpaired managed markers, and stores up to five mode-`0600` backups in `~/.envbox/backups`.
  Removing integration removes only the managed block and the activation script.
- EnvBox does not automatically execute arbitrary profile values. A value that is intentionally a command
  substitution (for example `$(...)`) is exported literally; it is not evaluated by EnvBox. Shells may
  evaluate inherited values if the user chooses to use them that way.

### Clipboard

- Sensitive copies are marked with `org.nspasteboard.ConcealedType` so well-behaved clipboard managers
  do not persist them.
- Sensitive copies are optionally cleared after 45 seconds, and only if the pasteboard still contains the
  value EnvBox placed there. The timer stops if EnvBox quits.
- Clipboard contents are visible to other processes with pasteboard access; this is an OS-level limitation.

### Network and analytics

- EnvBox contains no networking code, telemetry, analytics, crash reporting or third-party SDKs.
- Release builds are compiled from source in GitHub Actions. Signing/notarization credentials are supplied as
  repository secrets and are not present in artifacts.

### Updates

EnvBox does not self-update. Users receive updates through GitHub Releases. Verify `SHA256SUMS.txt` when
downloading from an untrusted mirror.

## Hardening notes for contributors

- Never log variable values, passphrases, salts or derived keys.
- Do not display a secret by default.
- Do not write plaintext configuration to temporary files.
- Keep subprocess output bounded; `ProcessRunner` caps captured stdout/stderr and has an exit deadline.
- Keep export/import cryptography off the main actor.
- Preserve file permissions on atomic dotfile rewrites.
- Add regression tests for shell escaping, parser limits and crypto tampering.
