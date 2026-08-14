import Foundation

/// The `/usage` endpoints.
///
/// Split from the dispatcher so neither file outgrows the limits the repo lints for; the ordering
/// and coercion rules are unchanged and are the reference's.
extension ControlHandler {
    // MARK: - /usage

    func usageRecent(_ request: ControlRequest, _ deps: ControlDeps) -> ControlResponse {
        // `Number(x ?? 200)` — a junk value is NaN, and `slice(-NaN)` is `slice(0)`, so it returns
        // **every** record rather than none (N4). `Number` is not `Double.init`: an empty value is
        // `0` and a padded one trims, where `Double` yields nil for both.
        let limit = request.first(named: "limit").map(JSToNumber.number) ?? 200
        let records = deps.usage.recent(
            limit: limit,
            server: request.first(named: "server"),
            cwd: request.first(named: "cwd")
        )
        return .json(200, .object([
            JSONMember(key: "since", value: .string(JSString(deps.usage.summarySince()))),
            JSONMember(key: "records", value: .array(records.map(\.value)))
        ]))
    }

    func usageSummary(_ deps: ControlDeps) -> ControlResponse {
        let stats = deps.usage.summaryServers()
        let rows: [JSONValue] = deps.upstreams.map { entry in
            let stat = stats.first { $0.key == entry.name }?.value.asObjectMembers
            var members: [JSONMember] = [JSONMember(key: "name", value: .string(entry.name))]
            members.append(contentsOf: stat ?? ServerStat.zero.members)
            let projects = (stat.flatMap { members2 in
                members2.first { $0.key == JSString("projects") }?.value.asObjectMembers
            }) ?? []
            members.append(JSONMember(key: "projectNames", value: .array(projects.map { project in
                .object([
                    JSONMember(key: "cwd", value: .string(project.key)),
                    JSONMember(
                        key: "project",
                        value: projectOf(project.key.string)
                            .map { .string(JSString($0)) } ?? .null
                    ),
                    JSONMember(key: "calls", value: project.value)
                ])
            })))
            return .object(members)
        }
        return .json(200, .object([
            JSONMember(key: "since", value: .string(JSString(deps.usage.summarySince()))),
            JSONMember(key: "servers", value: .array(rows))
        ]))
    }

    func usageReset(_ deps: ControlDeps) -> ControlResponse {
        deps.usage.reset()
        return .json(200, .object([
            JSONMember(key: "ok", value: .bool(true)),
            JSONMember(key: "since", value: .string(JSString(deps.usage.summarySince())))
        ]))
    }

    func usageStream() -> ControlResponse {
        ControlResponse(
            status: 200,
            headers: [
                ("content-type", "text/event-stream"),
                ("cache-control", "no-store"),
                ("connection", "keep-alive")
            ],
            body: .stream(ControlStream()),
            handled: true
        )
    }
}
