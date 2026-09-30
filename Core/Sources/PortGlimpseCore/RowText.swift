import Foundation

/// The words a row shows about itself, kept here so they are tested with the rules that produce them.
extension Row {
    /// "1 worker" or "3 workers"; nil when nothing is folded into the row.
    public var workerSummary: String? {
        switch workerPIDs.count {
        case 0: nil
        case 1: "1 worker"
        case let count: "\(count) workers"
        }
    }

    /// The question asked before killing, naming the workers that stop with the server.
    public var killQuestion: String {
        let workers = workerSummary.map { " and \($0)" } ?? ""
        return "Kill \(command)\(workers) on :\(ports[0])?"
    }
}
