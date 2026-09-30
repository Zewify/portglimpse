import Testing
@testable import PortGlimpseCore

struct RowTextTests {
    func row(workers: [Int32]) -> Row {
        Row(pid: 20, ports: [5080, 5081], command: "granian wsgi", folder: "~/api", owner: nil, section: .dev, executablePath: "/bin/granian", workerPIDs: workers)
    }

    @Test func aRowWithoutWorkersHasNoSummary() {
        #expect(row(workers: []).workerSummary == nil)
    }

    @Test func workerSummariesCountWorkers() {
        #expect(row(workers: [21]).workerSummary == "1 worker")
        #expect(row(workers: [21, 22, 23]).workerSummary == "3 workers")
    }

    @Test func theKillQuestionNamesTheLowestPort() {
        #expect(row(workers: []).killQuestion == "Kill granian wsgi on :5080?")
    }

    @Test func theKillQuestionMentionsWorkers() {
        #expect(row(workers: [21]).killQuestion == "Kill granian wsgi and 1 worker on :5080?")
        #expect(row(workers: [21, 22]).killQuestion == "Kill granian wsgi and 2 workers on :5080?")
    }
}
