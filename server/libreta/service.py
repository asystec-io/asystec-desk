"""Asystec Desk personal address book. Run behind an HTTPS reverse proxy."""
import getpass
import hashlib
import os
import re
import secrets
import sqlite3
import time
import uuid
from contextlib import closing
from pathlib import Path

import click
from flask import Flask, abort, g, jsonify, request
from werkzeug.security import check_password_hash, generate_password_hash


def create_app(database=None):
    app = Flask(__name__)
    app.config['MAX_CONTENT_LENGTH'] = 2 * 1024 * 1024
    path = Path(database or os.environ.get('BOOK_DB', 'libreta.sqlite3')).resolve()
    with closing(sqlite3.connect(path)) as db:
        db.executescript("""
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS account(
              name TEXT PRIMARY KEY, verifier TEXT NOT NULL, guid TEXT UNIQUE NOT NULL);
            CREATE TABLE IF NOT EXISTS session(
              digest TEXT PRIMARY KEY, owner TEXT NOT NULL, expires INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS entry(
              owner TEXT NOT NULL, key TEXT NOT NULL, revision INTEGER NOT NULL,
              value TEXT NOT NULL, PRIMARY KEY(owner,key));
        """)

    def connection():
        if 'db' not in g:
            g.db = sqlite3.connect(path, timeout=10)
        return g.db

    @app.teardown_appcontext
    def disconnect(_error):
        if 'db' in g:
            g.db.close()

    @app.cli.command('create-user')
    @click.argument('name')
    def create_user(name):
        password = getpass.getpass('Contraseña de la cuenta (12 caracteres mínimo): ')
        if len(password) < 12 or password != getpass.getpass('Repetir contraseña: '):
            raise click.ClickException('Contraseña insuficiente o diferente.')
        add_account(connection(), name, password)

    @app.errorhandler(400)
    @app.errorhandler(401)
    @app.errorhandler(403)
    @app.errorhandler(413)
    def error_response(error):
        return jsonify(error=error.description), error.code

    def body():
        value = request.get_json(force=True)
        if not isinstance(value, dict):
            abort(400)
        return value

    def identity():
        auth = request.headers.get('Authorization', '')
        if not auth.startswith('Bearer '):
            abort(401)
        digest = token_digest(auth[7:])
        row = connection().execute(
            'SELECT name,guid FROM account JOIN session ON owner=name '
            'WHERE digest=? AND expires>?', (digest, time.time())).fetchone()
        if not row:
            abort(401)
        return (*row, digest)

    @app.get('/api/login-options')
    def options():
        response = jsonify([])
        response.headers['X-Asystec-Registration'] = '1'
        return response

    @app.post('/api/login')
    def login():
        data = body()
        row = connection().execute('SELECT name,verifier FROM account WHERE name=?',
                                   (str(data.get('username', '')),)).fetchone()
        password = data.get('password')
        if not isinstance(password, str) or not row or not check_password_hash(row[1], password):
            abort(401, 'Usuario o contraseña incorrectos')
        return session_response(row[0])

    @app.post('/api/asystec/register')
    def register():
        data = body()
        name, password = data.get('username'), data.get('password')
        if not isinstance(name, str) or not re.fullmatch(r'[A-Za-z0-9._-]{3,40}', name):
            abort(400, 'Usá entre 3 y 40 letras sin acentos, números, puntos, guiones o guiones bajos.')
        if not isinstance(password, str) or not 12 <= len(password) <= 128:
            abort(400, 'La contraseña debe tener entre 12 y 128 caracteres.')
        try:
            add_account(connection(), name, password)
        except sqlite3.IntegrityError:
            return jsonify(error='Ese usuario ya existe. Iniciá sesión o elegí otro nombre.'), 409
        return session_response(name), 201

    def session_response(name):
        token = secrets.token_urlsafe(32)
        with connection() as db:
            db.execute('DELETE FROM session WHERE expires<=?', (time.time(),))
            db.execute('INSERT INTO session VALUES(?,?,?)',
                       (token_digest(token), name, int(time.time()) + 30 * 86400))
        return jsonify(type='access_token', access_token=token, user={'name': name})

    @app.post('/api/currentUser')
    def current_user():
        return jsonify(name=identity()[0])

    @app.post('/api/logout')
    def logout():
        digest = identity()[2]
        with connection() as db:
            db.execute('DELETE FROM session WHERE digest=?', (digest,))
        return jsonify({})

    @app.post('/api/ab/personal')
    def personal():
        return jsonify(guid=identity()[1])

    @app.post('/api/ab/settings')
    def settings():
        identity()
        return jsonify(max_peer_one_ab=0)

    @app.post('/api/ab/shared/profiles')
    @app.get('/api/device-group/accessible')
    @app.get('/api/peers')
    @app.get('/api/users')
    def empty_list():
        identity()
        return jsonify(total=0, data=[])

    @app.post('/api/asystec/book')
    def sync():
        name, guid, _ = identity()
        data = body()
        if data.get('guid') != guid:
            abort(403)
        changes = data.get('changes')
        if not isinstance(changes, dict):
            abort(400)
        for key, change in changes.items():
            validate_change(key, change)
        with connection() as db:
            db.execute('BEGIN IMMEDIATE')
            records = {key: dict(rev=r, value=app.json.loads(v)) for key, r, v in
                       db.execute('SELECT key,revision,value FROM entry WHERE owner=?', (name,))}
            conflicts = []
            updates = []
            for key, change in changes.items():
                old = records.get(key, {'rev': 0, 'value': None})
                if old['value'] == change['value']:
                    continue
                if change['rev'] != old['rev']:
                    conflicts.append(key)
                    continue
                updates.append((key, old['rev'] + 1, change['value']))
            if not conflicts:
                for key, rev, value in updates:
                    db.execute('INSERT OR REPLACE INTO entry VALUES(?,?,?,?)', (name, key, rev, app.json.dumps(value)))
                    records[key] = dict(rev=rev, value=value)
        return jsonify(records=records, conflicts=conflicts)

    return app


def token_digest(token):
    return hashlib.sha256(token.encode()).hexdigest()


def add_account(db, name, password):
    with db:
        db.execute('INSERT INTO account VALUES(?,?,?)',
                   (name, generate_password_hash(password), 'asystec-' + uuid.uuid4().hex))


def validate_change(key, change):
    if not 2 < len(key) <= 258 or not key.startswith(('p:', 't:')):
        abort(400)
    if not isinstance(change, dict) or set(change) != {'rev', 'value'}:
        abort(400)
    if type(change['rev']) is not int or change['rev'] < 0:
        abort(400)
    v = change['value']
    if v is None:
        return
    if key.startswith('t:'):
        if type(v) is not int or not 0 <= v <= 0xffffffff:
            abort(400)
        return
    if not isinstance(v, dict) or set(v) != {'alias', 'tags', 'note'}:
        abort(400)
    if not all(isinstance(v[k], str) and len(v[k]) <= 8192 for k in ('alias', 'note')):
        abort(400)
    if not isinstance(v['tags'], list) or any(not isinstance(t, str) or not 0 < len(t) <= 256 for t in v['tags']):
        abort(400)

