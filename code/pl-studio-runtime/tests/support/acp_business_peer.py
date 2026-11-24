
import json, os, pathlib, subprocess, sys, time
root = pathlib.Path(os.environ['ACP_FIXTURE_ROOT'])
(root / 'pid').write_text(str(os.getpid()))
with (root / 'spawns').open('a') as log:
    log.write(str(os.getpid()) + '\n')
(root / 'process-cwd').write_text(os.getcwd())
next_session = 0
next_probe = 0
probe_sessions = set()
stdio_endpoints = set()
stdio_capabilities = set()
stdio_sessions = 0
permission_prompts = {}
def emit(value):
    sys.stdout.write(json.dumps(value) + '\n')
    sys.stdout.flush()
def update(sid, text):
    emit({'jsonrpc':'2.0','method':'session/update','params':{
        'sessionId':sid,'update':{'sessionUpdate':'agent_message_chunk','content':{'type':'text','text':text}}}})
def title_update(sid, fields):
    emit({'jsonrpc':'2.0','method':'session/update','params':{
        'sessionId':sid,'update':{'sessionUpdate':'session_info_update', **fields}}})
for line in sys.stdin:
    msg=json.loads(line)
    if 'method' not in msg and msg.get('id') in permission_prompts:
        sid, prompt_id = permission_prompts.pop(msg['id'])
        (root / 'permission-outcome.json').write_text(json.dumps(msg['result']['outcome']))
        update(sid, 'actual answer')
        emit({'jsonrpc':'2.0','id':prompt_id,'result':{'stopReason':'end_turn'}})
        continue
    method=msg['method']
    with (root / 'calls').open('a') as log:
        log.write(method + '\n')
    if method.startswith('session/'):
        params = msg.get('params', {})
        probe = ((method == 'session/new' and not params.get('mcpServers', []))
                 or params.get('sessionId') in probe_sessions)
        with (root / ('probe-calls' if probe else 'business-calls')).open('a') as log:
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
        if mode == 'session-titles':
            capabilities['sessionCapabilities']['list'] = {}
        version_path=root / 'server-version'
        server_version=version_path.read_text().strip() if version_path.exists() else '1.5.2'
        result={'protocolVersion':1, 'agentCapabilities':capabilities,
                'agentInfo':{'name':'synthetic-peer','version':server_version},
                'authMethods':[{'id':'login','name':'Sign in','description':'Use the official server login'}]}
    elif method in ['session/new','session/load','session/resume']:
        mode=(root / 'mode').read_text()
        if mode == 'auth':
            emit({'jsonrpc':'2.0','id':rid,'error':{'code':-32000,'message':'Authentication required',
                  'data':{'instruction':'Use server login'}}})
            continue
        # Auth probes use an empty MCP list and a private cwd. Business fault modes
        # target the session with Host MCP; they must not block the account's probe.
        if method == 'session/new' and not msg['params'].get('mcpServers', []):
            next_probe += 1
            sid = 'probe-' + str(next_probe)
            probe_sessions.add(sid)
            with (root / 'sessions').open('a') as log:
                log.write(json.dumps({'id':sid, 'cwd':msg['params']['cwd'], 'mcp':False}) + '\n')
            emit({'jsonrpc':'2.0','id':rid,'result':{'sessionId':sid}})
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
        if mode == 'mcp-stdio':
            servers=msg['params'].get('mcpServers', [])
            assert len(servers) == 1 and servers[0].get('name') == 'anywork'
            server=servers[0]
            env={item['name']: item['value'] for item in server['env']}
            endpoint=env['ANYWORK_HOST_IPC_ENDPOINT']
            capability=env['ANYWORK_HOST_IPC_CAPABILITY']
            assert endpoint not in stdio_endpoints and capability not in stdio_capabilities
            stdio_endpoints.add(endpoint)
            stdio_capabilities.add(capability)
            stdio_sessions += 1
            # Only safe facts and the executable path leave the synthetic peer's memory.
            (root / 'stdio-isolation').write_text(str(stdio_sessions))
            with (root / 'stdio-helper-paths').open('a') as log:
                log.write(server['command'] + '\n')
        if method == 'session/new':
            next_session += 1
        sid=msg['params'].get('sessionId', 'remote-one' if next_session == 1 else 'remote-' + str(next_session))
        with (root / 'sessions').open('a') as log:
            log.write(json.dumps({'id':sid, 'cwd':msg['params']['cwd'], 'mcp':bool(msg['params'].get('mcpServers', []))}) + '\n')
        if mode in ['replay', 'load-hold']:
            update(sid, 'history before ready')
        if mode == 'session-titles' and method == 'session/load' and (root / 'load-title').exists():
            title_update(sid, {'title': (root / 'load-title').read_text()})
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
        if mode == 'config':
            result['configOptions']=[{'id':'format','name':'Output format','type':'select',
                'currentValue':'plain','options':[{'value':'plain','name':'Plain'}, {'value':'json','name':'JSON'}]}]
    elif method == 'session/set_config_option':
        assert msg['params']['configId'] == 'format'
        result={'configOptions':[{'id':'format','name':'Output format','type':'select',
            'currentValue':msg['params']['value'],'options':[{'value':'plain','name':'Plain'}, {'value':'json','name':'JSON'}]}]}
    elif method == 'session/prompt':
        sid=msg['params']['sessionId']
        assert sid
        if (root / 'mode').read_text() == 'mcp-permission':
            permission_id = 'permission-' + str(rid)
            permission_prompts[permission_id] = (sid, rid)
            request = json.loads((root / 'permission-request.json').read_text())
            for pre in request.pop('preUpdates', []):
                emit({'jsonrpc':'2.0','method':'session/update','params':{'sessionId':sid,'update':pre}})
            emit({'jsonrpc':'2.0','id':permission_id,'method':'session/request_permission',
                  'params':{'sessionId':sid, **request}})
            continue
        if (root / 'mode').read_text() == 'session-titles' and (root / 'title-updates.json').exists():
            for notification in json.loads((root / 'title-updates.json').read_text()):
                title_update(notification.get('sessionId', sid), notification['fields'])
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
    elif method == 'session/list' and (root / 'mode').read_text() == 'session-titles':
        result={'sessions':json.loads((root / 'listed.json').read_text())}
    elif method == 'authenticate':
        assert msg['params']['methodId'] == 'login'
        (root / 'mode').write_text('replay')
        result={}
    elif method == 'session/close':
        if (root / 'mode').read_text() == 'session-titles' and msg['params']['sessionId'] not in probe_sessions:
            title_update(msg['params']['sessionId'], {'title':'Late title after close'})
        result={}
    else:
        emit({'jsonrpc':'2.0','id':rid,'error':{'code':-32601,'message':'method not found'}})
        continue
    emit({'jsonrpc':'2.0','id':rid,'result':result})
