import CoreGraphics
import Foundation

/// The sheet a ``PDFOperation`` paginates onto.
///
/// Two named sizes rather than a free `width×height`: the question a caller
/// actually has is "US or the rest of the world", and a typed choice keeps
/// the paper out of the class of things that can be silently wrong. Both are
/// portrait; the dimensions are the PostScript points AppKit's
/// `NSPrintInfo.paperSize` speaks in (72 to the inch).
public enum PaperSize: String, CaseIterable, Friendly {
    /// US Letter, 8.5×11in — 612×792pt.
    case letter
    /// ISO A4, 210×297mm — 595.28×841.89pt.
    case a4

    /// The sheet's size in points, portrait.
    public var points: CGSize {
        switch self {
        case .letter: CGSize(width: 612, height: 792)
        case .a4: CGSize(width: 595.28, height: 841.89)
        }
    }
}
