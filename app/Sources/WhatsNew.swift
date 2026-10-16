// Offline release notes, also available from Help.
enum WhatsNew {
    static let version="1.0"
    static let items:[(symbol:String, title:String, detail:String)]=[
        ("gamecontroller","Your launch controls stay available",
         "Play and Open Steam remain visible while a game is running. Open Steam brings your Library forward."),
        ("rectangle.expand.vertical","Per-game launch options",
         "Choose common, display or custom resolutions and sync your choices to Steam Properties."),
        ("cursorarrow.motionlines","Input and fullscreen repairs",
         "Fixes raw-input timing and a captured fullscreen startup deadlock. Occasional black screens still require quitting and restarting the game."),
        ("circle.lefthalf.filled","Black and white",
         "A monochrome icon, solid backgrounds and a simpler main screen."),
    ]
}
