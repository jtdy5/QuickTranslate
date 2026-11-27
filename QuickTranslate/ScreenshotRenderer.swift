import Foundation
import CoreGraphics
import CoreText
import ImageIO

struct RecognizedTextBox: Sendable {
    let text: String
    let confidence: Float
    let rect: CGRect
    let glyphRects: [CGRect]
}

enum QuickTranslateRenderError: Error { case invalidResponse }

struct ScreenshotRenderer: Sendable {
    /// Render the translated overlay onto `image`.
    ///
    /// - Parameter skippedIndices: boxes that were intentionally left
    ///   untranslated (e.g. detected as a language the user already
    ///   understands). These get no mask at all — the source pixels show
    ///   through unchanged. Boxes outside this set are always masked, even
    ///   when translation came back identical to the source (treat as a
    ///   silent translation failure rather than letting the source bleed).
    func render(
        source image: CGImage,
        boxes: [RecognizedTextBox],
        translations: [String],
        skippedIndices: Set<Int> = []
    ) throws -> CGImage {
        guard boxes.count == translations.count else {
            throw QuickTranslateRenderError.invalidResponse
        }

        let width = image.width
        let height = image.height
        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw QuickTranslateRenderError.invalidResponse
        }

        // CGBitmapContext rows are stored such that pixel-row 0 in memory is
        // the BOTTOM of the drawn content (CG geometry is y-up). When written
        // as PNG, row 0 ends up as the top of the file. So `context.draw(image)`
        // by itself produces a PNG that's vertically mirrored relative to the
        // source. Flipping the CTM globally fixes the image but breaks all of
        // CG/CoreText drawing into a flipped frame.
        //
        // Instead: draw the image with no flip; let the bitmap rows be
        // "upside-down" in CG-geometry terms; then run a post-flip on the
        // final CGImage by re-drawing it through a flipping context.
        context.draw(image, in: canvas)

        // Vision/OCR rects use top-left origin (y increases downward). CGContext
        // is bottom-left. flipY converts between them.
        let H = CGFloat(height)
        func flipY(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: H - rect.maxY, width: rect.width, height: rect.height)
        }

        let downwardCeilings = Self.neighborCeilings(for: boxes, canvasHeight: H)
        let upwardFloors = Self.neighborFloors(for: boxes)

        for (index, (box, translation)) in zip(boxes, translations).enumerated() {
            if skippedIndices.contains(index) { continue }
            let trimmed = translation.trimmingCharacters(in: .whitespacesAndNewlines)
            // Translation succeeded when we got back something non-empty
            // that differs from the source. Otherwise we still draw the
            // mask (so the source can't bleed through), but skip the text
            // — there's nothing meaningful to put on top.
            let hasTranslation = !trimmed.isEmpty && trimmed != box.text

            let downwardCeiling = downwardCeilings[index]
            let upwardFloor = upwardFloors[index]
            // Pad vertically to swallow ascenders/descenders and diacritics
            // (Thai vowel marks, Devanagari matras) that sit outside the OCR
            // baseline box. CAP the padding to half the distance to the
            // nearest neighbour — otherwise tightly stacked chat lines (gap
            // = 1-2 px) inflate to overlapping masks that hide each other's
            // text. With no neighbour, full 7-pt padding applies.
            let topRoom = max(0, box.rect.minY - upwardFloor)
            let botRoom = max(0, downwardCeiling - box.rect.maxY)
            let topPad = min(7, topRoom / 2)
            let botPad = min(7, botRoom / 2)
            let base = CGRect(
                x: box.rect.minX - 2,
                y: box.rect.minY - topPad,
                width: box.rect.width + 4,
                height: box.rect.height + topPad + botPad
            )
            // Match the source font size. Two independent estimates, take
            // the smaller as a safety net:
            //
            //  1. Per-line bbox height × 0.65. OCR bbox heights include the
            //     full ascender + descender range (~30 % taller than the
            //     visible cap-height), so 0.65 of the bbox lands close to
            //     the source's visual size.
            //  2. Per-character width × 1.8. Thai stacked diacritics can
            //     inflate the height of one line 50-100 % over its
            //     neighbours at the same visual font size; the character
            //     WIDTH is far more stable. Using width-per-character as a
            //     ceiling stops "สุกี้ดาวเรียง" (h=71) from rendering at
            //     46 pt while its same-font sibling "ผัดกะเพรา…" (h=48)
            //     renders at 31 pt.
            //
            // 50 pt soft cap is a final guard against extreme outliers.
            let sourceLineCount = max(1, box.text.split(separator: "\n", omittingEmptySubsequences: false).count)
            let perSourceLineHeight = box.rect.height / CGFloat(sourceLineCount)
            let heightBasedFont = perSourceLineHeight * 0.84
            let charsPerLine = max(1, box.text.count / sourceLineCount)
            let widthBasedFont = (box.rect.width / CGFloat(charsPerLine)) * 2.1
            let targetFontSize = max(8, min(min(heightBasedFont, widthBasedFont), 50))
            // Keep each translation inside its own OCR box. Expanding a box
            // to fit a longer English phrase can cover neighbouring text in
            // dense shopping pages and manga panels. drawText scales and wraps
            // the translation to fit this original region instead.
            let padded = base.intersection(canvas)
            let palette = Self.ensureContrast(sampledPalette(from: image, box: box))
            let paddedFlipped = flipY(padded)
            let path = CGPath(
                roundedRect: paddedFlipped,
                cornerWidth: 2,
                cornerHeight: 2,
                transform: nil
            )
            // Always opaque: anything below 1.0 lets the original glyphs
            // ghost through, since the OCR box sits right on the source text.
            context.setFillColor(palette.background)
            context.addPath(path)
            context.fillPath()

            guard hasTranslation else { continue }
            drawText(
                trimmed,
                in: padded.insetBy(dx: 4, dy: 2),
                flippedRect: flipY(padded.insetBy(dx: 4, dy: 2)),
                context: context,
                foreground: palette.foreground,
                targetFontSize: targetFontSize
            )
        }

        guard let output = context.makeImage() else {
            throw QuickTranslateRenderError.invalidResponse
        }
        return output
    }

    // MARK: - Rect expansion

    private func expandedRect(
        base: CGRect,
        for text: String,
        targetFontSize: CGFloat,
        canvas: CGRect,
        downwardCeiling: CGFloat,
        upwardFloor: CGFloat
    ) -> CGRect {
        // Horizontal width/position is locked to the source OCR box. If the
        // translation doesn't fit at `targetFontSize` we grow the rect first
        // downward up to the neighbouring box's top edge, then — when that
        // isn't enough — upward up to the box above. We never grow sideways.
        let font = makeFont(size: targetFontSize)
        let measured = measureText(text, font: font, maxWidth: max(1, base.width - 8))
        let neededHeight = ceil(measured.height) + 6
        guard neededHeight > base.height else {
            return base.intersection(canvas)
        }

        let absoluteCeiling = min(downwardCeiling, canvas.maxY)
        let absoluteFloor = max(upwardFloor, canvas.minY)
        let downwardRoom = max(0, absoluteCeiling - base.maxY)
        let upwardRoom = max(0, base.minY - absoluteFloor)

        // Keep masks close to the original OCR line. Large expansion creates
        // opaque white bands that can cover the next translated line. Prefer
        // shrinking the translated text to fit rather than borrowing the
        // neighbouring line's space.
        let maxHeight = min(base.height + downwardRoom + upwardRoom, base.height * 1.20)
        let finalHeight = min(neededHeight, maxHeight)
        let extra = finalHeight - base.height

        // Spend the room downward first, then upward.
        let growDown = min(extra, downwardRoom)
        let growUp = min(extra - growDown, upwardRoom)
        let expanded = CGRect(
            x: base.minX,
            y: base.minY - growUp,
            width: base.width,
            height: base.height + growUp + growDown
        )
        return expanded.intersection(canvas)
    }

    /// For each box, the Y coordinate it is allowed to grow downward to —
    /// the top of the nearest other box that horizontally overlaps it and
    /// sits below. Boxes with no neighbour below get the canvas height.
    private static func neighborCeilings(for boxes: [RecognizedTextBox], canvasHeight: CGFloat) -> [CGFloat] {
        boxes.enumerated().map { index, box in
            var ceiling = canvasHeight
            for (otherIndex, other) in boxes.enumerated() where otherIndex != index {
                guard other.rect.minY >= box.rect.maxY - 1 else { continue }
                let horizontalOverlap = min(box.rect.maxX, other.rect.maxX) - max(box.rect.minX, other.rect.minX)
                guard horizontalOverlap > min(box.rect.width, other.rect.width) * 0.2 else { continue }
                if other.rect.minY < ceiling { ceiling = other.rect.minY }
            }
            return max(box.rect.maxY, ceiling - 2)
        }
    }

    /// For each box, the Y coordinate above the box that it is allowed to grow
    /// upward to — the bottom of the nearest box that horizontally overlaps it
    /// and sits above. Boxes with no neighbour above get 0 (top of canvas).
    private static func neighborFloors(for boxes: [RecognizedTextBox]) -> [CGFloat] {
        boxes.enumerated().map { index, box in
            var floor: CGFloat = 0
            for (otherIndex, other) in boxes.enumerated() where otherIndex != index {
                guard other.rect.maxY <= box.rect.minY + 1 else { continue }
                let horizontalOverlap = min(box.rect.maxX, other.rect.maxX) - max(box.rect.minX, other.rect.minX)
                guard horizontalOverlap > min(box.rect.width, other.rect.width) * 0.2 else { continue }
                if other.rect.maxY > floor { floor = other.rect.maxY }
            }
            return min(box.rect.minY, floor + 2)
        }
    }

    // MARK: - Text drawing (CoreText, cross-platform)

    private func makeFont(size: CGFloat) -> CTFont {
        // Match the iOS app's previous look (semibold system font). Use the
        // platform's preferred system UI font family.
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontSizeAttribute: size,
            kCTFontTraitsAttribute: [
                kCTFontWeightTrait: 0.3 // approx semibold
            ]
        ] as CFDictionary)
        return CTFontCreateUIFontForLanguage(.system, size, nil)
            ?? CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    private func measureText(_ text: String, font: CTFont, maxWidth: CGFloat) -> CGSize {
        let attr = makeAttributedString(text, font: font, color: nil)
        let framesetter = CTFramesetterCreateWithAttributedString(attr)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            nil
        )
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }

    private func makeAttributedString(_ text: String, font: CTFont, color: CGColor?) -> CFAttributedString {
        // 0.95 line-height multiple: Chinese/Japanese/Korean glyphs don't need
        // Latin-style leading; tightening the line height makes multi-line
        // translations fit their source line height much more often.
        let lineHeight = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
        let tightHeight = lineHeight * 0.95
        let alignmentPtr = UnsafeMutablePointer<CTTextAlignment>.allocate(capacity: 1)
        let maxPtr = UnsafeMutablePointer<CGFloat>.allocate(capacity: 1)
        let minPtr = UnsafeMutablePointer<CGFloat>.allocate(capacity: 1)
        defer {
            alignmentPtr.deallocate()
            maxPtr.deallocate()
            minPtr.deallocate()
        }
        alignmentPtr.pointee = .left
        maxPtr.pointee = tightHeight
        minPtr.pointee = tightHeight
        let settings = [
            CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: alignmentPtr),
            CTParagraphStyleSetting(spec: .maximumLineHeight, valueSize: MemoryLayout<CGFloat>.size, value: maxPtr),
            CTParagraphStyleSetting(spec: .minimumLineHeight, valueSize: MemoryLayout<CGFloat>.size, value: minPtr)
        ]
        let paragraphStyle = CTParagraphStyleCreate(settings, settings.count)

        var attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTParagraphStyleAttributeName: paragraphStyle
        ]
        if let color {
            attributes[kCTForegroundColorAttributeName] = color
        }
        return CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)
            ?? NSAttributedString(string: text) as CFAttributedString
    }

    private func drawText(
        _ text: String,
        in rect: CGRect,
        flippedRect: CGRect,
        context: CGContext,
        foreground: CGColor,
        targetFontSize: CGFloat
    ) {
        // Start at the target font size (visually matching the source UI).
        // Keep long translations inside their own OCR region. A smaller
        // legible font is preferable to allowing CoreText to clip lines or
        // painting over the following text region.
        let minimumFontSize: CGFloat = 5
        var fontSize = max(minimumFontSize, targetFontSize)

        func fits(_ size: CGFloat) -> Bool {
            let measured = measureText(text, font: makeFont(size: size), maxWidth: rect.width)
            return measured.height <= rect.height && measured.width <= rect.width
        }

        while fontSize > minimumFontSize, !fits(fontSize) {
            fontSize = max(minimumFontSize, fontSize - 0.5)
        }

        let font = makeFont(size: fontSize)
        let measured = measureText(text, font: font, maxWidth: rect.width)

        // Vertically center for boxes that closely match the text height
        // (single-line translations look natural sitting where the source
        // text was). For tall merged paragraphs — where the translated text
        // is much more compact than the original — center wastes the rect;
        // align to the top so the translation starts where the source did.
        let slack = rect.height - measured.height
        let topAlign = slack > measured.height
        let yOffset: CGFloat = topAlign ? 0 : max(0, slack / 2)
        let usedHeight = min(rect.height, max(measured.height, fontSize * 2))

        // Convert "top y offset in top-left coords" into a CG-bottom-left
        // rect that CoreText can draw into. yOffset moves down from the top
        // of the source rect; in CG terms, the drawn rect's max-y stays
        // pinned to flippedRect.maxY when yOffset=0 (top-aligned), and shifts
        // downward (lower max-y) as yOffset grows.
        let drawRect = CGRect(
            x: flippedRect.minX,
            y: flippedRect.maxY - yOffset - usedHeight,
            width: flippedRect.width,
            height: usedHeight
        )

        let attr = makeAttributedString(text, font: font, color: foreground)
        let framesetter = CTFramesetterCreateWithAttributedString(attr)
        let path = CGPath(rect: drawRect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, context)
    }

    // MARK: - Colour palette

    private struct ColorPalette {
        let foreground: CGColor
        let background: CGColor
    }

    private static let blackColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    private static let whiteColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

    /// Post-process the sampled palette to guarantee readable text. When the
    /// sampled foreground/background luminance delta is below ~0.35, the
    /// translation reads as a faded smudge against the mask even though both
    /// colours individually look correct. Force the foreground to black or
    /// white (whichever wins the contrast race against the background) when
    /// the natural delta is too small.
    private static func ensureContrast(_ palette: ColorPalette) -> ColorPalette {
        let bgLum = lumOf(palette.background)
        let fgLum = lumOf(palette.foreground)
        guard abs(bgLum - fgLum) < 0.35 else { return palette }
        let forced = bgLum > 0.5 ? blackColor : whiteColor
        return ColorPalette(foreground: forced, background: palette.background)
    }

    private static func lumOf(_ color: CGColor) -> CGFloat {
        guard let components = color.components else { return 0 }
        let count = color.numberOfComponents
        if count >= 3 {
            return 0.2126 * components[0] + 0.7152 * components[1] + 0.0722 * components[2]
        } else if count >= 1 {
            return components[0]
        }
        return 0
    }

    /// Sample foreground/background colours for the translation overlay.
    ///
    /// Strategy in order of preference:
    /// 1. If Vision gave us per-glyph rects, sample foreground from inside the
    ///    glyphs and background from gaps outside the glyphs. This works on
    ///    gradients, photos, and translucent overlays because we're looking at
    ///    where the actual text pixels live rather than the box as a whole.
    /// 2. Otherwise, fall back to inset luminance clustering — sample pixels
    ///    inside an inset of the OCR box, split them at the midpoint of the
    ///    observed luminance range, treat the bigger cluster as background.
    /// 3. If contrast is too low (no clear text/background distinction), use
    ///    the overall average colour as background and pick black/white for
    ///    the foreground.
    private func sampledPalette(from image: CGImage, box: RecognizedTextBox) -> ColorPalette {
        guard let dataProvider = image.dataProvider,
              let data = dataProvider.data,
              let bytes = CFDataGetBytePtr(data) else {
            return ColorPalette(foreground: Self.blackColor, background: Self.whiteColor)
        }
        let bytesPerPixel = max(1, image.bitsPerPixel / 8)
        let bytesPerRow = image.bytesPerRow
        let width = image.width
        let height = image.height
        let totalBytes = CFDataGetLength(data)

        let finiteGlyphs = box.glyphRects.filter(Self.isFiniteRect)
        if !finiteGlyphs.isEmpty, let palette = Self.glyphBoundedPalette(
            bytes: bytes,
            totalBytes: totalBytes,
            bytesPerPixel: bytesPerPixel,
            bytesPerRow: bytesPerRow,
            imageWidth: width,
            imageHeight: height,
            outer: box.rect,
            glyphs: finiteGlyphs
        ) {
            return palette
        }

        return Self.boxedLuminancePalette(
            bytes: bytes,
            totalBytes: totalBytes,
            bytesPerPixel: bytesPerPixel,
            bytesPerRow: bytesPerRow,
            imageWidth: width,
            imageHeight: height,
            originalBox: box.rect
        )
    }

    private static func glyphBoundedPalette(
        bytes: UnsafePointer<UInt8>,
        totalBytes: Int,
        bytesPerPixel: Int,
        bytesPerRow: Int,
        imageWidth: Int,
        imageHeight: Int,
        outer: CGRect,
        glyphs: [CGRect]
    ) -> ColorPalette? {
        var fgSamples: [(r: Int, g: Int, b: Int, lum: CGFloat)] = []
        var bgSamples: [(r: Int, g: Int, b: Int, lum: CGFloat)] = []

        for glyph in glyphs where isFiniteRect(glyph) {
            let inset = max(1, min(glyph.width, glyph.height) * 0.15)
            let inner = glyph.insetBy(dx: inset, dy: inset)
            guard isFiniteRect(inner), inner.width > 0, inner.height > 0 else {
                continue
            }
            let strideX = max(1, Int(inner.width / 4))
            let strideY = max(1, Int(inner.height / 3))
            var y = max(0, Int(inner.minY))
            let maxY = min(imageHeight - 1, Int(inner.maxY))
            let maxX = min(imageWidth - 1, Int(inner.maxX))
            while y <= maxY {
                var x = max(0, Int(inner.minX))
                while x <= maxX {
                    let offset = y * bytesPerRow + x * bytesPerPixel
                    if offset + 2 < totalBytes {
                        let r = Int(bytes[offset]), g = Int(bytes[offset + 1]), b = Int(bytes[offset + 2])
                        let lum = luminance(r: r, g: g, b: b)
                        fgSamples.append((r, g, b, lum))
                    }
                    x += strideX
                }
                y += strideY
            }
        }
        guard !fgSamples.isEmpty else { return nil }

        let pad: CGFloat = 1
        let strideX = max(1, Int(outer.width / 24))
        let strideY = max(1, Int(outer.height / 12))
        var y = max(0, Int(outer.minY))
        let maxY = min(imageHeight - 1, Int(outer.maxY))
        let maxX = min(imageWidth - 1, Int(outer.maxX))
        while y <= maxY {
            var x = max(0, Int(outer.minX))
            while x <= maxX {
                let point = CGPoint(x: CGFloat(x), y: CGFloat(y))
                let insideGlyph = glyphs.contains { $0.insetBy(dx: -pad, dy: -pad).contains(point) }
                if !insideGlyph {
                    let offset = y * bytesPerRow + x * bytesPerPixel
                    if offset + 2 < totalBytes {
                        let r = Int(bytes[offset]), g = Int(bytes[offset + 1]), b = Int(bytes[offset + 2])
                        let lum = luminance(r: r, g: g, b: b)
                        bgSamples.append((r, g, b, lum))
                    }
                }
                x += strideX
            }
            y += strideY
        }
        guard !bgSamples.isEmpty else { return nil }

        let fg = average(fgSamples)
        let bg = average(bgSamples)
        if abs(fg.lum - bg.lum) < 0.10 {
            return nil
        }
        return ColorPalette(foreground: fg.color, background: bg.color)
    }

    private static func isFiniteRect(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite
            && rect.origin.y.isFinite
            && rect.width.isFinite
            && rect.height.isFinite
    }

    private static func boxedLuminancePalette(
        bytes: UnsafePointer<UInt8>,
        totalBytes: Int,
        bytesPerPixel: Int,
        bytesPerRow: Int,
        imageWidth: Int,
        imageHeight: Int,
        originalBox: CGRect
    ) -> ColorPalette {
        let inset = max(2, min(originalBox.width, originalBox.height) * 0.08)
        let sample = originalBox.insetBy(dx: inset, dy: inset)
        let minX = max(0, Int(sample.minX))
        let maxX = min(imageWidth - 1, Int(sample.maxX))
        let minY = max(0, Int(sample.minY))
        let maxY = min(imageHeight - 1, Int(sample.maxY))
        guard maxX > minX, maxY > minY else {
            return ColorPalette(foreground: blackColor, background: whiteColor)
        }

        let strideX = max(1, (maxX - minX) / 24)
        let strideY = max(1, (maxY - minY) / 12)

        var samples: [(r: Int, g: Int, b: Int, lum: CGFloat)] = []
        samples.reserveCapacity(256)
        var minLum: CGFloat = 1
        var maxLum: CGFloat = 0

        var y = minY
        while y <= maxY {
            var x = minX
            while x <= maxX {
                let offset = y * bytesPerRow + x * bytesPerPixel
                if offset + 2 < totalBytes {
                    let r = Int(bytes[offset]), g = Int(bytes[offset + 1]), b = Int(bytes[offset + 2])
                    let lum = luminance(r: r, g: g, b: b)
                    samples.append((r, g, b, lum))
                    if lum < minLum { minLum = lum }
                    if lum > maxLum { maxLum = lum }
                }
                x += strideX
            }
            y += strideY
        }
        guard !samples.isEmpty else {
            return ColorPalette(foreground: blackColor, background: whiteColor)
        }

        let meanLum = samples.reduce(0) { $0 + $1.lum } / CGFloat(samples.count)
        let variance = samples.reduce(0) { acc, s in
            let d = s.lum - meanLum
            return acc + d * d
        } / CGFloat(samples.count)
        let stdLum = sqrt(variance)
        let contrastThreshold = max(0.10, stdLum * 1.5)
        guard (maxLum - minLum) > contrastThreshold else {
            let avg = average(samples)
            return ColorPalette(foreground: avg.lum > 0.55 ? blackColor : whiteColor, background: avg.color)
        }

        let midpoint = (minLum + maxLum) / 2
        let darkCluster = samples.filter { $0.lum <= midpoint }
        let brightCluster = samples.filter { $0.lum > midpoint }
        guard !darkCluster.isEmpty, !brightCluster.isEmpty else {
            let avg = average(samples)
            return ColorPalette(foreground: avg.lum > 0.55 ? blackColor : whiteColor, background: avg.color)
        }

        let darkAvg = average(darkCluster)
        let brightAvg = average(brightCluster)
        if brightCluster.count >= darkCluster.count {
            return ColorPalette(foreground: darkAvg.color, background: brightAvg.color)
        } else {
            return ColorPalette(foreground: brightAvg.color, background: darkAvg.color)
        }
    }

    private static func luminance(r: Int, g: Int, b: Int) -> CGFloat {
        (0.2126 * CGFloat(r) + 0.7152 * CGFloat(g) + 0.0722 * CGFloat(b)) / 255
    }

    private static func average(_ samples: [(r: Int, g: Int, b: Int, lum: CGFloat)]) -> (color: CGColor, lum: CGFloat) {
        var rSum = 0, gSum = 0, bSum = 0
        var lSum: CGFloat = 0
        for s in samples {
            rSum += s.r; gSum += s.g; bSum += s.b; lSum += s.lum
        }
        let n = CGFloat(samples.count)
        let color = CGColor(
            srgbRed: CGFloat(rSum) / n / 255,
            green: CGFloat(gSum) / n / 255,
            blue: CGFloat(bSum) / n / 255,
            alpha: 1
        )
        return (color, lSum / n)
    }
}
