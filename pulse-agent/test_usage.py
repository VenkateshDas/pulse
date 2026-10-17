import json
import tempfile
import unittest
from types import SimpleNamespace as Obj
from coworker.providers.base import AssistantTurn, TokenUsage, StreamChunk
from conversation_store import ConversationStore
from providers import ProviderConfiguration
from usage_accounting import UsageMeter, MeteredProvider, context_breakdown, estimate, normalize_usage

class UsageTests(unittest.TestCase):
    def meter(self,directory,session='session',endpoint='https://openrouter.ai/api/v1'):
        return UsageMeter(ConversationStore(directory+'/usage.db'),ProviderConfiguration(base_url=endpoint),'session' if session is None else session,'run')
    def raw(self,cost='0.1'):
        return {'prompt_tokens':1000,'completion_tokens':200,'prompt_tokens_details':{'cached_tokens':600,'cache_write_tokens':100},'completion_tokens_details':{'reasoning_tokens':150},'cost':cost}
    def begin(self,meter,purpose='answer'):
        return meter.begin([{'role':'user','content':'Question'}],[],purpose)
    def test_cache_and_reasoning_not_double_counted_and_cost_zero_distinct(self):
        usage=normalize_usage(self.raw('0'))
        self.assertEqual(dict(input=300,output=200,cacheRead=600,cacheWrite=100,costUSD='0'),usage)
        self.assertIsNone(normalize_usage(self.raw(None))['costUSD'])
        for cost in ['NaN','Infinity','-1','1000001',True,'0e-1000000']:
            self.assertIsNone(normalize_usage(self.raw(cost))['costUSD'])
        malformed=self.raw();malformed['prompt_tokens']=-1
        self.assertIsNone(normalize_usage(malformed))
    def test_context_categories_sum_same_guard_and_reserve_stays_separate(self):
        config=ProviderConfiguration()
        messages=[{'role':'system','content':'Rules <pulse_memory>Explicit preference</pulse_memory>'},
                  {'role':'user','content':'<compacted-history>Earlier summary</compacted-history>'},
                  {'role':'user','content':'Question <system-context>Cached vitals</system-context>'},
                  {'role':'tool','content':'Evidence page'}]
        tools=[{'name':'get_vitals'}]
        context=context_breakdown(messages,tools,config,'answer')
        self.assertEqual(estimate(messages,tools),context['estimatedTokens'])
        self.assertEqual(context['estimatedTokens'],sum(c['tokens'] for c in context['categories']))
        self.assertEqual(4096,context['outputReserve'])
        summary=context_breakdown(messages,tools,config,'compaction',2048)
        self.assertEqual(2048,summary['outputReserve'])
        ordinary=context_breakdown([{'role':'user','content':'Explain compacted memory'}],[],config,'answer')
        self.assertNotIn('Conversation summary',{row['label'] for row in ordinary['categories']})
        self.assertTrue({'Memory','Native snapshot','Conversation summary','Tool calls and results'} <= {c['label'] for c in context['categories']})
    def test_ledger_reopen_decimal_cost_idempotence_session_isolation(self):
        with tempfile.TemporaryDirectory() as d:
            meter=self.meter(d);a=self.begin(meter)
            meter.store.usage_report(a,normalize_usage(self.raw('0.1')))
            meter.store.usage_report(a,normalize_usage(self.raw('999')))
            meter.store.usage_begin(a,'session','run','openai-chat','fixture','answer',{})
            b=self.begin(meter,'compaction');meter.store.usage_report(b,normalize_usage(self.raw('0.2')))
            self.begin(meter)
            totals=ConversationStore(d+'/usage.db').usage('session')['totals']
            self.assertEqual('0.3',totals['costUSD']);self.assertEqual(3,totals['requests'])
            self.assertEqual(2400,totals['totalTokens']);self.assertEqual(1200,totals['compactionTokens'])
            self.assertEqual(1,totals['missingUsage']);self.assertEqual(1,totals['missingCost'])
            self.assertEqual(0,meter.store.usage('other')['totals']['requests'])
            self.assertIsNone(meter.store.usage('other')['context'])
    def test_reported_free_vs_unreported_and_historical_coverage(self):
        with tempfile.TemporaryDirectory() as d:
            meter=self.meter(d)
            self.assertIsNone(meter.store.usage('session')['totals']['costUSD'])
            meter.store.checkpoint('older',[{'role':'user','content':'Older prompt'}],[],'old','interrupted')
            meter=self.meter(d,session='older')
            identifier=self.begin(meter);meter.store.usage_report(identifier,normalize_usage(self.raw('0')))
            snapshot=meter.store.usage('older')
            self.assertTrue(snapshot['historical']);self.assertEqual('0',snapshot['totals']['costUSD'])
    def test_raw_stream_preserves_openrouter_charge_before_normalization(self):
        with tempfile.TemporaryDirectory() as d:
            meter=self.meter(d)
            create=meter.raw_create(lambda **kwargs:iter([Obj(usage=self.raw('0.012345'))]))
            class Provider:
                def stream(self,**kwargs):
                    list(create(stream=True))
                    yield StreamChunk(turn=AssistantTurn(usage=TokenUsage(input=9999,output=9999)))
            list(MeteredProvider(Provider(),meter).stream(messages=[],tools=[]))
            totals=meter.store.usage('session')['totals']
            self.assertEqual(1200,totals['totalTokens']);self.assertEqual('0.012345',totals['costUSD'])
            self.assertEqual(1,totals['requests'])
    def test_retried_transport_does_not_charge_success_to_failed_attempt(self):
        with tempfile.TemporaryDirectory() as d:
            meter=self.meter(d);calls=0
            def request(**kwargs):
                nonlocal calls
                calls+=1
                if calls==1:raise RuntimeError('Parameter rejected')
                return Obj(usage=self.raw('0.1'))
            create=meter.raw_create(request)
            class Provider:
                def complete(self,**kwargs):
                    try:create()
                    except RuntimeError:create()
                    return AssistantTurn(usage=TokenUsage(input=9999,output=9999))
            MeteredProvider(Provider(),meter).complete(messages=[])
            totals=meter.store.usage('session')['totals']
            self.assertEqual(2,totals['requests']);self.assertEqual(1200,totals['totalTokens'])
            self.assertEqual(1,totals['missingUsage']);self.assertEqual('0.1',totals['costUSD'])
    def test_summary_usage_is_in_session_total_and_reported_context(self):
        with tempfile.TemporaryDirectory() as d:
            meter=self.meter(d)
            class Provider:
                def complete(self,**kwargs):return AssistantTurn(usage=TokenUsage(input=100,output=25,cache_read=50,cache_write=10))
            MeteredProvider(Provider(),meter).complete(messages=[])
            snapshot=meter.store.usage('session')
            self.assertEqual(185,snapshot['totals']['totalTokens'])
            self.assertEqual(185,snapshot['totals']['compactionTokens'])
            self.assertEqual(160,snapshot['context']['reportedTokens'])
            self.assertEqual(1,snapshot['totals']['missingCost'])
    def test_cancelled_stream_without_final_report_remains_unknown(self):
        with tempfile.TemporaryDirectory() as d:
            meter=self.meter(d)
            class Provider:
                def stream(self,**kwargs):
                    yield StreamChunk(text_delta='Partial')
                    yield StreamChunk(turn=AssistantTurn(usage=TokenUsage(input=12,output=1)))
            stream=MeteredProvider(Provider(),meter).stream(messages=[])
            next(stream);stream.close()
            totals=meter.store.usage('session')['totals']
            self.assertEqual(1,totals['missingUsage']);self.assertIsNone(totals['costUSD'])
    def test_foreign_gateway_does_not_mislabel_arbitrary_cost_as_usd(self):
        with tempfile.TemporaryDirectory() as d:
            meter=self.meter(d,endpoint='https://gateway.example/v1');self.begin(meter)
            meter.raw_create(lambda **kwargs:Obj(usage=self.raw('0.1')))()
            self.assertIsNone(meter.store.usage('session')['totals']['costUSD'])
    def test_responses_terminal_event_and_wire_cost_capture(self):
        with tempfile.TemporaryDirectory() as d:
            meter=self.meter(d);self.begin(meter)
            response=Obj(usage={'input_tokens':500,'output_tokens':30,'input_tokens_details':{'cached_tokens':200},'cost':'0.01'})
            list(meter.raw_create(lambda **kwargs:iter([Obj(response=response)]))(stream=True))
            snapshot=meter.store.usage('session')
            self.assertEqual(530,snapshot['totals']['totalTokens']);self.assertEqual('0.01',snapshot['totals']['costUSD'])

    def test_real_openai_sdk_and_pinned_provider_preserve_stream_cost(self):
        import httpx
        from openai import OpenAI
        from unittest.mock import patch
        def respond(request):
            payload=json.loads(request.content)
            if payload.get('stream'):
                chunks=[{'id':'fixture','object':'chat.completion.chunk','created':0,'model':'fixture','choices':[{'index':0,'delta':{'content':'Done'},'finish_reason':'stop'}]},
                        {'id':'fixture','object':'chat.completion.chunk','created':0,'model':'fixture','choices':[],'usage':self.raw('0.01')}]
                return httpx.Response(200,headers={'content-type':'text/event-stream'},text=''.join('data: '+json.dumps(chunk)+'\n\n' for chunk in chunks)+'data: [DONE]\n\n')
            return httpx.Response(200,json={'id':'fixture','object':'chat.completion','created':0,'model':'fixture',
                                           'choices':[{'index':0,'message':{'role':'assistant','content':'Summary'},'finish_reason':'stop'}], 'usage':self.raw('0.02')})
        with tempfile.TemporaryDirectory() as d:
            meter=self.meter(d)
            client=OpenAI(api_key='fixture',base_url='https://openrouter.ai/api/v1',http_client=httpx.Client(transport=httpx.MockTransport(respond)))
            try:
                with patch('openai.OpenAI',return_value=client):provider=meter.configuration.make_provider(request_meter=meter)
                measured=MeteredProvider(provider,meter)
                chunks=list(measured.stream(model='fixture',messages=[{'role':'user','content':'Question'}]))
                self.assertEqual('Done',chunks[-1].turn.text)
                measured.complete(model='fixture',messages=[{'role':'user','content':'Summarize'}],max_tokens=2048)
                snapshot=meter.store.usage('session')
                self.assertEqual('0.03',snapshot['totals']['costUSD'])
                self.assertEqual(2400,snapshot['totals']['totalTokens'])
                self.assertEqual(1200,snapshot['totals']['compactionTokens'])
                self.assertEqual(0,snapshot['totals']['missingCost'])
                self.assertEqual(2048,snapshot['context']['outputReserve'])
            finally:client.close()
