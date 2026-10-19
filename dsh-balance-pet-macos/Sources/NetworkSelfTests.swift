import Foundation

/// Offline fixtures exercise the same parser and credential helpers as the app.
/// Only temporary files are written; no real keys are read or requests resumed.
enum NetworkSelfTests {
    static func run() -> Int {
        print("== network and credential self-test (offline) ==")
        var failures = 0
        func expect(_ condition: Bool, _ label: String) {
            print((condition ? "  PASS  " : "  FAIL  ") + label)
            if !condition { failures += 1 }
        }
        func parse(_ json: String, _ mode: AuthMode = .account) throws -> BalanceReading {
            try BalanceClient.parseResponse(status: 200, data: Data(json.utf8), mode: mode)
        }
        func rejected(_ json: String, _ mode: AuthMode = .account) -> Bool {
            do { _ = try parse(json, mode); return false }
            catch { return true }
        }
        func wallet(_ amount: String) -> String {
            "{\"normal_wallets\":[{\"currency\":\"CNY\",\"balance\":\(amount)}]}"
        }

        let fixture = #"{"code":0,"data":{"biz_code":0,"biz_data":{"normal_wallets":[{"currency":"CNY","balance":"38.6177023600000000"}],"bonus_wallets":[{"currency":"CNY","balance":"1.5"}],"total_costs":[{"currency":"CNY","amount":"0.00"}]}}}"#
        let reading = try? parse(fixture)
        expect(reading?.totalCents == 4012 && reading?.spentCny == 0, "platform envelope sums normal and bonus with a zero spent total")
        expect((try? parse(wallet("\"1.005\"")))?.totalCents == 101, "decimal half fen rounds correctly")
        expect((try? parse(wallet("\"-0.015\"")))?.totalCents == -2, "negative decimal half fen rounds correctly")
        expect((try? parse(#"{"normal_wallets":[{"currency":"CNY","balance":"0.1"}],"bonus_wallets":[{"currency":"CNY","balance":"0.2"}]}"#))?.totalCents == 30,
               "decimal wallet addition has no binary drift")
        expect((try? parse(#"{"is_available":true,"balance_infos":[{"currency":"USD","total_balance":"8"},{"currency":"CNY","total_balance":"1.005"}]}"#, .apiKey))?.totalCents == 101,
               "API key balance selects CNY when USD is also present")
        expect((try? parse(#"{"normal_wallets":[{"currency":"CNY","balance":"0"},{"currency":"USD","balance":"10"}]}"#))?.totalCents == 0,
               "zero CNY never falls back to another currency")
        expect(rejected(#"{"normal_wallets":[{"currency":"USD","balance":"12"}]}"#), "account USD-only wallet is rejected")
        expect(rejected(#"{"balance_infos":[{"currency":"USD","total_balance":"12"}]}"#, .apiKey), "API USD-only balance is rejected")
        expect(rejected(#"{"normal_wallets":[]}"#), "missing CNY wallet is not invented as zero")
        expect(rejected(#"{"normal_wallets":[{"currency":"CNY"}]}"#), "missing amount is rejected")
        for invalid in ["true", "false", "null", "\"NaN\"", "\"Infinity\"", "\"12oops\"", "\"1e500\"", "\"99999999999999999999\""] {
            expect(rejected(wallet(invalid)), "invalid/overflowing monetary scalar rejected: " + invalid)
        }
        expect(rejected(#"{"code":7,"data":{"normal_wallets":[{"currency":"CNY","balance":"12"}]}}"#), "nonzero platform code rejects otherwise valid balances")
        expect(rejected(#"{"code":0,"data":{"biz_code":2,"biz_data":{"normal_wallets":[{"currency":"CNY","balance":"12"}]}}}"#), "nonzero business code rejects stale balances")
        expect(rejected(#"{"code":true,"data":{"normal_wallets":[{"currency":"CNY","balance":"12"}]}}"#), "boolean success code is invalid")
        expect(rejected(#"{"debug":{"normal_wallets":[{"currency":"CNY","balance":"12"}]}}"#), "unrelated nested wallet is not accepted")
        expect(rejected(#"{"normal_wallets":[{"currency":"CNY","balance":"1"}],"bonus_wallets":{}}"#), "malformed optional wallet is not silently discarded")
        do {
            _ = try parse(#"{"code":0,"data":{"biz_code":40003}}"#)
            expect(false, "expired account grant is an auth error")
        } catch FetchError.auth { expect(true, "expired account grant is an auth error") }
        catch { expect(false, "expired account grant is an auth error") }
        do {
            _ = try BalanceClient.parseResponse(status: 502, data: Data("echoed-fixture-token".utf8), mode: .account)
            expect(false, "server error body is excluded from user-facing errors")
        } catch let error as FetchError {
            expect(!error.describe.contains("echoed-fixture-token"), "server error body is excluded from user-facing errors")
        } catch { expect(false, "server error body is excluded from user-facing errors") }

        let now = Date(timeIntervalSince1970: 0)
        expect(BalanceClient.retryDelay("120", now: now) == 120, "Retry-After delta seconds")
        expect(BalanceClient.retryDelay("Thu, 01 Jan 1970 00:02:00 GMT", now: now) == 120, "Retry-After HTTP date")
        expect(BalanceClient.retryDelay("Wed, 31 Dec 1969 23:59:00 GMT", now: now) == 0, "past Retry-After date clamps to zero")
        expect(BalanceClient.retryDelay("999999999", now: now) == 86_400, "huge Retry-After is bounded")
        for value in ["NaN", "inf", "-1", "1.5", "invalid"] {
            expect(BalanceClient.retryDelay(value, now: now) == nil, "malformed Retry-After rejected: " + value)
        }
        do {
            _ = try BalanceClient.parseResponse(status: 429, data: Data(), headers: ["Retry-After": "60"], mode: .apiKey)
            expect(false, "Retry-After header lookup is case insensitive")
        } catch let error as FetchError { expect(error.retryAfter == 60, "Retry-After header lookup is case insensitive") }
        catch { expect(false, "Retry-After header lookup is case insensitive") }

        let yaml = """
        # DEEPSEEK_API_KEY: commented-fixture-key
        providers:
          DEEPSEEK_API_KEY: 'fixture-api-key' # ignored comment
          'deepseek-account-platform/default':
            token: "fixture-account-token" # another comment

        # comments at column zero do not end the grant
            issuer: 'https://example.invalid/platform/'
            metadata:
              token: unrelated-nested-token
        """
        expect(CredentialStore.yamlAPIKey(from: yaml) == "fixture-api-key", "YAML API key skips comments and handles quotes")
        let grant = CredentialStore.accountGrant(from: yaml)
        expect(grant?.token == "fixture-account-token" && grant?.issuer == "https://example.invalid/platform/", "YAML grant handles comments without accepting nested token")
        // Match DSH's persisted kind/payload wrapper without assuming the kind
        // enum or reading a real credential. Token and issuer are siblings.
        let payloadYAML = """
        credentials:
          deepseek-account-platform/default:
            kind: fixture-account-kind
            payload:
              version: 1
              token: "fixture-payload-token"
              issuer: 'https://example.invalid'
              metadata:
                token: ignored-nested-token
                issuer: https://nested.invalid
            metadata:
              token: ignored-record-token
              issuer: https://record.invalid
        """
        let payloadGrant = CredentialStore.accountGrant(from: payloadYAML)
        expect(payloadGrant?.token == "fixture-payload-token" && payloadGrant?.issuer == "https://example.invalid",
               "DSH kind/payload credential is read from exact sibling fields")
        let legacyYAML = """
        deepseek-account-platform/default:
          token: fixture-legacy-token
          issuer: https://example.invalid
          metadata:
            token: ignored-legacy-metadata-token
            issuer: https://metadata.invalid
        """
        let legacyGrant = CredentialStore.accountGrant(from: legacyYAML)
        expect(legacyGrant?.token == "fixture-legacy-token" && legacyGrant?.issuer == "https://example.invalid",
               "legacy direct account credential remains supported")
        func rejectsGrantBody(_ body: String) -> Bool {
            let yaml = "deepseek-account-platform/default:\n" + body
            return CredentialStore.accountGrant(from: yaml) == nil
        }
        expect(rejectsGrantBody("  payload:\n    token: one\n    metadata:\n      issuer: https://example.invalid"),
               "payload token cannot pair with nested metadata issuer")
        expect(rejectsGrantBody("  first:\n    token: one\n  second:\n    issuer: https://example.invalid"),
               "unrelated sibling containers cannot form a grant")
        expect(rejectsGrantBody("  token: legacy\n  payload:\n    issuer: https://example.invalid"),
               "legacy token cannot pair with payload issuer")
        expect(rejectsGrantBody("  issuer: https://example.invalid\n  payload:\n    token: wrapped"),
               "payload token cannot pair with legacy issuer")
        expect(rejectsGrantBody("  token: legacy\n  issuer: https://legacy.invalid\n  payload:\n    token: wrapped\n    issuer: https://wrapped.invalid"),
               "ambiguous complete legacy and payload records are rejected")
        expect(rejectsGrantBody("  payload:\n    token: one\n    issuer: https://example.invalid\n  payload:\n    token: two\n    issuer: https://other.invalid"),
               "duplicate payload containers are rejected")
        expect(rejectsGrantBody("  payload:\n    token: one\n    token: two\n    issuer: https://example.invalid"),
               "duplicate payload token is rejected")
        expect(rejectsGrantBody("  payload:\n    token: one\n    issuer: https://example.invalid\n    issuer: https://other.invalid"),
               "duplicate payload issuer is rejected")
        expect(rejectsGrantBody("  token: one\n  issuer: https://example.invalid\n  issuer: https://other.invalid"),
               "duplicate legacy issuer is rejected")
        for value in ["plain-scalar", "'quoted-scalar'", "null", "[]", "true"] {
            expect(rejectsGrantBody("  kind: fixture-account-kind\n  payload: " + value),
                   "scalar or unsupported payload cannot authenticate: " + value)
        }
        expect(CredentialStore.yamlAPIKey(from: "# DEEPSEEK_API_KEY: ignored-key") == nil, "commented-out credential cannot authenticate")
        expect(CredentialStore.yamlAPIKey(from: "DEEPSEEK_API_KEY: first-key\nDEEPSEEK_API_KEY: second-key") == nil, "duplicate YAML key is rejected")
        expect(CredentialStore.accountGrant(from: "deepseek-account-platform/default:\n  token: one\n  token: two\n  issuer: https://example.invalid") == nil,
               "duplicate grant field is rejected")
        expect(CredentialStore.accountGrant(from: "deepseek-account-platform/default:\n  token: |\n    multiline\n  issuer: https://example.invalid") == nil,
               "unsupported multiline token fails closed")
        expect(CredentialStore.accountEndpoint(issuer: "https://example.invalid/base/", path: "/api/test")?.absoluteString == "https://example.invalid/base/api/test",
               "issuer path is joined predictably")
        for issuer in ["http://example.invalid", "file:///tmp/key", "https://user:pass@example.invalid", "https://example.invalid?token=x", "https://example.invalid#fragment", "https://exa mple.invalid"] {
            expect(CredentialStore.accountEndpoint(issuer: issuer, path: "/api/test") == nil, "unsafe issuer rejected")
        }
        for path in ["//other.invalid/test", "/../test", "/api?x=1", "/api#secret", "/%2e%2e/test"] {
            expect(CredentialStore.accountEndpoint(issuer: "https://example.invalid", path: path) == nil, "unsafe endpoint override rejected")
        }
        expect(!CredentialStore.isValidToken("a\r\nInjected: x") && !CredentialStore.isValidToken("key with spaces"), "credential header injection is rejected")

        let delegate = BalanceSessionDelegate()
        let session = URLSession(configuration: .ephemeral)
        let url = URL(string: "https://example.invalid")!
        let task = session.dataTask(with: url) // never resumed
        let redirect = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: ["Location": "https://other.invalid"])!
        var refused = false
        delegate.urlSession(session, task: task, willPerformHTTPRedirection: redirect,
                            newRequest: URLRequest(url: URL(string: "https://other.invalid")!)) { refused = $0 == nil }
        expect(refused, "authenticated redirects are refused before forwarding")
        session.invalidateAndCancel()

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dsh-network-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let keyURL = directory.appendingPathComponent("apikey.txt")
            try CredentialStore.saveAPIKey(" fixture-initial-key\n", to: keyURL)
            try CredentialStore.saveAPIKey("fixture-replacement-key", to: keyURL)
            let saved = try String(contentsOf: keyURL, encoding: .utf8)
            let mode = (try FileManager.default.attributesOfItem(atPath: keyURL.path)[.posixPermissions] as? NSNumber)?.intValue
            expect(saved == "fixture-replacement-key" && mode == 0o600, "saved/replaced key has mode 0600")
            do {
                try CredentialStore.saveAPIKey("bad\ninjected", to: keyURL)
                expect(false, "invalid key write leaves previous key intact")
            } catch {
                expect((try? String(contentsOf: keyURL, encoding: .utf8)) == saved, "invalid key write leaves previous key intact")
            }
            do {
                try CredentialStore.saveAPIKey("fixture-key", to: directory)
                expect(false, "write failure is reported")
            } catch { expect(true, "write failure is reported") }
            let stateURL = directory.appendingPathComponent("state.json")
            try Data(#"{"sizeIndex":999,"pollSeconds":-1,"originX":0,"originY":0}"#.utf8).write(to: stateURL)
            let loaded = PetState.load(from: stateURL)
            expect(loaded.sizeIndex == 1 && loaded.pollSeconds == 10, "invalid saved size and poll interval are bounded")
            var state = PetState()
            state.pollSeconds = .infinity
            state.windowOrigin = CGPoint(x: CGFloat.infinity, y: 0)
            state.save(to: stateURL)
            let restored = PetState.load(from: stateURL)
            expect(restored.pollSeconds == 30 && restored.windowOrigin == nil, "nonfinite state cannot corrupt JSON")
        } catch {
            expect(false, "temporary credential/state fixture operations completed")
        }
        return failures
    }
}
