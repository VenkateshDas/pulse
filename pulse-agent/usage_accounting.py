"""Content-free usage ledger integration; estimates never masquerade as billing."""
import json
import threading
import time
import uuid
from decimal import Decimal, InvalidOperation


def estimate(messages, tools=()):
    raw=json.dumps([messages,tools],ensure_ascii=False,default=str).encode()
    return int(sum(1 if byte>=128 else 1/3 for byte in raw))+256


def context_breakdown(messages, tools, configuration, purpose, output_limit=None):
    # Attribute serialized content with the same weights as the runtime guard.
    # JSON framing and the safety allowance are explicit rather than hidden.
    weights={label:0.0 for label in ['Instructions','Tool definitions','Native snapshot','Memory','Conversation summary','Conversation','Tool calls and results']}
    def weight(value):
        return sum(1 if byte>=128 else 1/3 for byte in json.dumps(value,ensure_ascii=False,default=str).encode())
    weights['Tool definitions']=weight(tools)
    for message in messages:
        role=message.get('role');content=message.get('content','')
        if role=='system':label='Instructions'
        elif role=='tool' or message.get('tool_calls'):label='Tool calls and results'
        elif role=='user' and isinstance(content,str) and content.startswith('<compacted-history>'):label='Conversation summary'
        else:label='Conversation'
        body=dict(message)
        if isinstance(content,str):
            for start,end,target in [('<system-context>','</system-context>','Native snapshot'),('<pulse_memory>','</pulse_memory>','Memory')]:
                if start in content and end in content:
                    left,rest=content.split(start,1);block,right=rest.split(end,1)
                    weights[target]+=weight(start+block+end);content=left+right
            body['content']=content
        weights[label]+=weight(body)
    total=estimate(messages,tools)
    categories=[{'label':label,'tokens':int(value)} for label,value in weights.items() if int(value)>0]
    # JSON boundary accounting can differ by a few tokens after splitting strings.
    overflow=max(0,sum(row['tokens'] for row in categories)-total)
    for row in sorted(categories,key=lambda row:row['tokens'],reverse=True):
        take=min(overflow,row['tokens']);row['tokens']-=take;overflow-=take
    categories.append({'label':'Framing and safety allowance','tokens':total-sum(row['tokens'] for row in categories)})
    return {'estimatedTokens':total,'limit':configuration.context_tokens,'outputReserve':min(output_limit,configuration.output_tokens) if isinstance(output_limit,int) and output_limit>0 else configuration.output_tokens,
            'purpose':purpose,'model':configuration.model,'measuredAt':int(time.time()),'categories':categories}


def value(obj,key,default=None):
    return obj.get(key,default) if isinstance(obj,dict) else getattr(obj,key,default)


def count(number):
    return number if isinstance(number,int) and not isinstance(number,bool) and 0<=number<=10**10 else None


def normalize_usage(usage):
    if usage is None:return None
    # Native Chat / Responses usage includes cached tokens inside prompt totals.
    prompt=count(value(usage,'prompt_tokens',value(usage,'input_tokens')))
    output=count(value(usage,'completion_tokens',value(usage,'output_tokens')))
    details=value(usage,'prompt_tokens_details',value(usage,'input_tokens_details',{})) or {}
    read=count(value(details,'cached_tokens',0));write=count(value(details,'cache_write_tokens',0))
    if prompt is None or output is None or read is None or write is None or read+write>prompt:return None
    cost=None
    try:
        raw=value(usage,'cost')
        if isinstance(raw,(str,int,float,Decimal)) and not isinstance(raw,bool) and len(str(raw))<=128:
            parsed=Decimal(str(raw))
            if parsed.is_finite() and 0<=parsed<=1_000_000 and -18<=parsed.as_tuple().exponent<=6:cost=format(parsed,'f')
    except (InvalidOperation,ValueError,TypeError):pass
    return {'input':prompt-read-write,'output':output,'cacheRead':read,'cacheWrite':write,'costUSD':cost}


class UsageMeter:
    def __init__(self,store,configuration,session_id,run_id):
        self.store,self.configuration,self.session_id,self.run_id=store,configuration,session_id,run_id
        self.store.usage_initialize(session_id)
        self.local=threading.local()
        self.on_change=lambda:None

    def notify(self):
        try:self.on_change()
        except Exception:pass

    def begin(self,messages,tools,purpose,output_limit=None):
        identifier=str(uuid.uuid4())
        context=context_breakdown(messages,tools or (),self.configuration,purpose,output_limit)
        self.store.usage_begin(identifier,self.session_id,self.run_id,self.configuration.provider,self.configuration.model,purpose,context)
        self.local.identifier=identifier;self.local.context=context;self.local.purpose=purpose;self.local.transports=0
        self.notify()
        return identifier

    def raw_create(self,create):
        # A run-owned SDK seam, never a global monkeypatch or a provider fork.
        def capture(**kwargs):
            identifier=getattr(self.local,'identifier',None)
            if identifier is None:return create(**kwargs)
            if self.local.transports:
                identifier=str(uuid.uuid4())
                self.store.usage_begin(identifier,self.session_id,self.run_id,self.configuration.provider,self.configuration.model,
                                       self.local.purpose,self.local.context)
            self.local.transports+=1
            response=create(**kwargs)
            def ingest(obj):
                usage=normalize_usage(value(obj,'usage'))
                if usage is None:
                    usage=normalize_usage(value(value(obj,'response',{}),'usage'))
                if usage is not None:
                    # Cost is a USD charge only for the documented OpenRouter host.
                    from urllib.parse import urlsplit
                    if urlsplit(self.configuration.base_url).hostname!='openrouter.ai':usage['costUSD']=None
                    self.store.usage_report(identifier,usage);self.notify()
            if not kwargs.get('stream'):
                ingest(response);return response
            def stream():
                try:
                    for chunk in response:
                        ingest(chunk);yield chunk
                finally:
                    if hasattr(response,'close'):response.close()
            return stream()
        return capture

    def normalized(self,identifier,turn):
        if getattr(self.local,'transports',0):return
        usage=turn.usage
        if usage is None:return
        values={key:count(getattr(usage,source,None)) for key,source in [('input','input'),('output','output'),('cacheRead','cache_read'),('cacheWrite','cache_write')]}
        if any(number is None for number in values.values()):return
        values['costUSD']=None
        self.store.usage_report(identifier,values);self.notify()


class MeteredProvider:
    def __init__(self,provider,meter):self.provider,self.meter=provider,meter
    def __getattr__(self,name):return getattr(self.provider,name)
    def complete(self,**kwargs):
        identifier=self.meter.begin(kwargs.get('messages',[]),kwargs.get('tools'), 'compaction',kwargs.get('max_tokens'))
        turn=self.provider.complete(**kwargs);self.meter.normalized(identifier,turn)
        return turn
    def stream(self,**kwargs):
        identifier=self.meter.begin(kwargs.get('messages',[]),kwargs.get('tools'),'answer',kwargs.get('max_tokens'))
        stream=self.provider.stream(**kwargs)
        try:
            for chunk in stream:
                if chunk.turn is not None:self.meter.normalized(identifier,chunk.turn)
                yield chunk
        finally:
            if hasattr(stream,'close'):stream.close()
