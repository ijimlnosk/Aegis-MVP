enum SkillProposalAnalysis {
  static func detect(detector: SkillCandidateDetector = SkillCandidateDetector(),
                     loadHistory: () throws -> [MemoryRecord],
                     loadSkills: () throws -> [LearnedSkill])
    -> Result<SkillCandidate?, Error> {
    do {
      let history = try loadHistory()
      let skills = try loadSkills()
      return .success(detector.detect(records: history, existing: skills))
    } catch {
      return .failure(error)
    }
  }
}
