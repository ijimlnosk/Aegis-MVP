import Foundation

enum UIElementResolver {
  static func resolve(label: String, role: UIElementRole? = nil,
                      elements: [UIElementDescriptor]) throws -> UIElementDescriptor {
    var candidates = elements.filter { role == nil || $0.role == role }
    let identifier = candidates.filter {
      $0.identifier?.caseInsensitiveCompare(label) == .orderedSame
    }
    if !identifier.isEmpty { candidates = identifier }
    else {
      candidates = candidates.filter {
        $0.label?.caseInsensitiveCompare(label) == .orderedSame
          || $0.title?.caseInsensitiveCompare(label) == .orderedSame
          || semanticAliases[label.lowercased()]?.contains($0.displayName.lowercased()) == true
      }
    }
    guard !candidates.isEmpty else { throw UIInteractionError.targetNotFound(label) }
    guard candidates.count == 1 else { throw UIInteractionError.ambiguousTarget(label) }
    guard candidates[0].enabled else { throw UIInteractionError.disabled }
    guard candidates[0].role.actionable else { throw UIInteractionError.unsupportedRole }
    return candidates[0]
  }

  private static let semanticAliases = [
    "검색": ["search", "검색"], "탐색기": ["explorer", "탐색기"],
    "소스 제어": ["source control", "소스 제어"],
  ]
}
