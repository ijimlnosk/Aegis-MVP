enum SkillSchema {
  static let sql = """
  CREATE TABLE IF NOT EXISTS learned_skills(
    id TEXT PRIMARY KEY,name TEXT NOT NULL UNIQUE,aliases_json TEXT NOT NULL,
    description TEXT NOT NULL,steps_json TEXT NOT NULL,confidence REAL NOT NULL,
    usage_count INTEGER NOT NULL,created_at TEXT NOT NULL,updated_at TEXT NOT NULL);
  CREATE TABLE IF NOT EXISTS skill_usage(
    id TEXT PRIMARY KEY,skill_id TEXT NOT NULL,request TEXT NOT NULL,
    succeeded INTEGER NOT NULL,created_at TEXT NOT NULL);
  """
}
