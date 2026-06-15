import CoreGraphics

/// Applies a target frame to a window using the macOS-safe attribute ordering.
///
/// The Accessibility API exposes a window's position and size as two separate
/// attributes. Setting the size resizes the window *in place* from its current
/// top-left corner, so macOS (and many apps) clamp the requested size to keep
/// the window on screen. If the window currently sits away from the destination
/// corner, that clamp leaves it smaller than intended — and repeated snaps only
/// converge slowly as the window inches toward the corner.
///
/// Setting the position *first* moves the window to the destination corner,
/// giving the subsequent size set room to apply without clamping. The position
/// is then re-asserted because some apps shift their origin when resized
/// (notably the right-half snap, whose origin is not at the screen corner).
///
/// The actual position/size writes live in the Platform adapter; this type owns
/// only the OS-independent *ordering* — which is where the bug was and what the
/// unit test pins down.
public enum WindowFrameApplier {
    public static func apply(
        _ frame: CGRect,
        setPosition: (CGPoint) -> Void,
        setSize: (CGSize) -> Void
    ) {
        setPosition(frame.origin)
        setSize(frame.size)
        setPosition(frame.origin)
    }
}
