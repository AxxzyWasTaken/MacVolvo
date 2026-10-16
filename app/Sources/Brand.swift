import Foundation

// The product's public identity in one place: name, tagline, project links,
// update feed and release file name. MacSL is a fork of Recall (Overwatch on
// the Mac) for Valve's Source 2 games; it has its own bundle identifier
// (app.macsl.launcher) and data folder (MacSL), so it never touches an
// installed Recall.
enum Brand {
    static let name="MacSL"
    static let tagline="SCP: Secret Laboratory on Apple Silicon."
    static let repositoryPath="AxxzyWasTaken/MacVolvo"
    static let repository=URL(string:"https://github.com/\(repositoryPath)")!
    static let releases=URL(string:"https://github.com/\(repositoryPath)/releases")!
    static let issues=URL(string:"https://github.com/\(repositoryPath)/issues/new/choose")!
    /// GitHub's latest-release API for the repository. The updater accepts any
    /// release disk image named "<anything>-<version>.dmg".
    static let releaseFeed=URL(string:"https://api.github.com/repos/\(repositoryPath)/releases/latest")!
    static func diskImage(_ version:String)->String { "\(name)-\(version).dmg" }
    static let trademarks="Not affiliated with or endorsed by Northwood Studios, Valve Corporation, Blizzard Entertainment or Apple. SCP: Secret Laboratory is a trademark of Northwood Studios. Steam is a trademark of Valve Corporation. Mac is a trademark of Apple Inc. Based on MacVolvo by @haeli05 and Recall by Joshua Asher Nelson."
    /// Who makes MacSL: shown in About.
    static let author="@AxxzyWasTaken"
    static let authorPage=URL(string:"https://github.com/AxxzyWasTaken")!
    /// The project MacSL is built on.
    static let upstream=URL(string:"https://github.com/AsherJN/recall")!
}
