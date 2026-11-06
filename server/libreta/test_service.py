from contextlib import closing
import sqlite3
import tempfile
import threading
import unittest
from unittest.mock import patch
import hashlib
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen
import json

from werkzeug.serving import make_server
from service import add_account, create_app
from index_peers import export


class SyncTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.db = Path(tmp.name) / 'book.sqlite'
        app = create_app(self.db)
        with closing(sqlite3.connect(self.db)) as db:
            for name in ('ana', 'bea'):
                add_account(db, name, 'local-test-password')
        server = make_server('127.0.0.1', 0, app, threaded=True)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        self.url = f'http://127.0.0.1:{server.server_port}/api/'
        self.a = self.login('ana')
        self.b = self.login('ana')
        self.guid = self.post('ab/personal', self.a)['guid']

    def post(self, path, token='', data=None):
        request = Request(self.url + path, json.dumps(data or {}).encode(),
                          {'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'})
        with urlopen(request, timeout=5) as res:
            return json.load(res)

    def login(self, user):
        return self.post('login', data={'username': user, 'password': 'local-test-password'})['access_token']

    def sync(self, token, changes=None):
        return self.post('asystec/book', token, {'guid': self.guid, 'changes': changes or {}})

    def test_register_then_sync_from_two_sessions(self):
        with urlopen(self.url + 'login-options') as res:
            self.assertEqual(res.getheader('X-Asystec-Registration'), '1')
            self.assertEqual(json.load(res), [])
        credentials = {'username': 'pc-user', 'password': 'local-test-password'}
        session = self.post('asystec/register', data=credentials)
        first = session['access_token']
        self.assertEqual(session['user']['name'], 'pc-user')
        self.guid = self.post('ab/personal', first)['guid']
        peer = {'alias': 'Caja', 'tags': [], 'note': ''}
        self.sync(first, {'p:123': {'rev': 0, 'value': peer}})
        second = self.login('pc-user')
        self.assertEqual(self.sync(second)['records']['p:123']['value'], peer)
        with self.assertRaises(HTTPError) as exc:
            self.sync(self.a)
        self.assertEqual(exc.exception.code, 403)
        exc.exception.close()

    def test_install_enroll_only_registered_device_once_in_asystec(self):
        with closing(sqlite3.connect(self.db)) as db:
            add_account(db, 'asystec', 'local-test-password')
        token = self.login('asystec')
        self.guid = self.post('ab/personal', token)['guid']
        hbbs = self.db.with_name('hbbs.sqlite')
        index = self.db.with_name('index.json')
        machine = '908013ac-68ef-446b-8766-358db11987c3'
        with closing(sqlite3.connect(hbbs)) as db, db:
            db.execute('CREATE TABLE peer(id TEXT,uuid BLOB,status INTEGER)')
            db.execute('INSERT INTO peer VALUES(?,?,NULL)', ('123456789', machine.encode()))
        export(hbbs, index)
        data = dict(id='123456789', alias='CAJA-01', proof='0' * 64)
        with patch.dict('os.environ', BOOK_ENROLL_GUID=self.guid, BOOK_PEER_INDEX=str(index)):
            with self.assertRaises(HTTPError) as exc:
                self.post('asystec/enroll', data=data)
            self.assertEqual(exc.exception.code, 403)
            exc.exception.close()
            data['proof'] = hashlib.sha256(f"asystec-enroll-v1:123456789:{machine}".encode()).hexdigest()
            def enroll():
                req = Request(self.url+'asystec/enroll', json.dumps(data).encode(),
                              {'Content-Type': 'application/json'})
                with urlopen(req) as res:
                    self.assertEqual((res.status, res.read()), (204, b''))
            enroll()
            key = 'p:123456789'
            record = self.sync(token)['records'][key]
            self.assertEqual(record, {'rev': 1, 'value': {'alias': 'CAJA-01', 'tags': [], 'note': ''}})
            self.sync(token, {key: {'rev': 1, 'value': dict(record['value'], alias='Sucursal')}})
            enroll()
            self.assertEqual(self.sync(token)['records'][key]['value']['alias'], 'Sucursal')
            self.sync(token, {key: {'rev': 2, 'value': None}})
            enroll()
            self.assertEqual(self.sync(token)['records'][key], {'rev': 3, 'value': None})

    def test_register_rejects_invalid_and_duplicate_credentials(self):
        for user, password, status in [('x', 'long-enough-password', 400),
                                       ('valid', 'short', 400),
                                       ('ana', 'other-new-password', 409)]:
            with self.assertRaises(HTTPError) as exc:
                self.post('asystec/register', data={'username': user, 'password': password})
            self.assertEqual(exc.exception.code, status)
            exc.exception.close()
        self.assertEqual(self.post('ab/personal', self.login('ana'))['guid'], self.guid)

    def test_two_computers_retry_conflict_and_deletion(self):
        key = 'p:123'
        peer = {'alias': 'Caja', 'tags': ['POS'], 'note': 'Local 1'}
        queued = {key: {'rev': 0, 'value': peer}, 't:POS': {'rev': 0, 'value': 42}}
        self.sync(self.a, queued)
        self.assertEqual(self.sync(self.b)['records'], self.sync(self.a, queued)['records'])
        changes = [{key: {'rev': 1, 'value': dict(peer, alias=a)}} for a in ('Ana', 'Bea')]
        with ThreadPoolExecutor(2) as pool:
            results = list(pool.map(self.sync, [self.a, self.b], changes))
        self.assertEqual(sum(not r['conflicts'] for r in results), 1)
        r = self.sync(self.a, {key: {'rev': 2, 'value': None}})
        self.assertEqual(r['records'][key], {'rev': 3, 'value': None})
        stale = self.sync(self.b, {**queued, 'p:456': {'rev': 0, 'value': peer}})
        self.assertEqual(stale['conflicts'], [key])
        self.assertNotIn('p:456', stale['records'])
        self.assertIsNone(stale['records'][key]['value'])

    def test_account_isolation_credentials_and_logout(self):
        with self.assertRaises(HTTPError) as exc:
            self.sync(self.login('bea'))
        exc.exception.close()
        self.assertEqual(exc.exception.code, 403)
        with self.assertRaises(HTTPError) as exc:
            self.sync(self.a, {'p:123': {'rev': 0, 'value': {'password': 'secret'}}})
        exc.exception.close()
        self.assertEqual(exc.exception.code, 400)
        self.post('logout', self.a)
        with self.assertRaises(HTTPError) as exc:
            self.sync(self.a)
        exc.exception.close()
        self.assertEqual(exc.exception.code, 401)
        self.assertEqual(self.sync(self.b)['records'], {})
