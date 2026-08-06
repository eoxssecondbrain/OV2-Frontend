# Deploying Cruz to Render

Companion to `PROJECT_SOT.md` 7h. Everything here is a one-time setup except
step 6, which repeats on every content change.

**Instance type: Standard (2 GB), not Starter.** Starter has the same 512 MB as
the free tier. The backend alone measures ~372 MB idle and this container also
runs two MCP bridges. Starter will OOM.

---

## 1. What is in the image

| | |
|---|---|
| `Dockerfile.render` | Slim image. **No torch / sentence-transformers**, so document upload and RAG stay disabled -- matching the setup that is actually verified to work. Keeps the build to minutes and the image small. |
| `render-start.sh` | Entrypoint. Starts both MCP bridges on `127.0.0.1:9090` / `:9091`, waits for them, then runs the backend. Bridges are supervised and restart if they die. |
| `backend/requirements-render.txt` | Generated from `backend/requirements.txt` with `sentence-transformers` removed. Regenerate if upstream requirements change. |
| `render.yaml` | Blueprint: Standard plan, 2 GB disk mounted at `/app/backend/data`, all secrets `sync: false`. |

The bridges run **inside** the web service container. That is deliberate: the
tool-server URLs stored in the database already point at `127.0.0.1:9090` and
`:9091`, so the existing configuration works in production with no rewrite.

---

## 2. Create the service

1. Render Dashboard -> **New** -> **Blueprint**.
2. Connect `eoxssecondbrain/OV2-Frontend`, branch **`deploy/render`**.
3. Render reads `render.yaml` and proposes the `cruz` service. Apply.

`WEBUI_SECRET_KEY` is generated automatically. Do **not** reuse the local dev
value.

## 3. Set the secrets

In the service's **Environment** tab, set these two (they are `sync: false`, so
they are never in git):

```
VAULT_MCP_URL     = https://raj-vault-mcp-server.onrender.com/<secret>/sse
THREADS_MCP_URL   = https://claude-notes-vault.onrender.com/<secret>/sse
DB_MCP_URL        = https://<db host>/mcp/<secret>/sse     # eoxs-wiki-db-full
USERS_MCP_URL     = https://<db host>/mcp/<secret>/sse     # eoxs-wiki-db-general
```

`DB_MCP_URL` and `USERS_MCP_URL` are two **scope tiers of the same corpus**, on
the same host, differing only in the secret path:

| | serverInfo | Contents | Bridge | Registered as |
|---|---|---|---|---|
| `DB_MCP_URL` | `eoxs-wiki-db-full` | Everything | `:9092` | `server:mcp:eoxs-db` |
| `USERS_MCP_URL` | `eoxs-wiki-db-general` | Sensitive material removed | `:9093` | `server:mcp:eoxs-users` |

**Do not cross them.** Both expose the same 20 tools with the same names and the
same version string, so a swapped pair produces no error and no visible symptom
— it just serves the unredacted corpus to ordinary users. The only way to tell
them apart is row counts. After setting or changing either, call `get_index`
through the bridge and check `wiki_pages`: `full` is ~1048, `general` ~307.

Paste the real URLs with **no angle brackets** -- `render-start.sh` refuses to
boot if it sees a leftover placeholder, rather than starting a service whose
tools silently fail.

## 4. First deploy

The disk starts empty, so Open WebUI creates a **fresh** database and shows the
create-admin screen. That is expected. Do not create an account -- the real
configuration is restored in the next step.

Watch the logs for `bridge on :9090 is listening` and `:9091`.

## 5. Restore the existing configuration (one time)

This carries over both workspace models with their prompts, params and tool
attachments, both MCP registrations with filter lists and access grants, all
accounts, and existing chats.

**a. Make a clean single-file copy locally.** The live database has a `-wal`
sidecar; copying `webui.db` alone would lose recent writes.

```bash
bash stop-cruz.sh          # so nothing is mid-write
.venv/Scripts/python.exe -c "import sqlite3; s=sqlite3.connect('backend/data/webui.db'); d=sqlite3.connect('backend/data/webui-seed.db'); s.backup(d); d.close(); s.close(); print('seed written')"
```

**b. Suspend the Render service** (Settings -> Suspend). Copying over a live
SQLite file will corrupt it.

**c. Upload it** using the SSH details on the service's **Connect** tab:

```bash
scp backend/data/webui-seed.db <srv-id>@ssh.<region>.render.com:/app/backend/data/webui.db
```

**d. Resume the service.** Log in with the existing admin account
(`ijassandhu.dev@gmail.com`). Confirm under Workspace -> Models that both
`eoxs-vault-assistant` models are present, and that the `+` menu in a chat lists
the vault tools.

## 6. Point WEBUI_URL at the real URL

Set `WEBUI_URL` to the service URL (e.g. `https://cruz.onrender.com`) and
redeploy. Used for absolute links and redirects.

---

## 7. Retire the laptop tunnel

**Important.** Once Render is live, stop the local stack:

```bash
bash stop-cruz.sh
schtasks /Change /TN "Cruz Demo Stack" /DISABLE
```

Running both means **two separate databases**. Chats and settings would diverge
depending on which URL someone happened to open, with no way to merge them
afterwards.

---

## 8. Known limitations carried into production

- **Document upload / RAG does not work** (no `sentence-transformers`). Adding
  it means torch, a much larger image, and more RAM than the 2 GB instance.
- **SQLite**, not Postgres. Single-writer; fine at this user count, and the
  reason the disk exists. Postgres is the move before real multi-user load.
- **One MCP identity for everyone.** Thread saves attribute to a single
  connector secret (SOT 7f), so all users' threads save under one name.
- **No per-user scoping in the vault** (SOT open issue #7). Anyone granted the
  vault tools can read everything in it, including CEO email and HR pages.
- **Upstream vault servers still speak SSE**, which is why the bridges exist.
  Fixing that (SOT 7c -- a three-line change per server) lets both bridges and
  this supervision logic be deleted.
