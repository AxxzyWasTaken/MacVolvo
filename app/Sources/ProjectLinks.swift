import SwiftUI
import AppKit

// Offline vector from GitHub's official favicon. See GITHUB-MARK-NOTICE.txt.
private struct GitHubMark:Shape {
    func path(in rect:CGRect)->Path {
        var p=Path()
        p.move(to:CGPoint(x:16,y:0))
        p.addCurve(to:CGPoint(x:0,y:16),control1:CGPoint(x:7.16,y:0),control2:CGPoint(x:0,y:7.16))
        p.addCurve(to:CGPoint(x:10.94,y:31.18),control1:CGPoint(x:0,y:23.08),control2:CGPoint(x:4.58,y:29.06))
        p.addCurve(to:CGPoint(x:12.04,y:30.42),control1:CGPoint(x:11.74,y:31.32),control2:CGPoint(x:12.04,y:30.84))
        p.addCurve(to:CGPoint(x:12.02,y:27.44),control1:CGPoint(x:12.04,y:30.04),control2:CGPoint(x:12.02,y:28.78))
        p.addCurve(to:CGPoint(x:6.64,y:25.56),control1:CGPoint(x:8,y:28.18),control2:CGPoint(x:6.96,y:26.46))
        p.addCurve(to:CGPoint(x:5,y:23.3),control1:CGPoint(x:6.46,y:25.1),control2:CGPoint(x:5.68,y:23.68))
        p.addCurve(to:CGPoint(x:4.98,y:22.24),control1:CGPoint(x:4.44,y:23),control2:CGPoint(x:3.64,y:22.26))
        p.addCurve(to:CGPoint(x:7.44,y:23.88),control1:CGPoint(x:6.24,y:22.22),control2:CGPoint(x:7.14,y:23.4))
        p.addCurve(to:CGPoint(x:12.1,y:25.2),control1:CGPoint(x:8.88,y:26.3),control2:CGPoint(x:11.18,y:25.62))
        p.addCurve(to:CGPoint(x:13.12,y:23.06),control1:CGPoint(x:12.24,y:24.16),control2:CGPoint(x:12.66,y:23.46))
        p.addCurve(to:CGPoint(x:5.84,y:15.16),control1:CGPoint(x:9.56,y:22.66),control2:CGPoint(x:5.84,y:21.28))
        p.addCurve(to:CGPoint(x:7.48,y:10.86),control1:CGPoint(x:5.84,y:13.42),control2:CGPoint(x:6.46,y:11.98))
        p.addCurve(to:CGPoint(x:7.64,y:6.62),control1:CGPoint(x:7.32,y:10.46),control2:CGPoint(x:6.76,y:8.82))
        p.addCurve(to:CGPoint(x:12.04,y:8.26),control1:CGPoint(x:7.64,y:6.62),control2:CGPoint(x:8.98,y:6.2))
        p.addCurve(to:CGPoint(x:16.04,y:7.72),control1:CGPoint(x:13.32,y:7.9),control2:CGPoint(x:14.68,y:7.72))
        p.addCurve(to:CGPoint(x:20.04,y:8.26),control1:CGPoint(x:17.4,y:7.72),control2:CGPoint(x:18.76,y:7.9))
        p.addCurve(to:CGPoint(x:24.44,y:6.62),control1:CGPoint(x:23.1,y:6.18),control2:CGPoint(x:24.44,y:6.62))
        p.addCurve(to:CGPoint(x:24.6,y:10.86),control1:CGPoint(x:25.32,y:8.82),control2:CGPoint(x:24.76,y:10.46))
        p.addCurve(to:CGPoint(x:26.24,y:15.16),control1:CGPoint(x:25.62,y:11.98),control2:CGPoint(x:26.24,y:13.4))
        p.addCurve(to:CGPoint(x:18.94,y:23.06),control1:CGPoint(x:26.24,y:21.3),control2:CGPoint(x:22.5,y:22.66))
        p.addCurve(to:CGPoint(x:20.02,y:26.02),control1:CGPoint(x:19.52,y:23.56),control2:CGPoint(x:20.02,y:24.52))
        p.addCurve(to:CGPoint(x:20,y:30.42),control1:CGPoint(x:20.02,y:28.16),control2:CGPoint(x:20,y:29.88))
        p.addCurve(to:CGPoint(x:21.1,y:31.18),control1:CGPoint(x:20,y:30.84),control2:CGPoint(x:20.3,y:31.34))
        p.addCurve(to:CGPoint(x:32,y:16),control1:CGPoint(x:27.42,y:29.06),control2:CGPoint(x:32,y:23.06))
        p.addCurve(to:CGPoint(x:16,y:0),control1:CGPoint(x:32,y:7.16),control2:CGPoint(x:24.84,y:0))
        p.addLine(to:CGPoint(x:p.currentPoint!.x,y:0))
        p.closeSubpath()
        let scale=min(rect.width,rect.height)/32
        return p.applying(CGAffineTransform(scaleX:scale,y:scale))
    }
}
struct RepositoryLink:View {
    var compact=false
    var body:some View {
        Link(destination:Brand.repository) {
            HStack(spacing:10) {
                GitHubMark().fill(.white).frame(width:20,height:20).accessibilityHidden(true)
                Text(Brand.repositoryPath).font(LauncherStyle.font(14,.semibold))
                Image(systemName:"arrow.up.right").font(.system(size:11,weight:.semibold)).accessibilityHidden(true)
            }.foregroundStyle(.white).padding(.horizontal,compact ? 16 : 0)
                .frame(maxWidth:compact ? nil : .infinity,minHeight:compact ? 38 : 46)
                .background(.black,in:Capsule())
                .overlay { Capsule().strokeBorder(.white.opacity(0.18),lineWidth:1) }
                .contentShape(Capsule())
        }.buttonStyle(.plain).environment(\.colorScheme,.light).accessibilityLabel("\(Brand.name) on GitHub")
            .help("Open the project repository in your browser")
    }
}

// Loaded once, offline; progress timer updates never decode these assets again.
private enum ProjectArtwork {
    static let wordmark=load("Wordmark","png")
    static let wordmarkDark=load("WordmarkDark","png")
    private static func load(_ name:String,_ type:String)->NSImage {
        Bundle.main.url(forResource:name,withExtension:type).flatMap { NSImage(contentsOf:$0) } ?? NSImage()
    }
}
/// The MacVolvo lockup (mark and name) in its light- and dark-appearance versions; the
/// mark is the square at its leading edge. A badge marks a state, as on the app icon
/// (a failure, a paused setup, a missing drive).
struct Wordmark:View {
    var height:CGFloat
    var badge:String?
    @Environment(\.colorScheme) private var scheme
    var body:some View {
        Image(nsImage:scheme == .dark ? ProjectArtwork.wordmarkDark : ProjectArtwork.wordmark)
            .resizable().interpolation(.high).scaledToFit().frame(height:height)
            .overlay(alignment:.leading) {
                if let badge {
                    Color.clear.frame(width:height,height:height).overlay(alignment:.bottomTrailing) {
                        Image(systemName:badge).font(.system(size:height*0.2,weight:.semibold))
                            .foregroundStyle(LauncherStyle.ink).frame(width:height*0.4,height:height*0.4)
                            .background(LauncherStyle.accent,in:Circle())
                            .overlay { Circle().strokeBorder(.background,lineWidth:2) }
                            .offset(x:height*0.08,y:height*0.04)
                    }
                }
            }
            .accessibilityElement().accessibilityLabel(Brand.name).accessibilityAddTraits(.isHeader)
    }
}
/// "by @haeli05", under the wordmark and in About; opens the author's GitHub.
struct AuthorLink:View {
    var body:some View {
        Link(destination:Brand.authorPage) {
            HStack(spacing:5) {
                Text("by").foregroundStyle(.secondary)
                Text(Brand.author).foregroundStyle(LauncherStyle.accent)
            }.font(LauncherStyle.font(13,.semibold)).tracking(0.6)
        }.buttonStyle(.plain).pointerStyle(.link).help("haeli05 on GitHub")
    }
}
/// The project MacVolvo is built on, credited in About.
struct UpstreamLink:View {
    var body:some View {
        Link(destination:Brand.upstream) {
            HStack(spacing:4) {
                Text("Based on Recall by Joshua Asher Nelson")
                Image(systemName:"arrow.up.right").font(.system(size:8,weight:.semibold)).accessibilityHidden(true)
            }.font(LauncherStyle.font(12,.medium))
        }.buttonStyle(.plain).foregroundStyle(.secondary).help("Open Recall’s repository in your browser")
    }
}
