
import json, os, pathlib, subprocess, sys, time
root = pathlib.Path(os.environ['ACP_FIXTURE_ROOT'])
(root / 'pid').write_text(str(os.getpid()))
with (root / 'spawns').open('a') as log:
    log.write(str(os.getpid()) + '\n')
(root / 'process-cwd').write_text(os.getcwd())
next_session = 0
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
        mode=(root / 'mode').read_text()
        if mode == 'initialize-hold':
            (root / 'initializing').write_text('received')
            while not (root / 'release-init').exists():
                time.sleep(0.01)
            mode=(root / 'mode').read_text()
        # Ordinary lifecycle cases use HTTP so they do not require the separately
        # packaged stdio executable. Dedicated stdio cases exercise that transport.
        capabilities={'loadSession':True, 'mcpCapabilities':{'http': mode != 'mcp-stdio'}, 'sessionCapabilities':{'close':{}}}
        result={'protocolVersion':1, 'agentCapabilities':capabilities,
                'agentInfo':{'name':'synthetic-peer','version':'1.4.5'},
                'authMethods':[{'id':'login','name':'Sign in','description':'Use the official server login'}]}
    elif method in ['session/new','session/load','session/resume']:
        mode=(root / 'mode').read_text()
        if mode == 'auth':
            emit({'jsonrpc':'2.0','id':rid,'error':{'code':-32000,'message':'Authentication required',
                  'data':{'instruction':'Use server login'}}})
            continue
        if mode == 'mcp-http':
            servers=msg['params'].get('mcpServers', [])
            http_servers=[server for server in servers if server.get('type') == 'http']
            valid=(len(http_servers) == 1
                   and http_servers[0].get('name') == 'anywork'
                   and http_servers[0].get('url', '').startswith('http://127.0.0.1:')
                   and http_servers[0].get('url', '').endswith('/mcp'))
            if valid:
                headers=http_servers[0].get('headers', [])
                valid=any(header.get('name', '').lower() == 'authorization'
                          and header.get('value', '').startswith('Bearer ')
                          and len(header.get('value', '')) > len('Bearer ')
                          for header in headers)
            # Persist only a safe boolean. Never write the endpoint or header values.
            (root / 'mcp-http-received').write_text('true' if valid else 'false')
            if not valid:
                emit({'jsonrpc':'2.0','id':rid,'error':{
                    'code':-32602,'message':'Expected host HTTP MCP setup was not received'}})
                continue
        if method == 'session/new':
            next_session += 1
        sid=msg['params'].get('sessionId', 'remote-one' if next_session == 1 else 'remote-' + str(next_session))
        with (root / 'sessions').open('a') as log:
            log.write(json.dumps({'id':sid, 'cwd':msg['params']['cwd'], 'mcp':bool(msg['params'].get('mcpServers', []))}) + '\n')
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
        sid=msg['params']['sessionId']
        assert sid
        if (root / 'mode').read_text() == 'prompt-fail':
            emit({'jsonrpc':'2.0','id':rid,'error':{'code':-32603,'message':'prompt failed'}})
            continue
        if (root / 'mode').read_text() == 'prompt-hold':
            (root / 'prompting').write_text('received')
            while not (root / 'release').exists():
                time.sleep(0.01)
        usage = msg['params']['prompt'] == [{'type':'text','text':'/usage'}]
        if usage:
            with (root / 'usage-sessions').open('a') as log:
                log.write(sid + '\n')
        update(sid, '### Quota Limits\n- No quota limits reported.' if usage else 'actual answer')
        result={'stopReason':'end_turn'}
    elif method == 'authenticate':
        assert msg['params']['methodId'] == 'login'
        (root / 'mode').write_text('replay')
        result={}
    elif method == 'session/close':
        result={}
    else:
        emit({'jsonrpc':'2.0','id':rid,'error':{'code':-32601,'message':'method not found'}})
        continue
    emit({'jsonrpc':'2.0','id':rid,'result':result})
