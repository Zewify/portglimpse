import Testing
@testable import PortGlimpseCore

struct CommandLabelTests {
    func label(_ arguments: [String], fallback: String = "fallback") -> String {
        CommandLabel.label(arguments: arguments, fallbackName: fallback)
    }

    @Test func nextThroughTheBinShim() {
        #expect(label(["node", "/Users/me/financy/node_modules/.bin/next", "dev"]) == "next dev")
    }

    @Test func nextThroughItsPackage() {
        #expect(label(["node", "/Users/me/app/node_modules/next/dist/bin/next", "dev"]) == "next dev")
    }

    @Test func scopedPackageUsesThePackageName() {
        #expect(label(["node", "/x/node_modules/@vue/cli-service/bin/vue-cli-service.js", "serve"]) == "cli-service serve")
    }

    @Test func viteWithAFullRuntimePath() {
        #expect(label(["/usr/local/bin/node", "/Users/me/dota/node_modules/vite/bin/vite.js"]) == "vite")
    }

    @Test func pythonModule() {
        #expect(label(["python3", "-m", "http.server", "8000"]) == "http.server")
    }

    @Test func pythonScriptWithSubcommand() {
        #expect(label(["/usr/bin/python3", "manage.py", "runserver"]) == "manage.py runserver")
    }

    @Test func capitalisedPythonFromPythonApp() {
        #expect(label(["/Library/Frameworks/Python.framework/Versions/3.12/Resources/Python.app/Contents/MacOS/Python", "-m", "uvicorn"]) == "uvicorn")
    }

    @Test func runtimeFlagsAreSkipped() {
        #expect(label(["node", "--inspect", "server.js"]) == "server.js")
    }

    @Test func runtimeWithSubcommands() {
        #expect(label(["bun", "run", "dev"]) == "bun run dev")
    }

    @Test func plainBinaryIsItsName() {
        #expect(label(["/opt/homebrew/opt/redis/bin/redis-server", "127.0.0.1:6379"]) == "redis-server")
    }

    @Test func noArgumentsUsesTheFallback() {
        #expect(label([], fallback: "mysqld") == "mysqld")
    }

    @Test func longLabelsAreTruncated() {
        let long = String(repeating: "a", count: 60)
        let result = label(["/bin/\(long)"])
        #expect(result.count == 40)
        #expect(result.hasSuffix("…"))
    }
}
