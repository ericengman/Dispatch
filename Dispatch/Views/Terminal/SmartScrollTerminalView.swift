//
//  SmartScrollTerminalView.swift
//  Dispatch
//
//  Subclass of SwiftTerm's LocalProcessTerminalView that preserves
//  the user's scroll position when new terminal output arrives.
//  Without this, scrolling up to review history is impossible because
//  every new line of output snaps the viewport back to the bottom.
//

import AppKit
import SwiftTerm

/// A terminal view that doesn't auto-scroll to bottom when the user has scrolled up.
///
/// SwiftTerm's built-in `Terminal.userScrolling` flag is internal and never set
/// by mouse wheel events, so new output always forces `yDisp = yBase`. This subclass
/// intercepts `dataReceived` to save and restore the scroll position when the user
/// has intentionally scrolled away from the bottom.
class SmartScrollTerminalView: LocalProcessTerminalView {
    /// Session ID for this terminal (set during creation for active-session tracking)
    var sessionId: UUID?

    /// Whether the user has scrolled away from the bottom of the terminal.
    private(set) var isUserScrolledUp = false

    /// Guard to prevent the scrolled() delegate callback from misinterpreting
    /// programmatic scroll restoration as user-initiated scrolling.
    private var isRestoringPosition = false

    /// Whether the scroller has been configured to hide the legacy scrollbar.
    private var scrollerConfigured = false

    // MARK: - Active Session Tracking

    /// Monitor for mouse-down events targeting this terminal so the active session
    /// follows keyboard focus. Uses NSEvent monitor because SwiftTerm's mouseDown
    /// override is non-open and cannot be overridden outside the module.
    private var mouseDownMonitor: Any?

    func setupMouseDownMonitor() {
        guard mouseDownMonitor == nil else { return }
        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self,
                  let sessionId = self.sessionId,
                  let eventWindow = event.window,
                  eventWindow == self.window else { return event }

            let locationInSelf = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(locationInSelf) else { return event }

            if TerminalSessionManager.shared.activeSessionId != sessionId {
                TerminalSessionManager.shared.setActiveSession(sessionId)
            }
            return event
        }
    }

    private func removeMouseDownMonitor() {
        if let monitor = mouseDownMonitor {
            NSEvent.removeMonitor(monitor)
            mouseDownMonitor = nil
        }
    }

    // MARK: - Scroller Fix & Drag Registration

    /// SwiftTerm hardcodes `NSScroller.Style.legacy` which shows a permanent
    /// old-style scrollbar. Hide it and zero its width so the terminal content
    /// uses the full available width. Users scroll via trackpad/mouse wheel.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }

        // Register for file drag-and-drop (before scroller guard so it re-registers if needed)
        registerForDraggedTypes([.fileURL])

        guard !scrollerConfigured else { return }
        for subview in subviews {
            if let nsScroller = subview as? NSScroller {
                nsScroller.isHidden = true
                nsScroller.frame = NSRect(x: bounds.maxX, y: 0, width: 0, height: bounds.height)
                scrollerConfigured = true
            }
        }
    }

    // MARK: - Drag and Drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else {
            return []
        }
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else {
            return []
        }
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty else {
            return false
        }

        let escapedPaths = urls.map { shellEscapePath($0.path) }
        let pathString = escapedPaths.joined(separator: " ")

        logDebug("Drag-and-drop: inserting \(urls.count) path(s) into terminal", category: .terminal)

        // Send via bracketed paste when available (matches dispatchPrompt behavior),
        // but do NOT press Enter — user can type after the path, matching Terminal.app behavior
        let terminalInstance = getTerminal()
        if terminalInstance.bracketedPasteMode {
            send(txt: "\u{1b}[200~\(pathString)\u{1b}[201~")
        } else {
            send(txt: pathString)
        }

        return true
    }

    /// Shell-escape a file path by wrapping in single quotes.
    /// Any single quotes within the path are escaped as `'\''`.
    private func shellEscapePath(_ path: String) -> String {
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    // MARK: - Scroll Tracking via Delegate

    /// Called by SwiftTerm whenever the viewport scrolls (user scroll wheel, scroller drag, etc.)
    /// but NOT during internal Terminal.scroll() auto-scroll from new data.
    override func scrolled(source: TerminalView, position: Double) {
        super.scrolled(source: source, position: position)

        // Ignore position changes from our own restoration
        guard !isRestoringPosition else { return }

        isUserScrolledUp = position < 0.999
    }

    // MARK: - Data Handling with Scroll Preservation

    override func dataReceived(slice: ArraySlice<UInt8>) {
        guard isUserScrolledUp else {
            feed(byteArray: slice)
            return
        }

        // Compute distance from bottom in absolute lines before new data arrives.
        // This is stable regardless of how many new lines the data feed adds.
        let distFromBottom = distanceFromBottom()

        // Feed data to terminal (this triggers internal auto-scroll to bottom)
        feed(byteArray: slice)

        // Restore the user's scroll position
        isRestoringPosition = true
        restorePosition(distFromBottom: distFromBottom)
        isRestoringPosition = false
    }

    // MARK: - User Input Resets Scroll

    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        if isUserScrolledUp {
            isUserScrolledUp = false
            scroll(toPosition: 1.0)
        }
        super.send(source: source, data: data)
    }

    // MARK: - Public API

    /// Programmatically scroll to the bottom and resume auto-scrolling.
    /// Call this when dispatching a prompt so the user sees the response.
    func scrollToBottom() {
        isUserScrolledUp = false
        scroll(toPosition: 1.0)
    }

    // MARK: - Scroll Pass-Through

    /// When the terminal is at the bottom of its scrollback and the user scrolls down,
    /// forward events to the parent (the SwiftUI ScrollView) so the stack container scrolls.
    /// Uses NSEvent.addLocalMonitorForEvents because TerminalView.scrollWheel is not open.
    private var scrollMonitor: Any?
    private var isPassingThroughScroll = false

    func setupScrollPassThrough() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return self.handleScrollEvent(event)
        }
    }

    private func removeScrollMonitor() {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
    }

    private func handleScrollEvent(_ event: NSEvent) -> NSEvent? {
        // Only intercept events targeting this terminal
        guard let eventWindow = event.window,
              eventWindow == window else { return event }

        let locationInSelf = convert(event.locationInWindow, from: nil)
        guard bounds.contains(locationInSelf) else { return event }

        let isAtBottom = scrollPosition >= 0.999
        let isAtTop = scrollPosition <= 0.001
        let hasNoScrollback = scrollThumbsize >= 0.999
        let isScrollingDown = event.scrollingDeltaY < 0
        let isScrollingUp = event.scrollingDeltaY > 0

        // Once passing through, continue for entire gesture (momentum)
        if isPassingThroughScroll {
            if let target = enclosingSwiftUIScrollView() {
                target.scrollWheel(with: event)
            }
            if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended {
                isPassingThroughScroll = false
            }
            return nil
        }

        if event.phase == .began { isPassingThroughScroll = false }

        // Pass through when terminal has no scrollback (all content visible)
        // or when at the boundary scrolling outward
        let shouldPassThrough = hasNoScrollback
            || (isAtBottom && isScrollingDown)
            || (isAtTop && isScrollingUp)

        if shouldPassThrough {
            isPassingThroughScroll = true
            if let target = enclosingSwiftUIScrollView() {
                target.scrollWheel(with: event)
            }
            return nil
        }

        return event
    }

    /// Find the SwiftUI ScrollView's backing NSScrollView by walking up the view hierarchy.
    /// SwiftTerm's TerminalView is an NSView (not an NSScrollView) so the first
    /// NSScrollView ancestor is the SwiftUI ScrollView's backing view.
    private func enclosingSwiftUIScrollView() -> NSScrollView? {
        var current: NSView? = superview
        while let view = current {
            if let scrollView = view as? NSScrollView {
                return scrollView
            }
            current = view.superview
        }
        return nil
    }

    deinit {
        removeScrollMonitor()
        removeMouseDownMonitor()
    }

    // MARK: - Private Helpers

    /// Compute the user's distance from the bottom of the scrollback in lines.
    ///
    /// Uses only public SwiftTerm APIs:
    /// - `scrollThumbsize` = visibleRows / totalLines
    /// - `scrollPosition`  = yDisp / maxScrollback
    /// - `Terminal.rows`    = number of visible rows
    private func distanceFromBottom() -> Double {
        let thumbSize = Double(scrollThumbsize)
        guard thumbSize > 0, thumbSize < 1.0 else { return 0 }

        let rows = Double(getTerminal().rows)
        let maxScrollback = rows * (1.0 - thumbSize) / thumbSize
        return maxScrollback * (1.0 - scrollPosition)
    }

    /// Restore scroll position to the same distance from bottom after new data was added.
    private func restorePosition(distFromBottom: Double) {
        guard distFromBottom > 0 else { return }

        let thumbSize = Double(scrollThumbsize)
        guard thumbSize > 0, thumbSize < 1.0 else { return }

        let rows = Double(getTerminal().rows)
        let newMaxScrollback = rows * (1.0 - thumbSize) / thumbSize
        guard newMaxScrollback > 0 else { return }

        let newPosition = 1.0 - (distFromBottom / newMaxScrollback)
        scroll(toPosition: max(0, min(1.0, newPosition)))

        // If the restore put us at the bottom, resume auto-scrolling
        if scrollPosition >= 0.999 {
            isUserScrolledUp = false
        }
    }
}
