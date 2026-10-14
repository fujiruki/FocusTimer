import Foundation

struct DictationComposer {
    private var base = ""
    private var committed = ""

    mutating func begin(current: String) {
        base = current.isEmpty ? "" : current + " "
        committed = ""
    }

    // 録音中に「追加」で確定した分を覚え、以降はその後に話した部分だけを使う
    mutating func commit(recognized: String) {
        base = ""
        committed = recognized
    }

    func compose(_ recognized: String) -> String {
        let rest = recognized.hasPrefix(committed)
            ? recognized.dropFirst(committed.count)
            : recognized.dropFirst(min(committed.count, recognized.count))
        return base + rest.trimmingCharacters(in: .whitespaces)
    }
}
