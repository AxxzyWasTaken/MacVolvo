import Foundation

// The product's public identity in one place: name, tagline, project links,
// update feed and release file name. MacVolvo is a fork of Recall (Overwatch on
// the Mac) for Valve's Source 2 games; it has its own bundle identifier
// (app.macvolvo.launcher) and data folder (MacVolvo), so it never touches an
// installed Recall.
enum Brand {
    static let name="MacVolvo"
    static let tagline="Counter-Strike 2 and Deadlock on Apple Silicon."
    static let repositoryPath="haeli05/MacVolvo"
    static let repository=URL(string:"https://github.com/\(repositoryPath)")!
    static let releases=URL(string:"https://github.com/\(repositoryPath)/releases")!
    static let issues=URL(string:"https://github.com/\(repositoryPath)/issues/new/choose")!
    /// GitHub's latest-release API for the repository. The updater accepts any
    /// release disk image named "<anything>-<version>.dmg".
    static let releaseFeed=URL(string:"https://api.github.com/repos/\(repositoryPath)/releases/latest")!
    static func diskImage(_ version:String)->String { "\(name)-\(version).dmg" }
    static let trademarks="Not affiliated with or endorsed by Valve Corporation, Volvo, Blizzard Entertainment or Apple. Counter-Strike, Deadlock and Steam are trademarks of Valve Corporation. Mac is a trademark of Apple Inc. Based on Recall by Joshua Asher Nelson."
    /// The project MacVolvo is built on.
    static let upstream=URL(string:"https://github.com/AsherJN/recall")!
}
