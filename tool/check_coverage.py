import sys
from pathlib import Path

path = Path('coverage/lcov.info')
if not path.exists():
    sys.exit('Missing coverage/lcov.info')
counts = [int(line.rsplit(',', 1)[1]) for line in path.read_text().splitlines() if line.startswith('DA:')]
if not counts:
    sys.exit('Empty coverage is not 100% coverage')
hits = sum(count > 0 for count in counts)
print(f'Coverage: {hits}/{len(counts)} ({hits / len(counts):.2%})')
if hits != len(counts):
    sys.exit('Release blocked: 100% coverage required')
