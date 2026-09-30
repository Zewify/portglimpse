import Testing
@testable import PortGlimpseCore

struct ClassifierTests {
    let me: UInt32 = 501

    func section(_ path: String?, uid: UInt32? = 501, overrides: [String: Placement] = [:]) -> Section {
        Classifier(currentUID: me, overrides: overrides).section(for: ProcessDetails(executablePath: path, uid: uid))
    }

    @Test func anotherUsersProcessIsOtherUsers() {
        #expect(section("/usr/local/bin/node", uid: 0) == .otherUsers)
    }

    @Test func unknownOwnerIsOtherUsers() {
        #expect(section("/usr/local/bin/node", uid: nil) == .otherUsers)
    }

    @Test func nodeIsDev() {
        #expect(section("/usr/local/bin/node") == .dev)
    }

    @Test func homebrewServerIsDev() {
        #expect(section("/opt/homebrew/Cellar/redis/7.2.4/bin/redis-server") == .dev)
    }

    @Test func applicationIsAppsAndSystem() {
        #expect(section("/Applications/DBeaver.app/Contents/MacOS/dbeaver") == .appsAndSystem)
    }

    @Test func helperNestedInAnAppIsAppsAndSystem() {
        #expect(section("/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/130.0/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper") == .appsAndSystem)
    }

    @Test func systemServicesAreAppsAndSystem() {
        #expect(section("/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter") == .appsAndSystem)
        #expect(section("/usr/libexec/rapportd") == .appsAndSystem)
        #expect(section("/usr/sbin/cupsd") == .appsAndSystem)
    }

    // Review Focus 1: Python's executable lives inside Python.app, but a Python server is a dev server.
    @Test func commandLineToolsPythonIsDev() {
        #expect(section("/Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python") == .dev)
    }

    @Test func xcodePythonIsDev() {
        #expect(section("/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python") == .dev)
    }

    @Test func missingPathIsAppsAndSystem() {
        #expect(section(nil) == .appsAndSystem)
    }

    @Test func overridesWinOverTheRule() {
        let dbeaver = "/Applications/DBeaver.app/Contents/MacOS/dbeaver"
        #expect(section(dbeaver, overrides: [dbeaver: .dev]) == .dev)
        #expect(section("/usr/local/bin/node", overrides: ["/usr/local/bin/node": .appsAndSystem]) == .appsAndSystem)
    }

    @Test func overridesNeverApplyToOtherUsers() {
        #expect(section("/usr/local/bin/node", uid: 0, overrides: ["/usr/local/bin/node": .dev]) == .otherUsers)
    }

    @Test func appBundleIsTheOutermostApp() {
        #expect(Classifier.appBundle(containing: "/Applications/DBeaver.app/Contents/MacOS/dbeaver") == "/Applications/DBeaver.app")
        #expect(Classifier.appBundle(containing: "/Applications/Google Chrome.app/Contents/Frameworks/X.framework/Helpers/Helper.app/Contents/MacOS/Helper") == "/Applications/Google Chrome.app")
        #expect(Classifier.appBundle(containing: "/usr/local/bin/node") == nil)
    }

    @Test func runtimeBundledInAnAppIsAppsAndSystem() {
        #expect(section("/Applications/Some.app/Contents/Resources/node") == .appsAndSystem)
        #expect(section("/Applications/Some.app/Contents/MacOS/java") == .appsAndSystem)
    }
}
