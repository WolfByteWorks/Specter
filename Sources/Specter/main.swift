import AppKit
import AVFoundation
import CoreImage
import os
import ServiceManagement
import Sparkle

// Plays a bundled one-second keep-alive tone on a timer so Bluetooth audio devices don't go to sleep.
// The tone is 25 Hz at -50 dB: too low and quiet to hear, but a real signal (soundbars such as the
// JBL BAR 1000 ignore pure digital silence and go to standby after about 10 minutes).
// Left-click the menu bar item for the menu, right-click to pause/resume.
// Updates come through Sparkle (feed and key in Info.plist, written by build.sh).

private let log = Logger(subsystem: "works.wolfbyte.Specter", category: "play")
private let intervalKey = "intervalMinutes"
private let iconStyleKey = "menuBarIconStyle"
private let oldWhiteIconKey = "whiteMenuBarIcon"
private let intervals = [1, 5, 10, 15]

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var aboutWindow: AboutWindow?
    private let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil,
                                                       userDriverDelegate: nil)

    /// The Specter logo in color, trimmed to its edges and drawn at 22 pt in its own colors:
    /// aqua tile (MenuBarIcon.png) or black tile (MenuBarIconBlack.png), both with a thicker,
    /// flat orange logo made for this size (no saturation boost, which would push orange to red).
    private static func colorIcon(_ name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 22, height: 22)
        return image
    }

    /// The same logo, grey and faded, while paused.
    private static func pausedIcon(of icon: NSImage?) -> NSImage? {
        guard let tiff = icon?.tiffRepresentation, let logo = CIImage(data: tiff) else { return nil }
        let rep = NSCIImageRep(ciImage: logo.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0]))
        let grey = NSImage(size: rep.size)
        grey.addRepresentation(rep)
        return NSImage(size: NSSize(width: 22, height: 22), flipped: false) { rect in
            grey.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.5)
            return true
        }
    }

    private let colorIcon = AppDelegate.colorIcon("MenuBarIcon")
    private let blackIcon = AppDelegate.colorIcon("MenuBarIconBlack")
    private lazy var colorPausedIcon = AppDelegate.pausedIcon(of: colorIcon)
    private lazy var blackPausedIcon = AppDelegate.pausedIcon(of: blackIcon)

    /// The logo shape alone as a template image, so macOS draws it white (or black) like other
    /// menu bar icons.
    private let whiteIcon: NSImage? = {
        let image = Bundle.main.image(forResource: "MenuBarTemplate")
        image?.isTemplate = true
        return image
    }()

    private enum IconStyle: String, CaseIterable {
        case color, black, white
        var title: String {
            switch self {
            case .color: return "GhostDragon"  // aqua with the orange logo
            case .black: return "Ember"        // black with the orange logo
            case .white: return "Snow"         // plain white template icon
            }
        }
    }

    private var iconStyle: IconStyle {
        get {
            if let stored = UserDefaults.standard.string(forKey: iconStyleKey), let style = IconStyle(rawValue: stored) {
                return style
            }
            return UserDefaults.standard.bool(forKey: oldWhiteIconKey) ? .white : .color  // 01.04.00 setting
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: iconStyleKey) }
    }

    private var intervalMinutes: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: intervalKey)
            return intervals.contains(stored) ? stored : 1
        }
        set { UserDefaults.standard.set(newValue, forKey: intervalKey) }
    }

    private var isRunning: Bool { timer != nil }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.main.url(forResource: "keep-alive-tone", withExtension: "mp3") {
            player = try? AVAudioPlayer(contentsOf: url)
        }
        if player == nil { log.error("Could not load keep-alive-tone.mp3") }

        // Fixed text on purpose: macOS can pop a status item's tooltip up away from the menu bar
        // when it changes while the pointer isn't on the icon. The live state is in the menu.
        statusItem.button?.toolTip = "Specter"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        start()
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            isRunning ? pause() : start()
            return
        }
        statusItem.menu = buildMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil  // so the next click comes back to statusItemClicked
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: isRunning ? "Running – every \(intervalMinutes) min" : "Paused", action: nil, keyEquivalent: "")
        let toggle = menu.addItem(withTitle: isRunning ? "Pause" : "Start", action: #selector(toggle), keyEquivalent: "")
        toggle.target = self
        menu.addItem(.separator())
        for minutes in intervals {
            let item = menu.addItem(withTitle: minutes == 1 ? "Every 1 minute" : "Every \(minutes) minutes",
                                    action: #selector(chooseInterval(_:)), keyEquivalent: "")
            item.target = self
            item.tag = minutes
            item.state = minutes == intervalMinutes ? .on : .off
        }
        menu.addItem(.separator())
        let styles = NSMenu()
        for style in IconStyle.allCases {
            let item = styles.addItem(withTitle: style.title, action: #selector(chooseIconStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            item.state = style == iconStyle ? .on : .off
        }
        menu.addItem(withTitle: "Menu Bar Icon", action: nil, keyEquivalent: "").submenu = styles
        let login = menu.addItem(withTitle: "Start at Login", action: #selector(toggleStartAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "About Specter", action: #selector(showAbout), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quit Specter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @objc private func showAbout() {
        if aboutWindow == nil { aboutWindow = AboutWindow() }
        NSApp.activate(ignoringOtherApps: true)
        aboutWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        updater.checkForUpdates(nil)
    }

    @objc private func toggle() { isRunning ? pause() : start() }

    /// Adds or removes Specter as a login item (shown in System Settings > General > Login Items).
    @objc private func toggleStartAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            log.error("Start at Login change failed: \(error.localizedDescription, privacy: .public)")
            let alert = NSAlert()
            alert.messageText = "Couldn't change Start at Login"
            alert.informativeText = "\(error.localizedDescription)\n\nYou can add Specter in System Settings > General > Login Items."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func chooseIconStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = IconStyle(rawValue: raw) else { return }
        iconStyle = style
        updateIcon()
    }

    @objc private func chooseInterval(_ sender: NSMenuItem) {
        intervalMinutes = sender.tag
        if isRunning { start() }
    }

    private func start() {
        timer?.invalidate()
        play()
        timer = Timer.scheduledTimer(timeInterval: TimeInterval(intervalMinutes * 60), target: self,
                                     selector: #selector(play), userInfo: nil, repeats: true)
        updateIcon()
    }

    private func pause() {
        timer?.invalidate()
        timer = nil
        log.info("Paused")
        updateIcon()
    }

    @objc private func play() {
        player?.currentTime = 0
        let ok = player?.play() ?? false
        log.info("Played keep-alive tone (ok: \(ok), interval: \(self.intervalMinutes) min)")
    }

    private func updateIcon() {
        switch iconStyle {
        case .white:
            // Template icon: macOS colors it; dimmed while paused.
            statusItem.button?.image = whiteIcon
            statusItem.button?.appearsDisabled = !isRunning
        case .color:
            statusItem.button?.image = isRunning ? colorIcon : colorPausedIcon
            statusItem.button?.appearsDisabled = false
        case .black:
            statusItem.button?.image = isRunning ? blackIcon : blackPausedIcon
            statusItem.button?.appearsDisabled = false
        }
        statusItem.button?.setAccessibilityLabel(isRunning ? "Specter, running" : "Specter, paused")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
