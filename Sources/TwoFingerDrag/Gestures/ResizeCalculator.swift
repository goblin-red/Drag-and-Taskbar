import CoreGraphics

struct ResizeEdgeShares {
    let leading: CGFloat
    let trailing: CGFloat

    static let balanced = ResizeEdgeShares(leading: 0.5, trailing: 0.5)
}

enum ResizeCalculator {
    static func edgeShares(for frame: CGRect, bounds: CGRect?, axis: Int, accX: CGFloat, accY: CGFloat) -> ResizeEdgeShares {
        guard let bounds = bounds else { return .balanced }

        let left = max(0, frame.minX - bounds.minX)
        let right = max(0, bounds.maxX - frame.maxX)
        let top = max(0, frame.minY - bounds.minY)
        let bottom = max(0, bounds.maxY - frame.maxY)
        let horizontalTotal = left + right
        let verticalTotal = top + bottom

        if (axis == 1 || abs(accX) >= abs(accY)), horizontalTotal > 0 {
            return ResizeEdgeShares(leading: left / horizontalTotal, trailing: right / horizontalTotal)
        } else if verticalTotal > 0 {
            return ResizeEdgeShares(leading: top / verticalTotal, trailing: bottom / verticalTotal)
        }

        return .balanced
    }

    static func resizeFrame(_ frame: CGRect, axis: Int, delta: CGFloat, bounds: CGRect?, shares: ResizeEdgeShares) -> CGRect {
        guard abs(delta) > 0.01 else { return frame }
        let minSize: CGFloat = axis == 1 ? 120 : 80

        if delta > 0 {
            guard let bounds = bounds else {
                return centeredResizeFrame(frame, axis: axis, delta: delta, minSize: minSize)
            }
            return growFrame(frame, axis: axis, amount: delta, bounds: bounds, shares: shares)
        } else {
            return shrinkFrame(frame, axis: axis, amount: -delta, minSize: minSize, shares: shares)
        }
    }

    private static func centeredResizeFrame(_ frame: CGRect, axis: Int, delta: CGFloat, minSize: CGFloat) -> CGRect {
        if axis == 1 {
            let width = max(minSize, frame.width + delta)
            return CGRect(x: frame.midX - width / 2, y: frame.minY, width: width, height: frame.height)
        } else {
            let height = max(minSize, frame.height + delta)
            return CGRect(x: frame.minX, y: frame.midY - height / 2, width: frame.width, height: height)
        }
    }

    private static func growFrame(_ frame: CGRect, axis: Int, amount: CGFloat, bounds: CGRect, shares: ResizeEdgeShares) -> CGRect {
        if axis == 1 {
            let leadingCapacity = max(0, frame.minX - bounds.minX)
            let trailingCapacity = max(0, bounds.maxX - frame.maxX)
            let grow = min(amount, leadingCapacity + trailingCapacity)
            let parts = distribute(grow, leadingShare: shares.leading, leadingCapacity: leadingCapacity, trailingCapacity: trailingCapacity)
            return CGRect(x: frame.minX - parts.leading, y: frame.minY, width: frame.width + parts.leading + parts.trailing, height: frame.height)
        } else {
            let leadingCapacity = max(0, frame.minY - bounds.minY)
            let trailingCapacity = max(0, bounds.maxY - frame.maxY)
            let grow = min(amount, leadingCapacity + trailingCapacity)
            let parts = distribute(grow, leadingShare: shares.leading, leadingCapacity: leadingCapacity, trailingCapacity: trailingCapacity)
            return CGRect(x: frame.minX, y: frame.minY - parts.leading, width: frame.width, height: frame.height + parts.leading + parts.trailing)
        }
    }

    private static func shrinkFrame(_ frame: CGRect, axis: Int, amount: CGFloat, minSize: CGFloat, shares: ResizeEdgeShares) -> CGRect {
        if axis == 1 {
            let shrink = min(amount, max(0, frame.width - minSize))
            let leading = shrink * shares.leading
            let trailing = shrink - leading
            return CGRect(x: frame.minX + leading, y: frame.minY, width: frame.width - leading - trailing, height: frame.height)
        } else {
            let shrink = min(amount, max(0, frame.height - minSize))
            let leading = shrink * shares.leading
            let trailing = shrink - leading
            return CGRect(x: frame.minX, y: frame.minY + leading, width: frame.width, height: frame.height - leading - trailing)
        }
    }

    private static func distribute(_ amount: CGFloat, leadingShare: CGFloat, leadingCapacity: CGFloat, trailingCapacity: CGFloat) -> (leading: CGFloat, trailing: CGFloat) {
        guard amount > 0 else { return (0, 0) }
        let share = min(1, max(0, leadingShare))
        var leading = min(leadingCapacity, amount * share)
        var trailing = min(trailingCapacity, amount - leading)
        let missing = amount - leading - trailing

        if missing > 0 {
            let addLeading = min(leadingCapacity - leading, missing)
            leading += addLeading
            trailing += min(trailingCapacity - trailing, missing - addLeading)
        }

        return (leading, trailing)
    }
}
