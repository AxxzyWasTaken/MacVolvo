"""Steam Properties edits against synthetic data only; never opens Wine or Steam."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SteamLaunchOptions(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build_dir = tempfile.TemporaryDirectory(prefix="macvolvo-steam-options-tests-")
        cls.addClassCleanup(cls.build_dir.cleanup)
        folder = Path(cls.build_dir.name)
        header = (ROOT / "scripts/portable_steam.h").read_text()
        # Compile the actual persistence/parser and profile functions in isolation.
        source = header.split("/* A renderer selected in Deadlock's Video settings")[0]
        profile = header[header.index("static NSString *gamesProfile("):]
        harness = r'''
#import <Foundation/Foundation.h>
#include <sys/stat.h>
#include <errno.h>
static NSString *root;
static NSFileManager *fm;
static BOOL activeSession;
static NSString *join(NSString *a, NSString *b) {return [a stringByAppendingPathComponent:b];}
static BOOL matches(NSString *text, NSString *pattern) {
    return [text rangeOfString:pattern options:NSRegularExpressionSearch].location!=NSNotFound;
}
static NSArray *sessionProcesses(void) {return activeSession?@[@"synthetic-session"]:@[];}
static void event(NSString *name, NSDictionary *details) {(void)name;(void)details;}
'''+source+profile+r'''
int main(int argc, const char *argv[]) { @autoreleasepool {
    if(argc!=2)return 3;
    NSDictionary *input=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[1])] options:0 error:nil];
    fm=NSFileManager.defaultManager;root=input[@"root"];activeSession=[input[@"active"] boolValue];
    NSDictionary *defaults=steamLaunchDefaults(input[@"options"]);
    NSDictionary *result;
    @try {
        if([input[@"op"] isEqual:@"configure"]) {
            BOOL needs=NO,valid=steamLaunchOptionsNeedUpdate(defaults,&needs);
            result=@{@"valid":@(valid),@"needs":@(needs),@"configured":@(configureSteamLaunchOptions(defaults))};
        } else if([input[@"op"] isEqual:@"profile"]) {
            result=@{@"text":gamesProfile(input[@"text"],input[@"options"])};
        } else result=@{@"text":mvUpdatedSteamVDF(input[@"text"],defaults)};
    } @catch(NSException *error) {(void)error;result=@{@"error":@"invalid"};}
    NSData *data=[NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
    fwrite(data.bytes,1,data.length,stdout);return 0;
} }
'''
        path = folder / "steam-options.m"
        path.write_text(harness)
        cls.binary = folder / "steam-options-tests"
        subprocess.run(["/usr/bin/clang", "-fobjc-arc", "-Wall", "-Wextra", "-Werror",
                        "-Wno-unused-function", str(path), "-framework", "Foundation", "-o", str(cls.binary)], check=True)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="macvolvo-steam-options-fixture-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.options = {"cs2": {"width": 1920, "height": 1080, "fullscreen": True},
                        "deadlock": {"width": 2560, "height": 1600, "fullscreen": False}}

    def call(self, **values):
        fixture = self.base / "input.json"
        fixture.write_text(json.dumps({"options": self.options, **values}))
        result = subprocess.run([str(self.binary), str(fixture)], capture_output=True, text=True, check=True)
        return json.loads(result.stdout)

    def vdf(self, apps):
        return ('"UserLocalConfigStore"\n{\n\t"PrivateFixture" "keep untouched"\n'
                '\t"Software"\n\t{\n\t\t"Valve"\n\t\t{\n\t\t\t"Steam"\n\t\t\t{\n'
                '\t\t\t\t"apps"\n\t\t\t\t{\n'+apps+'\n\t\t\t\t}\n\t\t\t}\n\t\t}\n\t}\n}\n')

    def test_preserves_unrelated_config_and_quoted_arguments_and_custom_fps(self):
        text = self.vdf('"730" {"LaunchOptions" "-console +exec \\\"my autoexec.cfg\\\" +fps_max 75 -vulkan -w 999 -h 777 -windowed"}\n'
                        '"42" {"LaunchOptions" "-special untouched"}\n'
                        '"1422450" {"LaunchOptions" "-novid -dx12 -nojoy -fullscreen -width 640 -height 480 +exec custom.cfg"}')
        out = self.call(text=text)["text"]
        self.assertIn('"PrivateFixture" "keep untouched"', out)
        self.assertIn('"42" {"LaunchOptions" "-special untouched"}', out)
        self.assertIn('-nojoy -fullscreen -w 1920 -h 1080 -dx11 -console +exec \\\"my autoexec.cfg\\\" +fps_max 75', out)
        self.assertIn('-nojoy -windowed -w 2560 -h 1600 -dx11 -novid +exec custom.cfg', out)
        for conflicting in ["-vulkan", "-dx12", "999", "777", "-width", "-height"]:
            self.assertNotIn(conflicting, out)
        self.assertNotIn("+fps_max 120", out)
        self.assertEqual(self.call(text=out)["text"], out)

    def test_creates_only_missing_keys_and_adds_initial_cs2_fps_once(self):
        out = self.call(text=self.vdf('"730" {"Other" "keep"}'))["text"]
        self.assertIn('"Other" "keep"', out)
        self.assertEqual(out.count("+fps_max 120"), 1)
        self.assertIn('"1422450"', out)
        self.assertEqual(self.call(text=out)["text"], out)

    def test_preserves_crlf_comments_case_and_trailing_space_option(self):
        text = self.vdf('// untouched comment\n"730" {"launchoptions" "-nojoy "}').replace("\n", "\r\n")
        out = self.call(text=text)["text"]
        self.assertIn('// untouched comment\r\n', out)
        self.assertIn('"launchoptions"', out)
        self.assertNotIn("\n", out.replace("\r\n", ""))
        self.assertEqual(self.call(text=out)["text"], out)

    def test_rejects_ambiguous_or_malformed_config_without_guessing(self):
        for text in [self.vdf('"730" {"LaunchOptions" "-console" "LaunchOptions" "-novid"}'),
                     self.vdf('"730" {"LaunchOptions" "-console \\\"unfinished"}'),
                     '"UserLocalConfigStore" { "Software" "scalar not object" }',
                     self.vdf('"730" {} "730" {}'), '"unterminated']:
            with self.subTest(text=text):
                self.assertEqual(self.call(text=text), {"error": "invalid"})

    def config_path(self):
        path = self.base / "environment/drive_c/Program Files (x86)/Steam/userdata/123/config/localconfig.vdf"
        path.parent.mkdir(parents=True)
        return path

    def test_refuses_live_session_then_backs_up_and_updates_closed_config(self):
        path = self.config_path()
        before = self.vdf('"730" {"LaunchOptions" "-console"}')
        path.write_text(before)
        self.assertEqual(self.call(op="configure", root=str(self.base), active=True),
                         {"valid": True, "needs": True, "configured": False})
        self.assertEqual(path.read_text(), before)
        self.assertFalse(Path(str(path)+".macvolvo-backup").exists())
        self.assertTrue(self.call(op="configure", root=str(self.base))["configured"])
        backup = Path(str(path)+".macvolvo-backup")
        self.assertEqual(backup.read_text(), before)
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(backup.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.call(op="configure", root=str(self.base)),
                         {"valid": True, "needs": False, "configured": True})

    def test_refuses_symlink_config_and_backup(self):
        path = self.config_path()
        outside = self.base / "outside.txt"
        before = self.vdf('"730" {}')
        outside.write_text(before)
        path.symlink_to(outside)
        result = self.call(op="configure", root=str(self.base))
        self.assertFalse(result["valid"])
        self.assertFalse(result["configured"])
        self.assertEqual(outside.read_text(), before)
        path.unlink();path.write_text(before)
        Path(str(path)+".macvolvo-backup").symlink_to(outside)
        self.assertFalse(self.call(op="configure", root=str(self.base))["configured"])
        self.assertEqual(path.read_text(), before)
        self.assertEqual(outside.read_text(), before)

    def test_per_game_canvas_and_cs2_worker_count_leave_deadlock_profile_unchanged(self):
        text = (ROOT / "config/dxmt-source60-1200.conf").read_text()
        out = self.call(op="profile", text=text)["text"]
        cs2, deadlock = out.split("[deadlock.exe]")
        self.assertIn("d3d11.shaderCompilerThreads = 4", cs2)
        self.assertIn("dxgi.fullscreenCanvasWidth = 1920", cs2)
        self.assertIn("dxgi.fullscreenCanvasHeight = 1080", cs2)
        self.assertIn("d3d11.shaderCompilerThreads = 8", deadlock)
        self.assertIn("dxgi.fullscreenCanvasWidth = 2560", deadlock)
        self.assertIn("dxgi.fullscreenCanvasHeight = 1600", deadlock)
        self.assertEqual(out.count("d3d11.preferredMaxFrameRate = 0"), 2)


if __name__ == "__main__":
    unittest.main()
