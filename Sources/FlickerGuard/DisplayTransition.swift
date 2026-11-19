import Foundation

struct DisplayTransition: Sendable {
    enum Destination: Equatable, Sendable { case native, software }

    struct Levels: Equatable, Sendable {
        let hardware: Float
        let software: Double
    }

    static let duration: TimeInterval = 60
    let destination: Destination
    let from: Levels
    let to: Levels
    let startedAt: Date

    init(from: Levels, to: Levels, destination: Destination, startedAt: Date = Date()) {
        self.from = from
        self.to = to
        self.destination = destination
        self.startedAt = startedAt
    }

    func isComplete(at date: Date = Date()) -> Bool {
        date.timeIntervalSince(startedAt) >= Self.duration
    }

    func levels(at date: Date = Date()) -> Levels {
        let progress = min(1, max(0, date.timeIntervalSince(startedAt) / Self.duration))
        if progress == 0 { return from }
        if progress == 1 { return to }
        let weight = progress * progress * (3 - 2 * progress)
        return Levels(
            hardware: Float(Double(from.hardware) + (Double(to.hardware) - Double(from.hardware)) * weight),
            software: from.software + (to.software - from.software) * weight
        )
    }
}
