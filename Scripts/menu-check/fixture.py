"""usage: fixture.py FIXTURE_BIN LOG_PREFIX HARNESS [ARG...]
Starts the fixture (`FIXTURE_BIN serve LOG_PREFIX.log 120`), runs `HARNESS PID LOG_PREFIX.log
FIXTURE_BIN [ARG...]` against it, and stops the fixture. A harness that wants the fixture gone
creates LOG_PREFIX.log.kill: this process, its parent, kills and reaps it, then removes the file (a
zombie still answers kill(pid, 0), which is how the host tells an app gone). `lsappinfo front` is
sampled every 0.1 s from before the fixture starts to after it stops; a change fails the run, as
does a fixture or harness left running. Exits with the harness's status otherwise."""
import os, signal, subprocess, sys, threading, time
fixture_bin, prefix, harness, extra = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
log = prefix + ".log"
def front(): return subprocess.run(["lsappinfo", "front"], capture_output=True, text=True).stdout.strip()
seen = []; stop = False
def sample():
    while not stop: seen.append(front()); time.sleep(0.1)
sampler = threading.Thread(target=sample); sampler.start(); time.sleep(0.3)
p = subprocess.Popen([fixture_bin, "serve", log, "120"], stdout=subprocess.PIPE, text=True, start_new_session=True)
print(p.stdout.readline().strip()); time.sleep(0.5)
def reaper():
    while not stop:
        if os.path.exists(log + ".kill"):
            os.kill(p.pid, signal.SIGKILL); p.wait(); os.remove(log + ".kill"); return
        time.sleep(0.05)
threading.Thread(target=reaper, daemon=True).start()
status = 1
try:
    r = subprocess.run([harness, str(p.pid), log, fixture_bin, *extra], capture_output=True, text=True, timeout=300)
    sys.stdout.write(r.stdout + r.stderr); status = r.returncode
finally:
    if p.poll() is None: os.kill(p.pid, signal.SIGTERM); p.wait(5)
    time.sleep(0.3); stop = True; sampler.join()
fronts = sorted(set(seen))
print(f"front: {len(seen)} samples, {'unchanged' if len(fronts) == 1 else 'CHANGED: ' + str(fronts)}")
left = [l for l in subprocess.run(["pgrep", "-lf", f"{fixture_bin} serve|{harness}"], capture_output=True, text=True).stdout.splitlines() if "pgrep" not in l]
if left: print("LEFT RUNNING:", left)
sys.exit(status if len(fronts) == 1 and not left else 1)
