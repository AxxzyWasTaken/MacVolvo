"""Check the production running-session branch without activating real apps."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RunningActions(unittest.TestCase):
    def test_open_steam_targets_client_and_play_keeps_game(self):
        source = (ROOT / 'scripts/portable_setup.m').read_text()
        start = source.index('    if(running) {', source.index('static void launchClient('))
        opening = source.index('{', start)
        end, depth = opening + 1, 1
        while depth:
            depth += (source[end] == '{') - (source[end] == '}')
            end += 1
        branch = source[start:end]
        harness = '''#import <Foundation/Foundation.h>
static NSArray *focused;
static BOOL focusSession(NSArray *rows) { focused=rows; return rows.count>0; }
static void run(NSArray *existing, BOOL game) {
    BOOL running=YES;
''' + branch + '''
}
int main(void) { @autoreleasepool {
    NSArray *rows=@[@{@"kind":@"game",@"pid":@11},@{@"kind":@"client",@"pid":@12}];
    run(rows,NO);
    if(focused.count!=1 || ![focused[0][@"pid"] isEqual:@12]) return 1;
    run(rows,YES);
    if(![focused isEqual:rows]) return 2;
    run(@[rows[0]],NO);
    if(focused.count) return 3;
    return 0;
}}
'''
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'actions.m'; path.write_text(harness)
            binary=Path(tmp)/'actions'
            result=subprocess.run(['clang','-fobjc-arc','-framework','Foundation',str(path),'-o',str(binary)],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            subprocess.run([str(binary)],check=True,timeout=5)


if __name__ == '__main__': unittest.main()
