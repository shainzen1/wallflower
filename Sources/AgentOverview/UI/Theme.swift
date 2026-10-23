import SwiftUI

/// Every tunable value lives here. Layout and window code read these, never literals.
///
/// Horizontal words ("left", "leftward") describe the panel on the right screen edge, the canonical
/// side. On the left edge (`PanelSide.left`) every such value applies mirrored: "left of the capsule"
/// reads "away from the screen edge".
enum Theme {
    // MARK: Layout

    /// Width of the black capsule at rest (collapsed), in points.
    static let capsuleWidth: CGFloat = 60
    /// Side of one face (a rounded square) inside the capsule.
    static let faceSize: CGFloat = 44
    /// Corner radius of a face as a fraction of its side (continuous corners, a soft squircle).
    static let faceCornerRadiusFraction: CGFloat = 0.3
    /// Vertical distance between the centres of two neighbouring rows.
    static let rowPitch: CGFloat = 52
    /// Black space above the first face and below the last one (inside the body, not counting the fillets).
    static let capsuleEndPadding: CGFloat = 8
    /// Radius of the two left corners of the capsule. Smaller than a pill: it reads like the MacBook notch's corners.
    static let capsuleCornerRadius: CGFloat = 16
    /// Radius of the concave fillets where the capsule meets the screen edge, like the notch meets the bezel.
    /// The capsule's silhouette is this much taller at each end; the fillet area is black.
    static let edgeFilletRadius: CGFloat = 10
    /// Body height from which the edge fillets are drawn at full `edgeFilletRadius`; a shorter body
    /// draws them in proportion (`GooLayout.edgeFilletRadius(bodyHeight:)`). Full size on a 60 pt body,
    /// the lone new session button's, the two fillets made the edge column a third taller than the
    /// rounded body, and it read as a rounded square in front of a taller strip on the screen edge.
    /// The window keeps the full fillet room above and below the body, so no slot moves.
    static let edgeFilletFullBody: CGFloat = 120
    /// Transparent slack to the left of the capsule inside the window (room for shadows and overshoot).
    static let windowPadding: CGFloat = 8
    /// Rows the capsule keeps when the store is empty: a short black stub of one row height,
    /// nothing in it, so the panel always shows where it lives.
    static let emptyCapsuleRows = 1

    /// Height of the capsule body (between the fillets) for a given number of rows.
    static func capsuleBodyHeight(rows: Int) -> CGFloat {
        capsuleBodyHeight(rows: rows, actions: 0)
    }

    /// Full capsule height including both fillets. `PanelWindow` sizes the window with this.
    static func capsuleHeight(rows: Int) -> CGFloat {
        capsuleHeight(rows: rows, actions: 0)
    }

    /// Row slots the live section occupies: the empty stub when there is nothing at all, no stub
    /// when action faces or the new session button fill the capsule instead (they show where the
    /// panel lives just as well).
    static func liveSlots(rows: Int, actions: Int, newSession: Bool = false) -> Int {
        rows == 0 && (actions > 0 || newSession) ? 0 : max(rows, emptyCapsuleRows)
    }

    /// Whether the divider between the live rows and the action faces is drawn: only with both sections present.
    static func hasDivider(rows: Int, actions: Int, newSession: Bool = false) -> Bool {
        liveSlots(rows: rows, actions: actions, newSession: newSession) > 0 && actions > 0
    }

    /// Whether the divider below the new session button is drawn: with the button and anything below it.
    static func hasTopDivider(rows: Int, actions: Int, newSession: Bool) -> Bool {
        newSession && (rows > 0 || actions > 0)
    }

    /// Height of the section above the live rows: the new session button's slot plus, when anything
    /// follows it, its divider. Zero without the button.
    static func topSectionHeight(rows: Int, actions: Int, newSession: Bool) -> CGFloat {
        guard newSession else { return 0 }
        return newSessionPitch + (hasTopDivider(rows: rows, actions: actions, newSession: true) ? dividerHeight : 0)
    }

    /// Height of the capsule body for the new session button (when shown), the live rows and the
    /// action section (divider and action rows).
    static func capsuleBodyHeight(rows: Int, actions: Int, newSession: Bool = false) -> CGFloat {
        let slots = liveSlots(rows: rows, actions: actions, newSession: newSession)
        let divider = hasDivider(rows: rows, actions: actions, newSession: newSession) ? dividerHeight : 0
        let top = topSectionHeight(rows: rows, actions: actions, newSession: newSession)
        return top + CGFloat(slots + actions) * rowPitch + divider + capsuleEndPadding * 2
    }

    /// Full capsule height including both fillets, with the new session button and the action section.
    static func capsuleHeight(rows: Int, actions: Int, newSession: Bool = false) -> CGFloat {
        capsuleBodyHeight(rows: rows, actions: actions, newSession: newSession) + edgeFilletRadius * 2
    }

    // MARK: Placement on the screen edge (drag, persisted offset)

    /// Gap the panel keeps to the menu bar above and the Dock below (the screen's `visibleFrame`)
    /// when it is dragged or clamped.
    static let dockEdgeInset: CGFloat = 8
    /// Vertical pointer travel after a press before the press becomes a drag of the panel; below it,
    /// the release stays a plain click on the row.
    static let dragThreshold: CGFloat = 4
    /// Length of the ease-out move back to the centre when "Reset position" is chosen.
    static let resetPositionDuration: TimeInterval = 0.25
    /// Put the panel into a window-server Space of its own (`StationarySpace`) so switching to or from
    /// a full-screen Space never slides it; false keeps the plain all-Spaces collection behaviour.
    static let panelOwnSpace = true
    /// Absolute level of that Space. 1 is the lowest that stays visible over full-screen Spaces
    /// (measured: at 0 the panel disappears while a full-screen app is active).
    static let panelSpaceLevel: Int32 = 1

    // MARK: Auto-hide (Settings > General > Hide the panel)

    /// When the panel slides off its edge by default: while nothing runs (`PanelAutoHide`).
    static let panelAutoHide: PanelAutoHide = .empty
    /// Length of the slide off the edge and back, along the edge normal (Core Animation, on the
    /// window content's sublayer transform; the window itself stays where it is).
    static let autoHideSlideDuration: TimeInterval = 0.28
    /// The slide's curve: a strong ease-out (fast start, long soft landing), both ways.
    static let autoHideSlideCurve: (Float, Float, Float, Float) = (0.16, 1, 0.3, 1)
    /// Reduce Motion: the panel fades out and in over this long instead of sliding.
    static let autoHideFadeDuration: TimeInterval = 0.2
    /// How long the pointer has to rest in the edge trigger before the panel comes out. Long enough
    /// that a pointer crossing an edge shared with another display (inside the strip for a frame or
    /// two) never brings it out, short enough to feel immediate at an outer edge.
    static let autoHideDwell: TimeInterval = 0.15
    /// After the pointer left a panel it brought out, the panel slides away this much later.
    static let autoHideDelay: TimeInterval = 0.5
    /// After the panel has nothing left to show (the last face left, nothing waits any more), it
    /// stays this long before it slides away, so the last face is seen leaving.
    static let autoHideLinger: TimeInterval = 1.5
    /// Width of the invisible edge trigger along the panel's band at an outer screen edge, where the
    /// pointer stops at the last column. Only there while the panel is hidden; it takes the clicks
    /// in this strip (a click brings the panel out at once).
    static let autoHideTriggerWidth: CGFloat = 2
    /// The trigger's width on an edge shared with another display, where the pointer does not stop
    /// at the edge: wide enough to rest the pointer in on purpose.
    static let autoHideSharedEdgeTriggerWidth: CGFloat = 6

    // MARK: Throw a face out of the capsule (stop watching a session)

    /// Leftward pointer travel (away from the screen edge) after a press on a session face that turns
    /// the press into a throw, provided it comes before `dragThreshold` of vertical travel (`PressAxis`).
    static let throwThreshold: CGFloat = 10
    /// Share of the pointer's vertical travel a held face follows; horizontally it follows 1:1.
    static let throwVerticalFollow: CGFloat = 0.3
    /// Largest tilt of a held face, in degrees, reached at `throwTiltVelocity` (none under Reduce Motion).
    static let throwTilt: CGFloat = 12
    /// Horizontal pointer speed, in points per second, at which a held face reaches its full tilt.
    static let throwTiltVelocity: CGFloat = 800
    /// Span of the most recent pointer samples the throw velocity is measured over, in seconds.
    static let throwVelocityWindow: TimeInterval = 0.08
    /// A face released with its centre farther than this left of the capsule's left edge is thrown out.
    static let throwDistance: CGFloat = 70
    /// A face released moving left faster than this, in points per second, is thrown out wherever it is.
    static let throwVelocity: CGFloat = 600
    /// Length of the fly-away (ease-out) of a thrown face, before its row departs.
    static let throwFlyDuration: TimeInterval = 0.25
    /// How far a thrown face travels on during the fly-away, along its throw direction.
    static let throwFlyDistance: CGFloat = 90
    /// Scale a thrown face shrinks to during the fly-away, while it fades out.
    static let throwFlyScale: CGFloat = 0.6
    /// Draw order of a held or flying face: above the hovered row (2) and waiting rows (1).
    static let throwZIndex: Double = 3
    /// A face let go short of a throw springs back into its slot on the open spring (`openSpring`:
    /// response 0.45, damping fraction 0.65, so bounce 0.35), as Core Animation physics.
    static let throwReturnSpring = EntranceSpring(response: 0.45, bounce: 0.35)
    /// Reduce Motion: a face let go short of a throw eases back into its slot over this long.
    static let throwReduceMotionReturn: TimeInterval = 0.2

    // MARK: Action faces (the section below the divider)

    /// Vertical room the divider takes between the last live row and the first action row (the row
    /// pitch continues on both sides of it). Holds a 1 pt line, centred.
    static let dividerHeight: CGFloat = 14
    /// The divider line: faint white on the capsule's black, like a menu separator inside a notch.
    static let dividerColor = Color.white.opacity(0.12)
    static let dividerLineWidth: CGFloat = 1
    /// How much of the capsule width the line spans, centred.
    static let dividerWidthFraction: CGFloat = 0.6
    /// Body colour of an action face: a soft lavender, clearly no status colour and no project hue
    /// (the project palette keeps its violet range darker and bluer). Overridable per action in `actions.json`.
    static let actionColor = EyeColor(name: "lavender", red: 0.74, green: 0.66, blue: 0.98)
    /// Silhouette of an action face: the four-point star, no session ever wears it.
    static let actionShape: BlobShape = .star
    /// Resting eyes of an action face: wide, flat lids (calm, nearly closed), level, a little low. They
    /// open to the normal pose on hover.
    static let actionRestingEye = BlobEye(width: 0.165, height: 0.075, tilt: 0)
    static let actionRestingSplit: Double = 50
    static let actionRestingLift: Double = 0.0
    /// Second bulge line of an action row: its prompt, in quiet grey.
    static let actionPromptColor = Color(white: 0.6)
    static let actionPromptFont = Font.system(size: 11)
    /// After a click the action face squints happily for this long, then shows the working cloud
    /// for `actionLaunchFeedback` so the click feels acknowledged while the new session starts.
    static let actionSquintDuration: TimeInterval = 0.5
    static let actionLaunchFeedback: TimeInterval = 1.5

    /// How an action starts its Claude Code session. `.deepLinkNew`: `claude://code/new?folder=&q=`
    /// (the desktop app opens a new session in the folder with the prompt prefilled, not sent).
    /// `.deepLinkAndSend`: the same link, then key presses posted to Claude once its composer holds the
    /// prompt (a slash prompt retyped, then Return), so the prompt is sent (needs Accessibility;
    /// without it, the prefill plus a hint).
    /// `.terminalCommand`: a temporary `.command` file (`cd <cwd> && claude "<prompt>"`) opened in the
    /// default terminal app; that CLI session runs the prompt at once, but outside the desktop app.
    enum ActionLauncher { case deepLinkNew, deepLinkAndSend, terminalCommand }
    /// Active launcher.
    static let actionLauncher: ActionLauncher = .terminalCommand
    /// `.terminalCommand`: open the `.command` file without bringing Terminal to the front, so the
    /// task runs in a window behind the current app (false: Terminal comes forward).
    static let terminalOpensInBackground = true
    /// `.deepLinkAndSend`: how long to wait for Claude to become the active app after the link opened
    /// (no wait when it already is).
    static let actionActivationTimeout: TimeInterval = 2
    /// `.deepLinkAndSend`: how often Claude's focused composer is read while the send runs.
    static let actionPollInterval: TimeInterval = 0.05
    /// `.deepLinkAndSend`: once the retyped prompt is in the composer, time for the slash command
    /// menu to filter before the Return picks from it (the one fixed pause; everything else waits
    /// for a composer state).
    static let actionSendDelay: TimeInterval = 0.3
    /// `.deepLinkAndSend`: after a key press, how long to wait for the composer text to change
    /// before the next decision may press again.
    static let actionReactTimeout: TimeInterval = 1
    /// `.deepLinkAndSend`: the composer has to stay empty this long after a Return to count as sent
    /// (a page that is reloading shows an empty composer for a moment, then the prefill again).
    static let actionSentConfirm: TimeInterval = 0.6
    /// `.deepLinkAndSend`: at most this many key actions (retype or Return) per click.
    static let actionMaxKeyActions = 6
    /// `.deepLinkAndSend`: key presses are only posted this soon after the link opened (and only
    /// while Claude is frontmost); later, they could land in whatever the person moved on to.
    /// Measured: the prefill lands 0.1 to 2.4 s after the link, a slash prompt then needs about
    /// 1.5 s more and the sent check 0.6 s.
    static let actionSendWindow: TimeInterval = 8
    /// Shown on the action bulge's second line when the prompt could only be prefilled.
    static let actionSendHint = "Press Return in Claude"
    static let actionSendHintDuration: TimeInterval = 4
    /// Colour of that hint: the needs-input amber, because the person has something to do.
    static let actionSendHintColor = Color(red: 1.0, green: 0.70, blue: 0.25)

    // MARK: Sessions from other tools

    /// Whether sessions other tools write into the external sessions folder show (Settings > Agents,
    /// "Sessions from other tools"; `docs/external-sessions.md`). Default on: the folder is empty unless a tool writes there.
    static let externalSessions = true

    // MARK: New session button (the control at the top of the column)

    /// Whether the new session button shows at the top of the column (Settings > General overrides it).
    static let newSessionButton = true
    /// Diameter of the button's ring: half a face, so it reads as a quiet control, not as a face.
    static let newSessionSize: CGFloat = faceSize * 0.5
    /// Height of the button's slot. Smaller than `rowPitch`: the ring is smaller than a face, and the
    /// space above it (`capsuleEndPadding` plus half the slack, 19 pt) matches the space beside it (19 pt).
    static let newSessionPitch: CGFloat = 44
    /// Stroke of the ring and of the plus inside it.
    static let newSessionStrokeWidth: CGFloat = 1.5
    /// Length of each arm of the plus, as a fraction of the ring's diameter.
    static let newSessionPlusFraction: CGFloat = 0.4
    /// Ring and plus at rest: the capsule's muted grey (between the divider line and the prompt text).
    static let newSessionRestColor = CGColor(gray: 0.42, alpha: 1)
    /// Ring and plus while hovered: white, like the bulge's first line.
    static let newSessionHoverColor = CGColor(gray: 1, alpha: 1)
    /// On hover the plus turns this far (radians) and the ring brightens, over `newSessionHoverDuration`
    /// (ease-out); both go back on exit. Under Reduce Motion only the colour changes.
    static let newSessionPlusTurn: CGFloat = .pi / 2
    static let newSessionHoverDuration: TimeInterval = 0.2
    /// Click feedback: the ring dips to this scale and back over `newSessionClickDuration` (Reduce Motion: a fade dip).
    static let newSessionClickScale: CGFloat = 0.82
    static let newSessionClickDuration: TimeInterval = 0.24
    /// Reduce Motion: the opacity the click feedback dips to instead of the scale.
    static let newSessionClickReduceMotionOpacity: Float = 0.5
    /// First line of the button's bulge.
    static let newSessionTitle = "New session"
    /// Terminal route: the `.command` file's name in the Application Support folder (actions use `launch-<id>`).
    static let newSessionCommandFile = "new-session.command"

    // MARK: Colours

    /// The capsule is pure black so it reads as the notch.
    static let capsuleColor = Color.black
    /// Top of the glossy face gradient (lighter, catches the light).
    static let discTopColor = Color(white: 0.24)
    /// Bottom of the glossy face gradient (near black).
    static let discBottomColor = Color(white: 0.05)
    /// Subtle highlight sheen across the top of each face.
    static let discHighlightColor = Color.white.opacity(0.16)
    /// Hairline rim around each face so it separates from the black capsule.
    static let discRimColor = Color.white.opacity(0.08)

    // MARK: Motion

    /// Spring for open and expand transitions; the low damping gives the goo its wobble.
    static let openSpring = Animation.spring(response: 0.45, dampingFraction: 0.65)
    /// Spring for close and collapse transitions; nearly critically damped, no wobble on the way back.
    static let closeSpring = Animation.spring(response: 0.45, dampingFraction: 0.9)
    /// Time after which `closeSpring` is visually settled (1 % amplitude is reached after ~0.37 s).
    /// The window shrinks this long after a row left, per animation rule 4.
    static let closeSpringSettleTime: TimeInterval = 0.55

    // MARK: Rows (enter, exit, press)

    /// Arrival, step 1 (room first): a new row's slot opens from 0 to `rowPitch` with an ease-out
    /// over this long, so the neighbours slide apart and the capsule body grows with them.
    static let rowOpenDuration: TimeInterval = 0.22
    /// Arrival, step 2: the face pops this long before the slot has finished opening.
    static let rowEnterOverlap: TimeInterval = 0.06
    /// The face pops in from this scale (never from 0) on `rowEnterSpring`, fading in from 0.
    static let rowEnterScale: CGFloat = 0.55
    /// The pop: a spring with a small visible overshoot (SwiftUI's response and bounce; the face
    /// layer gets the same physics as a `CASpringAnimation`, see `EntranceSpring`).
    static let rowEnterSpring = EntranceSpring(response: 0.42, bounce: 0.25)
    /// The face's fade-in at the start of the pop (ease-out), shorter than the spring.
    static let rowEnterFadeDuration: TimeInterval = 0.14
    /// The spring counts as settled once what is left of its swing is below this fraction of the
    /// travel; the lids open then (the face arrives with closed eyes and opens them, a blink).
    static let rowEnterSettleTolerance: Double = 0.03
    /// Several rows arriving in one scan (the first launch shows every session at once) pop one
    /// after the other, top to bottom, this far apart...
    static let rowEnterStagger: TimeInterval = 0.05
    /// ...for at most this many steps (later rows pop together with the last step).
    static let rowEnterStaggerCap = 6
    /// Departure, step 1 (quieter and faster than the arrival): the face shrinks to `rowExitScale`
    /// (ease-in-out) and fades (ease-out) over this long.
    static let rowLeaveDuration: TimeInterval = 0.18
    /// A row leaves the stack shrinking to here while fading out.
    static let rowExitScale: CGFloat = 0.8
    /// Departure, step 2: then the slot closes over this long (ease-in-out), the capsule with it.
    static let rowCloseDuration: TimeInterval = 0.2
    /// While a session is ended but still in the store (eyes closed, before the row leaves): dimmed and slightly smaller.
    static let endedRowOpacity: Double = 0.5
    static let endedFaceScale: CGFloat = 0.96
    /// Press feedback on a face: scale while the mouse is down, and how long the scale takes.
    static let pressScale: CGFloat = 0.96
    static let pressDuration: TimeInterval = 0.12

    // MARK: Goo bulge (hover)

    /// Width the bulge grows to, leftward out of the capsule, at rest while expanded.
    static let bulgeWidth: CGFloat = 200
    /// Widest the bulge may ever be: `bulgeWidth` plus slack for the open spring's overshoot.
    /// The window and the goo canvas are sized with this, never larger.
    static let bulgeMaxWidth: CGFloat = bulgeWidth + 24
    /// Width of the panel content: the capsule plus the widest bulge. The SwiftUI content is always
    /// laid out at this width (right-aligned); the window only reveals more or less of it.
    static let contentWidth: CGFloat = capsuleWidth + bulgeMaxWidth
    /// The bulge is this much taller than its row at the top and the bottom.
    static let bulgePadding: CGFloat = 6
    /// The bulge never comes closer than this to the capsule body's top or bottom (between the edge
    /// fillets), except at the first and the last slot: there its outer edge is flush with the body's
    /// (one straight line, the capsule's corner absorbed), the texts move with it (`GooLayout.bulgeSpan`).
    static let bulgeEdgeMargin: CGFloat = 6
    /// Corner radius of the bulge's left corners (its own rounded ends).
    static let bulgeCornerRadius: CGFloat = 22
    /// A flush bulge edge (first or last slot) reaches the body's edge only once the blob reaches this
    /// far out of the capsule: while it opens or closes, the edge rises from the margin to flush and the
    /// capsule's corner squares off with it, so a nearly closed blob never shows a square corner
    /// (`GooLayout.flushWeights`). One corner radius, the blob's own rounded end.
    static let bulgeFlushReach: CGFloat = bulgeCornerRadius
    /// How far the bulge blob reaches into the capsule, so the threshold merges the two with concave fillets.
    static let bulgeOverlap: CGFloat = 14
    /// `.path` renderer: radius of the concave fillets where the bulge meets the capsule.
    static let bulgeFilletRadius: CGFloat = 10
    /// `.blurThreshold` renderer: Gaussian blur radius before the alpha threshold; it sets the fillet size.
    static let gooBlur: CGFloat = 10
    /// `.blurThreshold` renderer: alpha below this is cut, above becomes solid capsule colour.
    static let gooThreshold: Double = 0.5
    /// `.blurThreshold` renderer: tiny blur after the threshold that anti-aliases the hard threshold edge (0 disables it).
    static let gooEdgeSoften: CGFloat = 0.5
    /// `.blurThreshold` renderer: how far the crisp pass of the capsule's edge fillets reaches past each
    /// fillet into the body, where it overlaps the blurred body (`GooLayout.capsuleTips`).
    static let gooTipOverlap: CGFloat = 4
    /// `.blurThreshold` renderer: how far past the window the goo canvas draws (blur must never see a clipped edge).
    static let gooBleed: CGFloat = gooBlur * 2
    /// Spring of the droplets that trail the bulge between rows: much lower response than the open spring,
    /// so they fall behind far enough to show as a bump on the capsule edge, then catch up and snap into the blob.
    static let dropletSpring = Animation.spring(response: 0.85, dampingFraction: 0.8)
    /// Radius of a trailing droplet at full size. They shrink to nothing as the lag closes. Under the
    /// blur a disc only survives the threshold from about `gooBlur` on, so this is a bump on the capsule edge, not a dot.
    static let dropletRadius: CGFloat = 11
    /// A droplet reaches full size once it lags this far behind the bulge's centre.
    static let dropletFullLag: CGFloat = 30
    /// Reduce Motion: the bulge appears and disappears with a fade of this length and never travels.
    static let reduceMotionBulgeFade: TimeInterval = 0.2

    // MARK: Reveal inside the bulge (name, then status)

    /// The name starts fading in this long after the hover began (the bulge is about 60 % open by then).
    static let revealDelay: TimeInterval = 0.12
    /// When the bulge travels to another row, the new row's name waits this long instead (the blob needs
    /// longer to arrive than to open in place; the text must appear inside it).
    static let revealTravelDelay: TimeInterval = 0.22
    /// Length of the fade in of one text line (plain ease-out opacity, nothing moves).
    static let revealDuration: TimeInterval = 0.16
    /// The status line follows the name by this much.
    static let revealStagger: TimeInterval = 0.05
    /// Both lines fade out this fast on collapse, before the bulge melts.
    static let revealExitDuration: TimeInterval = 0.10
    /// `.all` expand mode: each row's reveal starts this much later than the row above.
    static let allModeStagger: TimeInterval = 0.03
    /// Space between the bulge's left edge and the text.
    static let bulgeInnerPadding: CGFloat = 12
    /// Space between the end of the text block and the capsule's left edge (so text never touches the face).
    static let bulgeTextFaceGap: CGFloat = 10
    /// Session name: one line, semibold, white.
    static let bulgeNameFont = Font.system(size: 12, weight: .semibold)
    static let bulgeNameColor = Color.white
    /// Status line (`Needs input · 2m`): regular, in the row's status colour.
    static let bulgeStatusFont = Font.system(size: 11)
    /// Idle status text is dimmed so resting rows recede.
    static let bulgeIdleStatusOpacity: Double = 0.72
    /// An external session's tool (`Codex`), after the name on the first line: small, medium weight,
    /// grey like the branch line, so it reads as a label and not as part of the name.
    static let bulgeToolFont = Font.system(size: 10, weight: .medium)
    static let bulgeToolColor = Color(white: 0.6)
    /// Space between the name and the tool label.
    static let bulgeToolGap: CGFloat = 6
    /// A tool label longer than this many characters is cut with an ellipsis (a custom `tool` in a
    /// session file can be anything); every connected agent's name fits (the longest, `OpenCode`, is 8).
    static let bulgeToolMaxCharacters = 16

    // MARK: Switches

    /// Hover behaviour: `.row` bulges only the hovered row, `.all` widens the whole capsule.
    enum ExpandMode { case row, all }
    /// Active hover behaviour (`--expand <row|all>` overrides it at launch).
    static let expandMode: ExpandMode = .row

    /// How the goo capsule is drawn: blur + alpha threshold (default), a plain path, or a Metal SDF shader.
    enum GooRenderer { case blurThreshold, path, sdfShader }
    /// Active goo renderer (`--goo <blurThreshold|path>` overrides it at launch).
    /// `.sdfShader` needs Xcode for the Metal shader and falls back to `.path` for now.
    static let gooRenderer: GooRenderer = .blurThreshold

    /// Which face style the panel draws: the Y2K dot-matrix eyes on a glossy disc, or the flat
    /// blob (one coloured body shape with two capsule eyes cut into it). `--face-style` overrides it
    /// at launch, the playground at runtime.
    static let faceStyle: FaceStyle = .blob

    /// Screen filter laid over every face, whatever the style (`--face-filter`, playground toggle).
    static let faceFilter: FaceFilter = .none

    /// Whether the dot grid (LED look) is active: the dot-matrix screen filter. Kept for the
    /// code that only ever asked this question.
    static var dotMatrix: Bool { faceFilter == .dotMatrix }

    /// Blob style: what the body silhouette means. `.status`: the shape is the status (drop for
    /// needs input, cloud for working, capsule for your turn, idle and just finished, a flattened capsule for
    /// ended) and identity is a subtle eye delta only. `.identity`: one silhouette per seed, as briefed.
    enum BlobShapeMode { case status, identity }
    /// Active blob shape meaning (`--blob-shape <status|identity>` overrides it at launch).
    static let blobShapeMode: BlobShapeMode = .status

    /// What the body (or eye) colour means. `.status`: the colour is the status (amber, cyan, the lime
    /// of your turn, warm grey for idle, the mint flash, grey) and identity is the shape preset only.
    /// `.identity`: the seeded palette colour. `.project`: the project colour (`ProjectColor`, by project
    /// key, so every session of one repo shares a hue) while the shape still carries the status; idle is
    /// the project colour dimmed, ended grey. Two signal colours hold in every mode, so the faces that
    /// want the person stand out from the working ones: needs input is amber (loudest: an action is
    /// required) and your turn is `yourTurnColor` (louder than working, below amber), each with its halo
    /// and edge cue. Just finished flashes mint in `.status` and `.project` mode and eases into the lime.
    enum ColorMode: String, CaseIterable, Sendable {
        case status, identity, project

        /// The next mode when cycling in the playground.
        var next: ColorMode {
            let all = Self.allCases
            return all[(all.firstIndex(of: self)! + 1) % all.count]
        }
    }
    /// Active colour meaning (`--color-mode <status|identity|project>` overrides it at launch).
    static let colorMode: ColorMode = .project
    /// `.project` mode, idle: the project colour mixed this far toward black (0 = unchanged, 1 = black).
    /// A darker body reads as "resting" on the black capsule; a translucent one would just look faded.
    static let projectIdleDim: Double = 0.6

    /// Needs input look: `.eyes` = amber surprised/awe eyes looking at you (default),
    /// `.exclamation` = both eyes become "!" (parked: blinks and pulses only, no motion yet).
    enum NeedsInputStyle { case eyes, exclamation }
    /// Active needs input look.
    static let needsInputStyle: NeedsInputStyle = .eyes

    // MARK: Eye geometry (fractions of the face size, so 44 pt and 120 pt faces look the same)

    /// Horizontal distance between the two eye centres, as a fraction of the face size.
    static let eyeSpacing: Double = 0.36
    /// Vertical position of the eye centres above the face centre (positive = higher).
    static let eyeVerticalOffset: Double = 0.0
    /// Height of a closed eye (the "line" a blink or an ended session shows).
    static let closedEyeHeight: Double = 0.045
    /// Deepest allowed inverse (concave) bite, as a fraction of the eye height. Keeps the arc inside the shape.
    static let maxInverseDepth: Double = 0.85
    /// Gaze offset for "needs input": looks left, toward the screen and the person. Fraction of the face size.
    static let needsInputGaze = GazeOffset(x: -0.055, y: 0.0)
    /// How far the eyes glance sideways while working (dart amplitude), fraction of the face size.
    static let dartAmplitude: Double = 0.05

    // MARK: Exclamation eyes (needs input): each eye becomes a "!"

    /// Width of the exclamation bar, fraction of the face size.
    static let exclamationBarWidth: Double = 0.12
    /// Height of the exclamation bar.
    static let exclamationBarHeight: Double = 0.42
    /// How far the bar's centre sits above the eye centre, so the whole "!" (bar plus dot) stays centred.
    static let exclamationBarRaise: Double = 0.07
    /// Diameter of the dot below the bar.
    static let exclamationDotDiameter: Double = 0.12
    /// Gap between the bar's bottom end and the dot.
    static let exclamationDotGap: Double = 0.06
    /// Scale of the hidden dot (it springs from here to 1 when needs input starts).
    static let exclamationDotHiddenScale: Double = 0.6
    /// The dot enters this long after the bar started its spring.
    static let exclamationDotStagger: TimeInterval = 0.08
    /// The dot leaves faster than it came in.
    static let exclamationDotExitDuration: TimeInterval = 0.16

    // MARK: Eye palette

    /// Identity colours (`.identity` mode), picked per session seed. Amber is deliberately absent: it only ever means "needs input".
    static let eyePalette: [EyeColor] = [
        EyeColor(name: "mint", red: 0.50, green: 0.97, blue: 0.78),
        EyeColor(name: "cyan", red: 0.40, green: 0.86, blue: 1.00),
        EyeColor(name: "lilac", red: 0.80, green: 0.68, blue: 1.00),
        EyeColor(name: "white", red: 0.94, green: 0.96, blue: 1.00),
    ]
    /// The one colour reserved for "needs input".
    static let needsInputColor = EyeColor(name: "amber", red: 1.00, green: 0.70, blue: 0.25)
    /// Status palette (`.status` mode). Working: electric cyan.
    static let workingColor = EyeColor(name: "electric cyan", red: 0.30, green: 0.84, blue: 1.00)
    /// Idle: a muted warm grey (the soft white's hue at a lower value), so parked faces recede.
    static let idleColor = EyeColor(name: "muted warm grey", red: 0.60, green: 0.59, blue: 0.55)
    /// Just finished: mint green flash, then on to the your-turn mint.
    static let justFinishedColor = EyeColor(name: "mint flash", red: 0.45, green: 1.00, blue: 0.72)
    /// Your turn, in every colour mode: a vivid lime "go" green (hue about 88 degrees), the one signal
    /// besides amber. It pops on black, sits well clear of amber (36 degrees, needs input), of the
    /// working cyan and of every project colour (`projectPalette` keeps out of 20 to 140 degrees), and is
    /// yellower and more saturated than the mint flash it follows, so the done moment eases into it.
    static let yourTurnColor = EyeColor(name: "your turn lime", red: 0.62, green: 1.00, blue: 0.20)
    /// Ended: dim grey line.
    static let endedColor = EyeColor(name: "dim grey", red: 0.42, green: 0.43, blue: 0.45)
    /// Duration of a colour change (fill and glow), seconds.
    static let colorChangeDuration: TimeInterval = 0.35

    // MARK: Dot grid (the LED mask)

    /// Distance between dot centres in device pixels at the reference face size. Scales with the face size.
    static let dotPitchPixels: Double = 2.5
    /// Dot diameter in device pixels at the reference face size. Scales with the face size.
    static let dotDiameterPixels: Double = 1.7
    /// On a 1x display the 2x grid would be sub-pixel, so a coarser grid is used there.
    static let dotPitchPixelsLowDPI: Double = 2.0
    static let dotDiameterPixelsLowDPI: Double = 1.4
    /// Face size the pixel values above refer to (the 40 pt face the grid was tuned on). Larger faces scale the grid up so the dot count per eye stays the same.
    static let dotReferenceSize: CGFloat = 40

    /// Dot pitch and diameter in device pixels for a face of `size` on a display of `scale`.
    static func dotGrid(size: CGFloat, scale: CGFloat) -> (pitch: Double, diameter: Double) {
        let factor = Double(size / dotReferenceSize)
        if scale < 1.5 {
            return (dotPitchPixelsLowDPI * factor, dotDiameterPixelsLowDPI * factor)
        }
        return (dotPitchPixels * factor, dotDiameterPixels * factor)
    }

    // MARK: Glow

    /// Blur radius of the glow as a fraction of the face size (5.5 pt at a 44 pt face).
    static let glowRadiusFraction: Double = 0.125
    /// Opacity of the glow at rest (needs input, working, just finished).
    static let glowOpacity: Float = 1.0
    /// Glow of an idle face: dimmer, so resting faces recede. Your turn glows at `glowOpacity`.
    static let idleGlowOpacity: Float = 0.3
    /// Glow of an ended face: almost none.
    static let endedGlowOpacity: Float = 0.25
    /// Opacity of the solid light bleed drawn under the dots (fills the gaps faintly so the block reads as lit).
    static let glowBleedOpacity: Float = 0.38
    /// Needs-input pulse: glow opacity and radius swing between the rest values and these.
    static let pulseGlowOpacity: Float = 0.45
    static let pulseGlowRadiusFactor: Double = 0.6
    /// Needs-input pulse: eye brightness at the dim end of the swing.
    static let pulseEyeOpacity: Float = 0.80
    /// One half of the pulse (dim or brighten), seconds. The full cycle is twice this.
    static let pulseHalfDuration: TimeInterval = 1.4

    // MARK: Loop timings (seconds)

    /// Idle blink interval range; the seed picks a value in it.
    static let idleBlinkInterval: ClosedRange<Double> = 6 ... 10
    /// Idle: every n-th blink is a double blink.
    static let idleDoubleBlinkEvery = 3
    /// Needs-input blink interval range (a little livelier, with a double blink every second cycle).
    static let needsInputBlinkInterval: ClosedRange<Double> = 5 ... 8
    static let needsInputDoubleBlinkEvery = 2
    /// Sleepy blink interval range (slow).
    static let sleepyBlinkInterval: ClosedRange<Double> = 9 ... 14
    /// Time the lid takes to close or open in a blink.
    static let blinkEdgeDuration: TimeInterval = 0.06
    /// How long the eye stays closed in the middle of a blink.
    static let blinkHoldDuration: TimeInterval = 0.03
    /// Gap between the two blinks of a double blink.
    static let doubleBlinkGap: TimeInterval = 0.14
    /// Transition time between the working expressions (focused to squint and back).
    static let varietyTransitionDuration: TimeInterval = 0.4
    /// How long an alternative working expression (squint, skeptic) holds before focused returns.
    static let varietyHoldDuration: TimeInterval = 2.2
    /// Working: how long focused holds between two alternative poses; the seed picks a value in the range.
    static let workingPoseInterval: ClosedRange<Double> = 6 ... 9
    /// Working dart: time between glances (seeded in this range), the hold at the side, and the glance movement itself.
    static let dartInterval: ClosedRange<Double> = 2 ... 3.5
    static let dartHold: TimeInterval = 0.9
    static let dartMove: TimeInterval = 0.22
    /// Working: slow vertical "reading" scan, amplitude (fraction of the face size) and period.
    static let scanAmplitude: Double = 0.02
    static let scanPeriod: TimeInterval = 5.2
    /// Working: "thinking" scale breath of the eyes, peak scale and period.
    static let workingBreathScale: Double = 1.04
    static let workingBreathPeriod: TimeInterval = 2.4
    /// Idle: slow drifting gaze wander over a tiny ellipse (radii as fractions of the face size) and its period.
    static let wanderRadiusX: Double = 0.025
    static let wanderRadiusY: Double = 0.015
    static let wanderPeriod: TimeInterval = 9
    /// Idle: very slow breathing scale, peak scale and period.
    static let idleBreathScale: Double = 1.02
    static let idleBreathPeriod: TimeInterval = 4
    /// Idle: a tiny mood flicker (normal to happy or skeptic and back) every so often (seeded in the range) for this long.
    static let idleMoodInterval: ClosedRange<Double> = 20 ... 30
    static let idleMoodHold: TimeInterval = 1.0
    static let idleMoodTransitionDuration: TimeInterval = 0.3
    /// Idle drifts to sleepy after this long in idle. At least `yourTurnFor`, so a face never goes
    /// sleepy while it is still your turn.
    static let sleepyAfter: TimeInterval = 30 * 60
    /// Duration of the drift from normal to sleepy.
    static let sleepyDriftDuration: TimeInterval = 1.8
    /// How long the glee eyes hold after a session finished before the idle look returns. The mint
    /// colour and the halo hold longer (`doneHold`).
    static let justFinishedHold: TimeInterval = 2.0
    /// The finished bounce on scale: keyframes and total duration.
    static let bounceScales: [Double] = [0.9, 1.08, 1.0]
    static let bounceDuration: TimeInterval = 0.45
    /// Reduce Motion: pose changes become a crossfade of this length.
    static let reduceMotionFadeDuration: TimeInterval = 0.2

    // MARK: Springs (Core Animation, for the eye paths and gaze)

    /// Pose change spring: visible overshoot that settles within about 0.6 s.
    static let poseSpringMass: Double = 1.0
    static let poseSpringStiffness: Double = 320
    static let poseSpringDamping: Double = 19
    /// Gaze change spring: slightly softer than the pose spring.
    static let gazeSpringMass: Double = 1.0
    static let gazeSpringStiffness: Double = 220
    static let gazeSpringDamping: Double = 16

    // MARK: Face gloss

    /// Width of the inner shadow ring that makes the face read as a slightly recessed screen.
    static let discInnerShadowWidth: CGFloat = 3
    static let discInnerShadowColor = Color.black.opacity(0.55)

    // MARK: Blob style: body (fractions of the face size)

    /// Radius of the round silhouette: the blob fills 0.86 of the cell. Every other silhouette is
    /// built around this value and stays inside the cell.
    static let blobRadius: Double = 0.43
    /// Radius of the imaginary sphere the eyes sit on. Equal to the body radius, so eyes projected
    /// near the rim meet the silhouette and get clipped by it.
    static let blobSphereRadius: Double = 0.43
    /// How much the eye positions follow the body's local radius on non-round silhouettes
    /// (0 = eyes placed as on a sphere, 1 = fully scaled to the outline).
    static let blobEdgeFollow: Double = 0.55
    /// Catmull-Rom tension of the silhouette curve (1 = classic Catmull-Rom; lower is tighter).
    static let blobCurveTension: Double = 1.0
    /// Ended: the capsule flattens toward a line while the eyes close (vertical scale of the radii).
    static let blobEndedSquash: Double = 0.42
    /// Sleepy: the body sags a little (vertical scale of the radii).
    static let blobSleepySquash: Double = 0.97
    /// A body morph (shape change on a status or identity change), ease-out, no overshoot.
    static let blobMorphDuration: TimeInterval = 0.30
    /// Needs input on the drop silhouette (tip up: the shape that reads most like "attention" at 44 pt).
    static let blobNeedsInputShape: BlobShape = .drop
    static let blobWorkingShape: BlobShape = .cloud
    static let blobIdleShape: BlobShape = .pill

    // MARK: Blob style: eyes

    /// Eye colour: near black. The capsule is a dark hole in the body either way.
    static let blobEyeColor = EyeColor(name: "ink", red: 0.06, green: 0.06, blue: 0.07)
    /// Height of a closed eye as a fraction of its open height (the sliver a blink leaves).
    static let blobClosedLid: Double = 0.12
    /// Blink timing: a quick close, a short hold, a slower open (170 ms in all).
    static let blobBlinkClose: TimeInterval = 0.06
    static let blobBlinkHold: TimeInterval = 0.03
    static let blobBlinkOpen: TimeInterval = 0.08
    /// Sampling step of the pose-of-time loops before they become keyframes.
    static let blobSampleStep: TimeInterval = 0.1
    /// Identity in `.status` shape mode: per-seed eye tilt and spacing deltas (degrees), so faces are not clones.
    static let blobIdentityTiltRange: ClosedRange<Double> = -4 ... 4
    static let blobIdentitySplitRange: ClosedRange<Double> = -3 ... 3

    // MARK: Blob style: status motion

    /// Needs input: gaze toward the screen (negative yaw looks left), degrees.
    static let blobNeedsInputYaw: Double = -13
    static let blobNeedsInputPitch: Double = 2
    /// Needs input: soft body scale pulse 1.0 to 1.04, one way in 1.4 s.
    static let blobNeedsInputPulse = BreathLoop(scale: 1.04, period: 2.8)
    /// Working: body breath 1.0 to 1.02.
    static let blobWorkingBreath = BreathLoop(scale: 1.02, period: 3.6)
    /// Working: the gaze drifts on a slow loop of targets (seconds, yaw, pitch); each move eases out over `blobGazeMoveDuration`.
    static let blobWorkingGazeTargets: [(time: Double, yaw: Double, pitch: Double)] = [
        (0, 0, 0), (2.4, -11, 7), (5.6, 10, -1), (8.6, 0, 0),
    ]
    static let blobWorkingLoopDuration: TimeInterval = 11.0
    static let blobGazeMoveDuration: TimeInterval = 0.6
    /// Working: one blink per loop, at the return to centre.
    static let blobWorkingBlinkTime: TimeInterval = 8.6
    /// Idle: gaze wander on a tiny figure of eight (degrees) and its period.
    static let blobWanderYaw: Double = 3.0
    static let blobWanderPitch: Double = 1.6
    static let blobWanderPeriod: TimeInterval = 9
    /// Idle: every n-th blink is a double blink; the loop spans this many blink intervals.
    static let blobIdleLoopBlinks = 3
    /// Sleepy drift (normal to sleepy eyes and the sag), ease-out.
    static let blobSleepyDriftDuration: TimeInterval = 1.8
    /// Just finished: one soft scale bounce 1.0 to `blobBounceScale` and back, ease-out.
    static let blobBounceScale: Double = 1.06
    static let blobBounceDuration: TimeInterval = 0.5

    // MARK: Blob palette (`.identity` colour mode): eight body colours, none amber, none lime

    /// Seafoam replaced a sage at 105 degrees that sat on the hue of the your-turn lime (88 degrees)
    /// and read as a duller copy of it beside a your-turn face.
    static let blobPalette: [EyeColor] = [
        EyeColor(name: "coral", red: 0.96, green: 0.47, blue: 0.42),
        EyeColor(name: "rose", red: 0.93, green: 0.52, blue: 0.72),
        EyeColor(name: "lavender", red: 0.70, green: 0.62, blue: 0.95),
        EyeColor(name: "sky", red: 0.47, green: 0.71, blue: 0.98),
        EyeColor(name: "teal", red: 0.28, green: 0.78, blue: 0.74),
        EyeColor(name: "seafoam", red: 0.52, green: 0.82, blue: 0.64),
        EyeColor(name: "cream", red: 0.93, green: 0.90, blue: 0.82),
        EyeColor(name: "slate", red: 0.63, green: 0.67, blue: 0.73),
    ]

    // MARK: Screen filters (device pixels at the reference face size, scaled like the dot grid)

    /// ASCII grid: cell pitch, glyph size relative to the pitch, the glyph set (dense first) and
    /// how strongly dense glyphs are favoured (1 = uniform, higher = denser).
    static let asciiCellPixels: Double = 3.4
    static let asciiGlyphScale: Double = 1.25
    static let asciiGlyphs: [Character] = ["@", "#", "%", "&", "8", "*", "+", "=", ";", ":", "-", "."]
    static let asciiDensityBias: Double = 1.7
    /// Floor opacity between the glyphs, so the silhouette stays readable at 44 pt.
    static let asciiFloorOpacity: Double = 0.18
    /// Halftone: dot pitch of the 45 degree screen, dot radius (as a fraction of the pitch) at the
    /// face centre and at the rim. Centre dots overlap into a solid, rim dots thin out.
    static let halftonePitchPixels: Double = 4.4
    static let halftoneCentreRadius: Double = 0.66
    static let halftoneRimRadius: Double = 0.26
    /// Scanlines: line pitch and the lit fraction of it (2 px on, 1 px off at the reference size), gap opacity.
    static let scanlinePitchPixels: Double = 3.0
    static let scanlineOnFraction: Double = 2.0 / 3.0
    static let scanlineGapOpacity: Double = 0.3
    /// Pixel factor for every filter: the grid scales with the face so the cell count stays the same
    /// at 44 pt and 120 pt; a 1x display gets a coarser grid.
    static func filterPixelFactor(size: CGFloat, scale: CGFloat) -> Double {
        Double(size / dotReferenceSize) * (scale < 1.5 ? 0.8 : 1.0)
    }

    // MARK: Blob style: working substates (what a working session is doing)

    /// Every substate runs a little faster or slower per seed, so working faces never move in step.
    static let blobActivityTempo: ClosedRange<Double> = 0.85 ... 1.15
    /// Coding: the eyes narrow to this fraction of the focused height (concentration, not a squint).
    static let blobCodingEyeHeightScale: Double = 0.78
    /// Coding: the gaze steps from the left end to the right end of a typed line (degrees of yaw), level
    /// (running looks down; the line being typed is in front of the eyes).
    static let blobCodingYawRange: ClosedRange<Double> = -9 ... 9
    static let blobCodingPitch: Double = 1
    /// Coding: steps per line, the time the steps span, how long one step takes (ease-out).
    static let blobCodingSteps = 5
    static let blobCodingLineDuration: TimeInterval = 1.6
    static let blobCodingStepMove: TimeInterval = 0.12
    /// Coding: the quick return to the line start (with a blink), and the pause before the next line.
    static let blobCodingReturnDuration: TimeInterval = 0.2
    static let blobCodingLoopDuration: TimeInterval = 2.4
    /// Running: the eyes flick down-left and hold there, watching the output (degrees).
    static let blobRunningYaw: Double = -10
    static let blobRunningPitch: Double = -8
    /// Running: once per loop the gaze glances back to centre for `blobRunningGlanceHold`, then drops again with a blink.
    static let blobRunningLoopDuration: TimeInterval = 5.6
    static let blobRunningGlanceTime: TimeInterval = 4.4
    static let blobRunningGlanceHold: TimeInterval = 0.5
    /// Running: the eye pair pulses to this opacity and back every period, like a terminal cursor (no colour change).
    static let blobRunningEyePulse = BlobEyePulse(low: 0.7, period: 0.8)
    /// Reading: two lines are read left to right (yaw range), the first line higher than the second (pitch).
    static let blobReadingYawRange: ClosedRange<Double> = -11 ... 11
    static let blobReadingLinePitch: ClosedRange<Double> = -4 ... 4
    /// Reading: one sweep, the drop to the next line, the hold at the end and the return to the top (with a blink); 3.2 s in all.
    static let blobReadingSweepDuration: TimeInterval = 1.1
    static let blobReadingLineDropDuration: TimeInterval = 0.2
    static let blobReadingEndHold: TimeInterval = 0.25
    static let blobReadingReturnDuration: TimeInterval = 0.4
    static let blobReadingPeriod: TimeInterval = 3.2
    /// Delegating: the eyes look up and sit a little further apart (degrees), calm.
    static let blobDelegatingPitch: Double = 9
    static let blobDelegatingSplitDelta: Double = 4
    /// Delegating: slow blinks, every so often (seeded), each this many times slower than a normal blink.
    static let blobDelegatingBlinkInterval: ClosedRange<Double> = 4 ... 6
    static let blobDelegatingBlinkScale: Double = 2.6

    // MARK: Subagent satellites (small blobs orbiting a working face)

    /// Satellites shown at most; more subagents are capped here.
    static let satelliteMax = 4
    /// Diameter of a satellite as a fraction of the face size (6.6 pt at a 44 pt face).
    static let satelliteSize: Double = 0.15
    /// Horizontal radius of the orbit ellipse, fraction of the face size. With the satellite's own radius
    /// the farthest point is 0.675 of the face (29.7 pt): inside the 8 pt of capsule black beside a 44 pt face.
    static let satelliteOrbitRadius: Double = 0.60
    /// Vertical radius as a fraction of the horizontal one (the orbit is seen at an angle): 0.585 of the
    /// face with the satellite (25.7 pt) stays inside the row pitch band, and the lower satellites clear the cloud's rim.
    static let satelliteOrbitAspect: Double = 0.85
    /// One revolution, seconds.
    static let satelliteOrbitPeriod: TimeInterval = 6
    /// Satellite opacity (same colour as the body).
    static let satelliteOpacity: Float = 0.85
    /// A slight vertical bob on top of the orbit: amplitude (fraction of the face size) and period.
    static let satelliteBobAmplitude: Double = 0.02
    static let satelliteBobPeriod: TimeInterval = 1.9
    /// A satellite appears scaling up from `satelliteEnterScale` while fading in, ease-out; leaves with a fade.
    static let satelliteEnterDuration: TimeInterval = 0.25
    static let satelliteEnterScale: Double = 0.6
    static let satelliteExitDuration: TimeInterval = 0.16
    /// Two tiny ink dots as eyes on each satellite (diameter and centre spacing as fractions of the satellite size).
    static let satelliteEyes = true
    static let satelliteEyeDiameter: Double = 0.2
    static let satelliteEyeSpacing: Double = 0.36
    static let satelliteEyeLift: Double = 0.08

    // MARK: Attention hop (a session starts waiting for the person)

    /// The whole face hops up by this fraction of its size and lands again.
    static let hopHeight: Double = 0.12
    /// Total time of the hop; the way up takes `hopUpFraction` of it (ease-out), the way down the rest (ease-in-out).
    static let hopDuration: TimeInterval = 0.42
    static let hopUpFraction: Double = 0.42
    /// A tiny squash on landing (scale x and y), reached and released within `hopSquashDuration`.
    static let hopSquashScaleX: Double = 1.04
    static let hopSquashScaleY: Double = 0.96
    static let hopSquashDuration: TimeInterval = 0.08
    /// Play a sound with the hop (the system sound `attentionSoundName`, else the beep).
    static let attentionSound = false
    static let attentionSoundName = "Tink"

    // MARK: Excited (the person's message arrived)

    /// A session that was resting or waiting (idle, sleepy, your turn, just finished, needs input)
    /// starts working: the person's message arrived. The face perks up once, after the blink that
    /// hides the state change, in `excitedDuration`: the eyes widen to `excitedEyeScale` and look at
    /// the person, the body hops twice and wiggles, and brightens toward white by `excitedBrighten`.
    /// Then the working loops start where the reaction ends. Core Animation one-shots only; nothing
    /// under Reduce Motion.
    static let excitedDuration: TimeInterval = 0.62
    /// The first hop lifts the face by this fraction of its size (3.5 pt at 44 pt) over
    /// `excitedHopDuration`, up for `excitedHopUpFraction` of it (ease-out), down the rest (ease-in);
    /// the second, right after it, is `excitedSecondHop` as high and `excitedSecondHopTime` as long.
    static let excitedHopHeight: Double = 3.5 / 44
    static let excitedHopDuration: TimeInterval = 0.22
    static let excitedHopUpFraction: Double = 0.42
    static let excitedSecondHop: Double = 0.6
    static let excitedSecondHopTime: Double = 0.8
    /// A tiny squash after the second landing (scale x and y), within `excitedSquashDuration`.
    static let excitedSquashScaleX: Double = 1.04
    static let excitedSquashScaleY: Double = 0.96
    static let excitedSquashDuration: TimeInterval = 0.1
    /// The wiggle while it hops: the body tilts this far (radians, about 6 degrees) one way, the other
    /// way, half as far back, and settles, over the two hops.
    static let excitedWiggleAngle: Double = 6 * .pi / 180
    /// The eyes open this much taller (and `excitedEyeWiden` wider) and look at the person, within
    /// `excitedEyeOpen`; they hold until `excitedEyeRelease` before the end, then ease back to the working pose.
    static let excitedEyeScale: Double = 1.3
    static let excitedEyeWiden: Double = 1.1
    static let excitedEyeOpen: TimeInterval = 0.09
    static let excitedEyeRelease: TimeInterval = 0.22
    /// The body colour brightens toward white by this much, fullest after `excitedBrightPeak`, then
    /// eases back to the working colour by the end.
    static let excitedBrighten: Double = 0.4
    static let excitedBrightPeak: TimeInterval = 0.12

    // MARK: Attention grow (while a session keeps waiting)

    /// Every `attentionGrowInterval` the waiting body grows to `attentionGrowScale` and back within
    /// `attentionGrowDuration` (ease-out up for `attentionGrowUpFraction` of it, ease-in-out down),
    /// as a Core Animation loop next to the pulse; the phase is seeded so two waiting faces never sync.
    /// Reduce Motion: no grow loop.
    static let attentionGrowScale: Double = 1.12
    static let attentionGrowDuration: TimeInterval = 0.6
    static let attentionGrowInterval: TimeInterval = 3
    static let attentionGrowUpFraction: Double = 0.4
    static let attentionGrow = AttentionGrow(
        scale: attentionGrowScale, duration: attentionGrowDuration, interval: attentionGrowInterval, upFraction: attentionGrowUpFraction
    )
    /// A permission prompt is more urgent than a question: the body pulse runs faster and the grow comes every 2 s.
    static let permissionPulsePeriod: TimeInterval = 0.9
    static let permissionGrowInterval: TimeInterval = 2
    static let permissionPulse = BreathLoop(scale: blobNeedsInputPulse.scale, period: permissionPulsePeriod)
    static let permissionGrow = AttentionGrow(
        scale: attentionGrowScale, duration: attentionGrowDuration, interval: permissionGrowInterval, upFraction: attentionGrowUpFraction
    )
    /// A waiting face is a notch bigger at rest (the scaler's model scale; pulse and grow add to it).
    static let attentionScale: Double = 1.08

    // MARK: Attention halo (a soft glow behind a waiting face, and behind a finished one)

    /// The glow stays this far inside the capsule's side, so no halo ever lights the desktop.
    static let haloCapsuleInset: CGFloat = 2
    /// Outermost extent of the glow, in points at the panel face size: half the row pitch (the glow is
    /// spent at the row boundary, so two lit rows keep a dark gap) or the capsule's half width less
    /// `haloCapsuleInset`, whichever is smaller (26 pt today). The halo is not magnified.
    static let haloOuterRadius: CGFloat = min(rowPitch / 2, capsuleWidth / 2 - haloCapsuleInset)
    /// The glow is the body's silhouette (at its rest scale) scaled up by this much around the centre,
    /// filled with the halo colour and softened at the rim (`BlobHalo`). Where the scaled outline would
    /// carry the glow past `haloOuterRadius` (the long sides of the pill, the round), it is held at
    /// `BlobHalo.fillCap` instead, so the softened rim is spent at the outer radius.
    static let haloScale: Double = 1.22
    /// Softness of the glow's rim: the Gaussian sigma of its shadow (Core Animation's `shadowRadius` is
    /// the sigma, measured), as a fraction of the face size (2 pt at 44 pt: the old disc's fall from 0.9 to
    /// 0.09 over about 5 pt).
    static let haloSoftness: Double = 2.0 / 44
    /// The rim counts as spent this many sigmas beyond the fill's edge (2 % alpha left).
    static let haloTailSigmas: Double = 2
    /// Peak opacity of the amber halo, reached at the top of every grow; between grows it rests at
    /// `attentionHaloRestFraction` of the peak, so the row is lit the whole time. The loudest glow in the
    /// panel: its peak and its rest stay above the your-turn halo's (`yourTurnHaloOpacity`).
    static let attentionHaloOpacity: Double = 0.85
    static let attentionHaloRestFraction: Double = 0.65
    /// A breathing halo (done, your turn) swings from this fraction of its peak opacity up to the peak
    /// and back (the breath's `BreathLoop.scale`). 0.3 left the glow invisible at the bottom of the
    /// breath on coral and purple project colours (snapshots); 0.4 still reads there.
    static let haloBreathLow: Double = 0.4
    /// With each your-turn hop the glow swells to this scale around the centre and back: up while the
    /// face is in the air, at its fullest on the landing squash, back over `haloHopSwellRelease`.
    static let haloHopSwell: Double = 1.06
    static let haloHopSwellRelease: TimeInterval = 0.3
    /// The halo fades in and out in this long when a state starts or ends.
    static let haloFadeDuration: TimeInterval = 0.4

    // MARK: Done (a session just finished)

    /// The mint colour and the halo hold this long after a session finished before easing into your
    /// turn (`DataTuning.justFinishedDuration` is the matching data constant).
    static let doneHold: TimeInterval = 8
    /// The done halo: mint, this opacity at the peak, breathing from `haloBreathLow` of it to the peak
    /// and back (one way in half the period).
    static let doneHaloOpacity: Double = 0.6
    static let doneHaloPulse = BreathLoop(scale: haloBreathLow, period: 1.8)
    /// One-shot burst of tiny dots flying outward from the face as it finishes: count, how far they
    /// fly (fraction of the face size), their diameter, how long, and the scale they shrink to.
    static let doneBurstCount = 6
    static let doneBurstDistance: Double = 0.7
    static let doneBurstDotSize: Double = 0.09
    static let doneBurstDuration: TimeInterval = 0.6
    static let doneBurstEndScale: Double = 0.3
    /// The dots leave once the lids have closed on the old look (the blink that hides the state change).
    static let doneBurstDelay: TimeInterval = blobBlinkClose + blobBlinkHold
    /// The dots start this far from the centre (just inside the rim, so they emerge from behind the body).
    static let doneBurstStart: Double = 0.3

    // MARK: Your turn (an idle session waiting for the next instruction)

    /// How long a fresh idle period counts as your turn (unless the person opened the chat first).
    /// After it the session is plain idle. `sleepyAfter` is at least this long.
    static let yourTurnFor: TimeInterval = 15 * 60
    /// The your-turn halo: `yourTurnColor`, this opacity at the peak (above the done halo, clearly below
    /// amber's `attentionHaloOpacity`), breathing on `yourTurnHaloPulse`. The same breath as the done
    /// halo, so the 8 s done moment eases into your turn without restarting the loop.
    static let yourTurnHaloOpacity: Double = 0.65
    static let yourTurnHaloPulse: BreathLoop = doneHaloPulse
    /// The capsule edge cue of a your-turn row: `yourTurnColor` at this opacity at the top of its
    /// breath (lower than amber's `attentionEdgeOpacity`, and it dips further), breathing with the halo.
    static let yourTurnEdgeOpacity: Double = 0.9
    /// The done moment easing into your turn: the eyes glide to the your-turn gaze in this long
    /// (no blink: the shape stays the pill), colour and halo cross-fade alongside.
    static let yourTurnGlideDuration: TimeInterval = 0.45
    /// Your turn in `.status` shape mode: the body swaps between these two silhouettes on a loop
    /// (`BlobShapeSwap`). The first is the body at rest and should stay `blobIdleShape`, so the done
    /// moment glides in without a blink; neither is the needs-input drop.
    static let yourTurnShapes: (BlobShape, BlobShape) = (.pill, .round)
    /// Each silhouette holds this long, then the body morphs to the other in `yourTurnSwapDuration`
    /// (ease-in-out). One cycle is 3.5 s; each face starts it after a seeded fraction of a cycle.
    static let yourTurnSwapHold: TimeInterval = 1.4
    static let yourTurnSwapDuration: TimeInterval = 0.35
    /// With every swap the face hops this fraction of its size (3 pt at 44 pt): up for
    /// `yourTurnBounceUpFraction` of `yourTurnBounceDuration` (ease-out), down for the rest (ease-in),
    /// then a tiny squash (`yourTurnSquashScaleX` / `Y`) within `yourTurnSquashDuration`. In
    /// `.identity` shape mode only the hop plays. Under Reduce Motion neither, and a hovered face rests.
    static let yourTurnBounceHeight: Double = 3.0 / 44
    static let yourTurnBounceDuration: TimeInterval = 0.32
    static let yourTurnBounceUpFraction: Double = 0.45
    static let yourTurnSquashScaleX: Double = 1.03
    static let yourTurnSquashScaleY: Double = 0.97
    static let yourTurnSquashDuration: TimeInterval = 0.1
    /// A paused or ended swap eases from what is on screen back to the resting body in this long.
    static let yourTurnSettleDuration: TimeInterval = 0.25

    // MARK: Capsule edge cue (a thin amber line beside a waiting row)

    /// Width of the line along the capsule's left edge, its length (fraction of the row pitch) and its
    /// opacity at the top of the pulse; it pulses with the row's halo and rests at
    /// `attentionEdgeRestFraction` of the peak, higher than the your-turn cue ever dips, so the amber
    /// line stays the louder one through the whole loop.
    static let attentionEdgeWidth: CGFloat = 2
    static let attentionEdgeLengthFraction: CGFloat = 0.62
    static let attentionEdgeOpacity: Double = 1
    static let attentionEdgeRestFraction: Double = 0.7
    /// Inset of the line from the capsule's left edge (0 = flush with the edge).
    static let attentionEdgeInset: CGFloat = 0

    // MARK: Hover effect

    /// What a hover does to the faces. `.magnify`: Dock-style magnification, every face scales with a
    /// smooth falloff of its distance to the pointer and drifts toward it a little. `.stretch`: the
    /// genie stretch of the hovered face toward the bulge. `.none`: faces stay put (the bulge still opens).
    enum HoverEffect: String, CaseIterable, Sendable {
        case magnify, stretch, none

        /// The next effect when cycling in the playground.
        var next: HoverEffect {
            let all = Self.allCases
            return all[(all.firstIndex(of: self)! + 1) % all.count]
        }
    }
    /// Active hover effect (`--hover-effect <magnify|stretch|none>` overrides it at launch, the playground at runtime).
    static let hoverEffect: HoverEffect = .magnify

    // MARK: Magnification (hover, `.magnify`)

    /// Scale of the face right under the pointer. The falloff is a Gaussian of the pointer's distance
    /// to the face centre: `1 + (magnifyMax - 1) * exp(-(d / magnifySpread)^2)`, so neighbours grow a
    /// little and the rest stay at 1. The row pitch never changes; magnified faces overlap the black.
    static let magnifyMax: CGFloat = 1.28
    /// Width of the falloff, in points along the column (about 1.1 row pitches at panel size).
    static let magnifySpread: CGFloat = 1.1 * rowPitch
    /// Widest a magnified face may get: the capsule width minus this margin on both sides together.
    static let magnifyMargin: CGFloat = 2
    /// Follow: a face drifts toward the pointer by up to this much horizontally and vertically (at
    /// the panel face size; larger faces scale it), weighted by the same falloff, so the column leans
    /// toward the cursor and relaxes when it leaves.
    static let followX: CGFloat = 3
    static let followY: CGFloat = 3
    /// Pointer moves arrive as events: each one sets new model values and Core Animation eases the
    /// layer there over this long (ease-out), so the magnification glides between events.
    static let magnifyFollowDuration: TimeInterval = 0.12
    /// When the pointer leaves, every face eases back to 1 and zero offset over this long.
    static let magnifyReleaseDuration: TimeInterval = 0.25

    /// Least clear space between two faces' bodies, and between a body and the divider line or the
    /// capsule's end, under magnification and at the top of a grow (the magnify clamp shares the room).
    static let rowBodyGap: CGFloat = 4

    // MARK: Genie stretch (a hovered face reaches toward the bulge, `.stretch`)

    /// How much the radii grow at the leftmost point of the body (0 on the right; the squared smoothstep
    /// of the cosine toward the left in between, so the stretch tapers to a tip instead of a wide oval).
    static let genieStretch: Double = 0.4
    /// Leftward shift of the whole body, fraction of the face size.
    static let genieShift: Double = 0.06
    /// Vertical squeeze of the body while stretched.
    static let genieSqueeze: Double = 0.94
    /// The eyes slide a little further left than the body (fraction of the face size): they lean toward the pointer.
    static let genieEyeLean: Double = 0.03
    /// The one elastic motion in the app: the stretch springs with visible overshoot (ratio about 0.43),
    /// the snap back is tighter (ratio about 0.75).
    static let genieSpringMass: Double = 1
    static let genieSpringStiffness: Double = 260
    static let genieSpringDamping: Double = 14
    static let genieExitSpringStiffness: Double = 300
    static let genieExitSpringDamping: Double = 26
    /// Reduce Motion: a plain ease of this length to the stretched pose and back.
    static let genieReduceMotionDuration: TimeInterval = 0.2
    /// Dot-matrix style: a hovered face just scales up this much.
    static let genieDotMatrixScale: CGFloat = 1.06

    // MARK: Project dots and git branch (in the bulge)

    /// Diameter of the dot before the session name, and its gap to the name.
    static let projectDotSize: CGFloat = 6
    static let projectDotGap: CGFloat = 5
    /// Ten project colours, picked by a hash of the project key; the dot in the bulge and, in `.project`
    /// colour mode, the whole body. All vivid on black and none like a signal colour: the hue wheel runs
    /// from crimson through coral (8 degrees, the warm end) back round through pink, magenta, blue and
    /// teal to emerald (152 degrees); nothing between 20 and 140 degrees, so amber (35 degrees, needs
    /// input), yellow and the your-turn lime (88 degrees) keep a wide gap, and nothing in the violet wedge
    /// (245 to 275 degrees), which belongs to the lavender of the action faces. Emerald replaced a green
    /// at 128 degrees that read as a duller your-turn lime; it is deeper than the mint flash. The
    /// lightest (sky) still holds the ink eyes.
    static let projectPalette: [EyeColor] = [
        EyeColor(name: "crimson", red: 0.98, green: 0.22, blue: 0.36),
        EyeColor(name: "coral", red: 1.00, green: 0.50, blue: 0.42),
        EyeColor(name: "rose", red: 1.00, green: 0.42, blue: 0.72),
        EyeColor(name: "pink", red: 0.96, green: 0.40, blue: 0.92),
        EyeColor(name: "magenta", red: 0.80, green: 0.40, blue: 1.00),
        EyeColor(name: "periwinkle", red: 0.50, green: 0.58, blue: 1.00),
        EyeColor(name: "blue", red: 0.36, green: 0.68, blue: 1.00),
        EyeColor(name: "sky", red: 0.38, green: 0.86, blue: 1.00),
        EyeColor(name: "teal", red: 0.24, green: 0.90, blue: 0.78),
        EyeColor(name: "emerald", red: 0.12, green: 0.86, blue: 0.50),
    ]
    /// Branch line (`⎇ main`): grey, 10 pt, truncated at the tail.
    static let branchColor = Color(white: 0.6)
    static let branchFont = Font.system(size: 10)
    static let branchGlyph = "⎇"
    /// Vertical spacing between the bulge's text lines.
    static let bulgeLineSpacing: CGFloat = 2
}
