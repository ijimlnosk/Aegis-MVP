#if DEBUG
import Foundation

enum AccessibilityTreeInspector {
  static func compact(_ roots: [AccessibilityTreeNode], maximumDepth: Int = 8) -> [String] {
    var rows: [String] = []
    func append(_ node: AccessibilityTreeNode, depth: Int) {
      guard rows.count < 300, depth <= maximumDepth else { return }
      let item = node.descriptor
      let metadata = [item.identifier.map { "id=\"\($0)\"" },
        item.title.map { "title=\"\($0)\"" }, item.label.map { "description=\"\($0)\"" },
        item.focused ? "focused=true" : nil, item.enabled ? nil : "enabled=false",
        item.hasValueAttribute ? "valuePresent=true" : nil,
        item.valueSettable ? "valueSettable=true" : nil,
        item.supportedActions.isEmpty ? nil : "actions=\(item.supportedActions.joined(separator: ","))",
        "children=\(node.childCount)"].compactMap { $0 }.joined(separator: " ")
      rows.append(String(repeating: "  ", count: depth) + "\(node.accessibilityRole) \(metadata)")
      node.children.forEach { append($0, depth: depth + 1) }
    }
    roots.forEach { append($0, depth: 0) }
    return rows
  }

  static func logDifference(before: [AccessibilityTreeNode], after: [AccessibilityTreeNode]) {
    let old = Set(compact(before)), new = Set(compact(after))
    NSLog("VSCode Quick Open AX added/changed:\n%@", new.subtracting(old).sorted().joined(separator: "\n"))
  }
}
#endif
