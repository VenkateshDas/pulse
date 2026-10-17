"""Pulse adaptation of pinned OpenWorker TurnEngine (MIT; see OPENWORKER-LICENSE).

Own only integration seams: async native tools, strict consent, bounded streaming,
context budgets, durable checkpoints and metadata diagnostics. Upstream owns the loop,
call-pair repair, retry/truncation semantics and summary/working-state compaction.
"""
import asyncio
from concurrent.futures import TimeoutError as FutureTimeout
import inspect
import json
import os
from pathlib import Path
import threading
import time
import uuid
from coworker.engine import TurnEngine
from coworker import compaction as upstream_compaction
from coworker.events import Event, EventType
from coworker.permissions import PermissionEngine
from coworker.tools import ToolRegistry
from coworker.toolresult import PagedToolResult
from coworker.skills import SkillLoader, skill_catalog_text
from context import build_system_instructions
from pulse_toolkit import PulseToolkit
from diagnostics import record

# A stopped but blocked SDK thread still occupies capacity until it really exits.
PRODUCERS = threading.BoundedSemaphore(4)
COMPACTION_TIMEOUT = 65
INTERACTION_TIMEOUT = 300

def estimate(messages, tools=()):
    raw = json.dumps([messages, tools], ensure_ascii=False, default=str).encode()
    return int(sum(1 if byte >= 128 else 1/3 for byte in raw)) + 256

class _CompactionProvider:
    """Keep upstream summary policy; constrain its blocking provider transport."""
    def __init__(self, provider, configuration, cancel):
        self.provider, self.configuration, self.cancel = provider, configuration, cancel

    def __getattr__(self, name):
        return getattr(self.provider, name)

    def complete(self, **kwargs):
        if self.cancel.is_set():
            raise RuntimeError("Compaction interrupted")
        output = min(int(kwargs.get("max_tokens") or self.configuration.output_tokens), self.configuration.output_tokens)
        units = estimate(kwargs.get("messages", []), kwargs.get("tools") or ())
        if output <= 0 or units + output > self.configuration.context_tokens:
            # Upstream handles this as a failed summary and applies its honest trim policy.
            record("context.summary_skipped", context_estimate=units,
                   context_limit=self.configuration.context_tokens, status="over_budget")
            raise ValueError("Compaction input exceeds configured context budget")
        if not PRODUCERS.acquire(blocking=False):
            raise RuntimeError("Provider capacity occupied")
        try:
            if self.cancel.is_set():
                raise RuntimeError("Compaction interrupted")
            result = self.provider.complete(**{**kwargs, "max_tokens": output})
            if self.cancel.is_set():
                raise RuntimeError("Compaction interrupted")
            return result
        finally:
            # Cancellation never frees a still-running SDK worker's slot.
            PRODUCERS.release()

class PulseTurnEngine(TurnEngine):
    def __init__(self, *, configuration, store, session_id, run_id, provider=None, context="", memory=None, read_only=False):
        self.configuration = configuration
        self.store = store
        self.session_id = session_id
        self.run_id = run_id
        self.toolkit = PulseToolkit(run_id=run_id, session_id=session_id)
        self.pending = None
        self.decision = None
        self.tool_count = 0
        self.started = time.monotonic()
        self.memory = memory
        self.read_only = read_only
        self.checkpoint_lock = asyncio.Lock()
        self.registry = ToolRegistry()
        for func in self.toolkit.tools:
            self.registry.register(func)
        self.registry.register(self.search_conversation)
        self.registry.register(self.read_tool_result)
        self.registry.register(self.ask_user)
        self.registry.register(self.propose_plan)
        if memory and configuration.memory_enabled:
            self.registry.register(memory.save_pulse_memory)
        root = Path(os.environ.get("PULSE_SKILL_DIR") or Path(__file__).resolve().parent.parent / ".agents/skills/pulse")
        self.skill_root = root.resolve()
        self.skills = SkillLoader([root.parent])
        if not (root / "SKILL.md").is_file() or "pulse" not in self.skills.names():
            raise RuntimeError("Bundled Pulse skill unavailable")
        self.registry.register(self.load_skill)
        self.registry.register(self.read_skill_reference)
        checkpoint = store.view(session_id)
        history = checkpoint.get("messages", []) if isinstance(checkpoint,dict) else checkpoint
        prior_compaction = upstream_compaction.CompactionState.from_dict(checkpoint.get("compaction")) if isinstance(checkpoint,dict) else None
        self.saved_count = len(history)+1  # TurnEngine inserts the system message.
        instructions = build_system_instructions() + "\n" + skill_catalog_text(self.skills, {"pulse"})
        if memory:
            instructions += "\n" + memory.instructions() + "\n" + memory.build_context(memory.recall())
        instructions += "\nEarlier dialogue is searchable with search_conversation; full offloaded evidence is available with read_tool_result. Never infer omitted evidence.\n"
        if read_only:
            instructions += "\nRead-only investigation mode: changes and persistent memory writes are unavailable. Investigate and explain without attempting them.\n"
        super().__init__(provider=provider or configuration.make_provider(), registry=self.registry,
            permissions=PermissionEngine(workspace_root=Path(store.path).parent), model=configuration.model,
            instructions=instructions, messages=history, max_iterations=12,
            model_settings={"max_tokens": configuration.output_tokens}, tool_result_max_bytes=6000,
            context_provider=lambda: context)
        self.provider = _CompactionProvider(self.provider, configuration, self._cancel)
        self.compaction_state = prior_compaction

    def _compaction_config(self):
        # Include schema/output reserve; upstream defaults assume much larger contexts.
        available = self.configuration.context_tokens-self.configuration.output_tokens
        return {"enabled": True, "context_window": self.configuration.context_tokens, "threshold_pct": .65,
                "cap_tokens": int(available*.75), "summary_max_tokens": min(2048, self.configuration.output_tokens), "model": self.model}

    def _compaction_due(self):
        cfg = self._compaction_config()
        # Upstream uses chars/4; use the same conservative estimate as the hard guard.
        return estimate(self._outbound_messages(), self.registry.schemas()) >= cfg["cap_tokens"]

    def _outbound_messages(self):
        return [{k:v for k,v in message.items() if not k.startswith("_pulse_")}
                for message in super()._outbound_messages()]

    async def _compact_now(self, *, force=False):
        before = estimate(self._outbound_messages(), self.registry.schemas())
        # Cancelling this waiter does not stop a blocking SDK call. Its transport
        # retains PRODUCERS capacity until it really exits, and cannot publish state.
        text = await self._interruptible(
            asyncio.wait_for(super()._compact_now(force=force), timeout=COMPACTION_TIMEOUT), None)
        if self._cancel.is_set():
            return None
        budget = self.configuration.context_tokens - self.configuration.output_tokens
        # Imported history may already exceed the model window. If summarization
        # cannot fit, advance upstream's explicit no-summary trim until sendable.
        # Canonical history remains intact and searchable; never fake a summary.
        while estimate(self._outbound_messages(), self.registry.schemas()) > budget:
            previous = self.compaction_state
            trimmed = upstream_compaction.trim_state(self.messages, prior=previous,
                user_budget_tokens=upstream_compaction.user_message_budget(self._compaction_config()["cap_tokens"]))
            if trimmed is None or (previous is not None and trimmed.boundary_index <= previous.boundary_index):
                break
            self.compaction_state = trimmed
            self._last_context_tokens = None
            text = "Context trimmed to fit; earlier dialogue remains searchable (summary unavailable)."
        record("context.compaction", run_id=self.run_id, session_id=self.session_id,
               context_estimate=estimate(self._outbound_messages(), self.registry.schemas()),
               context_before=before, status="trimmed" if self.compaction_state and self.compaction_state.trimmed else "compacted" if text else "unchanged")
        return text

    async def checkpoint(self, status="running"):
        async with self.checkpoint_lock:
            new = self.messages[self.saved_count:]
            for message in new:
                message.setdefault("_pulse_message_id", str(uuid.uuid4()))
            # Preserve structured compaction state, not its rendered synthetic user
            # message. Recompacting that message after every reopen pins summaries
            # inside summaries and eventually consumes the entire context window.
            state = self.compaction_state
            if state and 0 < state.boundary_index < len(self.messages):
                tail = self.messages[state.boundary_index:]
                compact = state.as_dict(); compact["boundary_index"] = 1
                view = {"messages":tail,"compaction":compact}
            else:
                view = {"messages":[m for m in self.messages if m.get("role")!="system"],"compaction":None}
            # Provider reasoning is never part of public history or diagnostics.
            clean = [{k:v for k,v in m.items() if k not in {"reasoning"}} for m in new]
            saved_end = len(self.messages)
            commit = asyncio.create_task(asyncio.to_thread(self.store.checkpoint, self.session_id, clean, view, self.run_id, status,
                                    next((str(m["content"])[:80] for m in self.messages if m.get("role")=="user"), "Conversation")))
            try:await asyncio.shield(commit)
            except asyncio.CancelledError:
                # Keep checkpoint ordering while the SQLite transaction finishes.
                # Stable canonical IDs additionally make an uncertain retry safe.
                await commit
                self.saved_count = saved_end
                raise
            self.saved_count = saved_end

    async def search_conversation(self, query: str) -> dict:
        """Search earlier dialogue in this conversation. Use when compacted details matter."""
        return await asyncio.to_thread(self.store.search, self.session_id, query)

    async def read_tool_result(self, result_id: str, offset: int = 0) -> dict:
        """Read a bounded page of this conversation's offloaded evidence. Offset is characters."""
        return PagedToolResult(await asyncio.to_thread(self.store.read_result, self.session_id, result_id, offset))

    async def ask_user(self, question: str, options: list[str] = []) -> dict:
        """Ask one focused clarification, with optional choices and a free-text answer."""
        return {"error":"Questions require the interaction gate"}

    async def propose_plan(self, plan: str) -> dict:
        """Present an investigation plan for review. Plan acceptance grants no action approval."""
        return {"error":"Plans require the interaction gate"}

    async def load_skill(self, name: str = "pulse") -> dict:
        """Load the bundled Pulse diagnostic skill. Other skills are not available."""
        skill = self.skills.get(name) if name=="pulse" else None
        return {"name":"pulse", "instructions":skill.instructions} if skill else {"error":"Unknown skill"}

    async def read_skill_reference(self, path: str) -> dict:
        """Read a bundled Pulse reference using its relative path; scripts cannot run."""
        candidate = (self.skill_root / path).resolve()
        if not candidate.is_relative_to(self.skill_root) or candidate.suffix != ".md" or not candidate.is_file():
            return {"error":"Unknown bundled reference"}
        if candidate.stat().st_size>64000:
            return {"error":"Reference exceeds read limit"}
        return {"text": await asyncio.to_thread(candidate.read_text, encoding="utf-8")}

    def _record_result(self, call, result, status):
        if not isinstance(result, PagedToolResult):
            text = json.dumps(result, ensure_ascii=False, default=str)
            if len(text.encode())>6000:
                try:
                    identifier = self.store.result(self.session_id, text)
                    result={"result_id":identifier,"preview":text[:1000],"truncated":True,
                            "total_bytes":len(text.encode()),"instruction":"Use read_tool_result for the remaining evidence."}
                except Exception:
                    result={"preview":text[:1000],"truncated":True,"full_result_available":False}
        event = super()._record_result(call,result,status)
        self.messages[-1]["_pulse_operation"] = call.name
        self.messages[-1]["_pulse_status"] = status
        # Upstream emits only a 300-character preview; Pulse can inspect a bounded result.
        event.data["detail"] = result
        return event

    async def _handle_tool_calls(self, calls):
        # Upstream's registry is sync. This seam awaits native async operations directly.
        # Serial execution preserves preview/action ordering and keeps scan concurrency bounded.
        for call in calls:
            if self._cancel.is_set():
                yield self._interrupted_tool(call); continue
            spec = self.registry.get(call.name)
            if not spec or self.tool_count>=16 or "_raw" in call.arguments:
                yield self._record_result(call,{"error":"Unknown tool, malformed arguments or tool budget reached"},"error")
                continue
            self.tool_count+=1
            if self.read_only and call.name in self.toolkit.mutations | {"save_pulse_memory"}:
                yield self._record_result(call,{"error":"Read-only investigation mode. Changes require switching mode and fresh approval."},"denied")
                continue
            allowed = True
            interaction = "question" if call.name=="ask_user" else "plan" if call.name=="propose_plan" else "action"
            if interaction != "action":
                text = call.arguments.get("question" if interaction=="question" else "plan")
                options = call.arguments.get("options", [])
                if (not isinstance(text,str) or not text.strip() or len(text.encode())>12000
                        or not isinstance(options,list) or len(options)>8
                        or any(not isinstance(option,str) or not option.strip() or len(option.encode())>500 for option in options)):
                    yield self._record_result(call,{"error":"Supply bounded review text and up to eight short text options"},"error")
                    continue
            if call.name in self.toolkit.mutations or interaction != "action":
                evidence = self.toolkit.approval_evidence(call.name, call.arguments) if interaction=="action" else call.arguments
                if len(json.dumps(evidence,ensure_ascii=False).encode())>24000:
                    yield self._record_result(call,{"error":"Review exceeds display limit; narrow the request"},"error");continue
                identifier = await asyncio.to_thread(self.store.pending,self.run_id,self.session_id,call.id,call.name,call.arguments,evidence)
                self.pending={"id":identifier,"call":call,"evidence":evidence,"kind":interaction}
                self.decision=asyncio.get_running_loop().create_future()
                await self.checkpoint("waiting")
                yield Event(EventType.PERMISSION_REQUIRED,{"approval_id":identifier,"tool_call_id":call.id,"name":call.name,"detail":evidence,"interaction":interaction})
                try:
                    allowed = await self._interruptible(
                        asyncio.wait_for(self.decision, timeout=INTERACTION_TIMEOUT), False)
                except TimeoutError:
                    await asyncio.to_thread(self.store.resolve, identifier, self.run_id, False)
                    raise TimeoutError("Interaction expired; request a fresh review")
                finally:
                    # CAS is harmless after an accepted answer; expire unanswered
                    # decisions on Stop as well as timeout before forgetting them.
                    try:await asyncio.to_thread(self.store.resolve, identifier, self.run_id, False)
                    finally:self.pending=None;self.decision=None
            if interaction != "action":
                result = {"answer":allowed} if interaction=="question" else {"approved":bool(allowed),"notice":"This plan grants no permission for mutations."}
                yield self._record_result(call,result,"ok" if allowed else "denied")
                continue
            if not allowed or self._cancel.is_set():
                yield self._record_result(call,{"error":"Action declined or interrupted"},"denied")
                continue
            start=time.monotonic()
            yield Event(EventType.TOOL_STARTED,{"name":call.name,"tool_call_id":call.id})
            record("tool.started",run_id=self.run_id,session_id=self.session_id,call_id=call.id,operation=call.name)
            try:
                result=spec.func(**call.arguments)
                if inspect.isawaitable(result):
                    result=await self._interruptible(result, {"error":"Interrupted; inspect any action already started"})
                status="error" if isinstance(result,dict) and (result.get("error") or result.get("exitCode")) else "ok"
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                result={"error":"Tool failed. Inspect state before retrying an action."};status="error"
                record("tool.failed",run_id=self.run_id,call_id=call.id,operation=call.name,error_type=type(exc).__name__)
            record("tool.finished",run_id=self.run_id,call_id=call.id,operation=call.name,status=status,elapsed_ms=int((time.monotonic()-start)*1000))
            yield self._record_result(call,result,status)

    async def _astream(self):
        loop=asyncio.get_running_loop()
        queue=asyncio.Queue(maxsize=128)
        tools=self.registry.schemas() or None
        messages=self._outbound_messages()
        units=estimate(messages,tools)
        if units>self.configuration.context_tokens-self.configuration.output_tokens:
            raise ValueError("Context budget reached after compaction; use conversation search or a larger configured context")
        record("provider.request",run_id=self.run_id,session_id=self.session_id,provider=self.configuration.provider,
               context_estimate=units,context_limit=self.configuration.context_tokens,message_count=len(messages))
        if not PRODUCERS.acquire(blocking=False):
            raise RuntimeError("Provider capacity occupied; wait for stopped connections to close")
        def send(kind,value):
            if self._cancel.is_set():return False
            pending=asyncio.run_coroutine_threadsafe(queue.put((kind,value)),loop)
            while True:
                try:pending.result(timeout=.1);return True
                except FutureTimeout:
                    if self._cancel.is_set():pending.cancel();return False
                except Exception:return False
        def produce():
            stream=None
            last_activity=0
            try:
                stream=self.provider.stream(model=self.model,messages=messages,tools=tools,**self.model_settings)
                for chunk in stream:
                    if self._cancel.is_set():break
                    # Do not queue private reasoning text. Sparse transport activity
                    # keeps a legitimately thinking provider from looking disconnected.
                    chunk.reasoning_delta=None
                    if chunk.text_delta and len(chunk.text_delta.encode())>128000:
                        raise ValueError("Provider chunk exceeds limit")
                    if chunk.turn is not None:
                        turn=chunk.turn
                        turn.reasoning=None
                        calls=[{"id":call.id,"name":call.name,"arguments":call.arguments} for call in turn.tool_calls]
                        if len((turn.text or "").encode())>128000 or len(json.dumps(calls,ensure_ascii=False).encode())>128000:
                            raise ValueError("Provider response exceeds limit")
                    if not chunk.text_delta and chunk.turn is None:
                        if time.monotonic()-last_activity>=1:
                            last_activity=time.monotonic()
                            if not send("activity",None):break
                        continue
                    if not send("chunk",chunk):break
            except Exception as exc:send("error",exc)
            finally:
                if stream and hasattr(stream,"close"):
                    try:stream.close()
                    except Exception:pass
                PRODUCERS.release();send("done",None)
        producer=loop.run_in_executor(None,produce)
        cancel=asyncio.create_task(self._cancel.wait())
        completed=False
        try:
            while True:
                get=asyncio.create_task(queue.get())
                try:
                    done,_=await asyncio.wait({get,cancel},timeout=65,return_when=asyncio.FIRST_COMPLETED)
                    if cancel in done:return
                    if get not in done:raise TimeoutError("Provider stream inactive")
                    kind,value=get.result()
                finally:
                    if not get.done():get.cancel()
                if kind=="activity":continue
                if kind=="error":raise value
                if kind=="done":completed=True;return
                yield value
        finally:
            cancel.cancel()
            # A cancelled observer must also stop the queue producer; never leave it blocked on put.
            if not completed and not producer.done():self._cancel.set()
