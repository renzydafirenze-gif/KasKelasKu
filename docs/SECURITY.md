# Security review and release checklist

Status: internal implementation review only, not an independent audit.

## Controls

- SQLCipher activation/integrity verified when opening native database.
- Random 256-bit database key, credential-wrapped per account in secure storage.
- PBKDF2-HMAC-SHA256 600,000 iterations, independent random 32-byte salts.
- AES-256-GCM with authenticated context, 12-byte nonces, 16-byte tags.
- Read authorization and transaction-scoped write authorization.
- Chairperson locks enforced by SQL triggers; immutable entries, audited deletes.
- Backup restore only into empty initialized vault, validated shapes and bounded
  inputs, one SQLite transaction including trigger removal/recreation.
- Imported identities disabled. Credentials never carried in backups.
- Five failed password attempts cause 30-second local cooldown.
- Idle/background lock; live identity/role check every two seconds.
- Explicit plaintext-sharing warning; generated plaintext cleaned after sharing.
- Android cloud backup disabled; no app network permission in release manifest.

## Known limits / mandatory release work

- Local administrator/root/jailbreak can read process keys and alter binaries.
- Biometric re-entry keeps last authenticated key in Dart process memory.
- Dart strings and garbage collection cannot guarantee key zeroization.
- Account role is repository-authorized, not an SQLCipher per-user grant.
- Biometric OS owner is not proof of a particular class member's identity.
- Automatic reports use database key as password input to a separate salted KDF;
  they are device-local and must be re-exported with user password for portability.
- File picker/share extensions can pause app; lock may abort current export.
- Crash during plaintext sharing may leave temporary plaintext until app cache
  cleanup; OS sandbox and device encryption remain required.
- Pending setup is resumed after credential authentication; crash between writing
  credential wrapper and pending marker still needs explicit support recovery.
- Legacy SQLCipher 4.5.4 and old Flutter/plugin stack need native vulnerability,
  16 KB page compatibility and 2026 app-store policy review.
- Export multi-file generation is atomic per file, not across PDF/CSV pair.
- Local audit is not tamper-evident to an attacker holding database key.

## Required independent evidence

Test real Android/iOS SQLCipher headers, wrong-key rejection, integrity failure,
credential/backup tampering, role matrix, revoked/deactivated sessions, lock races,
disk-full rollback, process termination mid-write/restore, Unicode PDF overflow,
10,000-row scrolling, TalkBack/VoiceOver, 200% text, contrast, landscape and tablets.
Do not label release production-ready until CI 100% coverage gate and these
reviews pass. Host SQLite business tests are not encryption tests.
