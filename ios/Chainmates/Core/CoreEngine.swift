import Foundation
import JavaScriptCore

/// Runs the shared game core, `core/handoff-core.js`, in JavaScriptCore.
///
/// Every game rule (validation, guess/undo/hint, scoring, share text, stats, streaks and the
/// date-to-puzzle mapping) lives in that file and is tested once in Node. The app never
/// re-implements one: it hands the core JSON and decodes the JSON it answers
/// (docs/decisions.md, "iOS architecture").
///
/// The core's index (`buildIndex(players.json)`) is built once, in the context, and kept there
/// as `__idx`. A game state stays the JSON the core returned (`GameState.json`), so a field the
/// app doesn't know about yet still round-trips untouched.
///
/// It's an actor, so calls are serialized off the main thread; `buildIndex` takes a few hundred
/// milliseconds on JavaScriptCore's interpreter, everything else is far below a frame.
actor CoreEngine {
    enum EngineError: LocalizedError {
        case missingResource(String)
        case javaScript(String)
        case undefinedResult(String)

        var errorDescription: String? {
            switch self {
            case .missingResource(let name): "The app is missing \(name)."
            case .javaScript(let message): "The game engine stopped: \(message)"
            case .undefinedResult(let expression): "The game engine gave no answer to \(expression)."
            }
        }
    }

    private let context: JSContext

    /// Loads the core from `bundle` and builds the index from `playersJSON` (the raw bytes of
    /// players.json). Tests pass the fixture data; the app passes `Bundle.main`'s.
    init(bundle: Bundle = .main, playersJSON: Data) throws {
        guard let url = bundle.url(forResource: "handoff-core", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            throw EngineError.missingResource("handoff-core.js")
        }
        guard let context = JSContext() else { throw EngineError.javaScript("no JavaScript context") }
        context.name = "Chainmates core"
        self.context = context

        var caught: String?
        context.exceptionHandler = { _, value in caught = value?.toString() }
        context.evaluateScript(source, withSourceURL: url)
        if let caught { throw EngineError.javaScript(caught) }

        // JSON.parse in JavaScript is far faster than bridging a Swift dictionary.
        context.setObject(String(decoding: playersJSON, as: UTF8.self), forKeyedSubscript: "__playersText" as NSString)
        context.evaluateScript("var H = HandoffCore; var __idx = H.buildIndex(JSON.parse(__playersText)); __playersText = null;")
        if let caught { throw EngineError.javaScript(caught) }
        // From here on an exception is left in `context.exception` for `evaluate` to throw.
        context.exceptionHandler = { context, exception in context?.exception = exception }
    }

    // MARK: - Calling the core

    /// Evaluates `H.<function>(args...)` and returns the JSON text of its result. Arguments are
    /// encoded to JSON and parsed in the context; pass `CoreEngine.index` to splice in the index.
    func callJSON(_ function: String, _ args: [CoreArg]) throws -> String {
        let argList = args.map(\.javaScript).joined(separator: ", ")
        let expression = "JSON.stringify(H.\(function)(\(argList)))"
        return try evaluate(expression)
    }

    /// `callJSON`, decoded into `T`.
    func call<T: Decodable>(_ type: T.Type, _ function: String, _ args: [CoreArg]) throws -> T {
        let text = try callJSON(function, args)
        return try JSONDecoder().decode(T.self, from: Data(text.utf8))
    }

    /// Evaluates any expression that produces a string, for constants and tests.
    func evaluate(_ expression: String) throws -> String {
        let value = context.evaluateScript(expression)
        if let exception = context.exception, !exception.isUndefined, !exception.isNull {
            context.exception = nil
            throw EngineError.javaScript(exception.toString() ?? "unknown error")
        }
        guard let value, !value.isUndefined, let string = value.toString() else {
            throw EngineError.undefinedResult(expression)
        }
        return string
    }
}

/// One argument to a core function, written into the JavaScript call.
enum CoreArg {
    /// The players index built at launch (`__idx`).
    case index
    /// A value encoded with `JSONEncoder`.
    case value(any Encodable)
    /// Raw JSON text, such as a saved game state, passed through untouched.
    case json(String)

    var javaScript: String {
        switch self {
        case .index:
            return "__idx"
        case .json(let text):
            return "JSON.parse(\(CoreArg.quote(text)))"
        case .value(let value):
            let data = (try? JSONEncoder().encode(AnyEncodable(value))) ?? Data("null".utf8)
            return "JSON.parse(\(CoreArg.quote(String(decoding: data, as: UTF8.self))))"
        }
    }

    /// A JSON string literal is also a valid JavaScript string literal (U+2028/9 are escaped for older engines).
    private static func quote(_ text: String) -> String {
        let data = (try? JSONEncoder().encode(text)) ?? Data("\"\"".utf8)
        return String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }
}

private struct AnyEncodable: Encodable {
    let value: any Encodable
    init(_ value: any Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}
