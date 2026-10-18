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
                CREATE TABLE IF NOT EXISTS conversation_meta(session TEXT PRIMARY KEY, title_origin TEXT NOT NULL DEFAULT 'provisional',
                    revision INTEGER NOT NULL DEFAULT 0, pinned INTEGER NOT NULL DEFAULT 0, archived INTEGER NOT NULL DEFAULT 0);
                CREATE TABLE IF NOT EXISTS workspace_settings(key TEXT PRIMARY KEY, value TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS conversation_tasks(session TEXT PRIMARY KEY, payload TEXT NOT NULL);
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

    def sessions(self, page=1, query='', archived=False):
        query=query.strip()
        if len(query)>200: raise ValueError('Search is limited to 200 characters')
        with self.connection() as db:
            rows=db.execute("""SELECT c.*,coalesce(m.pinned,0) pinned,coalesce(m.archived,0) archived,
                coalesce(m.title_origin,'provisional') title_origin,coalesce(m.revision,0) revision
                FROM conversations c LEFT JOIN conversation_meta m ON m.session=c.id
                WHERE coalesce(m.archived,0)=? AND (?='' OR instr(lower(c.title),lower(?))>0 OR EXISTS(
                    SELECT 1 FROM messages x WHERE x.session=c.id AND json_extract(x.payload,'$.role') IN ('user','assistant')
                    AND instr(lower(json_extract(x.payload,'$.content')),lower(?))>0))
                ORDER BY pinned DESC,c.updated DESC,c.id LIMIT 50 OFFSET ?""", (int(archived),query,query,query,(page-1)*50)).fetchall()
        return [{'session_id':r['id'],'name':r['title'],'updated_at':r['updated'],
                 'pinned':bool(r['pinned']),'archived':bool(r['archived']),'title_origin':r['title_origin'],'revision':r['revision']} for r in rows]

    def session_metadata(self, session):
        with self.connection() as db:
            row=db.execute("SELECT c.title,coalesce(m.revision,0) revision,coalesce(m.title_origin,'provisional') origin FROM conversations c LEFT JOIN conversation_meta m ON m.session=c.id WHERE c.id=?",(session,)).fetchone()
        return dict(row) if row else None

    def update_session(self, session, *, title=None, pinned=None, archived=None):
        if title is not None:
            title=' '.join(title.split())
            if not title or len(title)>80:raise ValueError('Use a title of 1–80 characters')
        with self.connection() as db:
            db.execute('BEGIN IMMEDIATE')
            if not db.execute('SELECT 1 FROM conversations WHERE id=?',(session,)).fetchone():raise ValueError('Conversation unavailable')
            db.execute('INSERT OR IGNORE INTO conversation_meta(session) VALUES(?)',(session,))
            if title is not None:
                db.execute('UPDATE conversations SET title=? WHERE id=?',(title,session))
                db.execute("UPDATE conversation_meta SET title_origin='manual' WHERE session=?",(session,))
            if pinned is not None:db.execute('UPDATE conversation_meta SET pinned=? WHERE session=?',(int(pinned),session))
            if archived is not None:db.execute('UPDATE conversation_meta SET archived=? WHERE session=?',(int(archived),session))
            db.execute('UPDATE conversation_meta SET revision=revision+1 WHERE session=?',(session,))

    def set_generated_title(self, session, title, revision):
        with self.connection() as db:
            db.execute('BEGIN IMMEDIATE')
            db.execute('INSERT OR IGNORE INTO conversation_meta(session) VALUES(?)',(session,))
            changed=db.execute("UPDATE conversation_meta SET title_origin='generated',revision=revision+1 WHERE session=? AND revision=? AND title_origin='provisional' AND archived=0",(session,revision)).rowcount
            if changed:db.execute('UPDATE conversations SET title=? WHERE id=?',(title,session))
        return bool(changed)

    def title_evidence(self, session):
        with self.connection() as db:
            rows=db.execute("SELECT payload FROM messages WHERE session=? AND json_extract(payload,'$.role') IN ('user','assistant') ORDER BY id LIMIT 4",(session,)).fetchall()
        return [{'role':m['role'],'content':str(m.get('content') or '')[:1000]} for row in rows if (m:=json.loads(row[0])).get('content') and not m.get('tool_calls')]

    def setting(self, key, default=''):
        with self.connection() as db:row=db.execute('SELECT value FROM workspace_settings WHERE key=?',(key,)).fetchone()
        return row[0] if row else default

    def set_setting(self, key, value):
        if key!='user_instructions' or len(value)>4000 or len(value.encode())>6000:raise ValueError('Instructions exceed 4,000 characters / 6,000 bytes')
        with self.connection() as db:db.execute('INSERT OR REPLACE INTO workspace_settings VALUES(?,?)',(key,value))

    def tasks(self, session):
        with self.connection() as db:row=db.execute('SELECT payload FROM conversation_tasks WHERE session=?',(session,)).fetchone()
        return json.loads(row[0]) if row else []

    def set_tasks(self, session, tasks, run=None):
        if len(tasks)>20 or any(not isinstance(t,dict) or not isinstance(t.get('title'),str) or not 1<=len(t['title'].strip())<=200 or t.get('status') not in {'pending','running','completed'} for t in tasks):
            raise ValueError('Use up to 20 tasks with a title and pending/running/completed status')
        payload=[{'title':t['title'].strip(),'status':t['status']} for t in tasks]
        with self.connection() as db:
            db.execute('BEGIN IMMEDIATE')
            if run is not None:
                current=db.execute('SELECT id,status FROM executions WHERE session=? ORDER BY updated DESC,rowid DESC LIMIT 1',(session,)).fetchone()
                if not current or current['id']!=run or current['status']!='running':raise ValueError('Investigation no longer owns task progress')
            db.execute('INSERT OR REPLACE INTO conversation_tasks VALUES(?,?)',(session,json.dumps(payload)))
        return payload

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
        return [{"id":row["id"],"revision":0,**json.loads(row["payload"])} for row in rows]

    def remember(self, identifier, payload):
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            if db.execute("SELECT 1 FROM memories WHERE content=?",(payload['content'],)).fetchone():
                return {"status":"Already remembered"}
            if db.execute("SELECT count(*) FROM memories").fetchone()[0]>=100:
                return {"error":"Memory full. Review and remove old memories first"}
            db.execute("INSERT INTO memories VALUES(?,?,?)",(identifier,payload['content'],json.dumps(payload)))
        return {"status":"Remembered","id":identifier}

    def update_memory(self, identifier, payload, revision):
        with self.connection() as db:
            db.execute('BEGIN IMMEDIATE')
            row=db.execute('SELECT payload FROM memories WHERE id=?',(identifier,)).fetchone()
            if not row:raise ValueError('Memory unavailable')
            previous=json.loads(row[0])
            if previous.get('revision',0)!=revision:raise ValueError('Memory changed; reload before editing')
            updated={**previous,**{k:payload[k] for k in ('content','evidence','kind')},'revision':revision+1,'updated_at':int(time.time())}
            try:db.execute('UPDATE memories SET content=?,payload=? WHERE id=?',(updated['content'],json.dumps(updated),identifier))
            except sqlite3.IntegrityError:raise ValueError('That memory already exists')
        return {'status':'Updated','id':identifier,'revision':revision+1}

    def undo_memory_save(self, identifier, revision):
        with self.connection() as db:
            db.execute('BEGIN IMMEDIATE')
            row=db.execute('SELECT payload FROM memories WHERE id=?',(identifier,)).fetchone()
            if not row or json.loads(row[0]).get('revision',0)!=revision:return False
            db.execute('DELETE FROM memories WHERE id=?',(identifier,))
        return True

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
                totals['requests']+=1
                request_context=json.loads(row['context'])
                if row['purpose'] not in {'title','second_opinion'}:context=request_context
                if row['reported'] is None:
                    totals['missingUsage']+=1;totals['missingCost']+=1;continue
                usage=json.loads(row['reported'])
                for key in ('input','output','cacheRead','cacheWrite'):totals[key]+=usage[key]
                used=sum(usage[key] for key in ('input','output','cacheRead','cacheWrite'))
                if row['purpose']=='compaction':totals['compactionTokens']+=used
                if usage['costUSD'] is None:totals['missingCost']+=1
                else:amount+=Decimal(usage['costUSD']);costs+=1
                if row['purpose'] not in {'title','second_opinion'}:context['reportedTokens']=usage['input']+usage['cacheRead']+usage['cacheWrite']
        totals['totalTokens']=sum(totals[key] for key in ('input','output','cacheRead','cacheWrite'))
        if costs:totals['costUSD']=format(amount,'f')
        return dict(context=context,totals=totals,historical=bool(historical[0]))
