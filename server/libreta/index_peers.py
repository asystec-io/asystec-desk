"""Export enrollment verifiers without granting the book API access to HBBS keys."""
import hashlib
import json
import os
import sqlite3
import uuid
from contextlib import closing
from pathlib import Path


def export(database, target):
    peers = {}
    with closing(sqlite3.connect(database.resolve().as_uri() + '?mode=ro', uri=True)) as db:
        for peer, raw in db.execute('SELECT id,uuid FROM peer WHERE status IS NULL OR status=0'):
            try:
                device = str(uuid.UUID(bytes(raw).decode('ascii')))
            except (TypeError, ValueError, UnicodeError):
                continue
            proof = hashlib.sha256(f'asystec-enroll-v1:{peer}:{device}'.encode()).hexdigest()
            peers[peer] = hashlib.sha256(proof.encode()).hexdigest()
    temp = target.with_suffix('.tmp')
    temp.write_text(json.dumps(peers), encoding='utf-8')
    os.replace(temp, target)


if __name__ == '__main__':
    export(Path('/var/lib/rustdesk/db_v2.sqlite3'), Path('/run/asystec-enroll/peers.json'))
