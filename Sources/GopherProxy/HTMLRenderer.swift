import Foundation
import GopherHelpers
import SwiftGopherClient

/// Renders gopher content as plain, script-free HTML pages.
struct HTMLRenderer {
    let title: String
    /// Builds the link for a menu item; `nil` when the item isn't linkable.
    let link: (GopherLocation) -> String?

    func menu(_ data: Data, location: GopherLocation) -> String {
        var rows: [String] = []
        for item in GopherResponseParser.parse(data: data) where item.rawLine != "." {
            rows.append(menuRow(item))
        }
        return page(location: location, body: "<pre class=\"menu\">\n\(rows.joined(separator: "\n"))\n</pre>")
    }

    func text(_ data: Data, location: GopherLocation) -> String {
        var text = Self.decode(data)
        if text.hasSuffix("\r\n.\r\n") {
            text.removeLast(3)
        } else if text.hasSuffix("\n.\n") {
            text.removeLast(2)
        }
        return page(location: location, body: "<pre class=\"text\">\(Self.escape(text))</pre>")
    }

    func searchForm(location: GopherLocation, prompt: String? = nil) -> String {
        let label = Self.escape(prompt ?? "Search")
        let body = """
            <form class="search" method="get" action="\(Self.escape(location.proxyPath))">
            <label for="q">\(label)</label>
            <input type="search" id="q" name="q" autofocus>
            <button type="submit">Search</button>
            </form>
            """
        return page(location: location, body: body)
    }

    func error(status: Int, message: String, location: GopherLocation? = nil) -> String {
        let heading = "\(status) \(HTTPResponse.reasonPhrase(for: status))"
        return page(
            location: location,
            heading: heading,
            body: "<p class=\"error\">\(Self.escape(message))</p>"
        )
    }

    private func menuRow(_ item: GopherItem) -> String {
        let type = item.rawLine.first ?? "i"
        let label = Self.escape(item.message)

        switch type {
        case "i":
            return "<span class=\"t\">    </span>\(label)"
        case "3":
            return "<span class=\"t\">ERR </span><span class=\"error\">\(label)</span>"
        case "8", "T":
            let host = item.host.contains(":") ? "[\(item.host)]" : item.host
            let href = Self.escape("telnet://\(host):\(item.port)")
            return "<span class=\"t\">TEL </span><a href=\"\(href)\">\(label)</a>"
        case "h" where item.selector.hasPrefix("URL:"):
            let url = String(item.selector.dropFirst(4))
            guard Self.isSafeExternalURL(url) else {
                return "<span class=\"t\">URL </span>\(label)"
            }
            return "<span class=\"t\">URL </span><a href=\"\(Self.escape(url))\" rel=\"noreferrer\">\(label)</a>"
        default:
            let location = GopherLocation(host: item.host, port: item.port, type: type, selector: item.selector)
            guard let href = link(location) else {
                return "<span class=\"t\">\(Self.typeLabel(type))</span>\(label)"
            }
            return "<span class=\"t\">\(Self.typeLabel(type))</span><a href=\"\(Self.escape(href))\">\(label)</a>"
        }
    }

    private func page(location: GopherLocation?, heading: String? = nil, body: String) -> String {
        var header = "<a href=\"/\">\(Self.escape(title))</a>"
        if let location {
            let root = GopherLocation(host: location.host, port: location.port)
            header += " <span class=\"url\"><a href=\"\(Self.escape(root.proxyPath))\">"
                + "\(Self.escape(location.host)):\(location.port)</a> "
                + "<a href=\"\(Self.escape(location.gopherURL))\">\(Self.escape(location.gopherURL))</a></span>"
        }
        let headingHTML = heading.map { "<h1>\(Self.escape($0))</h1>\n" } ?? ""
        let pageTitle = heading ?? location.map { $0.gopherURL } ?? title

        return """
            <!DOCTYPE html>
            <html lang="en">
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>\(Self.escape(pageTitle))</title>
            <style>\(Self.css)</style>
            </head>
            <body>
            <header>\(header)</header>
            <main>
            \(headingHTML)\(body)
            </main>
            </body>
            </html>
            """
    }

    static let css = """
        :root{color-scheme:light dark;--fg:#1b1b1b;--bg:#fbfbf8;--muted:#77756f;--link:#0b57d0;--err:#b3261e}
        @media (prefers-color-scheme:dark){:root{--fg:#e6e4dc;--bg:#161614;--muted:#8d8b84;--link:#8ab4f8;--err:#f2b8b5}}
        body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.45 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}
        header{padding:.6rem 1rem;border-bottom:1px solid var(--muted);display:flex;gap:1rem;flex-wrap:wrap}
        header .url a{color:var(--muted)}
        main{padding:1rem;max-width:80ch}
        pre{margin:0;white-space:pre-wrap;overflow-wrap:anywhere;font:inherit}
        .t{color:var(--muted);user-select:none}
        a{color:var(--link)}
        .error{color:var(--err)}
        h1{font-size:1.2rem}
        form.search{display:flex;gap:.5rem;align-items:center;flex-wrap:wrap}
        input,button{font:inherit}
        """

    static func typeLabel(_ type: Character) -> String {
        switch type {
        case "0": return "TXT "
        case "1": return "DIR "
        case "7": return "FIND"
        case "g", "I", "p", ":": return "IMG "
        case "h": return "HTML"
        case "s", "<": return "SND "
        case ";": return "VID "
        default: return "BIN "
        }
    }

    static func isSafeExternalURL(_ url: String) -> Bool {
        let lowered = url.lowercased()
        return ["http://", "https://", "gopher://"].contains { lowered.hasPrefix($0) }
    }

    static func decode(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    static func escape(_ string: String) -> String {
        var result = ""
        result.reserveCapacity(string.count)
        for character in string {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default: result.append(character)
            }
        }
        return result
    }
}
