// Offline release notes, also available from Help.
enum WhatsNew {
    static let version="1.0"
    static let items:[(symbol:String, title:String, detail:String)]=[
        ("gamecontroller","SCP: Secret Laboratory",
         "MacSL installs Steam in its own environment and starts SCP: Secret Laboratory on Direct3D 11 through DXMT, Recall's Metal translation."),
        ("rectangle.expand.vertical","Launch options",
         "Choose fullscreen or windowed and a resolution. MacSL writes them to Steam's launch options and the game's own window-mode setting."),
        ("cursorarrow.motionlines","Raw mouse and Game Mode",
         "The mouse is read directly, and the game starts as a Mac game so macOS gives it priority."),
        ("exclamationmark.triangle","Early build",
         "Unsigned community build based on MacVolvo and Recall. Performance hasn't been measured against CrossOver yet."),
    ]
}
