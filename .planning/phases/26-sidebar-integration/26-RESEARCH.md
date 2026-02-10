# Phase 26: Sidebar Integration - Research

**Researched:** 2026-02-09
**Domain:** SwiftUI Sidebar UI, Thumbnail Grids, MRU List Management
**Confidence:** HIGH

## Summary

Phase 26 adds a Quick Capture section to the existing sidebar, providing quick access to capture actions and recent captures. The core challenges are **sidebar section UI design**, **thumbnail grid performance**, and **MRU (Most Recently Used) list management**.

The existing codebase already has:
- **SidebarView** - List-based sidebar with collapsible sections (Projects, Chains)
- **ScreenshotStripView** - Horizontal thumbnail strip with lazy loading (reusable pattern)
- **CaptureCoordinator** - Handles capture results and window opening
- **QuickCapture model** - Lightweight struct for non-Run screenshots

This phase adds UI to trigger captures from the sidebar and displays recent captures as clickable thumbnails. No new capture logic needed - that infrastructure exists from Phases 23-24.

**Primary recommendation:** Add collapsible "Quick Capture" section to SidebarView using existing Section pattern. Use LazyHGrid for recent captures thumbnail strip (3-5 items). Track MRU list in UserDefaults with simple array of QuickCapture IDs. Implement thumbnail generation using CGImageSource for performance. Reuse window capture session picker for re-capture from MRU list.

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI List + Section | macOS 14+ | Sidebar structure | Native collapsible sections, built-in styling |
| LazyHGrid | SwiftUI | Thumbnail grid | Lazy loading, horizontal scroll, memory efficient |
| CGImageSource | Core Graphics | Thumbnail generation | 10-40x faster than NSImage, optimized for thumbnails |
| UserDefaults | Foundation | MRU persistence | Simple key-value storage, appropriate for small data |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| NSCache | Foundation | Image thumbnail caching | Thread-safe, automatic memory management |
| Task.detached | Swift Concurrency | Background thumbnail loading | Off-main-thread image processing |
| ScrollViewReader | SwiftUI | Programmatic scrolling | Auto-scroll to selected capture |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| CGImageSource | NSImage resize | NSImage is 10-40x slower for thumbnails |
| UserDefaults | SwiftData @Model | Over-engineered for simple MRU list (5-10 items max) |
| LazyHGrid | LazyVStack | Horizontal layout better for "strip" UX, saves vertical space |
| NSCache | Manual Dictionary | NSCache provides automatic eviction on memory pressure |

**Installation:**
Built-in SwiftUI, AppKit, and Foundation frameworks - no dependencies needed.

## Architecture Patterns

### Recommended Project Structure
```
Views/Sidebar/
├── SidebarView.swift                 # ✓ Exists: add Quick Capture section
└── QuickCaptureSidebarSection.swift  # → New: section content with buttons + thumbnails

Services/
└── QuickCaptureManager.swift         # → New: MRU list management + persistence

Models/
└── QuickCapture.swift                # ✓ Exists: already Hashable + Codable
```

### Pattern 1: Collapsible Sidebar Section with Action Buttons
**What:** Section header with buttons alongside text, collapsible content below
**When to use:** Sidebar sections that provide both actions (trigger captures) and content (recent captures)
**Example:**
```swift
// Source: https://www.kodeco.com/books/swiftui-cookbook/v1.0/chapters/6-implement-section-headers-in-a-list-in-swiftui
// Source: https://switch2mac.medium.com/swiftui-list-with-collapsible-sections-beb58760ef2c

Section {
    // Recent captures grid
    LazyHGrid(rows: [GridItem(.fixed(80))], spacing: 8) {
        ForEach(recentCaptures) { capture in
            QuickCaptureThumbnail(capture: capture)
                .onTapGesture {
                    openWindow(value: capture)
                }
        }
    }
    .padding(.vertical, 8)
} header: {
    HStack {
        Text("Quick Capture")
            .font(.headline)

        Spacer()

        // Action buttons in header
        HStack(spacing: 8) {
            Button {
                triggerRegionCapture()
            } label: {
                Image(systemName: "viewfinder")
                    .help("Region Capture")
            }
            .buttonStyle(.borderless)

            Button {
                triggerWindowCapture()
            } label: {
                Image(systemName: "macwindow")
                    .help("Window Capture")
            }
            .buttonStyle(.borderless)
        }
    }
}
```

**Key insights:**
- Buttons in section headers must use `.buttonStyle(.borderless)` to prevent list row selection
- HStack with Spacer() pushes buttons to trailing edge
- Use SF Symbols with `.help()` modifier for compact icon-only buttons
- Section content is collapsible by default in .sidebar list style

### Pattern 2: High-Performance Thumbnail Grid with LazyHGrid
**What:** Horizontal scrolling grid of thumbnails with lazy loading and caching
**When to use:** Displaying 3-5 recent captures without blocking UI or consuming excessive memory
**Example:**
```swift
// Source: https://www.avanderlee.com/swiftui/grid-lazyvgrid-lazyhgrid-gridviews/
// Source: https://codewithchris.com/photo-gallery-app-swiftui-part-2/

struct QuickCapturesGrid: View {
    let captures: [QuickCapture]
    let onSelect: (QuickCapture) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: [GridItem(.fixed(80))], spacing: 8) {
                ForEach(captures) { capture in
                    QuickCaptureThumbnail(capture: capture)
                        .id(capture.id)
                        .onTapGesture {
                            onSelect(capture)
                        }
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 90)
    }
}

struct QuickCaptureThumbnail: View {
    let capture: QuickCapture

    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.5)
                    }
            }
        }
        .frame(width: 80, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onAppear {
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        Task.detached(priority: .userInitiated) {
            let thumb = await ThumbnailCache.shared.thumbnail(for: capture)
            await MainActor.run {
                self.thumbnail = thumb
            }
        }
    }
}
```

**Benefits:**
- LazyHGrid only creates views when needed (performance)
- Task.detached moves image loading off main thread
- ThumbnailCache centralizes caching logic

### Pattern 3: Fast Thumbnail Generation with CGImageSource
**What:** Generate thumbnails using Core Graphics instead of NSImage for 10-40x performance improvement
**When to use:** Loading multiple image thumbnails where speed matters
**Example:**
```swift
// Source: https://nshipster.com/image-resizing/
// Source: https://macguru.dev/fast-thumbnails-with-cgimagesource/

actor ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()
    private let maxPixelSize: CGFloat = 120

    init() {
        cache.countLimit = 50
        cache.totalCostLimit = 10 * 1024 * 1024 // 10MB
    }

    func thumbnail(for capture: QuickCapture) async -> NSImage? {
        let key = capture.filePath as NSString

        // Check cache first
        if let cached = cache.object(forKey: key) {
            return cached
        }

        // Generate thumbnail using CGImageSource (fast path)
        guard let thumbnail = generateThumbnail(from: capture.fileURL) else {
            return nil
        }

        // Cache with cost = estimated bytes
        let cost = Int(thumbnail.size.width * thumbnail.size.height * 4)
        cache.setObject(thumbnail, forKey: key, cost: cost)

        return thumbnail
    }

    private func generateThumbnail(from url: URL) -> NSImage? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: .zero)
    }
}
```

**Performance comparison:**
- CGImageSource: 16-145ms for thumbnail generation
- NSImage resize: 600+ms for same operation
- NSCache handles memory pressure automatically
- Actor isolation prevents race conditions

### Pattern 4: MRU List Management with UserDefaults
**What:** Maintain a short list of recently used items with automatic eviction of oldest entries
**When to use:** Tracking 3-10 recent items that need to persist across app launches
**Example:**
```swift
// Source: https://en.wikipedia.org/wiki/Cache_replacement_policies
// Source: https://mahigarg.github.io/blogs/lru-cache-implementation-in-swift/

@MainActor
final class QuickCaptureManager: ObservableObject {
    static let shared = QuickCaptureManager()

    @Published private(set) var recentCaptures: [QuickCapture] = []

    private let maxRecent = 5
    private let userDefaultsKey = "recentQuickCaptures"

    init() {
        loadRecentCaptures()
    }

    /// Add capture to MRU list (moves to front if already exists)
    func addRecent(_ capture: QuickCapture) {
        // Remove existing if present (deduplication)
        recentCaptures.removeAll { $0.id == capture.id }

        // Insert at front
        recentCaptures.insert(capture, at: 0)

        // Trim to max size
        if recentCaptures.count > maxRecent {
            recentCaptures = Array(recentCaptures.prefix(maxRecent))
        }

        saveRecentCaptures()
    }

    /// Remove capture from MRU list
    func removeRecent(id: UUID) {
        recentCaptures.removeAll { $0.id == id }
        saveRecentCaptures()
    }

    /// Clear all recent captures
    func clearRecent() {
        recentCaptures.removeAll()
        saveRecentCaptures()
    }

    private func saveRecentCaptures() {
        if let encoded = try? JSONEncoder().encode(recentCaptures) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }

    private func loadRecentCaptures() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([QuickCapture].self, from: data) else {
            return
        }

        // Filter out captures whose files no longer exist
        recentCaptures = decoded.filter { capture in
            FileManager.default.fileExists(atPath: capture.filePath)
        }

        // Save filtered list if anything was removed
        if recentCaptures.count != decoded.count {
            saveRecentCaptures()
        }
    }
}
```

**Key insights:**
- MRU adds to front, LRU would evict from front
- Deduplication prevents duplicates in list
- File existence check prevents showing missing files
- UserDefaults appropriate for small lists (< 100 items)

### Pattern 5: Window Picker for Re-Capture with Hover Preview
**What:** Show live thumbnail previews of capturable windows, allow selection to re-capture
**When to use:** User wants to capture same window again from MRU list
**Example:**
```swift
// Source: Existing WindowCaptureSession pattern (Phase 24)
// Source: https://developer.apple.com/documentation/coregraphics/cgwindow

struct WindowRecaptureView: View {
    let previousCapture: QuickCapture
    @Environment(\.openWindow) private var openWindow
    @State private var isCapturing = false

    var body: some View {
        Button {
            recaptureWindow()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "arrow.clockwise")
                Text("Re-capture")
                    .font(.caption2)
            }
        }
        .buttonStyle(.borderless)
        .disabled(isCapturing)
    }

    private func recaptureWindow() {
        Task {
            isCapturing = true

            // Use existing WindowCaptureSession
            let session = WindowCaptureSession()
            let result = await session.start()

            isCapturing = false

            // Handle result via CaptureCoordinator
            await CaptureCoordinator.shared.handleCaptureResult(result)
        }
    }
}
```

**Integration:**
- Reuses existing WindowCaptureSession from Phase 24
- No new capture logic needed
- CaptureCoordinator opens annotation window automatically

### Anti-Patterns to Avoid
- **Loading full images in thumbnails:** Always use CGImageSource with maxPixelSize
- **Blocking main thread for thumbnails:** Use Task.detached for image loading
- **No cache limits:** Always set countLimit and totalCostLimit on NSCache
- **Persisting MRU in SwiftData:** UserDefaults is simpler and appropriate for small lists
- **Manually managing memory:** Let NSCache handle eviction automatically

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Thumbnail generation | NSImage resize | CGImageSource with kCGImageSourceThumbnailMaxPixelSize | 10-40x faster, optimized path |
| Image caching | Custom Dictionary | NSCache with cost limits | Thread-safe, automatic memory management |
| MRU list logic | Custom data structure | Array with insert(at: 0) + prefix() | Simple, readable, sufficient for small lists |
| Thumbnail lazy loading | Manual isVisible tracking | LazyHGrid | SwiftUI handles view recycling automatically |
| Window thumbnails | screencapture + preview | CGWindowListCopyWindowInfo for live previews | Real-time updates, no file I/O |

**Key insight:** Performance matters for thumbnails. CGImageSource is the correct API for fast thumbnail generation. NSImage resize is too slow for multi-image grids.

## Common Pitfalls

### Pitfall 1: Using NSImage for Thumbnail Generation
**What goes wrong:** UI becomes sluggish when loading multiple thumbnails, scroll stutters
**Why it happens:** NSImage loads full image into memory, then resizes - expensive for large screenshots
**How to avoid:** Use CGImageSource with kCGImageSourceThumbnailMaxPixelSize option
**Warning signs:** Thumbnail grid scrolling lags, memory usage spikes when viewing recent captures

### Pitfall 2: No Cache Size Limits
**What goes wrong:** Memory usage grows unbounded as user captures more screenshots
**Why it happens:** NSCache without countLimit or totalCostLimit never evicts items
**How to avoid:** Set both countLimit (item count) and totalCostLimit (bytes) on NSCache
**Warning signs:** App memory usage grows continuously, doesn't decrease after scrolling away

### Pitfall 3: Loading Thumbnails on Main Thread
**What goes wrong:** UI freezes briefly when displaying each thumbnail
**Why it happens:** Synchronous image I/O blocks main thread
**How to avoid:** Use Task.detached to load thumbnails on background thread
**Warning signs:** Jank when scrolling through thumbnails, main thread watchdog warnings

### Pitfall 4: MRU List Not Filtering Deleted Files
**What goes wrong:** Recent captures show broken thumbnails for deleted files
**Why it happens:** Files deleted outside app (Finder, cleanup), but MRU list not updated
**How to avoid:** Filter by file existence when loading MRU list from UserDefaults
**Warning signs:** Empty/broken thumbnails in recent captures section

### Pitfall 5: Section Not Collapsible
**What goes wrong:** Quick Capture section can't be collapsed, wastes sidebar space
**Why it happens:** Forgetting to use Section with header in .sidebar list style
**How to avoid:** Wrap content in Section { } header: { } - automatic disclosure in .sidebar style
**Warning signs:** No disclosure triangle next to section header

### Pitfall 6: Thumbnail Tap Gesture Not Working
**What goes wrong:** Clicking thumbnails doesn't open annotation window
**Why it happens:** List row selection conflicts with onTapGesture
**How to avoid:** Use .buttonStyle(.borderless) on thumbnail buttons, or embed in custom view outside List
**Warning signs:** List row highlights instead of opening window

## Code Examples

Verified patterns from official sources:

### Complete Sidebar Quick Capture Section
```swift
// Source: Synthesized from existing SidebarView + research patterns

extension SidebarView {
    private var quickCaptureSection: some View {
        Section {
            if captureManager.recentCaptures.isEmpty {
                // Empty state
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)

                    Text("No recent captures")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Use buttons above to capture")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                // Recent captures grid
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHGrid(rows: [GridItem(.fixed(80))], spacing: 8) {
                        ForEach(captureManager.recentCaptures) { capture in
                            QuickCaptureThumbnailCell(
                                capture: capture,
                                onSelect: { openWindow(value: capture) },
                                onRecapture: { recaptureWindow(capture) }
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .frame(height: 90)
            }
        } header: {
            HStack {
                Label("Quick Capture", systemImage: "camera")
                    .font(.headline)

                Spacer()

                // Capture action buttons
                HStack(spacing: 4) {
                    Button {
                        triggerRegionCapture()
                    } label: {
                        Image(systemName: "viewfinder.rectangular")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Region Capture")

                    Button {
                        triggerWindowCapture()
                    } label: {
                        Image(systemName: "macwindow")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Window Capture")
                }
            }
        }
    }

    private func triggerRegionCapture() {
        Task {
            let result = await ScreenshotCaptureService.shared.captureRegion()
            await CaptureCoordinator.shared.handleCaptureResult(result)
        }
    }

    private func triggerWindowCapture() {
        Task {
            let result = await WindowCaptureSession().start()
            await CaptureCoordinator.shared.handleCaptureResult(result)
        }
    }

    private func recaptureWindow(_ capture: QuickCapture) {
        Task {
            let result = await WindowCaptureSession().start()
            await CaptureCoordinator.shared.handleCaptureResult(result)
        }
    }
}
```

### QuickCapture Thumbnail Cell with Hover Actions
```swift
// Source: Adapted from ScreenshotThumbnailView pattern

struct QuickCaptureThumbnailCell: View {
    let capture: QuickCapture
    let onSelect: () -> Void
    let onRecapture: () -> Void

    @State private var thumbnail: NSImage?
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 4) {
            // Thumbnail
            thumbnailImage
                .frame(width: 80, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) {
                    if isHovering {
                        recaptureButton
                    }
                }

            // Timestamp
            Text(capture.relativeTimestamp)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .onAppear {
            loadThumbnail()
        }
    }

    @ViewBuilder
    private var thumbnailImage: some View {
        if let thumbnail = thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .overlay {
                    ProgressView()
                        .scaleEffect(0.5)
                }
        }
    }

    private var recaptureButton: some View {
        Button {
            onRecapture()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.caption)
                .padding(4)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .offset(x: 4, y: -4)
        .help("Re-capture window")
    }

    private func loadThumbnail() {
        Task.detached(priority: .userInitiated) {
            let thumb = await ThumbnailCache.shared.thumbnail(for: capture)
            await MainActor.run {
                self.thumbnail = thumb
            }
        }
    }
}

extension QuickCapture {
    var relativeTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}
```

### CaptureCoordinator Integration
```swift
// Source: Existing CaptureCoordinator + QuickCaptureManager integration

extension CaptureCoordinator {
    func handleCaptureResult(_ result: CaptureResult) {
        switch result {
        case let .success(url):
            guard FileManager.default.fileExists(atPath: url.path) else {
                logError("Capture file not found: \(url.path)", category: .capture)
                return
            }

            let capture = QuickCapture(fileURL: url)

            // Add to MRU list
            Task { @MainActor in
                QuickCaptureManager.shared.addRecent(capture)
            }

            // Open annotation window
            pendingCapture = capture
            logInfo("Capture ready for annotation: \(url.lastPathComponent)", category: .capture)

        case .cancelled:
            logInfo("Capture cancelled by user", category: .capture)

        case let .error(error):
            logError("Capture failed: \(error)", category: .capture)
        }
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| NSImage resize | CGImageSource thumbnails | Core Graphics API | 10-40x performance improvement for thumbnails |
| Manual Dictionary cache | NSCache with cost/count limits | Foundation (always available) | Automatic memory management under pressure |
| Vertical thumbnails | LazyHGrid horizontal strip | SwiftUI 3.0 (2021) | Better space efficiency in sidebar |
| Manual section collapse | Section with header in .sidebar | SwiftUI 2.0 (2020) | Automatic disclosure, no custom state |

**Deprecated/outdated:**
- **NSImage-based thumbnail generation:** Too slow for multi-image grids
- **Manual cache eviction logic:** NSCache handles this automatically
- **Custom collapsible section UI:** Section + .sidebar style provides this built-in

## Open Questions

Things that couldn't be fully resolved:

1. **Window thumbnail live previews**
   - What we know: WindowCaptureSession shows hover highlights, but no thumbnail preview
   - What's unclear: Should MRU list show live window thumbnails (requires polling) or static captures?
   - Recommendation: Start with static thumbnails from last capture. Live previews add complexity and polling overhead. If user wants to re-capture, they click re-capture button.

2. **MRU list persistence across deletions**
   - What we know: Files can be deleted outside app (Finder, cleanup scripts)
   - What's unclear: Should we track file moves/renames, or just filter on existence?
   - Recommendation: Filter by existence only. File tracking (FSEvents) is complex. If file missing, it disappears from MRU. Simple and correct.

3. **Thumbnail size optimization**
   - What we know: Sidebar width varies, thumbnails need to fit
   - What's unclear: Fixed 80x60 vs. dynamic sizing based on sidebar width?
   - Recommendation: Fixed 80x60. Predictable layout, matches existing ScreenshotThumbnailView pattern. Dynamic sizing adds complexity.

## Sources

### Primary (HIGH confidence)
- [Image Resizing Techniques - NSHipster](https://nshipster.com/image-resizing/)
- [Fast Thumbnails with CGImageSource - MacGuru.dev](https://macguru.dev/fast-thumbnails-with-cgimagesource/)
- [SwiftUI Grid, LazyVGrid, LazyHGrid - SwiftLee](https://www.avanderlee.com/swiftui/grid-lazyvgrid-lazyhgrid-gridviews/)
- [Building a Photo Gallery app in SwiftUI Part 2 - CodeWithChris](https://codewithchris.com/photo-gallery-app-swiftui-part-2/)
- [SwiftUI list with collapsible sections - Medium](https://switch2mac.medium.com/swiftui-list-with-collapsible-sections-beb58760ef2c)

### Secondary (MEDIUM confidence)
- [SwiftUI Cookbook: Section Headers - Kodeco](https://www.kodeco.com/books/swiftui-cookbook/v1.0/chapters/6-implement-section-headers-in-a-list-in-swiftui)
- [LRU Cache Implementation in Swift - Mahi Garg](https://mahigarg.github.io/blogs/lru-cache-implementation-in-swift/)
- [How to add sections to a list - HackingWithSwift](https://www.hackingwithswift.com/quick-start/swiftui/how-to-add-sections-to-a-list)
- [Downloading and Caching images in SwiftUI - SwiftLee](https://www.avanderlee.com/swiftui/downloading-caching-images/)

### Tertiary (LOW confidence)
- [Cache replacement policies - Wikipedia](https://en.wikipedia.org/wiki/Cache_replacement_policies)
- [AsyncImage limitations - Medium](https://medium.com/@alex_persian/the-case-against-asyncimage-22a073044746)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - CGImageSource, NSCache, LazyHGrid are official Apple APIs with established patterns
- Architecture: HIGH - Existing SidebarView structure verified, ScreenshotStripView provides proven pattern
- Pitfalls: HIGH - Performance characteristics of NSImage vs CGImageSource well-documented
- MRU management: MEDIUM - Simple array-based approach works for small lists, not exhaustively tested at scale

**Research date:** 2026-02-09
**Valid until:** 2026-03-09 (30 days - stable APIs, established patterns)
**CGImageSource availability:** macOS 10.4+
**LazyHGrid introduced:** SwiftUI 3.0 (macOS 12.0, September 2021)
**NSCache availability:** macOS 10.6+
