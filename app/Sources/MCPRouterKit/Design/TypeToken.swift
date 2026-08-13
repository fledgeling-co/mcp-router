import Foundation

/// The eight type roles from `DESIGN.md` §2. Nothing ships off this ladder.
///
/// 13pt body is the loudest native-versus-web discriminator in the whole system — a 16px body
/// means it is not a Mac app — so the ladder is encoded as data and checked against the design
/// document rather than being retyped per surface.
public enum TypeToken: String, CaseIterable, Sendable {
    case largeTitle = "LargeTitle"
    case title1 = "Title1"
    case title2 = "Title2"
    case title3 = "Title3"
    case body = "Body"
    case callout = "Callout"
    case subheadline = "Subheadline"
    case caption = "Caption"

    public var size: Double {
        switch self {
        case .largeTitle: 26
        case .title1: 22
        case .title2: 17
        case .title3: 15
        case .body: 13
        case .callout: 12
        case .subheadline: 11
        case .caption: 10
        }
    }

    public var lineHeight: Double {
        switch self {
        case .largeTitle: 32
        case .title1: 26
        case .title2: 22
        case .title3: 20
        case .body: 16
        case .callout: 15
        case .subheadline: 14
        case .caption: 13
        }
    }

    /// Emphasis is Semibold, not Bold, below the title roles — stated in `DESIGN.md` §2.
    public var emphasis: TypeEmphasis {
        switch self {
        case .largeTitle, .title1, .title2: .bold
        case .title3, .body, .callout, .subheadline, .caption: .semibold
        }
    }
}

public enum TypeEmphasis: String, CaseIterable, Sendable {
    case bold = "Bold"
    case semibold = "Semibold"
}
