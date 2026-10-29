# Security review and release checklist

Status: internal implementation review only, not an independent audit.

## Controls

- Read authorization and transaction-scoped write authorization by role
  (Bendahara writes, Ketua approves/locks, Guru Wali verifies).
- Chairperson locks enforced by SQL triggers; immutable entries, audited deletes.
- Backup restore only into empty data, validated shapes and bounded inputs, one
  SQLite transaction including trigger removal/recreation.
- Untrusted backup boundary rejected before touching the live database.
- CSV cells protected against spreadsheet formula injection.
- No network permission in release manifest; Android cloud backup disabled.

## Deliberate trade-off: no encryption

KasKelasKu 1.2.2 stores everything unencrypted on purpose: SQLite plaintext,
JSON backups and plain PDF/CSV reports. There are no accounts, passwords or
biometrics; anyone who opens the app can read and change data. Role checks are
still enforced in the repository and by SQL triggers, but they are **not** a
security boundary against someone holding the device or the database file — the
UI lets a user switch role without proof of identity.

Do not store sensitive or disputed financial records here. Keep the device
locked and do not share backup/report files over untrusted channels.

## Known limits

- Legacy encrypted database from <=1.1.1 is quarantined as `.legacy`; its data
  is not migrated and stays encrypted/unusable.
- Local audit is not tamper-evident; anyone with the database file can rewrite it.
- Export generation is atomic per file, not across the PDF/CSV pair.
- Crash during sharing may leave temporary plaintext in app cache.

## Required independent evidence

Test real Android/iOS devices for role matrix, report/backup restore, disk-full
rollback, process termination mid-write/restore, Unicode PDF overflow,
10,000-row scrolling, TalkBack/VoiceOver, 200% text, contrast, landscape and
tablets. Do not label release production-ready until CI gates and these reviews pass.
