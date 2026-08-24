import Foundation

struct AccessibilityTreeNode: Equatable, Sendable {
  let descriptor: UIElementDescriptor
  let accessibilityRole: String
  let childCount: Int
  let children: [AccessibilityTreeNode]

  init(descriptor: UIElementDescriptor, accessibilityRole: String? = nil,
       childCount: Int, children: [AccessibilityTreeNode]) {
    self.descriptor = descriptor
    self.accessibilityRole = accessibilityRole ?? descriptor.role.rawValue
    self.childCount = childCount
    self.children = children
  }
}

enum AccessibilityTreeSearch {
  static func first(in roots: [AccessibilityTreeNode], maximumDepth: Int = 8,
                    maximumElements: Int = 300,
                    cancelled: () -> Bool = { false },
                    where predicate: (UIElementDescriptor) -> Bool) -> UIElementDescriptor? {
    var queue = roots.map { ($0, 0) }
    var inspected = 0
    while !queue.isEmpty, inspected < maximumElements, !cancelled() {
      let (node, depth) = queue.removeFirst()
      inspected += 1
      if predicate(node.descriptor) { return node.descriptor }
      if depth < maximumDepth { queue.append(contentsOf: node.children.map { ($0, depth + 1) }) }
    }
    return nil
  }

  static func flattened(_ roots: [AccessibilityTreeNode], maximumDepth: Int = 8,
                        maximumElements: Int = 300) -> [AccessibilityTreeNode] {
    var queue = roots.map { ($0, 0) }, output: [AccessibilityTreeNode] = []
    while !queue.isEmpty, output.count < maximumElements {
      let (node, depth) = queue.removeFirst(); output.append(node)
      if depth < maximumDepth { queue.append(contentsOf: node.children.map { ($0, depth + 1) }) }
    }
    return output
  }
}
