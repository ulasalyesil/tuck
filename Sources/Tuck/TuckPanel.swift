import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Borderless panel that drops from the Tuck icon. It takes key status without
/// activating Tuck, so the keyboard works while the app you were in stays in front.
final class TuckPanel: NSPanel {
    let model = PanelModel()
    private var anchor: NSRect = .zero
    private let host: NSHostingView<PanelView>
    /// Bumped on every show/dismiss so a finishing exit can't hide a fresh open.
    private var generation = 0

    init() {
        host = NSHostingView(rootView: PanelView(model: model))
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered, defer: true)
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        becomesKeyOnlyIfNeeded = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        contentView = host
    }

    override var canBecomeKey: Bool { true }

    /// Pointer opens grow out of the icon; keyboard opens are instant and select the first row.
    func show(items: [MenuBarItem], under anchor: NSRect, animated: Bool) {
        Motion.log.debug("show animated=\(animated)")
        generation += 1
        let token = generation
        self.anchor = anchor
        model.reset()
        model.items = items
        if !animated { model.move(1) }
        model.isPresented = !animated
        relayout(animated: false)
        makeKeyAndOrderFront(nil)
        guard animated else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == token else { return }
            withAnimation(Motion.enter, completionCriteria: .logicallyComplete) {
                self.model.isPresented = true
            } completion: { [weak self] in
                Motion.log.debug("enter done")
                self?.invalidateShadow() // the shadow was computed while the content was clear
            }
        }
    }

    /// A fresher scan arrived while open. Only the top-level list changes, and
    /// only when the set of items did; keyboard users keep a selection.
    func update(items: [MenuBarItem]) {
        guard isVisible, model.stack.isEmpty, items.map(\.id) != model.items.map(\.id) else { return }
        let hadSelection = model.selection != nil
        model.perform(animated: true) {
            model.items = items
            if hadSelection { model.move(1) }
        }
    }

    func dismiss(animated: Bool) {
        guard isVisible else { return }
        Motion.log.debug("dismiss animated=\(animated)")
        generation += 1
        let token = generation
        guard animated else {
            orderOut(nil)
            model.isPresented = false
            return
        }
        withAnimation(Motion.exit, completionCriteria: .logicallyComplete) {
            model.isPresented = false
        } completion: { [weak self] in
            guard let self, self.generation == token else { return }
            Motion.log.debug("exit done")
            self.orderOut(nil)
        }
    }

    /// Fit the content with the top-right corner pinned under the icon. Pointer
    /// changes glide to the new size; keyboard changes jump.
    func relayout(animated: Bool) {
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main!
        let x = min(max(anchor.maxX - size.width, screen.frame.minX + 8), screen.frame.maxX - size.width - 8)
        let target = NSRect(x: x, y: anchor.minY - size.height - 6, width: size.width, height: size.height).integral
        guard target != frame else { return }
        guard animated, isVisible else { return setFrame(target, display: true) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.resizeDuration
            context.timingFunction = Motion.resizeTiming
            animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            Motion.log.debug("resize done")
            self?.invalidateShadow()
        }
    }

    /// Menu-style keys, handled before SwiftUI sees them. Never animated.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, handleKey(event) { return }
        super.sendEvent(event)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let model = model
        switch Int(event.keyCode) {
        case kVK_DownArrow: model.perform(animated: false) { model.move(1) }
        case kVK_UpArrow: model.perform(animated: false) { model.move(-1) }
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Space: model.perform(animated: false) { model.activate(model.selection) }
        case kVK_RightArrow: model.perform(animated: false) { model.activateIfDeeper(model.selection) }
        case kVK_LeftArrow, kVK_Delete: model.perform(animated: false) { model.back() }
        case kVK_Escape: model.perform(animated: false) { if !model.back() { model.close() } }
        default:
            guard event.modifierFlags.intersection([.command, .control]).isEmpty,
                  let text = event.charactersIgnoringModifiers,
                  text.first?.isLetter == true || text.first?.isNumber == true else { return false }
            model.perform(animated: false) { model.jump(to: text) }
        }
        return true
    }
}

// MARK: Views

struct PanelView: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        LevelView(model: model, depth: model.stack.count,
                  appearsAnimated: model.changesAreAnimated, direction: model.direction)
            // A new identity per level, so each level fades in on its own.
            .id(model.stack.count)
            .padding(5)
            .frame(minWidth: 220, maxWidth: 340, alignment: .leading)
            .fixedSize()
            // While the window glides to a new size, content stays pinned to the top.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(VisualEffect())
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .scaleEffect(model.isPresented ? 1 : Motion.hiddenScale, anchor: .topTrailing)
            .opacity(model.isPresented ? 1 : 0)
    }
}

/// One level: the item list or a mirrored (sub)menu.
private struct LevelView: View {
    @ObservedObject var model: PanelModel
    let depth: Int
    let direction: PanelModel.Direction
    @State private var shown: Bool

    init(model: PanelModel, depth: Int, appearsAnimated: Bool, direction: PanelModel.Direction) {
        self.model = model
        self.depth = depth
        self.direction = direction
        // Pointer moves between levels fade in; keyboard moves and the first open don't.
        let isLevelChange = depth > 0 || direction == .back
        _shown = State(initialValue: !(appearsAnimated && isLevelChange))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let level = model.stack.last { header(level.title) }
            if model.rows.isEmpty { emptyState }
            ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                rowView(row, at: index)
            }
            if model.stack.isEmpty, !model.rows.isEmpty { footer }
        }
        .opacity(shown ? 1 : 0)
        .offset(x: shown ? 0 : (direction == .forward ? Motion.levelSlide : -Motion.levelSlide))
        .onAppear {
            guard !shown else { return }
            withAnimation(Motion.swap) { shown = true }
        }
    }

    /// Pointer actions animate; the keyboard path in TuckPanel bypasses this.
    private func pointer(_ change: () -> Void) { model.perform(animated: true, change) }

    @ViewBuilder
    private func rowView(_ row: PanelModel.Row, at index: Int) -> some View {
        switch row.kind {
        case .separator:
            Divider().padding(.horizontal, 8).padding(.vertical, 4)
        case .label(let text):
            Text(text.isEmpty ? " " : text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(height: 22, alignment: .leading)
        case .item(let item):
            RowButton(icon: item.icon, title: item.label, loading: model.loadingID == item.id,
                      selected: model.selection == index, hover: { hover(index, $0) }) {
                pointer { model.activate(index) }
            }
        case .entry(let entry):
            RowButton(icon: nil, title: entry.title.isEmpty ? "(custom item)" : entry.title,
                      leading: entry.mark, trailing: entry.submenu != nil ? "›" : "",
                      selected: model.selection == index, hover: { hover(index, $0) }) {
                pointer { model.activate(index) }
            }
        }
    }

    /// Hover highlight is instant, like a native menu.
    private func hover(_ index: Int, _ inside: Bool) {
        if inside { model.selection = index } else if model.selection == index { model.selection = nil }
    }

    private func header(_ title: String) -> some View {
        Button { pointer { model.back() } } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing tucked away.")
                .font(.system(size: 13, weight: .medium))
            Text("Arrange, then ⌘-drag icons to the left of the “← tucked” line.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Arrange Items…") { pointer { model.arrange() } }
                .controlSize(.small)
        }
        .frame(width: 230, alignment: .leading)
        .padding(8)
    }

    private var footer: some View {
        Text("\(Shortcut.display) to open · right-click ⋯ to arrange")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }
}

private struct RowButton: View {
    let icon: NSImage?
    let title: String
    var leading: String = ""
    var trailing: String = ""
    var loading = false
    let selected: Bool
    let hover: (Bool) -> Void
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                } else {
                    Text(leading).font(.system(size: 12)).frame(width: 10)
                }
                Text(title).font(.system(size: 13)).lineLimit(1)
                Spacer(minLength: 12)
                if loading {
                    ProgressView().controlSize(.mini).tint(selected ? .white : nil)
                } else {
                    Text(trailing).font(.system(size: 13)).opacity(0.6)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: icon == nil ? 22 : 26)
            .background(RoundedRectangle(cornerRadius: 5).fill(selected ? Color.accentColor : .clear))
            .foregroundStyle(selected ? Color.white : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover(perform: hover)
    }
}

/// The native menu material behind the content.
private struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.state = .active
        view.blendingMode = .behindWindow
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
