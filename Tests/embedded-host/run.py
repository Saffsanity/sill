import os, pathlib, selectors, subprocess, time
root=pathlib.Path(__file__).resolve().parents[2]
executable=root/'.build/release/SillMenuBar'
for mode in ['early-eof','eof','quit','invalid']:
    p=subprocess.Popen([str(executable),'--embedded','--synthetic','-SillLogFile','/dev/null'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)
    selector=selectors.DefaultSelector();selector.register(p.stdout,selectors.EVENT_READ)
    ready=False;pending=b'';end=time.monotonic()+20
    try:
        if mode=='early-eof':
            p.stdin.close()
            assert p.wait(timeout=8)==0
            print('embedded synthetic host: early EOF orderly shutdown passed')
            continue
        while time.monotonic()<end and p.poll() is None:
            if not selector.select(.2):continue
            chunk=os.read(p.stdout.fileno(),4096)
            if not chunk:break
            pending+=chunk
            lines=pending.split(b'\n');pending=lines.pop()
            if b'SILL_EMBEDDED_READY' in lines:
                ready=True;break
        assert ready, 'embedded host did not become ready'
        if mode in ['invalid','quit']:
            p.stdin.write(b'not-a-command\n' if mode=='invalid' else b'quit\n');p.stdin.flush()
        else:p.stdin.close()
        code=p.wait(timeout=8)
        assert code==0,(mode,code)
        print(f'embedded synthetic host: {mode} orderly shutdown passed')
    finally:
        selector.close()
        if p.poll() is None:p.terminate();p.wait(timeout=8)
