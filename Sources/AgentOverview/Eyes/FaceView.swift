import SwiftUI

/// One session face in the active style: the glossy disc with dot-matrix eyes, or the flat blob.
/// The panel drives it with a `FaceStatus`; the playground with an explicit `Expression`.
struct FaceView: View {
    let seed: String
    let mode: FaceMode
    var size: CGFloat = Theme.faceSize

    private var identityOverride: FaceIdentity?
    private var styleOverride: FaceStyle?
    private var filterOverride: FaceFilter?
    private var shapeModeOverride: Theme.BlobShapeMode?
    private var colorModeOverride: Theme.ColorMode?
    private var projectKey: String?
    private var bodyOverride: BlobBody?
    private var blinkToken = 0
    private var replayToken = 0
    private var squintToken = 0
    private var activity: SessionActivity = .thinking
    private var satelliteCount = 0
    private var attentionToken = 0
    private var excitedToken = 0
    private var hovered = false
    private var hoverEffectOverride: Theme.HoverEffect?
    private var magnify = MagnifyState.identity
    private var enterDelay: TimeInterval = 0
    private var throwPose = FaceThrowPose.rest
    private var side = PanelSide.default
    /// Set by a departing row (`RowDeparture`); the face shrinks and fades with it.
    @Environment(\.faceLeave) private var leave

    /// Status driven face (panel rows).
    init(seed: String, status: FaceStatus, size: CGFloat = Theme.faceSize) {
        self.seed = seed
        self.mode = .status(status)
        self.size = size
    }

    /// Action face (the rows below the divider).
    init(seed: String, action: ActionFace, size: CGFloat = Theme.faceSize) {
        self.seed = seed
        self.mode = .action(action)
        self.size = size
    }

    /// Expression driven face (playground).
    init(seed: String, expression: Expression, size: CGFloat = Theme.faceSize) {
        self.seed = seed
        self.mode = .expression(expression)
        self.size = size
    }

    var body: some View {
        Group {
            switch styleOverride ?? FaceLook.style {
            case .dotMatrix:
                // The eyes magnify in their layer tree; the disc is a SwiftUI shape and eases along with the same curve.
                let config = configuration
                ZStack {
                    FaceDisc(size: size)
                        .scaleEffect(leave.scale)
                        .opacity(leave.opacity)
                        .scaleEffect(magnify.scale)
                        .offset(x: magnify.dx, y: magnify.dy)
                        .animation(.easeOut(duration: magnify == .identity ? Theme.magnifyReleaseDuration : Theme.magnifyFollowDuration), value: magnify)
                        // The throw (the eyes take it in their layer tree; SwiftUI turns clockwise, hence the sign).
                        .scaleEffect(throwPose.scale)
                        .rotationEffect(.radians(-throwPose.angle))
                        .offset(x: throwPose.dx, y: throwPose.dy)
                        .opacity(throwPose.opacity)
                        .animation(Self.discAnimation(throwPose.motion), value: throwPose)
                    EyesLayerView(configuration: config)
                        .frame(width: size, height: size)
                }
                .scaleEffect(config.stretched ? Theme.genieDotMatrixScale : 1)
                .animation(.easeOut(duration: Theme.genieReduceMotionDuration), value: config.stretched)
            case .blob:
                BlobLayerView(configuration: configuration)
            }
        }
        .frame(width: size, height: size)
    }

    private var configuration: FaceConfiguration {
        FaceConfiguration(
            identity: identityOverride ?? FaceIdentity(seed: seed),
            mode: mode,
            size: size,
            filter: filterOverride ?? FaceLook.filter,
            blobShapeMode: shapeModeOverride ?? FaceLook.blobShapeMode,
            colorMode: colorModeOverride ?? FaceLook.colorMode,
            projectKey: projectKey,
            blobBody: bodyOverride,
            blinkToken: blinkToken,
            replayToken: replayToken,
            squintToken: squintToken,
            activity: activity,
            satellites: satelliteCount,
            attentionToken: attentionToken,
            excitedToken: excitedToken,
            hovered: hovered,
            hoverEffect: hoverEffectOverride ?? FaceLook.hoverEffect,
            magnify: magnify,
            enterDelay: enterDelay,
            leave: leave,
            throwPose: throwPose,
            side: side
        )
    }

    /// The dot-matrix disc's SwiftUI counterpart of a throw pose's motion.
    private static func discAnimation(_ motion: FaceThrowPose.Motion) -> Animation? {
        switch motion {
        case .immediate: nil
        case .flyAway: .easeOut(duration: Theme.throwFlyDuration)
        case .springBack: Theme.openSpring
        case .easeBack: .easeOut(duration: Theme.throwReduceMotionReturn)
        }
    }

    // MARK: Session modifiers (panel rows and playground)

    /// What a working session is doing: picks the blob's working substate loop.
    func activity(_ activity: SessionActivity) -> FaceView {
        var copy = self
        copy.activity = activity
        return copy
    }

    /// Subagents running for the session: small blobs orbit a working blob face.
    func satellites(_ count: Int) -> FaceView {
        var copy = self
        copy.satelliteCount = count
        return copy
    }

    /// Bump the token to make the blob face hop once (a session started waiting).
    func attention(token: Int) -> FaceView {
        var copy = self
        copy.attentionToken = token
        return copy
    }

    /// Bump the token to make a working blob face perk up once (its session just started working
    /// after resting or waiting: the person's message arrived). Faces whose program has no excited
    /// reaction ignore it, and so does the dot-matrix style.
    func excited(token: Int) -> FaceView {
        var copy = self
        copy.excitedToken = token
        return copy
    }

    /// The row is under the pointer: under the `.stretch` effect the blob stretches toward the bulge like the Dock genie.
    func hovered(_ hovered: Bool) -> FaceView {
        var copy = self
        copy.hovered = hovered
        return copy
    }

    /// Dock-style magnification for this face (scale and drift toward the pointer), from the model's pointer.
    func magnify(_ state: MagnifyState) -> FaceView {
        var copy = self
        copy.magnify = state
        return copy
    }

    /// Where a held or thrown face is drawn (the throw out of the capsule, `FaceThrowPose`).
    func thrown(_ pose: FaceThrowPose) -> FaceView {
        var copy = self
        copy.throwPose = pose
        return copy
    }

    /// The panel's screen edge: on the left edge the face is drawn mirrored, so it looks and
    /// stretches toward the screen (`FaceConfiguration.side`).
    func side(_ side: PanelSide) -> FaceView {
        var copy = self
        copy.side = side
        return copy
    }

    /// Seconds before the face pops in when it first appears (its slot opens first, new rows stagger).
    func entrance(delay: TimeInterval) -> FaceView {
        var copy = self
        copy.enterDelay = delay
        return copy
    }

    /// The project key the body colour comes from in `.project` colour mode.
    func project(_ key: String?) -> FaceView {
        var copy = self
        copy.projectKey = key
        return copy
    }

    /// Bump the token for one quick happy squint (an action face was clicked).
    func squint(token: Int) -> FaceView {
        var copy = self
        copy.squintToken = token
        return copy
    }

    // MARK: Playground modifiers

    /// Forces an identity (for one column per preset or silhouette).
    func identity(_ identity: FaceIdentity) -> FaceView {
        var copy = self
        copy.identityOverride = identity
        return copy
    }

    /// Runtime override of the face style.
    func faceStyle(_ style: FaceStyle) -> FaceView {
        var copy = self
        copy.styleOverride = style
        return copy
    }

    /// Runtime override of the screen filter.
    func faceFilter(_ filter: FaceFilter) -> FaceView {
        var copy = self
        copy.filterOverride = filter
        return copy
    }

    /// Runtime override of the blob shape mode.
    func blobShapeMode(_ mode: Theme.BlobShapeMode) -> FaceView {
        var copy = self
        copy.shapeModeOverride = mode
        return copy
    }

    /// Runtime override of the colour mode.
    func colorMode(_ mode: Theme.ColorMode) -> FaceView {
        var copy = self
        copy.colorModeOverride = mode
        return copy
    }

    /// Runtime override of the hover effect.
    func hoverEffect(_ effect: Theme.HoverEffect) -> FaceView {
        var copy = self
        copy.hoverEffectOverride = effect
        return copy
    }

    /// Forces the blob body (the playground's status shapes and silhouette columns).
    func blobBody(_ body: BlobBody?) -> FaceView {
        var copy = self
        copy.bodyOverride = body
        return copy
    }

    /// Bump `blink` to blink once, `replay` to replay the finished bounce.
    func triggers(blink: Int, replay: Int) -> FaceView {
        var copy = self
        copy.blinkToken = blink
        copy.replayToken = replay
        return copy
    }
}
