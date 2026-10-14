import Foundation

public struct QueueState: Codable, Sendable {
    public private(set) var jobs: [ConversionJob]
    public let limit: Int
    public init(limit: Int = 1, jobs: [ConversionJob] = []) throws {
        guard (1...4).contains(limit) else { throw MediaForgeError.invalidSettings("Queue concurrency must be one to four.") }
        guard Set(jobs.map(\.id)).count == jobs.count else { throw MediaForgeError.invalidSettings("Queue contains duplicate job identifiers.") }
        guard jobs.filter({ $0.status == .running }).count <= limit else { throw MediaForgeError.invalidSettings("Queue contains more running jobs than its concurrency limit.") }
        self.limit = limit
        self.jobs = jobs
    }
    private enum CodingKeys: String, CodingKey { case jobs, limit }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(limit: values.decode(Int.self, forKey: .limit), jobs: values.decode([ConversionJob].self, forKey: .jobs))
    }
    public mutating func enqueue(_ request: ConversionRequest) throws {
        guard !jobs.contains(where: { $0.id == request.id }) else { throw MediaForgeError.invalidSettings("Job is already queued.") }
        jobs.append(.init(request: request))
    }
    public mutating func claimNext() -> ConversionRequest? {
        guard jobs.filter({ $0.status == .running }).count < limit, let index = jobs.firstIndex(where: { $0.status == .waiting }) else { return nil }
        jobs[index].status = .running
        return jobs[index].request
    }
    public mutating func finish(id: UUID, status: JobStatus, errorMessage: String? = nil) throws {
        guard [.completed, .failed, .cancelled].contains(status), let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].status == .running || (status == .cancelled && jobs[index].status == .waiting) else {
            throw MediaForgeError.invalidSettings("Invalid queue transition.")
        }
        jobs[index].status = status
        jobs[index].errorMessage = errorMessage
    }
    public mutating func recoverInterruptedJobs() {
        for index in jobs.indices where jobs[index].status == .running {
            jobs[index].status = .waiting
            jobs[index].errorMessage = "Interrupted before the app exited; ready to retry."
        }
    }
}
