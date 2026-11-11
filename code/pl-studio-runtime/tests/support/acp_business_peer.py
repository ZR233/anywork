
import json, os, pathlib, subprocess, sys, time
root = pathlib.Path(os.environ['ACP_FIXTURE_ROOT'])
(root / 'pid').write_text(str(os.getpid()))
def emit(value):
    sys.stdout.write(json.dumps(value) + '\n')
    sys.stdout.flush()
def update(sid, text):
    emit({'jsonrpc':'2.0','method':'session/update','params':{
        'sessionId':sid,'update':{'sessionUpdate':'agent_message_chunk','content':{'type':'text','text':text}}}})
for line in sys.stdin:
    msg=json.loads(line)
    method=msg['method']
    with (root / 'calls').open('a') as log:
        log.write(method + '\n')
    if 'id' not in msg:
        assert method == 'session/cancel', method
        continue
    rid=msg['id']
    if method == 'initialize':
        result={'protocolVersion':1, 'agentCapabilities':{'loadSession':True},
                'authMethods':[{'id':'login','name':'Sign in','description':'Use the official server login'}]}
    elif method in ['session/new','session/load','session/resume']:
        mode=(root / 'mode').read_text()
        if mode == 'auth':
            emit({'jsonrpc':'2.0','id':rid,'error':{'code':-32000,'message':'Authentication required',
                  'data':{'instruction':'Use server login'}}})
            continue
        sid=msg['params'].get('sessionId', 'remote-one')
        if mode in ['replay', 'load-hold']:
            update(sid, 'history before ready')
        if mode == 'load-hold':
            (root / 'opening').write_text('received')
            while not (root / 'release').exists():
                time.sleep(0.01)
        if mode == 'gap':
            for i in range(65):
                update(sid, 'history ' + str(i))
        if mode in ['hang', 'hang-auth']:
            child=subprocess.Popen([sys.executable,'-c','import time; time.sleep(120)'])
            (root / 'child').write_text(str(child.pid))
            (root / 'opening').write_text('received')
            while not (root / 'release').exists():
                time.sleep(0.01)
            if mode == 'hang-auth':
                emit({'jsonrpc':'2.0','id':rid,'error':{'code':-32000,'message':'Authentication required'}})
                continue
        result={'sessionId':sid}
    elif method == 'session/prompt':
        assert msg['params']['sessionId'] == 'remote-one'
        if (root / 'mode').read_text() == 'prompt-fail':
            emit({'jsonrpc':'2.0','id':rid,'error':{'code':-32603,'message':'prompt failed'}})
            continue
        if (root / 'mode').read_text() == 'prompt-hold':
            (root / 'prompting').write_text('received')
            while not (root / 'release').exists():
                time.sleep(0.01)
        update('remote-one','actual answer')
        result={'stopReason':'end_turn'}
    elif method == 'session/close':
        result={}
    else:
        emit({'jsonrpc':'2.0','id':rid,'error':{'code':-32601,'message':'method not found'}})
        continue
    emit({'jsonrpc':'2.0','id':rid,'result':result})
