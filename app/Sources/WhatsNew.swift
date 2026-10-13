// Shown once after an update and from the Help menu, offline. Edit for each
// release alongside the public release notes; short, plain sentences.
enum WhatsNew {
    static let version="0.9"
    static let items:[(symbol:String, title:String, detail:String)]=[
        ("rectangle.expand.vertical","More resolution choices",
         "Choose common, display or custom resolutions separately for each game, directly from the Play screen."),
        ("gamecontroller","Shared Steam launch options",
         "Starting through \(Brand.name) also saves your options in Steam Properties for Library launches."),
        ("cursorarrow.motionlines","Mouse and startup fixes",
         "Corrects mouse fallback timing, recognizes running games reliably and waits for the game window before handing over focus."),
        ("speedometer","CS2 performance tuning",
         "CS2 starts with a 120 FPS cap unless you set another in Steam Launch Options. Its compiler settings now differ from Deadlock’s."),
    ]
}
