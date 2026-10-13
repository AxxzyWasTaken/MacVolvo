/* MacVolvo: Steam and Valve's Source 2 games in place of Battle.net and Overwatch.
 *
 * Games. Each is started through Steam (steam.exe -applaunch <id>) with its own options
 * (space-separated): fullscreen or windowed at the chosen size, no joystick polling (-nojoy).
 *
 * Steam's window. On Wine 11 (the engine is CrossOver 26.3) Steam's browser draws black
 * whenever it runs with its GPU off (https://github.com/gauthierpiarrette/highball/issues/282).
 * With the GPU on, Chrome's separate GPU process cannot present into the browser's window
 * (every Wine process has its own Cocoa windows), and this engine's DXMT cannot find a Mac view
 * for Chrome's child window. So GPU web views are turned on (GPUAccelWebViewsV3) and a
 * stand-in steamwebhelper.exe (scripts/webhelper_wrapper.c, shipped as a resource) runs the
 * real one with --in-process-gpu plus WEBHELPER_EXTRA_ARGS (--use-angle=vulkan: ANGLE draws
 * through MoltenVK in the process that owns the window). Steam's startup check would put
 * the original helper back, so Steam starts with -noverifyfiles once the stand-in is in place.
 *
 * Game Mode. The engine's Wine restarts a program listed in WINE_GAME_MODE from
 * lib/wine/game-mode/<name>.app, a bundle that declares itself a game. The engine ships
 * Overwatch.app; one per game is made from it, renamed and signed ad hoc with the same
 * entitlements. verifyRuntime leaves those generated bundles out of the manifest check. */

typedef struct { NSString *key, *name, *exe, *appID, *folder, *options; } MVGame;
static const MVGame mvGames[]={
    {@"cs2",@"Counter-Strike 2",@"cs2.exe",@"730",@"Counter-Strike Global Offensive/game/bin/win64",@""},
    // -dx11: DXMT translates Direct3D 11 only, and Deadlock may otherwise pick Vulkan.
    // -novid: skips Deadlock's intro video (CS2 has none).
    {@"deadlock",@"Deadlock",@"deadlock.exe",@"1422450",@"Deadlock/game/bin/win64",@"-dx11 -novid"},
};
static const NSUInteger mvGameCount=sizeof(mvGames)/sizeof(mvGames[0]);
static const MVGame *mvGame(NSString *key) {
    for(NSUInteger i=0;i<mvGameCount;i++)if([mvGames[i].key isEqual:key])return &mvGames[i];
    return NULL;
}
static NSString *steamFolder(void) {return join(root,@"environment/drive_c/Program Files (x86)/Steam");}
static NSString *gamePath(const MVGame *game) {
    return join(join(join(steamFolder(),@"steamapps/common"),game->folder),game->exe);
}
static NSArray *installedGames(void) {
    NSMutableArray *found=[NSMutableArray array];
    for(NSUInteger i=0;i<mvGameCount;i++)if([fm fileExistsAtPath:gamePath(&mvGames[i])])[found addObject:mvGames[i].key];
    return found;
}
static BOOL isGameProcess(NSString *name) {
    for(NSUInteger i=0;i<mvGameCount;i++)if([name hasSuffix:[@"\\" stringByAppendingString:mvGames[i].exe]])return YES;
    return NO;
}
/* Every game, for WINEMAC_MOUSELOOK (';') and WINE_GAME_MODE (','). */
static NSString *gameList(NSString *separator) {
    NSMutableArray *names=[NSMutableArray array];
    for(NSUInteger i=0;i<mvGameCount;i++)[names addObject:mvGames[i].exe];
    return [names componentsJoinedByString:separator];
}

static BOOL registryValue(NSString *engine, NSString *key, NSString *name, NSString *type, NSString *data, NSString *log) {
    return !waitTask(task(join(engine,@"bin/wine"),@[@"reg.exe",@"add",key,@"/v",name,@"/t",type,@"/d",data,@"/f"],wineEnv(engine),log),60);
}

/* Whether a file is the stand-in: it names the real helper (UTF-16), which Steam's own
 * helper never does. A hash would not do: any earlier build of the stand-in would read as
 * Steam's helper, be moved into the real one's place and start itself without end. */
static BOOL isStandIn(NSString *path) {
    NSData *data=[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    NSData *mark=[@"steamwebhelper_real.exe" dataUsingEncoding:NSUTF16LittleEndianStringEncoding];
    return data && [data rangeOfData:mark options:0 range:NSMakeRange(0,data.length)].location!=NSNotFound;
}
/* Puts the stand-in helper in place (again after a Steam update replaced it) and turns GPU
 * web views on. NO when Steam's own helper isn't there to run: before Steam's first update,
 * or when it went missing, in which case the stand-ins are removed and Steam's startup check
 * (without -noverifyfiles) puts its helper back; the next start applies the fix. */
static BOOL steamWindowFix(NSString *engine) {
    NSString *cef=join(steamFolder(),@"bin/cef/cef.win64"),*helper=join(cef,@"steamwebhelper.exe"),*real=join(cef,@"steamwebhelper_real.exe");
    // The app ships it as a resource (Contents/Resources, beside Contents/Helpers).
    NSString *standIn=[helperPath(@"../Resources/steamwebhelper.exe") stringByStandardizingPath];
    if(![fm fileExistsAtPath:helper] || !isStandIn(standIn))return NO;
    if(!isStandIn(helper)) {
        // Steam's own helper, first run or after an update: it becomes the real one.
        [fm removeItemAtPath:real error:nil];
        if(![fm moveItemAtPath:helper toPath:real error:nil])fail(@"steam_helper_install_failed");
    } else if(![fm fileExistsAtPath:real] || isStandIn(real)) {
        [fm removeItemAtPath:helper error:nil];[fm removeItemAtPath:real error:nil];
        event(@"steam_helper_restoring",nil);
        return NO;
    } else if([hashFile(helper) isEqual:hashFile(standIn)]) helper=nil;
    if(helper) {
        [fm removeItemAtPath:helper error:nil];
        if(![fm copyItemAtPath:standIn toPath:helper error:nil])fail(@"steam_helper_install_failed");
    }
    if(!registryValue(engine,@"HKCU\\Software\\Valve\\Steam",@"GPUAccelWebViewsV3",@"REG_DWORD",@"1",@"steam-gpu-web-views.log"))fail(@"steam_helper_install_failed");
    return YES;
}

/* Steam lays itself out at Windows' 96 DPI, which Retina mode shows at half size. Twice
 * that (192) keeps its window Mac-sized with sharp text; the games handle it (DPI aware). */
static void configureScaling(NSString *engine) {
    registryValue(engine,@"HKCU\\Control Panel\\Desktop",@"LogPixels",@"REG_DWORD",@"192",@"scaling.log");
}

static void makeGameApps(NSString *engine) {
    NSString *dir=join(engine,@"lib/wine/game-mode"),*source=join(dir,@"Overwatch.app");
    if(![fm fileExistsAtPath:join(source,@"Contents/MacOS/wine")])return;
    NSString *entitlements=join(join(root,@"tmp"),@"game-mode.entitlements");
    for(NSUInteger i=0;i<mvGameCount;i++) {
        NSString *app=join(dir,[mvGames[i].key stringByAppendingString:@".app"]);
        if([fm isExecutableFileAtPath:join(app,@"Contents/MacOS/wine")])continue;
        [fm removeItemAtPath:app error:nil];
        if(![fm copyItemAtPath:source toPath:app error:nil])continue;
        NSString *plist=join(app,@"Contents/Info.plist");
        NSMutableDictionary *info=[[NSDictionary dictionaryWithContentsOfFile:plist] mutableCopy];
        if(!info) {[fm removeItemAtPath:app error:nil];continue;}
        info[@"CFBundleName"]=mvGames[i].name;
        info[@"CFBundleIdentifier"]=[@"app.macvolvo.game." stringByAppendingString:mvGames[i].key];
        info[@"NSMicrophoneUsageDescription"]=[mvGames[i].name stringByAppendingString:@" uses the microphone for voice chat."];
        [info removeObjectForKey:@"NSLocalNetworkUsageDescription"];
        [info writeToFile:plist atomically:YES];
        if(![fm fileExistsAtPath:entitlements])
            waitTask(task(@"/bin/sh",@[@"-c",@"/usr/bin/codesign -d --entitlements :- \"$1\" > \"$2\"",@"sh",source,entitlements],nil,@"game-mode-sign.log"),30);
        if(waitTask(task(@"/usr/bin/codesign",@[@"--force",@"--sign",@"-",@"--options",@"runtime",@"--entitlements",entitlements,app],nil,@"game-mode-sign.log"),60))
            [fm removeItemAtPath:app error:nil];
    }
}
static BOOL generatedGameApp(NSString *name) {
    for(NSUInteger i=0;i<mvGameCount;i++)
        if([name hasPrefix:[NSString stringWithFormat:@"lib/wine/game-mode/%@.app",mvGames[i].key]])return YES;
    return NO;
}

/* The engine's renderer profile names Overwatch.exe; every game gets the same section. */
static NSString *gamesProfile(NSString *profile) {
    NSRange start=[profile rangeOfString:@"[Overwatch.exe]"];
    if(start.location==NSNotFound)return profile;
    NSString *body=[profile substringFromIndex:NSMaxRange(start)];
    NSRange next=[body rangeOfString:@"\n["];
    if(next.location!=NSNotFound)body=[body substringToIndex:next.location+1];
    NSMutableString *out=[[profile substringToIndex:start.location] mutableCopy];
    for(NSUInteger i=0;i<mvGameCount;i++)[out appendFormat:@"[%@]%@\n",mvGames[i].exe,body];
    return out;
}
