import Foundation

public extension DiscoverCopy.DetailKey {
    var entry: DiscoverCopy.Entry {
        switch self {
        case .partialNoRepository:
            // A26: a fact, not a failure. GitHub was never asked, because a Smithery entry's
            // repository is its smithery.ai homepage and that is not a parseable repo URL.
            DiscoverCopy.Entry(
                headline: "Smithery doesn't publish repository activity for this entry.",
                body: "There's no last-commit date or archive status to show."
            )

        case .partialGitHubLimited:
            DiscoverCopy.Entry(
                headline: "Repository details are missing for this entry.",
                body: """
                GitHub limits how often it can be asked, so the last-commit date and archive \
                status couldn't be fetched this time.
                """
            )

        case .offline:
            DiscoverCopy.Entry(
                headline: "The router isn't running on {mac}.",
                body: "You can still save this here — send it from Queue when the router is back."
            )

        case .noLastCommit:
            DiscoverCopy.Entry(body: "No last-commit date")

        case .lastCommit:
            DiscoverCopy.Entry(body: "Last commit {count}")

        case .chipSourceOfficial:
            DiscoverCopy.Entry(body: "Official registry")

        case .chipSourceSmithery:
            DiscoverCopy.Entry(body: "Smithery")

        case .chipSourceBoth:
            DiscoverCopy.Entry(body: "Both registries")

        case .chipArchived:
            DiscoverCopy.Entry(body: "Archived")
        }
    }
}
