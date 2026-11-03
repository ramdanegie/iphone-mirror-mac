import CoreGraphics

/// Window size presets (FR-14). Percentages are relative to the iPhone's size in points.
public enum SizePreset: Int, CaseIterable, Sendable, Identifiable {
    case half = 50, threeQuarter = 75, full = 100, fit = 0

    public var id: Int { rawValue }
    public var label: String { self == .fit ? "Fit" : "\(rawValue)%" }
}

public enum WindowSizing {
    /// Design default: iPhone 15-class screen, 1179×2556 px.
    public static let defaultPixelSize = CGSize(width: 1179, height: 2556)

    /// iPhones with a short side ≥ 1080 px are @3x, older/SE/iPad are @2x.
    public static func pointScale(pixelSize: CGSize) -> CGFloat {
        min(pixelSize.width, pixelSize.height) >= 1080 ? 3 : 2
    }

    /// Content size for a preset, clamped so it always fits inside `visible` (the screen's visible frame).
    public static func contentSize(preset: SizePreset, pixelSize: CGSize, visible: CGSize) -> CGSize {
        let maxSize = CGSize(width: visible.width * 0.9, height: visible.height * 0.9)
        guard preset != .fit else { return fit(pixelSize, in: maxSize) }
        let scale = pointScale(pixelSize: pixelSize)
        let factor = CGFloat(preset.rawValue) / 100
        let size = CGSize(width: pixelSize.width / scale * factor, height: pixelSize.height / scale * factor)
        return size.width <= maxSize.width && size.height <= maxSize.height ? size.rounded : fit(pixelSize, in: maxSize)
    }

    /// After a rotation / resolution change: keep the window's long side, adopt the new aspect, stay on screen.
    public static func resized(current: CGSize, newPixelSize: CGSize, visible: CGSize) -> CGSize {
        let longSide = max(current.width, current.height)
        let aspect = newPixelSize.width / newPixelSize.height
        let target = aspect >= 1
            ? CGSize(width: longSide, height: longSide / aspect)
            : CGSize(width: longSide * aspect, height: longSide)
        let maxSize = CGSize(width: visible.width * 0.9, height: visible.height * 0.9)
        return target.width <= maxSize.width && target.height <= maxSize.height ? target.rounded : fit(newPixelSize, in: maxSize)
    }

    /// Rounded corners follow the iPhone screen shape: radius ≈ 9% of the short side (design: 27pt @ 300pt wide).
    public static func cornerRadius(for size: CGSize) -> CGFloat {
        (min(size.width, size.height) * 0.09).rounded()
    }

    static func fit(_ pixelSize: CGSize, in box: CGSize) -> CGSize {
        let s = min(box.width / pixelSize.width, box.height / pixelSize.height)
        // floor, not round: the result must never exceed the box
        return CGSize(width: (pixelSize.width * s).rounded(.down), height: (pixelSize.height * s).rounded(.down))
    }
}

extension CGSize {
    var rounded: CGSize { CGSize(width: width.rounded(), height: height.rounded()) }
}
