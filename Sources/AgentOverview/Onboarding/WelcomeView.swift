import SwiftUI
import WallflowerHookCore

/// The welcome window's content: the app's one branded moment. Pure black, the real faces, one
/// accent, generous spacing. Eight pages (`WelcomeModel.Page`) slide and crossfade on a spring (fades only under Reduce
/// Motion); page dots, "Back" from page 2, the primary button answers Return. With agents ticked,
/// "Start" first lays every file change over the page in one confirmation.
struct WelcomeView: View {
    @Bindable var model: WelcomeModel
    /// The look in force; the face style follows "Pick a look", and every page but that one colours by status.
    var look: PanelLook
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                page(model.page)
                    .id(model.page)
                    .transition(pageTransition)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .animation(pageAnimation, value: model.page)

            bottomBar
        }
        .padding(.top, WelcomeStyle.titlebarHeight)
        .overlay {
            if let items = model.confirmation {
                WelcomeAgentConfirmation(model: model, items: items)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.confirmation != nil)
        .frame(width: WelcomeStyle.size.width, height: WelcomeStyle.size.height)
        .background(Color.black)
        // The content runs under the transparent titlebar; the top padding above already keeps clear of it.
        .ignoresSafeArea()
        .foregroundStyle(.white)
        .tint(WelcomeStyle.accent)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Pages

    /// The first page is centred; the others hang from the same top line, so their titles do not jump.
    @ViewBuilder
    private func page(_ number: Int) -> some View {
        switch WelcomeModel.Page(rawValue: number) ?? .hello {
        case .hello: hello
        case .status: shapeIsStatus.topAligned()
        case .look: pickALook.topAligned()
        case .sound: WelcomeSoundPage(model: model, look: welcomeLook).topAligned()
        case .gestures: hoverClickDrag.topAligned()
        case .actions: WelcomeActionsPage(look: chosenLook, actionsFile: model.actionsFile, copyFeedback: model.setupPromptFeedback).topAligned()
        case .agents: WelcomeAgentsPage(model: model).topAligned()
        case .setUp: setUp.topAligned()
        }
    }

    /// The look picked on "Pick a look".
    private var chosenLook: PanelLook {
        var look = look
        look.faceStyle = model.faceStyle
        look.colorMode = model.colorMode
        return look
    }

    private var welcomeLook: PanelLook {
        var look = chosenLook
        look.colorMode = .status
        return look
    }

    /// Face and Colour, the same settings as Settings > Appearance, with four faces showing the result.
    private var pickALook: some View {
        VStack(spacing: 0) {
            WelcomeTitle("Pick a look")
            StatusFaceSamples(
                look: chosenLook, idleSince: model.idleSince, faceSize: 48, spacing: 34,
                labelFont: .system(size: 11, weight: .medium), labelColor: WelcomeStyle.secondary, labelGap: 10
            )
            // A new face style builds the faces anew, so the samples follow it at once.
            .id(model.faceStyle)
            .padding(.top, 28)
            VStack(spacing: 0) {
                WelcomeChoiceRow(title: "Face") {
                    WelcomeSegmentedPicker(selection: $model.faceStyle, values: FaceStyle.settingsOrder, labels: FaceStyle.settingsOrder.map(\.settingsTitle), accessibilityLabel: "Face")
                }
                WelcomeHairline()
                WelcomeChoiceRow(title: "Colour") {
                    WelcomeSegmentedPicker(
                        selection: $model.colorMode, values: Theme.ColorMode.settingsOrder, labels: Theme.ColorMode.settingsOrder.map(\.settingsTitle),
                        accessibilityLabel: "Colour"
                    )
                }
            }
            .welcomeCard()
            .padding(.top, 26)
            Text("Change it any time in Settings > Appearance.")
                .font(.system(size: 12))
                .foregroundStyle(WelcomeStyle.tertiary)
                .padding(.top, 14)
        }
    }

    private var hello: some View {
        VStack(spacing: 0) {
            StatusFace(look: welcomeLook, status: .idle(since: model.idleSince), seed: "welcome-hello", size: 96)
            Text(AppInfo.name)
                .font(.system(size: 40, weight: .bold))
                .tracking(-0.6)
                .padding(.top, 22)
            Text(AppInfo.tagline)
                .font(.system(size: 15))
                .foregroundStyle(WelcomeStyle.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 310)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
        .padding(.bottom, 8)
    }

    private var shapeIsStatus: some View {
        VStack(spacing: 0) {
            WelcomeTitle("Shape is status")
            WelcomeStatusLegend(look: welcomeLook, idleSince: model.idleSince)
                .padding(.top, 32)
            WelcomeBody("Every session gets a face on the edge of your screen. The two that want you glow, so they stand out.")
                .padding(.top, 30)
        }
    }

    private var hoverClickDrag: some View {
        VStack(spacing: 0) {
            WelcomeTitle("Hover, click, drag")
            VStack(alignment: .leading, spacing: 18) {
                WelcomeGestureRow(symbol: "cursorarrow.motionlines", text: "Hover to see the name and status.")
                WelcomeGestureRow(symbol: "cursorarrow.click.2", text: "Click to jump into that chat.")
                WelcomeGestureRow(symbol: "arrow.up.and.down", text: "Drag along the edge to move the column.")
            }
            .padding(.top, 36)
        }
    }

    /// The card holds both rows inside `WelcomeStyle.setUpInset`: every row is exactly the content
    /// width (the segmented control too, with labels short enough to fit it, so it never takes its
    /// wider natural size and pushes the card's content out), and the hairline spans the card.
    private var setUp: some View {
        VStack(spacing: 0) {
            WelcomeTitle("Set up")
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Where do you run Claude Code?")
                        .font(.system(size: 13, weight: .medium))
                    WelcomeSegmentedPicker(
                        selection: $model.sessionSource, values: SessionSource.allCases, labels: SessionSource.allCases.map(\.shortTitle),
                        accessibilityLabel: "Where do you run Claude Code?"
                    )
                    .frame(width: WelcomeStyle.setUpContentWidth)
                }
                .frame(width: WelcomeStyle.setUpContentWidth, alignment: .leading)
                .padding(WelcomeStyle.setUpInset)
                WelcomeHairline()
                HStack(spacing: 0) {
                    Text("Launch at login")
                        .font(.system(size: 13, weight: .medium))
                    Spacer(minLength: 8)
                    Toggle("Launch at login", isOn: $model.launchAtLogin)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                .frame(width: WelcomeStyle.setUpContentWidth)
                .padding(.horizontal, WelcomeStyle.setUpInset)
                .padding(.vertical, 12)
            }
            .welcomeCard()
            .padding(.top, 28)
            Text("No sessions yet. Start one and its face appears on the edge.")
                .font(.system(size: 12))
                .foregroundStyle(WelcomeStyle.tertiary)
                .padding(.top, 14)
                .opacity(model.showsNoSessionsHint ? 1 : 0)
                .accessibilityHidden(!model.showsNoSessionsHint)
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        ZStack {
            WelcomePageDots(page: model.page, count: WelcomeModel.pageCount, reduceMotion: reduceMotion)
            HStack {
                if !model.isFirstPage {
                    Button("Back") { model.back() }
                        .buttonStyle(WelcomeSecondaryButtonStyle())
                        .transition(.opacity)
                }
                Spacer()
                Button(model.primaryTitle) { model.primary() }
                    .buttonStyle(WelcomePrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .animation(.easeOut(duration: 0.18), value: model.isFirstPage)
        }
        .background {
            // Esc, whatever holds the focus (the window's own cancelOperation is the fallback).
            Button("Close") { model.dismiss() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.plain)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 24)
        .frame(height: WelcomeStyle.bottomBarHeight)
        .padding(.bottom, 12)
    }

    // MARK: Motion

    private var pageAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.46, dampingFraction: 0.88)
    }

    private var pageTransition: AnyTransition {
        let shift: CGFloat = reduceMotion ? 0 : 44
        let incoming = model.movesForward ? shift : -shift
        return .asymmetric(
            insertion: .modifier(active: WelcomePageFade(progress: 1, offset: incoming), identity: WelcomePageFade(progress: 0, offset: 0)),
            removal: .modifier(active: WelcomePageFade(progress: 1, offset: -incoming), identity: WelcomePageFade(progress: 0, offset: 0))
        )
    }
}

/// A page coming or going: shifted sideways and faded. The arriving page's faces fade through
/// `FaceLeave` (SwiftUI's own opacity does not reach a face's layer tree); the leaving page's faces do
/// not get environment updates any more once SwiftUI removed the page, so the window controller fades
/// those itself (`WelcomeModel.onPageWillChange`).
struct WelcomePageFade: ViewModifier, Animatable {
    /// 0 on screen, 1 gone.
    var progress: Double
    var offset: CGFloat

    nonisolated var animatableData: AnimatablePair<Double, CGFloat> {
        get { AnimatablePair(progress, offset) }
        set {
            progress = newValue.first
            offset = newValue.second
        }
    }

    func body(content: Content) -> some View {
        let opacity = max(0, min(1, 1 - progress))
        content
            .environment(\.faceLeave, FaceLeave(scale: 1, opacity: opacity))
            .opacity(opacity)
            .offset(x: offset)
    }
}

/// Colours and metrics of the welcome window.
enum WelcomeStyle {
    static let size = CGSize(width: 560, height: 440)
    /// The transparent titlebar the content runs under (the close button sits there).
    static let titlebarHeight: CGFloat = 28
    static let bottomBarHeight: CGFloat = 56
    /// Where the titles of every page but the first start, below the titlebar.
    static let pageTop: CGFloat = 50
    /// The one accent: the mint of a finished session.
    static let accent = Color(red: 0.45, green: 1.0, blue: 0.72)
    static let secondary = Color.white.opacity(0.62)
    static let tertiary = Color.white.opacity(0.42)
    static let panelFill = Color.white.opacity(0.06)
    static let hairline = Color.white.opacity(0.09)
    /// The "Set up" card: its width, the inset of both rows, and the width the rows get inside it.
    static let setUpCardWidth: CGFloat = 380
    static let setUpInset: CGFloat = 16
    static let setUpContentWidth: CGFloat = setUpCardWidth - 2 * setUpInset
}

/// A segmented control whose segments share the width it is given (`fillEqually`), so it spans a
/// card's content exactly: "Where do you run Claude Code?" (`SessionSource.shortTitle`), and Face and
/// Colour on "Pick a look". SwiftUI's segmented picker never grows past its labels' natural width (it
/// sat centred, narrower than the card) and could take that natural width when it was wider than the card.
struct WelcomeSegmentedPicker<Value: Hashable>: NSViewRepresentable {
    @Binding var selection: Value
    let values: [Value]
    let labels: [String]
    let accessibilityLabel: String

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: labels, trackingMode: .selectOne,
            target: context.coordinator, action: #selector(Coordinator.changed(_:))
        )
        control.segmentDistribution = .fillEqually
        // The welcome's one accent is mint; the selection stays neutral (the grey of an inactive window)
        // instead of AppKit's blue accent in a key window.
        control.selectedSegmentBezelColor = NSColor(white: 0.22, alpha: 1)
        control.setAccessibilityLabel(accessibilityLabel)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        if let index = values.firstIndex(of: selection), control.selectedSegment != index {
            control.selectedSegment = index
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context) -> CGSize? {
        let natural = nsView.intrinsicContentSize
        return CGSize(width: proposal.width ?? natural.width, height: natural.height)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection, values: values)
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<Value>
        let values: [Value]

        init(selection: Binding<Value>, values: [Value]) {
            self.selection = selection
            self.values = values
        }

        @objc func changed(_ sender: NSSegmentedControl) {
            guard values.indices.contains(sender.selectedSegment) else { return }
            selection.wrappedValue = values[sender.selectedSegment]
        }
    }
}

/// One row of a welcome card: a title on the left, a control filling the rest.
struct WelcomeChoiceRow<Control: View>: View {
    let title: String
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 64, alignment: .leading)
            control()
        }
        .frame(width: WelcomeStyle.setUpContentWidth)
        .padding(.horizontal, WelcomeStyle.setUpInset)
        .padding(.vertical, 12)
    }
}

struct WelcomeTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 26, weight: .semibold))
            .tracking(-0.3)
    }
}

struct WelcomeBody: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(WelcomeStyle.secondary)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .frame(maxWidth: 360)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension View {
    /// Every page but the first: the content from `WelcomeStyle.pageTop` down, centred horizontally.
    fileprivate func topAligned() -> some View {
        padding(.top, WelcomeStyle.pageTop)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// A welcome card: `WelcomeStyle.setUpCardWidth` wide, the soft fill, a hairline border.
    func welcomeCard() -> some View {
        frame(width: WelcomeStyle.setUpCardWidth)
            .background(WelcomeStyle.panelFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(WelcomeStyle.hairline))
    }
}

/// The line between two rows of a welcome card, the card's full width.
struct WelcomeHairline: View {
    var body: some View {
        Rectangle().fill(WelcomeStyle.hairline).frame(width: WelcomeStyle.setUpCardWidth, height: 1)
    }
}

/// One line of "Hover, click, drag" and "Action faces": a symbol on a soft tile, one sentence, and
/// optionally a control after it ("Copy Setup Prompt").
struct WelcomeGestureRow<Accessory: View>: View {
    let symbol: String
    let text: String
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 38, height: 38)
                .background(WelcomeStyle.panelFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(WelcomeStyle.hairline))
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.88))
            accessory()
                .padding(.leading, -4)
        }
    }
}

extension WelcomeGestureRow where Accessory == EmptyView {
    init(symbol: String, text: String) {
        self.init(symbol: symbol, text: text) { EmptyView() }
    }
}

/// Page dots: the current one white and wider, the rest dim.
struct WelcomePageDots: View {
    let page: Int
    let count: Int
    var reduceMotion = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...count, id: \.self) { index in
                Capsule()
                    .fill(index == page ? Color.white : Color.white.opacity(0.22))
                    .frame(width: index == page ? 16 : 6, height: 6)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.85), value: page)
        .accessibilityElement()
        .accessibilityLabel("Page \(page) of \(count)")
    }
}

/// White capsule, black text: the one filled button per page.
struct WelcomePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 20)
            .frame(minWidth: 88, minHeight: 32)
            .background(Color.white.opacity(configuration.isPressed ? 0.82 : 1), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Text only, dimmed: "Back".
struct WelcomeSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.white.opacity(configuration.isPressed ? 0.4 : 0.62))
            .padding(.horizontal, 14)
            .frame(minHeight: 32)
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
