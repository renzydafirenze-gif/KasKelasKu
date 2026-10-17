"""Run: python3 tool/check_schema.py. Real SQLite invariants, no extra packages."""
import sqlite3
from pathlib import Path

db = sqlite3.connect(':memory:')
db.execute('PRAGMA foreign_keys=ON')
db.executescript((Path(__file__).resolve().parents[1] / 'lib/data/schema.sql').read_text())
for identity, role in [('b', 'bendahara'), ('k', 'ketua'), ('g', 'guruWali'), ('s', 'siswa')]:
    db.execute('INSERT INTO users(id,name,role) VALUES(?,?,?)', (identity, role, role))

def rejected(sql, args=()):
    try:
        db.execute(sql, args)
    except sqlite3.IntegrityError:
        return
    raise AssertionError(f'Expected rejection: {sql}')

insert = '''INSERT INTO transactions(amount,type,category,tx_date,description,
created_by,created_at,fingerprint,submission_id) VALUES(?,?,?,?,?,?,?,?,?)'''
def row(actor='b', date='2026-10-15', token='one', amount=5000):
    return (amount, 'IN', 'Kas', date, 'Iuran', actor, '2026-10-15', 'hash', token)

rejected(insert, row(actor='s'))
rejected(insert, row(date='2026-02-30'))
rejected(insert, row(amount=0))
db.execute(insert, row())
rejected(insert, row())
rejected("UPDATE transactions SET amount=100 WHERE id=1")
rejected("INSERT INTO monthly_reports(period,approved_by,approved_at) VALUES('2026-10','s','now')")
db.execute("INSERT INTO monthly_reports(period,approved_by,approved_at) VALUES('2026-10','k','now')")
rejected(insert, row(token='two'))
rejected('DELETE FROM transactions WHERE id=1')
rejected("UPDATE monthly_reports SET approved_by=NULL,approved_at=NULL")
rejected('DELETE FROM monthly_reports')
rejected("UPDATE monthly_reports SET verified_by='s',verified_at='now'")
db.execute("UPDATE monthly_reports SET verified_by='g',verified_at='now'")
rejected("UPDATE monthly_reports SET verified_by=NULL,verified_at=NULL")
db.execute("UPDATE users SET role='siswa' WHERE id='b'")
rejected(insert, row(date='2026-11-01', token='three'))
assert db.execute('SELECT SUM(amount) FROM transactions').fetchone()[0] == 5000
print('Schema checks passed: RBAC, calendar, amounts, duplicates, immutable transactions, report locks, role changes.')
