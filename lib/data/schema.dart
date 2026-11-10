/// SQL for the local database, kept as plain data so the same statements can
/// be reviewed, unit-tested and re-run by the migration test.
///
/// Version history
///  v1  tournaments / teams / groups_table / matches
///  v2  two-leg ties and penalty columns
///  v3  rating_events (Elo replay log)
///  v4  rating_events.sport
///  v5  foreign keys with ON DELETE CASCADE (teams, groups_table, matches),
///      tournaments.scoring (points rule), extra indexes.
///      Existing tournaments get scoring = '3,1,0' so their tables do not
///      change; new tournaments use their sport's default rule.
///  v6  matches.detail (JSON of the sport-specific detailed result).
library;

const int kDbVersion = 6;

/// Statements that create the complete current schema on a fresh install.
const List<String> kCreateSchema = [
  r'''
CREATE TABLE tournaments (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  type TEXT NOT NULL,
  hasGroupStage INTEGER NOT NULL DEFAULT 0,
  seedingMode TEXT NOT NULL,
  sport TEXT NOT NULL DEFAULT 'other',
  password TEXT,
  twoLegged INTEGER NOT NULL DEFAULT 0,
  createdAt TEXT NOT NULL,
  isDeleted INTEGER NOT NULL DEFAULT 0,
  deletedAt TEXT,
  champion TEXT,
  runnerUp TEXT,
  thirdPlace TEXT,
  scoring TEXT
)''',
  ..._childTables,
  ..._indexes,
  r'''
CREATE TABLE rating_events (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  matchId TEXT NOT NULL UNIQUE,
  tournamentId TEXT NOT NULL,
  sport TEXT NOT NULL DEFAULT 'other',
  teamA TEXT NOT NULL,
  teamB TEXT NOT NULL,
  goalsA INTEGER NOT NULL,
  goalsB INTEGER NOT NULL,
  resultA REAL NOT NULL
)''',
  r'CREATE INDEX idx_rating_events_tournament ON rating_events(tournamentId)',
];

const List<String> _childTables = [
  r'''
CREATE TABLE teams (
  id TEXT PRIMARY KEY,
  tournamentId TEXT NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  imagePath TEXT
)''',
  r'''
CREATE TABLE groups_table (
  id TEXT PRIMARY KEY,
  tournamentId TEXT NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  teamIds TEXT NOT NULL
)''',
  r'''
CREATE TABLE matches (
  id TEXT PRIMARY KEY,
  tournamentId TEXT NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
  groupId TEXT REFERENCES groups_table(id) ON DELETE CASCADE,
  teamAId TEXT,
  teamBId TEXT,
  scoreA INTEGER,
  scoreB INTEGER,
  scoreA2 INTEGER,
  scoreB2 INTEGER,
  penA INTEGER,
  penB INTEGER,
  isPlayed INTEGER NOT NULL DEFAULT 0,
  round INTEGER NOT NULL,
  matchOrder INTEGER NOT NULL,
  winnerId TEXT,
  isBye INTEGER NOT NULL DEFAULT 0,
  isThirdPlaceMatch INTEGER NOT NULL DEFAULT 0,
  scheduledAt TEXT,
  detail TEXT
)''',
];

const List<String> _indexes = [
  r'CREATE INDEX idx_teams_tournament ON teams(tournamentId)',
  r'CREATE INDEX idx_groups_tournament ON groups_table(tournamentId)',
  r'CREATE INDEX idx_matches_tournament ON matches(tournamentId)',
  r'CREATE INDEX idx_matches_group ON matches(groupId)',
  r'CREATE INDEX idx_matches_round ON matches(tournamentId, round, matchOrder)',
];

/// v4 -> v5. Runs inside sqflite's upgrade transaction with foreign keys
/// still OFF (they are switched on in onOpen), which is what allows tables to
/// be rebuilt. Rows that point to a tournament or group that no longer exists
/// (unreachable leftovers) are not copied; a full file backup is taken
/// before this runs (see DatabaseHelper).
const List<String> kMigrateV4toV5 = [
  r'ALTER TABLE tournaments ADD COLUMN scoring TEXT',
  r"UPDATE tournaments SET scoring = '3,1,0' WHERE scoring IS NULL",
  r'''
CREATE TABLE teams_v5 (
  id TEXT PRIMARY KEY,
  tournamentId TEXT NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  imagePath TEXT
)''',
  r'''
INSERT INTO teams_v5 (id, tournamentId, name, imagePath)
SELECT id, tournamentId, name, imagePath FROM teams
WHERE tournamentId IN (SELECT id FROM tournaments)''',
  r'''
CREATE TABLE groups_v5 (
  id TEXT PRIMARY KEY,
  tournamentId TEXT NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  teamIds TEXT NOT NULL
)''',
  r'''
INSERT INTO groups_v5 (id, tournamentId, name, teamIds)
SELECT id, tournamentId, name, teamIds FROM groups_table
WHERE tournamentId IN (SELECT id FROM tournaments)''',
  r'''
CREATE TABLE matches_v5 (
  id TEXT PRIMARY KEY,
  tournamentId TEXT NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
  groupId TEXT REFERENCES groups_table(id) ON DELETE CASCADE,
  teamAId TEXT,
  teamBId TEXT,
  scoreA INTEGER,
  scoreB INTEGER,
  scoreA2 INTEGER,
  scoreB2 INTEGER,
  penA INTEGER,
  penB INTEGER,
  isPlayed INTEGER NOT NULL DEFAULT 0,
  round INTEGER NOT NULL,
  matchOrder INTEGER NOT NULL,
  winnerId TEXT,
  isBye INTEGER NOT NULL DEFAULT 0,
  isThirdPlaceMatch INTEGER NOT NULL DEFAULT 0,
  scheduledAt TEXT
)''',
  r'''
INSERT INTO matches_v5 (id, tournamentId, groupId, teamAId, teamBId, scoreA, scoreB,
  scoreA2, scoreB2, penA, penB, isPlayed, round, matchOrder, winnerId, isBye,
  isThirdPlaceMatch, scheduledAt)
SELECT id, tournamentId, groupId, teamAId, teamBId, scoreA, scoreB,
  scoreA2, scoreB2, penA, penB, isPlayed, round, matchOrder, winnerId, isBye,
  isThirdPlaceMatch, scheduledAt FROM matches
WHERE tournamentId IN (SELECT id FROM tournaments)
  AND (groupId IS NULL OR groupId IN (SELECT id FROM groups_table))''',
  r'DROP TABLE matches',
  r'DROP TABLE groups_table',
  r'DROP TABLE teams',
  r'ALTER TABLE teams_v5 RENAME TO teams',
  r'ALTER TABLE groups_v5 RENAME TO groups_table',
  r'ALTER TABLE matches_v5 RENAME TO matches',
  ..._indexes,
  r'CREATE INDEX IF NOT EXISTS idx_rating_events_tournament ON rating_events(tournamentId)',
];

/// v5 -> v6: detailed, sport-specific result of a match.
const List<String> kMigrateV5toV6 = [
  'ALTER TABLE matches ADD COLUMN detail TEXT',
];
