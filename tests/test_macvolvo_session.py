"""Compile production session discovery against both Wine process-name formats."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]

class SessionMembership(unittest.TestCase):
    def test_windows_and_unix_names_require_owned_engine_and_prefix(self):
        steam=(ROOT/'scripts/portable_steam.h').read_text()
        games=steam[steam.index('typedef struct'):steam.index('static NSString *steamFolder')]
        names=steam[steam.index('static NSString *mvProcessName'):steam.index('/* Every game,')]
        session=(ROOT/'scripts/portable_session.h').read_text()
        session=session[session.index('static NSMutableDictionary *membershipCache'):session.index('static BOOL focusSession')]
        harness=r'''#import <Foundation/Foundation.h>
#include <signal.h>
#include <unistd.h>
static NSString *root;
static NSFileManager *fm;
static NSDictionary *fixture;
static NSString *runtime(void) {return [root stringByAppendingPathComponent:@"engine"];}
static NSString *join(NSString *a,NSString *b) {return [a stringByAppendingPathComponent:b];}
static void fail(NSString *reason) {@throw [NSException exceptionWithName:reason reason:reason userInfo:nil];}
static NSString *capture(NSString *exe,NSArray *args) {
    if([exe isEqual:@"/bin/ps"])return fixture[@"ps"];
    return fixture[@"maps"][args[2]];
}
'''+games+names+session+r'''
int main(int argc,const char **argv) {@autoreleasepool {
    fixture=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[1])] options:0 error:nil];
    root=fixture[@"root"];fm=NSFileManager.defaultManager;
    NSData *out=[NSJSONSerialization dataWithJSONObject:sessionProcesses() options:0 error:nil];
    puts([[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding].UTF8String);
}}
'''
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);source=folder/'session.m';source.write_text(harness)
            binary=folder/'session'
            subprocess.run(['clang','-fobjc-arc','-framework','Foundation',str(source),'-o',str(binary)],check=True,capture_output=True)
            names=[r'C:\Steam\steam.exe',str(folder/'environment/drive_c/Steam/steam.exe'),
                   r'C:\Games\CS2.EXE',str(folder/'environment/drive_c/Deadlock/deadlock.exe'),
                   str(folder/'environment/drive_c/Steam/steam.exe'),r'C:\Other\cs2.exe',
                   r'C:\Games\notcs2.exe',r'C:\Steam\steam.exe\helper.exe']
            mappings={str(101+i):f'n{folder}/engine/lib/wine/winemac.so\nn{folder}/environment/game.dll\n' for i in range(len(names))}
            mappings['105']=f'n{folder}/foreign-engine/winemac.so\nn{folder}/environment/game.dll\n'
            mappings['106']=f'n{folder}/engine/winemac.so\nn{folder}/foreign-prefix/game.dll\n'
            data={'root':str(folder),'ps':'\n'.join(f'{101+i} Tue Oct 13 13:07:18 2026 {name}' for i,name in enumerate(names)),'maps':mappings}
            fixture=folder/'fixture.json';fixture.write_text(json.dumps(data))
            result=json.loads(subprocess.check_output([str(binary),str(fixture)]))
            self.assertEqual([(p['pid'],p['kind']) for p in result],[(101,'client'),(102,'client'),(103,'game'),(104,'game')])

if __name__=='__main__':unittest.main()
