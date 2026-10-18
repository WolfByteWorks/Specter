import SwiftUI
import AppKit

// The WolfByte.Works About ID card (shared by WolfByte.Works apps), with Specter's name,
// tagline, version fields, logo and colors (aqua and orange from the logo).

/// Specter's palette, from the logo and the palette reference in Design/.
enum SpecterColor {
    static let aqua = Color(brandHex: 0x4BD3E5)
    static let lightAqua = Color(brandHex: 0x94EBE7)
    static let deepAqua = Color(brandHex: 0x60B3C1)
    static let orange = Color(brandHex: 0xFC7F01)
    static let deepOrange = Color(brandHex: 0xEC6404)
}

/// The About window: the ID card alone. Esc or Cmd-W closes it.
final class AboutWindow: NSWindow {
    convenience init() {
        let host = NSHostingView(rootView: AboutIDCard().padding(24))
        self.init(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
        title = "About Specter"
        contentView = host
        isReleasedWhenClosed = false
        center()
    }

    override func cancelOperation(_ sender: Any?) { close() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "w" {
            close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Brand colors

extension Color {
    init(brandHex hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

@MainActor
enum BrandAssets {
    /// The Specter logo, shown in the card's ring.
    static let logo = load("Logo", subdirectory: nil)
    /// The WolfByte.Works SIM-card chip, rendered at 1x to 4x, drawn at 50 x 37 points.
    static let simChip: NSImage? = {
        let image = NSImage(size: NSSize(width: 50, height: 37))
        for name in ["wolfbyte-sim-chip-1x", "wolfbyte-sim-chip-2x",
                     "wolfbyte-sim-chip-3x", "wolfbyte-sim-chip"] {
            guard let file = load(name),
                  let data = file.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: data) else { continue }
            rep.size = image.size
            image.addRepresentation(rep)
        }
        return image.representations.isEmpty ? nil : image
    }()

    private static func load(_ name: String, subdirectory: String? = "Branding") -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: subdirectory) else { return nil }
        return NSImage(contentsOf: url)
    }
}

/// The app's logo.
struct BrandMark: View {
    var size: CGFloat = 22
    /// Draws the logo larger than its frame (the overflow is clipped by the caller).
    var zoom: CGFloat = 1

    var body: some View {
        if let image = BrandAssets.logo {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
                .frame(width: size * zoom, height: size * zoom)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "hexagon")
                .font(.system(size: size * 0.8))
                .foregroundColor(.white)
        }
    }
}

// MARK: - HUD helpers

/// Oxanium (readouts) and Chakra Petch (headings) ship in Branding/Fonts under
/// the SIL Open Font License. System fonts stand in if they cannot load.
@MainActor
enum HUDFonts {
    private static var registered = false

    static func register() {
        guard !registered else { return }
        registered = true
        for url in Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Branding/Fonts") ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func readout(_ size: CGFloat, bold: Bool = true) -> Font {
        named(bold ? "OxaniumRoman-Bold" : "OxaniumRoman-SemiBold", size: size)
            ?? .system(size: size, weight: bold ? .bold : .semibold, design: .rounded).monospacedDigit()
    }

    static func heading(_ size: CGFloat, bold: Bool = true) -> Font {
        named(bold ? "ChakraPetch-Bold" : "ChakraPetch-SemiBold", size: size)
            ?? .system(size: size, weight: bold ? .bold : .semibold)
    }

    private static func named(_ name: String, size: CGFloat) -> Font? {
        register()
        return NSFont(name: name, size: size) != nil ? Font.custom(name, size: size) : nil
    }
}

/// Small top-left and bottom-right radii, large top-right and bottom-left
/// (border-radius: 6px 22px 6px 22px on the card).
struct CutCornerShape: Shape {
    var small: CGFloat = 4
    var large: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        let s = min(small, rect.height / 2, rect.width / 2), l = min(large, rect.height / 2, rect.width / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + s, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - l, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - l, y: rect.minY + l), radius: l, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - s))
        p.addArc(center: CGPoint(x: rect.maxX - s, y: rect.maxY - s), radius: s, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + l, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + l, y: rect.maxY - l), radius: l, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + s))
        p.addArc(center: CGPoint(x: rect.minX + s, y: rect.minY + s), radius: s, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

struct BreathingHalo: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let color: Color
    var minRadius: CGFloat = 6
    var maxRadius: CGFloat = 16
    @State private var high = false

    func body(content: Content) -> some View {
        content
            .clipShape(Circle())
            .background(Circle().fill(Color.black)
                            .shadow(color: color.opacity(high ? 0.8 : 0.45), radius: high ? maxRadius : minRadius))
            .overlay(Circle().stroke(color.opacity(high ? 0.55 : 0.3), lineWidth: 1).padding(-1))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) { high = true }
            }
    }
}

extension View {
    func breathingHalo(_ color: Color, min: CGFloat = 6, max: CGFloat = 16) -> some View {
        modifier(BreathingHalo(color: color, minRadius: min, maxRadius: max))
    }
}

// MARK: - About card

/// The ID card: spinning reactor ring around the
/// logo, neon name, details, a holographic sweep, and a barcode and QR code
/// for wolfbyte.works. It is always dark, like a physical card.
struct AboutIDCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false
    @State private var holo: CGFloat = -1

    private let ember = SpecterColor.orange
    private let blaze = SpecterColor.deepOrange
    private let flare = SpecterColor.aqua
    private let dim = SpecterColor.deepAqua

    private let info = Bundle.main.infoDictionary ?? [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 24) {
                ring
                VStack(alignment: .leading, spacing: 0) {
                    Text("Specter")
                        .font(HUDFonts.heading(36))
                        .foregroundColor(SpecterColor.lightAqua)
                        .shadow(color: ember.opacity(0.9), radius: 6)
                        .shadow(color: blaze.opacity(0.5), radius: 16)
                    Text("bluetooth audio · kept awake")
                        .font(.system(size: 12, weight: .medium))
                        .tracking(1)
                        .foregroundColor(ember)
                        .shadow(color: ember.opacity(0.6), radius: 4)
                        .padding(.top, 7)
                    fields.padding(.top, 16)
                }
                Spacer(minLength: 0)
            }
            codes
        }
        .padding(24)
        .frame(width: 640)
        .background(background)
        .overlay(chip, alignment: .topTrailing)
        .overlay(holoSweep)
        .clipShape(CutCornerShape(small: 6, large: 22))
        .overlay(CutCornerShape(small: 6, large: 22).stroke(SpecterColor.aqua.opacity(0.5), lineWidth: 1))
        .shadow(color: SpecterColor.aqua.opacity(0.22), radius: 20)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: false)) { holo = 1 }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Pieces

    private var ring: some View {
        ZStack {
            Circle()
                .strokeBorder(AngularGradient(gradient: Gradient(stops: [
                    .init(color: .clear, location: 0), .init(color: .clear, location: 0.12),
                    .init(color: blaze, location: 0.30), .init(color: flare, location: 0.55),
                    .init(color: .clear, location: 0.75), .init(color: .clear, location: 1)
                ]), center: .center), lineWidth: 6)
                .shadow(color: ember.opacity(0.9), radius: 10)
                .rotationEffect(.degrees(spin ? 360 : 0))
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundColor(SpecterColor.aqua.opacity(0.3))
                .padding(12)
                .rotationEffect(.degrees(spin ? -60 : 0))
            // Zoomed so the logo's square fills the round frame (no black at its sides).
            BrandMark(size: 134, zoom: 1.12).breathingHalo(SpecterColor.aqua, min: 10, max: 22)
        }
        .frame(width: 182, height: 182)
        .accessibilityHidden(true)
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 6) {
            field("Version", info["CFBundleShortVersionString"] as? String ?? "")
            field("Build", info["CFBundleVersion"] as? String ?? "")
            field("Requires", "macOS 13 or later")
            field("Publisher", "WolfByte.Works")
            field("Designed and Built by", "WolfByte.Works")
            field("Copyright", "© 2026 WolfByte.Works")
        }
    }

    private func field(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label.uppercased())
                .font(HUDFonts.readout(11, bold: false))
                .tracking(1.1)
                .foregroundColor(dim)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(width: 176, alignment: .leading)
            Text(value)
                .font(HUDFonts.readout(12.5, bold: false))
                .foregroundColor(Color(brandHex: 0xEAF9FB))
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var codes: some View {
        HStack(spacing: 12) {
            if let bars = WolfByteCodes.barcode {
                Image(nsImage: bars)
                    .resizable()
                    .interpolation(.none)
                    .frame(height: 40)
                    .frame(maxWidth: .infinity)
                    .opacity(0.75)
                    .shadow(color: SpecterColor.aqua.opacity(0.6), radius: 4)
                    .accessibility(label: Text("Barcode: wolfbyte.works"))
            }
            if let qr = WolfByteCodes.qr {
                Image(nsImage: qr)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .shadow(color: SpecterColor.aqua.opacity(0.35), radius: 7)
                    .accessibility(label: Text("QR code: wolfbyte.works"))
            }
        }
        .help("wolfbyte.works: scan the QR code with a phone")
    }

    private var background: some View {
        LinearGradient(gradient: Gradient(stops: [
            .init(color: Color(brandHex: 0x0A1C20), location: 0),
            .init(color: Color(brandHex: 0x030607), location: 0.6),
            .init(color: Color(brandHex: 0x030607), location: 1)
        ]), startPoint: .topLeading, endPoint: .bottomTrailing)
        .overlay(RadialGradient(gradient: Gradient(colors: [.clear, SpecterColor.aqua.opacity(0.08)]),
                                center: .center, startRadius: 120, endRadius: 360))
    }

    /// The WolfByte.Works SIM-card chip (Branding/wolfbyte-sim-chip*.png, 1x to 4x),
    /// the same chip every WolfByte.Works About card shows.
    @ViewBuilder private var chip: some View {
        if let image = BrandAssets.simChip {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 50, height: 37)
                .shadow(color: ember.opacity(0.55), radius: 3.5)
                .opacity(0.92)
                .padding(.top, 22)
                .padding(.trailing, 24)
                .accessibilityHidden(true)
        }
    }

    /// A soft diagonal glint that crosses the card. The band is far taller
    /// than the card and fades to nothing at both edges, so no corner or
    /// straight edge of it can ever show inside the card.
    private var holoSweep: some View {
        GeometryReader { geometry in
            if !reduceMotion {
                let w = geometry.size.width, h = geometry.size.height
                LinearGradient(gradient: Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: SpecterColor.lightAqua.opacity(0.05), location: 0.3),
                    .init(color: SpecterColor.lightAqua.opacity(0.14), location: 0.5),
                    .init(color: ember.opacity(0.05), location: 0.7),
                    .init(color: .clear, location: 1)
                ]), startPoint: .leading, endPoint: .trailing)
                .frame(width: w * 0.32, height: h * 3)
                .blur(radius: 10)
                .rotationEffect(.degrees(20))
                .position(x: w * 0.5 + holo * w, y: h * 0.5)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Code 128 barcode and QR code for wolfbyte.works, drawn once with Core Image.
@MainActor
enum WolfByteCodes {
    static let barcode: NSImage? = render("CICode128BarcodeGenerator", message: "wolfbyte.works",
                                          extra: ["inputQuietSpace": 0],
                                          ink: NSColor(srgbRed: 0.294, green: 0.827, blue: 0.898, alpha: 1),
                                          paper: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0), scale: 4)
    static let qr: NSImage? = render("CIQRCodeGenerator", message: "https://wolfbyte.works",
                                     extra: ["inputCorrectionLevel": "M"],
                                     ink: NSColor(srgbRed: 0.01, green: 0.10, blue: 0.11, alpha: 1),
                                     paper: NSColor(srgbRed: 0.92, green: 0.98, blue: 0.98, alpha: 1), scale: 8, quietZone: 2)

    private static func render(_ name: String, message: String, extra: [String: Any],
                               ink: NSColor, paper: NSColor, scale: CGFloat, quietZone: CGFloat = 0) -> NSImage? {
        guard let generator = CIFilter(name: name) else { return nil }
        generator.setValue(Data(message.utf8), forKey: "inputMessage")
        extra.forEach { generator.setValue($0.value, forKey: $0.key) }
        guard let image = generator.outputImage,
              let colored = CIFilter(name: "CIFalseColor"),
              let inkColor = CIColor(color: ink), let paperColor = CIColor(color: paper) else { return nil }
        colored.setValue(image, forKey: kCIInputImageKey)
        colored.setValue(inkColor, forKey: "inputColor0")
        colored.setValue(paperColor, forKey: "inputColor1")
        guard var output = colored.outputImage else { return nil }
        if quietZone > 0 {
            // Scanners expect a plain margin around a QR code.
            output = output.composited(over: CIImage(color: paperColor)
                .cropped(to: output.extent.insetBy(dx: -quietZone, dy: -quietZone)))
        }
        output = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: output)
        let result = NSImage(size: rep.size)
        result.addRepresentation(rep)
        return result
    }
}
