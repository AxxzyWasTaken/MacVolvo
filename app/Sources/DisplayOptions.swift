import AppKit

/// A game launch size. The canvas supports any dimensions from 640 × 480 to
/// 16384 × 16384; a size larger than Wine's main display is fitted at launch.
struct DisplayResolution:Hashable {
    enum Shape:CaseIterable { case macBook, monitor }
    enum Size:CaseIterable { case standard, high, ultra }
    let width:Int
    let height:Int
    static let standard=DisplayResolution(width:1920,height:1200)
    /// Keep the original defaults when upgrading an existing installation.
    static let legacy=Shape.allCases.flatMap { shape in Size.allCases.map { DisplayResolution(shape:shape,size:$0) } }
    /// Common game sizes, including CS2's competitive 4:3 choices. The menu also
    /// includes this display's modes and any valid size the player saved.
    static let all:[DisplayResolution]=[
        [640,480],[800,600],[1024,768],[1152,864],[1280,960],[1440,1080],[1600,1200],[1920,1440],
        [1280,1024],
        [960,600],[1280,800],[1440,900],[1680,1050],[1920,1200],[2304,1440],[2560,1600],[3840,2400],
        [960,540],[1024,576],[1280,720],[1366,768],[1600,900],[1920,1080],[2048,1152],[2560,1440],
        [3840,2160],[5120,2880],[7680,4320],
        [1440,960],[2160,1440],[2880,1920],[3000,2000],
        [2560,1080],[3440,1440],[3840,1600],[5120,2160],
        [3840,1080],[5120,1440],[7680,2160]
    ].map { DisplayResolution(width:$0[0],height:$0[1]) }
    init(width:Int, height:Int) { self.width=width;self.height=height }
    init(shape:Shape, size:Size) {
        let width=[Size.standard:1920,.high:2560,.ultra:3840][size]!
        self.init(width:width,height:shape == .macBook ? width*10/16 : width*9/16)
    }
    var shape:Shape { width*10 == height*16 ? .macBook : .monitor }
    var size:Size { width >= 3840 ? .ultra : width >= 2560 ? .high : .standard }
    var label:String { "\(width) × \(height)" }
    var isSupported:Bool { (640...16384).contains(width) && (480...16384).contains(height) }
    var isPreset:Bool { DisplayResolution.all.contains(self) }
    var ratio:CGFloat { CGFloat(width)/CGFloat(max(height,1)) }
    var aspect:String {
        let named=DisplayResolution.aspectName(ratio)
        guard named.hasSuffix(":1") else { return named }
        func gcd(_ a:Int,_ b:Int) -> Int { b == 0 ? a : gcd(b,a%b) }
        let divisor=gcd(max(width,1),max(height,1))
        return "\(width/divisor):\(height/divisor)"
    }
    /// The nearest common name for a width-to-height ratio.
    static func aspectName(_ ratio:CGFloat) -> String {
        let known:[(String,CGFloat)]=[("16:10",1.6),("16:9",16.0/9),("21:9",2.37),("32:9",32.0/9),("3:2",1.5),("4:3",4.0/3),("5:4",1.25)]
        let nearest=known.min { abs($0.1-ratio) < abs($1.1-ratio) }!
        return abs(nearest.1-ratio)/nearest.1 < 0.02 ? nearest.0 : String(format:"%.2f:1",Double(ratio))
    }
    static func parsed(width:String,height:String) -> DisplayResolution? {
        guard let w=Int(width.trimmingCharacters(in:.whitespacesAndNewlines)),
              let h=Int(height.trimmingCharacters(in:.whitespacesAndNewlines)) else { return nil }
        let choice=DisplayResolution(width:w,height:h)
        return choice.isSupported ? choice : nil
    }
    static func choices(on display:MainDisplay?,keeping saved:DisplayResolution) -> [DisplayResolution] {
        let choices=all+(display?.resolutions ?? [])+[saved]
        return Set(choices.filter(\.isSupported)).sorted {
            $0.width == $1.width ? $0.height < $1.height : $0.width < $1.width
        }
    }
    struct Group:Identifiable {
        let aspect:String
        let resolutions:[DisplayResolution]
        var id:String { aspect }
    }
    static func grouped(_ choices:[DisplayResolution]) -> [Group] {
        let grouped=Dictionary(grouping:choices,by:\.aspect)
        let order=["4:3","5:4","16:10","16:9","3:2","21:9","32:9"]
        let aspects=order.filter { grouped[$0] != nil }+grouped.keys.filter { !order.contains($0) }.sorted()
        return aspects.map { Group(aspect:$0,resolutions:grouped[$0]!) }
    }
    /// Where a new installation starts, and where Troubleshooting's reset returns:
    /// 1080p in the main display's shape.
    static func initial(for main:MainDisplay?) -> DisplayResolution {
        main?.shape == .monitor ? DisplayResolution(shape:.monitor,size:.standard) : .standard
    }
}

/// One of a display's modes, as System Settings › Displays offers it.
struct DisplayMode:Equatable {
    /// The size players pick in Displays.
    let points:CGSize
    /// What macOS draws at that size: twice the points in a sharp (HiDPI) mode.
    let pixels:CGSize
    let refresh:Double
    /// macOS marks the modes drawn at the screen's own pixels native.
    let native:Bool
    var label:String { "\(Int(points.width)) × \(Int(points.height))" }
    /// A display's desktop modes, including the low-resolution twins Displays lists
    /// under Show all resolutions.
    static func all(_ id:CGDirectDisplayID) -> [DisplayMode] {
        let options=[kCGDisplayShowDuplicateLowResolutionModes:kCFBooleanTrue] as CFDictionary
        let modes=CGDisplayCopyAllDisplayModes(id,options) as? [CGDisplayMode] ?? []
        return modes.filter { $0.isUsableForDesktopGUI() }.map {
            DisplayMode(points:CGSize(width:$0.width,height:$0.height),pixels:CGSize(width:$0.pixelWidth,height:$0.pixelHeight),
                        refresh:$0.refreshRate,native:$0.ioFlags & 0x0200_0000 != 0) // kDisplayModeNativeFlag
        }
    }
}

/// The main display (the one with the menu bar), where the game opens.
struct MainDisplay:Equatable {
    let name:String
    let builtIn:Bool
    /// The whole screen in points, as Wine sees it at twice the size (Retina mode).
    let points:CGSize
    /// What macOS draws the whole screen at: the points times the backing scale. In a
    /// scaled mode it differs from the screen's own pixels and is resized to fit them.
    let drawn:CGSize
    /// The screen's own pixels, when macOS marks a native mode.
    let native:CGSize?
    /// The pixels fullscreen apps fill on the screen (those drawn when its own are
    /// unknown): below the camera housing on MacBooks with one.
    let pixels:CGSize
    /// The current refresh rate, 0 when unknown.
    let refresh:Double
    /// Game-sized dimensions from macOS's modes, plus the visible fullscreen area.
    let resolutions:[DisplayResolution]
    /// The Displays setting drawn at the screen's own pixels nearest the current desktop
    /// size, with the fastest refresh rate it offers.
    let sharpest:DisplayMode?
    static var current:MainDisplay? { NSScreen.screens.first.map(MainDisplay.init) }
    init(_ screen:NSScreen) {
        let id=(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        self.init(name:screen.localizedName,builtIn:CGDisplayIsBuiltin(id) != 0,points:screen.frame.size,scale:screen.backingScaleFactor,
                  cameraInset:screen.safeAreaInsets.top,refresh:CGDisplayCopyDisplayMode(id)?.refreshRate ?? 0,modes:DisplayMode.all(id))
    }
    init(name:String, builtIn:Bool, points:CGSize, scale:CGFloat, cameraInset:CGFloat=0, refresh:Double=0, modes:[DisplayMode]=[]) {
        self.name=name;self.builtIn=builtIn;self.points=points;self.refresh=refresh
        drawn=CGSize(width:(points.width*scale).rounded(),height:(points.height*scale).rounded())
        let area={ (size:CGSize) in size.width*size.height }
        let native=modes.filter(\.native).map(\.pixels).max { area($0) < area($1) }
        self.native=native
        // Below the camera housing: the same share of the screen as of its points.
        let full=native ?? CGSize(width:points.width*scale,height:points.height*scale)
        pixels=CGSize(width:full.width.rounded(),height:(full.height*(points.height-cameraInset)/max(points.height,1)).rounded())
        let dimensions=modes.flatMap { [$0.points,$0.pixels] }+[pixels]
        resolutions=Array(Set(dimensions.map { DisplayResolution(width:Int($0.width),height:Int($0.height)) }.filter(\.isSupported)))
            .sorted { $0.width == $1.width ? $0.height < $1.height : $0.width < $1.width }
        sharpest=native.flatMap { native in
            let candidates=modes.filter { $0.pixels == native }
            let distance={ (mode:DisplayMode) in abs(log(mode.points.width/max(points.width,1))) }
            guard let best=candidates.min(by:{ distance($0) < distance($1) }) else { return nil }
            let fastest=candidates.filter { $0.points == best.points }.map(\.refresh).max() ?? best.refresh
            return DisplayMode(points:best.points,pixels:best.pixels,refresh:fastest,native:true)
        }
    }
    init(name:String, builtIn:Bool, points:CGSize, pixels:CGSize) {
        self.name=name;self.builtIn=builtIn;self.points=points;self.pixels=pixels
        drawn=pixels;native=nil;refresh=0;sharpest=nil
        let size=DisplayResolution(width:Int(pixels.width),height:Int(pixels.height))
        resolutions=size.isSupported ? [size] : []
    }
    var shape:DisplayResolution.Shape { pixels.width/max(pixels.height,1) < 1.69 ? .macBook : .monitor }
    var aspect:String { DisplayResolution.aspectName(pixels.width/max(pixels.height,1)) }
    var size:String { "\(Int(pixels.width)) × \(Int(pixels.height))" }
    /// The game's window has to fit inside the display as Wine sees it, or the pointer
    /// can't reach all of it. The worker applies the same rule when the game opens.
    func fits(_ resolution:DisplayResolution) -> Bool {
        CGFloat(resolution.width) <= points.width*2 && CGFloat(resolution.height) <= points.height*2
    }
    /// What the game uses on this display: scale oversized choices proportionally
    /// so their aspect ratio and pointer coordinates continue to agree.
    func fitted(_ resolution:DisplayResolution) -> DisplayResolution {
        guard !fits(resolution) else { return resolution }
        guard resolution.isSupported else { return .standard }
        let scale=min(points.width*2/CGFloat(resolution.width),points.height*2/CGFloat(resolution.height))
        let scaled=DisplayResolution(width:Int(floor(CGFloat(resolution.width)*scale)),height:Int(floor(CGFloat(resolution.height)*scale)))
        if scaled.isSupported { return scaled }
        let fallbackScale=min(1,points.width*2/1920,points.height*2/1200)
        let fallback=DisplayResolution(width:Int(floor(1920*fallbackScale)),height:Int(floor(1200*fallbackScale)))
        return fallback.isSupported ? fallback : resolution
    }
    /// What the player sees with a resolution on this display, for Settings.
    func caption(for choice:DisplayResolution) -> String {
        let sharper="Larger sizes look sharper and lower your frame rate."
        if !fits(choice) {
            return "Too large for this main display: the game uses \(fitted(choice).label) until a larger display is your main display."
        }
        // Shapes within 2% look the same (a MacBook's area below the camera is 16:10).
        let screen=pixels.width/max(pixels.height,1)
        if choice.ratio < screen*0.98 {
            return "Your main display is wider than \(choice.aspect), so the picture has black bars at the sides. \(sharper)"
        }
        if choice.ratio > screen*1.02 {
            return "Your main display is taller than \(choice.aspect), so the picture has black bars above and below. \(sharper)"
        }
        if CGFloat(choice.width) == pixels.width && CGFloat(choice.height) == pixels.height {
            return "Matches your main display exactly: the sharpest picture. Smaller sizes run faster."
        }
        if CGFloat(choice.width) > pixels.width {
            return "Larger than your main display: smoother edges, but a much lower frame rate."
        }
        return "Scaled up to fill your main display. \(sharper)"
    }
    /// For a monitor macOS draws at a size other than its own pixels (issue #9: a 1440p
    /// monitor at "1920 × 1080" drawn at 3840 × 2160): what that does to the game's
    /// picture and the Displays setting that draws it pixel for pixel; Settings shows it with
    /// a button to Display Settings. MacBook screens get
    /// none: a 13-inch MacBook Air's default is drawn about 1.15 times its screen, and
    /// changing it would resize everything else on the Mac. Changing the mode while
    /// the game runs moves Wine's pointer mapping, hence "close the game".
    var scalingNote:String? {
        guard !builtIn, let native, let sharpest else { return nil }
        let ratio=drawn.width/max(native.width,1)
        guard ratio > 1.02 || ratio < 0.98 else { return nil }
        // Numbers and their units stay on one line (no-break spaces).
        let hz={ (rate:Double) in "\(Int(rate.rounded()))\u{00A0}Hz" }
        let label=sharpest.label.replacingOccurrences(of:" ",with:"\u{00A0}")
        let faster=refresh > 0 && sharpest.refresh >= refresh+1
        // A low-resolution mode shares its name with the sharp one.
        let pick=sharpest.points == points ? "\(label), not the “low resolution” one" : label
        let slower=faster ? " and runs at \(hz(refresh)) instead of \(hz(sharpest.refresh))" : ""
        let rate=faster ? " at \(hz(sharpest.refresh))" : ""
        return "macOS is resizing everything on this monitor, so the game looks softer than it should\(slower). To fix it, close the game and set this monitor to \(pick)\(rate)."
    }
}
