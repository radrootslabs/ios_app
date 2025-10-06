import Foundation
import RadrootsKit

enum DebugDump {
    static func posts(_ items: [NostrPostEventMetadata], label: String = "PostFeed.kind1") {
        let mapped = items.map {
            DumpPost(id: $0.id, author: $0.author, publishedAt: $0.publishedAt, content: $0.post.content)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonString = (try? encoder.encode(mapped)).flatMap { String(data: $0, encoding: .utf8) }
        let dumpString: String = jsonString ?? {
            var s = ""
            dump(mapped, to: &s, maxDepth: Int.max, maxItems: Int.max)
            return s
        }()
        RadrootsLogger.debug("\(label) count=\(items.count)")
        let chunks = dumpString.chunked(into: 900)
        for (i, chunk) in chunks.enumerated() {
            RadrootsLogger.debug("\(label) \(i + 1)/\(chunks.count):\n\(chunk)")
        }
    }

    private struct DumpPost: Codable {
        let id: String
        let author: String
        let publishedAt: UInt64
        let content: String
    }
}

private extension String {
    func chunked(into size: Int) -> [String] {
        guard size > 0, !isEmpty else { return [self] }
        var result: [String] = []
        var idx = startIndex
        while idx < endIndex {
            let end = index(idx, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(String(self[idx..<end]))
            idx = end
        }
        return result
    }
}
