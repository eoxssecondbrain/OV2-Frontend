#!/usr/bin/env python3
"""Apply the Cruz configuration to an Open WebUI database.

None of the Cruz work below lives in git -- it is all database state: model
names and ids, hidden base models, system prompts, tool-server registration,
prompt suggestions and per-user settings. Deploying the branch does not carry
any of it. This script does.

    python scripts/cruz_migrate.py                       # local, dry run
    python scripts/cruz_migrate.py --apply
    python scripts/cruz_migrate.py --db /app/backend/data/webui.db --apply

Idempotent: safe to run repeatedly. Everything is done in ONE transaction, so a
failure part-way leaves the database untouched rather than half-migrated.

The model-id rename is the dangerous part. A model id is referenced from FOUR
places -- model.id, chat.chat, config, and access_grant. Missing access_grant
silently removes users' access to the assistant with no error anywhere, which is
exactly what happened during development.
"""

import argparse
import json
import sqlite3
import sys
import time
import uuid

HAIKU = 'claude-haiku-4-5-20251001'

RENAMES = [  # longest first, so the -opus suffix is not eaten by the shorter key
    ('eoxs-vault-assistant-opus', 'cruz-pro', 'Cruz Pro'),
    ('eoxs-vault-assistant', 'cruz', 'Cruz'),
]

# Base models: resolvable but absent from the picker. Note meta.hidden, NOT
# is_active=0 -- deactivating a base model breaks resolution for any workspace
# model built on it ("Model not found").
HIDE_BASE = ['claude-sonnet-5', 'claude-opus-5', HAIKU]
DEACTIVATE = ['qwen3:8b', 'eoxs-vault-local']

ALLOWED_ANTHROPIC = ['claude-sonnet-5', 'claude-opus-5', HAIKU]

SUGGESTIONS = [
    {'title': ['Client health check', 'recent activity across email, calls and tickets'],
     'content': 'Give me a health check on <client>: recent email threads, the last call, open tickets, and anything that looks like a risk.'},
    {'title': ['Outstanding invoices', "what's unpaid and how overdue"],
     'content': 'Which invoices are outstanding for <client>, how overdue are they, and what was the last communication about payment?'},
    {'title': ['Catch me up', 'what changed with an account this month'],
     'content': 'Catch me up on <client> over the last month. What changed, what was decided, and what needs a decision from me?'},
    {'title': ['Prospect pipeline', 'where deals actually stand'],
     'content': 'Summarise the current prospect pipeline: who is active, what stage each is at, and which ones have gone quiet.'},
]

USER_SETTINGS = {
    'detectArtifacts': False,   # charts render inline; the side panel would duplicate them
    'collapseCodeBlocks': True,
}

log = []


def note(msg):
    log.append(msg)
    print('  ' + msg)


def jload(v, default):
    try:
        return json.loads(v) if v else default
    except Exception:
        return default


def migrate(db_path, apply):
    c = sqlite3.connect(db_path)
    c.execute('BEGIN')
    try:
        _run(c)
    except Exception:
        c.rollback()
        c.close()
        raise
    if apply:
        c.commit()
        print('\nCOMMITTED')
    else:
        c.rollback()
        print('\nDRY RUN -- nothing written. Re-run with --apply.')
    c.close()


def _run(c):
    now = int(time.time())
    admin = list(c.execute("select id from user where role='admin' limit 1"))
    if not admin:
        raise SystemExit('no admin user found -- is this the right database?')
    admin = admin[0][0]

    print('\n[1] model ids and names')
    for old, new, label in RENAMES:
        if list(c.execute('select 1 from model where id=?', (old,))):
            c.execute('update model set id=?, name=? where id=?', (new, label, old))
            note(f'{old} -> {new} ({label})')
            # All four reference sites, in one place.
            c.execute('update chat set chat = replace(chat, ?, ?) where chat like ?', (old, new, f'%{old}%'))
            c.execute('update config set value = replace(value, ?, ?) where value like ?', (old, new, f'%{old}%'))
            n = c.execute("update access_grant set resource_id=? where resource_type='model' and resource_id=?",
                          (new, old)).rowcount
            note(f'  references migrated (access_grant rows: {n})')
        elif list(c.execute('select 1 from model where id=?', (new,))):
            note(f'{new} already renamed')

    print('\n[2] base models hidden from the picker (still resolvable)')
    for mid in HIDE_BASE:
        row = list(c.execute('select meta from model where id=?', (mid,)))
        if row:
            m = jload(row[0][0], {})
            if not m.get('hidden'):
                m['hidden'] = True
                c.execute('update model set meta=?, is_active=1 where id=?', (json.dumps(m), mid))
                note(f'{mid} -> hidden')
        else:
            c.execute('insert into model (id,user_id,base_model_id,name,params,meta,updated_at,created_at,is_active) '
                      'values (?,?,?,?,?,?,?,?,1)',
                      (mid, admin, None, mid, json.dumps({}), json.dumps({'hidden': True}), now, now))
            note(f'{mid} -> created, hidden')

    for mid in DEACTIVATE:
        if c.execute('update model set is_active=0 where id=?', (mid,)).rowcount:
            note(f'{mid} -> deactivated')

    print('\n[3] Cruz Lite (Haiku)')
    src = list(c.execute("select params,meta from model where id='cruz'"))
    if not src:
        note('SKIPPED: cruz not present')
    elif list(c.execute("select 1 from model where id='cruz-lite'")):
        note('cruz-lite already exists')
    else:
        params = jload(src[0][0], {})
        meta = jload(src[0][1], {})
        params.pop('reasoning_effort', None)   # fast tier: deliberation defeats the point
        meta['description'] = 'Fast, low-cost lookups over the same company records. Use for simple questions.'
        meta.pop('hidden', None)
        c.execute('insert into model (id,user_id,base_model_id,name,params,meta,updated_at,created_at,is_active) '
                  'values (?,?,?,?,?,?,?,?,1)',
                  ('cruz-lite', admin, HAIKU, 'Cruz Lite', json.dumps(params), json.dumps(meta), now, now))
        note('cruz-lite created')
        for pid, perm in list(c.execute("select principal_id,permission from access_grant "
                                        "where resource_type='model' and resource_id='cruz'")):
            c.execute('insert into access_grant (id,resource_type,resource_id,principal_type,principal_id,permission,created_at) '
                      'values (?,?,?,?,?,?,?)', (str(uuid.uuid4()), 'model', 'cruz-lite', 'user', pid, perm, now))
            note(f'  grant copied -> {pid[:8]}')

    print('\n[4] anthropic connection allowlist')
    row = list(c.execute("select value from config where key='openai.api_configs'"))
    urls = jload(list(c.execute("select value from config where key='openai.api_base_urls'"))[0][0], [])
    if row:
        cfgs = jload(row[0][0], {})
        for idx, url in enumerate(urls):
            if 'anthropic.com' in url:
                cur = cfgs.setdefault(str(idx), {}).get('model_ids') or []
                if sorted(cur) != sorted(ALLOWED_ANTHROPIC):
                    cfgs[str(idx)]['model_ids'] = ALLOWED_ANTHROPIC
                    note(f'connection {idx} model_ids -> {ALLOWED_ANTHROPIC}')
        c.execute("update config set value=? where key='openai.api_configs'", (json.dumps(cfgs),))

    print('\n[5] eoxs-db tool server')
    row = list(c.execute("select value from config where key='tool_server.connections'"))
    conns = jload(row[0][0], []) if row else []
    if any(x.get('info', {}).get('id') == 'eoxs-db' for x in conns):
        note('already registered')
    elif not conns:
        note('SKIPPED: no existing connections to copy grants from')
    else:
        conns.append({
            'url': 'http://127.0.0.1:9092/mcp', 'path': '', 'type': 'mcp', 'auth_type': 'none',
            'headers': None, 'key': None,
            'config': {'enable': True, 'access_grants': conns[0]['config']['access_grants']},
            'info': {'id': 'eoxs-db', 'name': 'EOXS Vault (Database)',
                     'description': 'Database-backed EOXS vault with full-text search (bridge :9092)'},
        })
        c.execute("update config set value=? where key='tool_server.connections'", (json.dumps(conns),))
        note('registered -- REQUIRES DB_MCP_URL in the environment')

    for mid in ('cruz', 'cruz-pro', 'cruz-lite'):
        row = list(c.execute('select meta from model where id=?', (mid,)))
        if not row:
            continue
        m = jload(row[0][0], {})
        tools = m.get('toolIds', [])
        if 'server:mcp:eoxs-db' not in tools:
            tools.append('server:mcp:eoxs-db')
            m['toolIds'] = tools
            c.execute('update model set meta=? where id=?', (json.dumps(m), mid))
            note(f'{mid} attached to eoxs-db')

    print('\n[6] prompt suggestions and arena')
    c.execute("update config set value=? where key='ui.prompt_suggestions'", (json.dumps(SUGGESTIONS),))
    note(f'{len(SUGGESTIONS)} executive prompts')
    if c.execute("update config set value=? where key='evaluation.arena.enable'", (json.dumps(False),)).rowcount:
        note('arena model disabled')

    print('\n[7] per-user settings')
    for uid, email, s in list(c.execute('select id,email,settings from user')):
        d = jload(s, {})
        if not isinstance(d, dict):
            d = {}
        ui = d.get('ui') or {}
        ui.update(USER_SETTINGS)
        d['ui'] = ui
        d['collapseCodeBlocks'] = True
        c.execute('update user set settings=? where id=?', (json.dumps(d), uid))
        note(f'{email}')

    print('\n[8] final model visibility')
    for i, n, m, a in c.execute('select id,name,meta,is_active from model order by is_active desc, id'):
        hidden = jload(m, {}).get('hidden')
        state = 'VISIBLE' if (a and not hidden) else ('hidden' if a else 'inactive')
        print(f'  {state:9} {n} ({i})')


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--db', default='backend/data/webui.db')
    ap.add_argument('--apply', action='store_true', help='write changes (default is a dry run)')
    a = ap.parse_args()
    print(f'database: {a.db}')
    migrate(a.db, a.apply)
    if not a.apply:
        print('\nNOTE: system prompts are NOT migrated by this script -- they are long and')
        print('editorial. Copy them from Workspace -> Models, or export/import the model.')
