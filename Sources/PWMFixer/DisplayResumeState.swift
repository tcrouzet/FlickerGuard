import Foundation
import IOKit

enum LidStateReader {
    static func isClosed() -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
    }
}

struct DisplayResumeState {
    private(set) var pending = false
    private(set) var sleeping = false
    private(set) var applicationBlocked = false
    private var ignoreAmbientUntil: Date?

    var shouldResume: Bool { pending && !sleeping && !applicationBlocked }

    mutating func setApplicationBlocked(_ blocked: Bool) { applicationBlocked = blocked }

    mutating func interrupt(wasActive: Bool, sleeping: Bool) {
        pending = pending || wasActive
        self.sleeping = self.sleeping || sleeping
    }

    mutating func wake() { sleeping = false }

    mutating func didResume(at date: Date = Date()) {
        pending = false
        ignoreAmbientUntil = date.addingTimeInterval(3)
    }

    func canReadAmbient(at date: Date = Date()) -> Bool {
        !sleeping && !applicationBlocked && (ignoreAmbientUntil.map { date >= $0 } ?? true)
    }

    mutating func cancel() {
        pending = false
        ignoreAmbientUntil = nil
    }
}
