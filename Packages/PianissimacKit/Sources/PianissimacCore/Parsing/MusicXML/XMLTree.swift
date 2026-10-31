import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Minimal in-memory XML element tree, built with Foundation's `XMLParser`.
final class XMLElementNode {
    let name: String
    let attributes: [String: String]
    private(set) var children: [XMLElementNode] = []
    fileprivate(set) var text = ""

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    func append(_ child: XMLElementNode) {
        children.append(child)
    }

    func child(_ name: String) -> XMLElementNode? {
        children.first { $0.name == name }
    }

    func children(_ name: String) -> [XMLElementNode] {
        children.filter { $0.name == name }
    }

    /// Trimmed text of a direct child element.
    func text(of childName: String) -> String? {
        child(childName)?.trimmedText
    }

    var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    func int(of childName: String) -> Int? {
        text(of: childName).flatMap { Int($0) }
    }

    func double(of childName: String) -> Double? {
        text(of: childName).flatMap { Double($0) }
    }
}

enum XMLTreeError: Error {
    case malformed(String)
}

enum XMLTree {
    static func parse(_ data: Data) throws -> XMLElementNode {
        let builder = TreeBuilder()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = false
        parser.delegate = builder
        guard parser.parse(), let root = builder.root else {
            throw XMLTreeError.malformed(parser.parserError?.localizedDescription ?? "invalid XML")
        }
        return root
    }
}

private final class TreeBuilder: NSObject, XMLParserDelegate {
    var root: XMLElementNode?
    private var stack: [XMLElementNode] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let node = XMLElementNode(name: elementName, attributes: attributeDict)
        if let parent = stack.last {
            parent.append(node)
        } else {
            root = node
        }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        _ = stack.popLast()
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.text += string
    }
}
