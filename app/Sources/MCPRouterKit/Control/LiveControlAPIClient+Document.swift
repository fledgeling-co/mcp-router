import Foundation

/// `GET /servers/:name/document` — M30's route, from the app's side.
///
/// In a file of its own because it is the one read whose failures are a **different error type**.
/// Every other operation on this client answers `ControlAPIError`; this one answers
/// `CapabilityDocumentError`, because the panel's designed states are "nothing is published", "this
/// server has no package" and "the document is over the cap" — and folding those into
/// *the router couldn't complete that* would give the product one wording for four situations, which
/// is what `DESIGN.md` §6 forbids.
public extension LiveControlAPIClient {
    func capabilityDocument(for server: String) async throws(CapabilityDocumentError) -> Payload {
        let envelope: DocumentEnvelope
        switch await documentEnvelope(for: server) {
        case let .success(decoded):
            envelope = decoded
        case let .failure(error):
            // 405 is what a router built before this route answers: `isControlPath` claims
            // `/servers/…` either way, so the path is owned and the method is refused rather than
            // the path being unknown. That is version skew, and it takes the wording this client
            // already carries for it.
            if case let .server(status, _, _) = error, status == 405 {
                throw .router(.malformedResponse(detail: "this router has no document route"))
            }
            throw .router(error)
        }

        if let refusal = envelope.refusal {
            throw ControlAPICapabilityDocumentSource.error(from: refusal, capability: server)
        }
        guard let payload = envelope.payload else {
            // A 404 with no `reason` is the route's existing unknown-server answer, which reaches
            // here as neither a payload nor a typed refusal.
            throw .notFound(capability: server)
        }
        return payload
    }

    /// The request behind `capabilityDocument(for:)`, answered as a `Result` rather than thrown.
    ///
    /// Swift 6.4 (swiftlang-6.4.0.34.1) crashes in SILGen when a typed `throw` sits inside a
    /// `catch` clause: `emitCatchDispatch` → `emitThrow` → `createInitExistentialRef` trips
    /// `isBridgeableObjectType()` for this function. Returning the failure keeps the `throw` out of
    /// the `catch`, and the caller maps it to `CapabilityDocumentError` where the throw is legal.
    private func documentEnvelope(for server: String) async -> Result<DocumentEnvelope, ControlAPIError> {
        do {
            return try await .success(send(
                .get,
                "servers/\(segment(server))/document",
                // The route's own refusals carry a typed body. Passing them through the generic
                // failure path would reduce a named state to a status code and a sentence.
                typedFailureStatuses: [404, 413],
                as: DocumentEnvelope.self
            ))
        } catch {
            return .failure(error)
        }
    }
}

/// Either the document or the refusal, decided by whether the body carries a `reason`.
///
/// One type rather than two calls: the route answers 200 with a payload and 404/413 with a refusal,
/// and both arrive through the same request. Decoding is attempted in refusal-first order because a
/// refusal body is the smaller shape and a payload never carries `reason`.
struct DocumentEnvelope: Decodable {
    let payload: CapabilityDocumentPayload?
    let refusal: CapabilityDocumentRefusal?

    private enum ProbeKeys: String, CodingKey { case reason }

    init(from decoder: any Decoder) throws {
        let probe = try decoder.container(keyedBy: ProbeKeys.self)
        if probe.contains(.reason) {
            payload = nil
            refusal = try CapabilityDocumentRefusal(from: decoder)
            return
        }
        refusal = nil
        payload = try? CapabilityDocumentPayload(from: decoder)
    }
}
