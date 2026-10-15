#!/usr/bin/env python3
"""Opt-in bounded CS2/Deadlock counters, attributed by the installed session worker.

Build the native reader first: python3 scripts/process_probe.py --build
Run this collector with arch -arm64 /usr/bin/python3 on Apple Silicon.
Run alongside diagnostic-launch; this command does not launch or stop games.
No process arguments, account files, screenshots or target memory are recorded.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time

from measure_resources import RotatingJSONL, command, gpu_statistics, thermal_state, timestamp
from process_probe import NativeProbe, ProcessRecorder

ROOT=Path(__file__).resolve().parents[1]
NAMES={'cs2.exe','deadlock.exe','steam.exe'}

def admitted_processes(worker, root, probe):
    # Bracket the worker's engine/prefix admission with kernel start identities.
    candidates={}
    for line in command('ps','-axo','pid=,comm=').splitlines():
        parts=line.strip().split(None,1)
        if len(parts)!=2:continue
        name=parts[1].replace('\\','/').rsplit('/',1)[-1].lower()
        if name not in NAMES or len(candidates)>=32:continue
        pid=int(parts[0])
        try:candidates[pid]=(name,probe.sample(pid)['start_abstime'])
        except OSError:pass
    result=subprocess.run([str(worker),'session','--root',str(root)],capture_output=True,text=True,timeout=15)
    if result.returncode:raise RuntimeError('session_query_failed')
    events=[json.loads(line) for line in result.stdout.splitlines() if line.startswith('{')]
    rows=next((event['processes'] for event in events if event.get('stage')=='session'),None)
    if rows is None:raise RuntimeError('session_query_missing')
    admitted=[]
    for row in rows:
        if row['pid'] not in candidates:continue
        name,start=candidates[row['pid']]
        try:values=probe.sample(row['pid'],start)
        except OSError:continue
        admitted.append(dict(pid=row['pid'],name=name,kind=row['kind'],native_start_abstime=start,
                             physical_footprint_bytes=values['footprint_bytes']))
    return admitted

def system_sample():
    vm=command('vm_stat')
    values={name:int(value) for name,value in re.findall(r'^([^:\n]+):\s+(\d+)\.',vm,re.M)}
    swap=re.search(r'used = ([\d.]+)M',command('sysctl','-n','vm.swapusage'))
    return dict(vm_page_size=int(re.search(r'page size of (\d+) bytes',vm)[1]),
                vm_counters={key:values.get(key) for key in ('Swapins','Swapouts','Pageouts','Compressions','Decompressions')},
                swap_used_mib=float(swap[1]) if swap else None,
                gpu_system_wide=gpu_statistics(),thermal=thermal_state())

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--worker',type=Path,required=True)
    parser.add_argument('--root',type=Path,default=Path.home()/'Library/Application Support/MacVolvo')
    parser.add_argument('--output',type=Path,required=True,help='New private output directory')
    parser.add_argument('--seconds',type=int,default=600)
    args=parser.parse_args()
    if not 1<=args.seconds<=3600:parser.error('--seconds must be 1..3600')
    probe=NativeProbe()  # Refuses a missing/stale build instead of compiling during play.
    os.umask(0o077);os.nice(10)
    args.output.mkdir(parents=True,exist_ok=False)
    stream=RotatingJSONL(args.output/'resources.jsonl')
    recorder=ProcessRecorder(args.output/'process.csv',probe)
    recorder.start();deadline=time.monotonic()+args.seconds
    rows=[]
    try:
        while time.monotonic()<deadline:
            started=time.monotonic();record=dict(schema_version=1,**timestamp())
            record['monotonic_ns']=time.clock_gettime_ns(time.CLOCK_UPTIME_RAW)
            try:
                alive=[]
                for row in rows:
                    try:
                        values=probe.sample(row['pid'],row['native_start_abstime'])
                        alive.append(dict(row,physical_footprint_bytes=values['footprint_bytes']))
                    except OSError:pass
                # Once admitted, kernel start identities keep a running game
                # scoped without competing for the launcher's lock every tick.
                rows=alive if any(row['kind']=='game' for row in alive) else admitted_processes(args.worker,args.root,probe)
                recorder.set_targets([row for row in rows if row['kind']=='game'])
                record.update(processes=rows,**system_sample())
            except (OSError,RuntimeError,subprocess.SubprocessError,ValueError,KeyError) as exc:
                recorder.set_targets([]);record['sample_error']=type(exc).__name__
            record['sample_duration_ms']=round((time.monotonic()-started)*1000,2)
            stream.write(record)
            time.sleep(max(0,min(2-(time.monotonic()-started),deadline-time.monotonic())))
    except KeyboardInterrupt:pass
    finally:
        recorder.close();stream.close()
        (args.output/'capture.json').write_text(json.dumps(recorder.status(),indent=2)+'\n')
    print('Capture saved:',args.output)

if __name__=='__main__':main()
