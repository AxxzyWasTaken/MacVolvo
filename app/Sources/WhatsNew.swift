// Shown once after an update and from the Help menu, offline. Edit for each
// release alongside the public release notes; short, plain sentences.
enum WhatsNew {
    static let version="0.1"
    static let items:[(symbol:String, title:String, detail:String)]=[
        ("gamecontroller","Counter-Strike 2 and Deadlock",
         "\(Brand.name) installs Steam and starts either game from its Play screen, on the engine Recall built for Overwatch."),
        ("macwindow","Steam’s window works",
         "Steam’s store, library and sign-in draw with GPU web views on Wine 11."),
        ("cursorarrow.motionlines","Raw mouse input",
         "Aim follows your mouse directly, without macOS pointer acceleration."),
        ("bolt","Game Mode",
         "macOS Game Mode gives the game priority on your Mac’s CPU and GPU while you play."),
    ]
}
