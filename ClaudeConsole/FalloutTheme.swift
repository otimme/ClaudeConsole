//
//  FalloutTheme.swift
//  ClaudeConsole
//
//  Fallout Pip-Boy inspired theme with CRT effects
//

import SwiftUI

// MARK: - Fallout Color Palette

extension Color {
    struct Fallout {
        // Primary Greens (Pip-Boy phosphor)
        static let primary = Color(hex: "14FF00")
        static let secondary = Color(hex: "0FBF00")
        static let tertiary = Color(hex: "0A8000")
        static let dim = Color(hex: "0A8000").opacity(0.5)

        // Backgrounds
        static let background = Color(hex: "0A0F08")
        static let backgroundAlt = Color(hex: "0D1A0B")
        static let backgroundPanel = Color(hex: "0F1E0D")

        // Glow & Effects
        static let glow = Color(hex: "00FF00")
        static let scanline = Color.black.opacity(0.15)

        // Status Colors
        static let warning = Color(hex: "FFB000")
        static let danger = Color(hex: "FF3300")
        static let inactive = Color(hex: "1A2818")

        // UI Elements
        static let border = Color(hex: "14FF00").opacity(0.8)
        static let borderDim = Color(hex: "0A8000").opacity(0.5)
        static let selection = Color(hex: "14FF00").opacity(0.2)
    }
}

// Note: Color(hex:) initializer is defined in RadialMenuView.swift

// MARK: - Fallout Fonts

extension Font {
    struct Fallout {
        static func display(_ size: CGFloat) -> Font {
            .system(size: size, weight: .medium, design: .monospaced)
        }

        static func mono(_ size: CGFloat) -> Font {
            .system(size: size, design: .monospaced)
        }

        static let title = display(28)
        static let heading = display(20)
        static let subheading = display(16)
        static let body = mono(14)
        static let caption = mono(12)
        static let stats = mono(18)
    }
}

// MARK: - Fallout Text Glow Effect

struct FalloutGlow: ViewModifier {
    let color: Color
    let radius: CGFloat

    init(color: Color = Color.Fallout.glow, radius: CGFloat = 4) {
        self.color = color
        self.radius = radius
    }

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.8), radius: radius / 2)
            .shadow(color: color.opacity(0.5), radius: radius)
            .shadow(color: color.opacity(0.3), radius: radius * 2)
    }
}

extension View {
    func falloutGlow(radius: CGFloat = 4) -> some View {
        modifier(FalloutGlow(radius: radius))
    }

    func falloutGlow(color: Color, radius: CGFloat = 4) -> some View {
        modifier(FalloutGlow(color: color, radius: radius))
    }
}

// MARK: - Beveled Rectangle Shape

struct BeveledRectangle: Shape {
    let cornerSize: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: cornerSize, y: 0))
        path.addLine(to: CGPoint(x: rect.width - cornerSize, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: cornerSize))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - cornerSize))
        path.addLine(to: CGPoint(x: rect.width - cornerSize, y: rect.height))
        path.addLine(to: CGPoint(x: cornerSize, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height - cornerSize))
        path.addLine(to: CGPoint(x: 0, y: cornerSize))
        path.closeSubpath()

        return path
    }
}

// MARK: - Diamond Shape

struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Fallout Frame Modifier

struct FalloutFrame: ViewModifier {
    let title: String?
    let cornerStyle: CornerStyle

    enum CornerStyle {
        case sharp
        case beveled
        case rounded
    }

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title = title {
                HStack {
                    Text(title.uppercased())
                        .font(.Fallout.subheading)
                        .foregroundColor(Color.Fallout.primary)
                        .falloutGlow(radius: 2)
                        .tracking(2)

                    Spacer()

                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle()
                                .fill(Color.Fallout.primary)
                                .frame(width: 6, height: 6)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.Fallout.primary.opacity(0.1))
            }

            content
                .padding(12)
        }
        .background(backgroundShape)
        .overlay(frameOverlay)
    }

    @ViewBuilder
    private var backgroundShape: some View {
        switch cornerStyle {
        case .sharp:
            Color.Fallout.backgroundPanel
        case .beveled:
            Color.Fallout.backgroundPanel
                .clipShape(BeveledRectangle(cornerSize: 8))
        case .rounded:
            Color.Fallout.backgroundPanel
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    @ViewBuilder
    private var frameOverlay: some View {
        switch cornerStyle {
        case .sharp:
            Rectangle()
                .stroke(Color.Fallout.border, lineWidth: 2)
        case .beveled:
            BeveledRectangle(cornerSize: 8)
                .stroke(Color.Fallout.border, lineWidth: 2)
        case .rounded:
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.Fallout.border, lineWidth: 2)
        }
    }
}

extension View {
    func falloutFrame(title: String? = nil, corners: FalloutFrame.CornerStyle = .beveled) -> some View {
        modifier(FalloutFrame(title: title, cornerStyle: corners))
    }
}

// MARK: - CRT Scanline Overlay

struct ScanlineOverlay: View {
    let lineSpacing: CGFloat
    let lineOpacity: Double

    init(lineSpacing: CGFloat = 3, lineOpacity: Double = 0.06) {
        self.lineSpacing = lineSpacing
        self.lineOpacity = lineOpacity
    }

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let lineCount = Int(size.height / lineSpacing)

                for i in 0..<lineCount {
                    let y = CGFloat(i) * lineSpacing
                    let rect = CGRect(x: 0, y: y, width: size.width, height: 1)
                    context.fill(
                        Path(rect),
                        with: .color(.black.opacity(lineOpacity))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Vignette Overlay

struct VignetteOverlay: View {
    let intensity: CGFloat

    init(intensity: CGFloat = 0.6) {
        self.intensity = intensity
    }

    var body: some View {
        GeometryReader { geometry in
            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0.3),
                    .init(color: .black.opacity(0.2 * intensity), location: 0.6),
                    .init(color: .black.opacity(0.5 * intensity), location: 0.85),
                    .init(color: .black.opacity(0.7 * intensity), location: 1.0)
                ]),
                center: .center,
                startRadius: 0,
                endRadius: max(geometry.size.width, geometry.size.height) * 0.7
            )
        }
        .allowsHitTesting(false)
    }
}

// MARK: - CRT Effects Container

struct CRTEffectsOverlay: View {
    var body: some View {
        ZStack {
            ScanlineOverlay()
            VignetteOverlay()
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Fallout Segmented Progress Bar

struct FalloutProgressBar: View {
    let value: Double
    let segments: Int
    let label: String?
    let showPercentage: Bool
    let style: ProgressStyle

    enum ProgressStyle {
        case normal
        case warning
        case danger
    }

    init(
        value: Double,
        segments: Int = 20,
        label: String? = nil,
        showPercentage: Bool = true,
        style: ProgressStyle = .warning
    ) {
        self.value = min(max(value, 0), 1)
        self.segments = segments
        self.label = label
        self.showPercentage = showPercentage
        self.style = style
    }

    private var fillColor: Color {
        switch style {
        case .normal:
            return Color.Fallout.primary
        case .warning:
            if value > 0.9 { return Color.Fallout.danger }
            if value > 0.7 { return Color.Fallout.warning }
            return Color.Fallout.primary
        case .danger:
            if value > 0.5 { return Color.Fallout.danger }
            return Color.Fallout.primary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if label != nil || showPercentage {
                HStack {
                    if let label = label {
                        Text(label.uppercased())
                            .font(.Fallout.caption)
                            .foregroundColor(Color.Fallout.secondary)
                            .tracking(1)
                    }
                    Spacer()
                    if showPercentage {
                        Text("\(Int(value * 100))%")
                            .font(.Fallout.stats)
                            .foregroundColor(fillColor)
                            .falloutGlow(radius: 2)
                    }
                }
            }

            HStack(spacing: 2) {
                ForEach(0..<segments, id: \.self) { index in
                    let segmentThreshold = Double(index + 1) / Double(segments)
                    let isFilled = value >= segmentThreshold

                    RoundedRectangle(cornerRadius: 1)
                        .fill(isFilled ? fillColor : Color.Fallout.inactive)
                        .frame(height: 14)
                        .shadow(
                            color: isFilled ? fillColor.opacity(0.5) : .clear,
                            radius: 2
                        )
                }
            }
            .padding(3)
            .background(Color.Fallout.background)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.Fallout.borderDim, lineWidth: 1)
            )
        }
    }
}

// MARK: - Fallout Stat Display

struct FalloutStat: View {
    let label: String
    let value: String
    let unit: String?
    let alignment: HorizontalAlignment
    let valueColor: Color

    init(
        label: String,
        value: String,
        unit: String? = nil,
        alignment: HorizontalAlignment = .leading,
        valueColor: Color = Color.Fallout.primary
    ) {
        self.label = label
        self.value = value
        self.unit = unit
        self.alignment = alignment
        self.valueColor = valueColor
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label.uppercased())
                .font(.Fallout.caption)
                .foregroundColor(Color.Fallout.tertiary)
                .tracking(1.5)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.Fallout.stats)
                    .foregroundColor(valueColor)
                    .falloutGlow(radius: 2)

                if let unit = unit {
                    Text(unit)
                        .font(.Fallout.caption)
                        .foregroundColor(Color.Fallout.secondary)
                }
            }
        }
    }
}

// MARK: - Fallout Divider

struct FalloutDivider: View {
    let orientation: Orientation

    enum Orientation {
        case horizontal
        case vertical
    }

    init(_ orientation: Orientation = .horizontal) {
        self.orientation = orientation
    }

    var body: some View {
        switch orientation {
        case .horizontal:
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color.Fallout.borderDim)
                    .frame(height: 1)

                Diamond()
                    .fill(Color.Fallout.primary)
                    .frame(width: 6, height: 6)

                Rectangle()
                    .fill(Color.Fallout.borderDim)
                    .frame(height: 1)
            }
            .padding(.vertical, 6)

        case .vertical:
            VStack(spacing: 8) {
                Rectangle()
                    .fill(Color.Fallout.borderDim)
                    .frame(width: 1)

                Diamond()
                    .fill(Color.Fallout.primary)
                    .frame(width: 6, height: 6)

                Rectangle()
                    .fill(Color.Fallout.borderDim)
                    .frame(width: 1)
            }
            .padding(.horizontal, 6)
        }
    }
}

// MARK: - Fallout Button Style

struct FalloutButtonStyle: ButtonStyle {
    let isDestructive: Bool

    init(isDestructive: Bool = false) {
        self.isDestructive = isDestructive
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.Fallout.body)
            .foregroundColor(isDestructive ? Color.Fallout.danger : Color.Fallout.primary)
            .tracking(1)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                configuration.isPressed
                    ? (isDestructive ? Color.Fallout.danger : Color.Fallout.primary).opacity(0.2)
                    : Color.Fallout.backgroundPanel
            )
            .overlay(
                BeveledRectangle(cornerSize: 4)
                    .stroke(
                        isDestructive ? Color.Fallout.danger : Color.Fallout.border,
                        lineWidth: configuration.isPressed ? 2 : 1
                    )
            )
            .clipShape(BeveledRectangle(cornerSize: 4))
            .shadow(
                color: configuration.isPressed
                    ? (isDestructive ? Color.Fallout.danger : Color.Fallout.glow).opacity(0.3)
                    : .clear,
                radius: 4
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == FalloutButtonStyle {
    static var fallout: FalloutButtonStyle { FalloutButtonStyle() }
    static var falloutDestructive: FalloutButtonStyle { FalloutButtonStyle(isDestructive: true) }
}

// MARK: - Fallout Status Bar

struct FalloutStatusBar: View {
    let title: String
    let showIndicators: Bool

    init(title: String = "VAULT-TEC TERMINAL", showIndicators: Bool = true) {
        self.title = title
        self.showIndicators = showIndicators
    }

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "gear.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Color.Fallout.primary)
                Text(title)
                    .font(.Fallout.caption)
                    .foregroundColor(Color.Fallout.primary)
                    .tracking(1.5)
            }

            Spacer()

            Text(Date(), style: .time)
                .font(.Fallout.caption)
                .foregroundColor(Color.Fallout.secondary)

            Spacer()

            if showIndicators {
                HStack(spacing: 12) {
                    StatusIndicatorDot(label: "SYS", isActive: true)
                    StatusIndicatorDot(label: "NET", isActive: true)
                    StatusIndicatorDot(label: "CLI", isActive: true)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.Fallout.backgroundAlt)
        .overlay(
            Rectangle()
                .fill(Color.Fallout.border)
                .frame(height: 2),
            alignment: .bottom
        )
    }
}

struct StatusIndicatorDot: View {
    let label: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isActive ? Color.Fallout.primary : Color.Fallout.inactive)
                .frame(width: 8, height: 8)
                .shadow(color: isActive ? Color.Fallout.glow.opacity(0.5) : .clear, radius: 4)

            Text(label)
                .font(.Fallout.caption)
                .foregroundColor(isActive ? Color.Fallout.primary : Color.Fallout.tertiary)
        }
    }
}

// MARK: - Fallout Recording Overlay

struct FalloutRecordingOverlay: View {
    let isRecording: Bool
    let isTranscribing: Bool

    var body: some View {
        if isRecording || isTranscribing {
            VStack(spacing: 16) {
                if isRecording {
                    RecordingWaveform()
                } else {
                    ProcessingIndicator()
                }

                Text(isRecording ? "RECORDING..." : "PROCESSING...")
                    .font(.Fallout.heading)
                    .foregroundColor(Color.Fallout.primary)
                    .tracking(2)
                    .falloutGlow(radius: 4)
            }
            .padding(32)
            .background(Color.Fallout.background.opacity(0.95))
            .overlay(
                BeveledRectangle(cornerSize: 12)
                    .stroke(Color.Fallout.primary, lineWidth: 2)
            )
            .clipShape(BeveledRectangle(cornerSize: 12))
            .shadow(color: Color.Fallout.glow.opacity(0.3), radius: 20)
        }
    }
}

struct RecordingWaveform: View {
    @State private var levels: [CGFloat] = Array(repeating: 0.3, count: 7)
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.Fallout.primary)
                    .frame(width: 6, height: 20 + levels[index] * 30)
                    .shadow(color: Color.Fallout.glow.opacity(0.5), radius: 4)
            }
        }
        .frame(height: 50)
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.1)) {
                    levels = levels.map { _ in CGFloat.random(in: 0.2...1.0) }
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}

struct ProcessingIndicator: View {
    @State private var rotation: Double = 0

    var body: some View {
        Image(systemName: "gear")
            .font(.system(size: 40))
            .foregroundColor(Color.Fallout.primary)
            .rotationEffect(.degrees(rotation))
            .shadow(color: Color.Fallout.glow.opacity(0.5), radius: 4)
            .onAppear {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}
