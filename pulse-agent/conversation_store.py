"""Transactional canonical history + bounded restart state, independent of engine lifetime."""
from contextlib import contextmanager
import json
import os
from pathlib import Path
import sqlite3
import time
import uuid

class ConversationStore:
    def __init__(self, path):
        self.path = str(path)
        Path(path).parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        with self.connection() as db:
            db.executescript("""
                PRAGMA journal_mode=WAL;
                CREATE TABLE IF NOT EXISTS conversations(id TEXT PRIMARY KEY, title TEXT NOT NULL, updated INTEGER);
                CREATE TABLE IF NOT EXISTS messages(id INTEGER PRIMARY KEY, session TEXT NOT NULL, payload TEXT NOT NULL);
                CREATE INDEX IF NOT EXISTS messages_session ON messages(session,id);
                CREATE UNIQUE INDEX IF NOT EXISTS messages_identity ON messages(session,json_extract(payload,'$._pulse_message_id'))
                    WHERE json_extract(payload,'$._pulse_message_id') IS NOT NULL;
                CREATE TABLE IF NOT EXISTS checkpoints(session TEXT PRIMARY KEY, payload TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS executions(id TEXT PRIMARY KEY, session TEXT, status TEXT, updated INTEGER);
                CREATE TABLE IF NOT EXISTS decisions(id TEXT PRIMARY KEY, run TEXT, session TEXT, call TEXT,
                    operation TEXT, arguments TEXT, preview TEXT, status TEXT NOT NULL, created INTEGER);
                CREATE TABLE IF NOT EXISTS results(id TEXT PRIMARY KEY, session TEXT, payload TEXT, created INTEGER);
                CREATE TABLE IF NOT EXISTS usage_requests(id TEXT PRIMARY KEY, session TEXT NOT NULL, run TEXT, provider TEXT, model TEXT,
                    purpose TEXT, context TEXT NOT NULL, reported TEXT, created INTEGER);
                CREATE INDEX IF NOT EXISTS usage_session ON usage_requests(session,created);
                CREATE TABLE IF NOT EXISTS usage_sessions(session TEXT PRIMARY KEY, historical INTEGER NOT NULL);
                CREATE TABLE IF NOT EXISTS migration(id TEXT PRIMARY KEY);
                CREATE TABLE IF NOT EXISTS memories(id TEXT PRIMARY KEY, content TEXT UNIQUE NOT NULL, payload TEXT NOT NULL);
            """)
        os.chmod(self.path, 0o600)

    @contextmanager
    def connection(self):
        with sqlite3.connect(self.path, timeout=5) as db:
            db.row_factory = sqlite3.Row
            db.execute("PRAGMA foreign_keys=ON")
            yield db

    def recover(self):
        with self.connection() as db:
            db.execute("UPDATE executions SET status='interrupted' WHERE status IN ('running','waiting')")
            db.execute("UPDATE decisions SET status='expired' WHERE status='pending'")

    def checkpoint(self, session, messages, view, run, status, title="Conversation"):
        now = int(time.time())
        with self.connection() as db:
            db.execute("INSERT INTO conversations VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET updated=excluded.updated",
                       (session, title[:80], now))
            db.executemany("INSERT OR IGNORE INTO messages(session,payload) VALUES(?,?)",
                           [(session, json.dumps(m, ensure_ascii=False)) for m in messages if m.get("role") != "system"])
            db.execute("INSERT OR REPLACE INTO checkpoints VALUES(?,?)", (session, json.dumps(view, ensure_ascii=False)))
            db.execute("INSERT OR REPLACE INTO executions VALUES(?,?,?,?)", (run, session, status, now))

    def view(self, session):
        with self.connection() as db:
            row = db.execute("SELECT payload FROM checkpoints WHERE session=?", (session,)).fetchone()
        return json.loads(row[0]) if row else []

    def sessions(self, page=1):
        with self.connection() as db:
            rows = db.execute("SELECT * FROM conversations ORDER BY updated DESC,id LIMIT 50 OFFSET ?", ((page-1)*50,)).fetchall()
        return [{"session_id": row["id"], "name": row["title"], "updated_at": row["updated"]} for row in rows]

    def history(self, session, page=1):
        with self.connection() as db:
            rows = db.execute("SELECT id,payload FROM messages WHERE session=? AND json_extract(payload,'$.role') IN ('user','assistant','tool','notice') "
                              "AND (length(coalesce(json_extract(payload,'$.content'),''))>0 OR json_extract(payload,'$.role')='notice') ORDER BY id DESC LIMIT 51 OFFSET ?",
                              (session, (page-1)*50)).fetchall()
            execution=db.execute("SELECT status FROM executions WHERE session=? ORDER BY updated DESC,rowid DESC LIMIT 1",(session,)).fetchone()
        messages=[]
        for row in reversed(rows[:50]):
            m=json.loads(row['payload']);text=str(m.get('content') or '')
            if m['role']=='notice':
                text='Earlier request interrupted.' if m.get('kind')=='interrupted' else 'Earlier request failed.' if m.get('kind')=='error' else str(m.get('text') or 'Context updated.')
            messages.append({'id':str(row['id']),'role':m['role'],'content':text.encode()[:64000].decode('utf-8',errors='ignore'),
                             'name':m.get('_pulse_operation'),'status':m.get('_pulse_status')})
        return {"messages":messages,"has_more":len(rows)>50,"interrupted":bool(execution and execution[0]=='interrupted')}

    def search(self, session, query):
        query = query.strip()
        if not 2 <= len(query) <= 200:
            return {"error": "Use 2–200 characters"}
        with self.connection() as db:
            rows = db.execute("SELECT id,payload FROM messages WHERE session=? AND instr(lower(json_extract(payload,'$.content')),lower(?))>0 "
                              "ORDER BY id DESC LIMIT 10", (session, query)).fetchall()
        matches=[]
        for row in rows:
            message=json.loads(row["payload"]);text=str(message.get("content") or "")
            start=max(0,text.lower().find(query.lower())-500)
            matches.append({"id":row["id"],"role":message["role"],"text":text[start:start+2000],"offset":start,
                            "total_characters":len(text)})
        return {"matches":matches,"limit":10}

    def pending(self, run, session, call, operation, arguments, preview):
        identifier = str(uuid.uuid4())
        with self.connection() as db:
            db.execute("INSERT INTO decisions VALUES(?,?,?,?,?,?,?,'pending',?)",
                       (identifier, run, session, call, operation, json.dumps(arguments, sort_keys=True), json.dumps(preview), int(time.time())))
        return identifier

    def resolve(self, identifier, run, approved):
        with self.connection() as db:
            changed = db.execute("UPDATE decisions SET status=? WHERE id=? AND run=? AND status='pending' AND created>?",
                                 ("approved" if approved else "denied", identifier, run, int(time.time())-300)).rowcount
        return changed == 1

    def result(self, session, payload):
        if len(payload.encode())>4_000_000:
            raise ValueError('Result exceeds storage limit')
        identifier = str(uuid.uuid4())
        with self.connection() as db:
            db.execute("DELETE FROM results WHERE created<?", (int(time.time())-7*86400,))
            db.execute("INSERT INTO results VALUES(?,?,?,?)", (identifier, session, payload, int(time.time())))
            total=db.execute("SELECT coalesce(sum(length(CAST(payload AS BLOB))),0) FROM results").fetchone()[0]
            while total>128_000_000:
                victim=db.execute("SELECT id,length(CAST(payload AS BLOB)) FROM results ORDER BY created,rowid LIMIT 1").fetchone()
                db.execute("DELETE FROM results WHERE id=?",(victim[0],));total-=victim[1]
        return identifier

    def read_result(self, session, identifier, offset=0):
        if not isinstance(offset, int) or offset < 0:
            return {"error": "Invalid offset"}
        with self.connection() as db:
            row = db.execute("SELECT substr(payload,?,4000),length(payload) FROM results WHERE id=? AND session=? AND created>?",
                             (offset+1, identifier, session, int(time.time())-7*86400)).fetchone()
        if not row:
            return {"error": "Result unavailable or expired"}
        return {"text": row[0], "offset": offset, "next_offset": offset+len(row[0]) if offset+len(row[0])<row[1] else None,
                "total_characters": row[1]}

    def memory_rows(self):
        with self.connection() as db:
            rows=db.execute("SELECT id,payload FROM memories ORDER BY rowid DESC LIMIT 100").fetchall()
        return [{"id":row["id"],**json.loads(row["payload"])} for row in rows]

    def remember(self, identifier, payload):
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            if db.execute("SELECT 1 FROM memories WHERE content=?",(payload['content'],)).fetchone():
                return {"status":"Already remembered"}
            if db.execute("SELECT count(*) FROM memories").fetchone()[0]>=100:
                return {"error":"Memory full. Review and remove old memories first"}
            db.execute("INSERT INTO memories VALUES(?,?,?)",(identifier,payload['content'],json.dumps(payload)))
        return {"status":"Remembered","id":identifier}

    def delete_memory(self, identifier):
        with self.connection() as db:
            if identifier=='all':db.execute("DELETE FROM memories")
            else:db.execute("DELETE FROM memories WHERE id=?",(identifier,))

    def migrate(self, legacy, user_id=None):
        """One transaction; uses legacy public APIs. Source remains untouched."""
        from agno.db.base import SessionType
        with self.connection() as db:
            if db.execute("SELECT 1 FROM migration WHERE id='agno-v1'").fetchone():
                return
            # Backup is SQLite-aware, including WAL; no private Agno table assumptions.
            source_path = getattr(legacy, "db_file", None)
            if source_path and Path(source_path).is_file():
                backup_path = self.path + ".legacy-backup"
                with sqlite3.connect(source_path) as source, sqlite3.connect(backup_path) as backup:
                    source.backup(backup)
                os.chmod(backup_path, 0o600)
            page = 1
            while True:
                sessions = legacy.get_sessions(session_type=SessionType.AGENT, component_id="pulse-agent", limit=50, page=page, include_runs=False)
                for item in sessions:
                    session = legacy.get_session(item.session_id, session_type=SessionType.AGENT)
                    messages = [{"role": m.role, "content": m.content} for m in session.get_messages(skip_roles=["system", "tool"], skip_statuses=[])
                                if m.role in {"user", "assistant"} and isinstance(m.content,str) and m.content and not m.tool_calls]
                    db.execute("INSERT OR IGNORE INTO conversations VALUES(?,?,?)", (item.session_id,(item.session_data or {}).get("session_name","Conversation"),item.updated_at or 0))
                    db.executemany("INSERT INTO messages(session,payload) VALUES(?,?)", [(item.session_id,json.dumps(m)) for m in messages])
                    # All dialogue is canonical and searchable. Bound initial replay explicitly.
                    tail=[]; size=0
                    for m in reversed(messages):
                        size += len(json.dumps(m).encode())
                        if size>16000: break
                        tail.insert(0,m)
                    if len(tail)<len(messages):
                        tail.insert(0,{"role":"assistant","content":"Earlier imported dialogue is available through search_conversation; it was omitted from this bounded context."})
                    db.execute("INSERT OR IGNORE INTO checkpoints VALUES(?,?)", (item.session_id,json.dumps(tail)))
                if len(sessions)<50: break
                page+=1
            from storage import USER_ID
            for row in legacy.get_learnings(learning_type='pulse_memory',user_id=user_id or USER_ID,namespace=user_id or USER_ID,limit=100):
                payload=row['content']
                db.execute("INSERT OR IGNORE INTO memories VALUES(?,?,?)",(row['learning_id'],payload['content'],json.dumps(payload)))
            db.execute("INSERT INTO migration VALUES('agno-v1')")

    def usage_initialize(self, session):
        with self.connection() as db:
            db.execute("INSERT OR IGNORE INTO usage_sessions SELECT ?,EXISTS(SELECT 1 FROM messages WHERE session=?)",(session,session))

    def usage_begin(self, identifier, session, run, provider, model, purpose, context):
        with self.connection() as db:
            db.execute("INSERT OR IGNORE INTO usage_sessions SELECT ?,EXISTS(SELECT 1 FROM messages WHERE session=? AND json_extract(payload,'$.role')='assistant')",(session,session))
            db.execute("INSERT OR IGNORE INTO usage_requests VALUES(?,?,?,?,?,?,?,NULL,?)",
                       (identifier,session,run,provider,model,purpose,json.dumps(context),int(time.time())))

    def usage_report(self, identifier, reported):
        with self.connection() as db:
            # Raw transport reports win; normalization cannot overwrite cache splits/cost.
            db.execute("UPDATE usage_requests SET reported=? WHERE id=? AND reported IS NULL",(json.dumps(reported),identifier))

    def usage(self, session):
        from decimal import Decimal
        totals=dict(input=0,output=0,cacheRead=0,cacheWrite=0,totalTokens=0,requests=0,missingUsage=0,missingCost=0,costUSD=None,compactionTokens=0)
        amount=Decimal(0);costs=0;context=None
        with self.connection() as db:
            historical=db.execute("SELECT historical FROM usage_sessions WHERE session=?",(session,)).fetchone()
            if historical is None:
                historical=[db.execute("SELECT EXISTS(SELECT 1 FROM messages WHERE session=?)",(session,)).fetchone()[0]]
            # Stream rows; long sessions do not load the whole ledger into memory.
            for row in db.execute("SELECT context,reported,purpose FROM usage_requests WHERE session=? ORDER BY created,rowid",(session,)):
                totals['requests']+=1;context=json.loads(row['context'])
                if row['reported'] is None:
                    totals['missingUsage']+=1;totals['missingCost']+=1;continue
                usage=json.loads(row['reported'])
                for key in ('input','output','cacheRead','cacheWrite'):totals[key]+=usage[key]
                used=sum(usage[key] for key in ('input','output','cacheRead','cacheWrite'))
                if row['purpose']=='compaction':totals['compactionTokens']+=used
                if usage['costUSD'] is None:totals['missingCost']+=1
                else:amount+=Decimal(usage['costUSD']);costs+=1
                context['reportedTokens']=usage['input']+usage['cacheRead']+usage['cacheWrite']
        totals['totalTokens']=sum(totals[key] for key in ('input','output','cacheRead','cacheWrite'))
        if costs:totals['costUSD']=format(amount,'f')
        return dict(context=context,totals=totals,historical=bool(historical[0]))
