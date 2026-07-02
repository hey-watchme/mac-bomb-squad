import Foundation
import SQLite3

/// Local persistence for memory cards (persona / relationship), following the
/// same SQLite pattern as `LocalHistoryStore`. Stored in its own database so
/// history and memory can evolve (and sync, in M3) independently. The schema
/// mirrors the planned server-side `bs_memory_cards` table.
actor MemoryStore {
    static let shared = MemoryStore()

    private var database: OpaquePointer?
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    deinit {
        sqlite3_close(database)
    }

    // MARK: - Persona

    /// The single persona card, if one exists (bootstrap or auto-created).
    func personaCard() throws -> MemoryCard? {
        try fetchCards(kind: .persona).first
    }

    /// Create or replace the persona card content.
    func savePersona(contentMD: String, source: MemoryCard.Source) throws {
        if let existing = try personaCard() {
            try updateCard(id: existing.id, contentMD: contentMD, source: source)
        } else {
            try insertCard(kind: .persona, subject: nil, contentMD: contentMD, source: source)
        }
    }

    /// Append a distilled note to the persona card, creating a provisional
    /// card when none exists yet. Skipped when the card has grown past the
    /// size cap (re-distillation into a compact card is a later milestone).
    func appendPersonaNote(_ note: String) throws {
        let dateStamp = Self.dateStamp()
        if let existing = try personaCard() {
            guard existing.contentMD.count < Self.maxCardChars else { return }
            var content = existing.contentMD
            if !content.contains(Self.learnedSectionHeader) {
                content += "\n\n\(Self.learnedSectionHeader)\n"
            }
            content += "- \(dateStamp): \(note)\n"
            try updateCard(id: existing.id, contentMD: content, source: .distilled)
        } else {
            let content = """
            # スタイルプロファイル（自動学習・暫定）

            まだブートストラップが行われていないため、使用中の学習だけで作られた暫定プロファイルです。

            \(Self.learnedSectionHeader)
            - \(dateStamp): \(note)
            """
            try insertCard(kind: .persona, subject: nil, contentMD: content, source: .distilled)
        }
    }

    // MARK: - Relationships

    func relationshipCards() throws -> [MemoryCard] {
        try fetchCards(kind: .relationship)
    }

    /// Append a distilled note to the card for `subject`, creating it on first
    /// encounter.
    func appendRelationshipNote(subject: String, note: String) throws {
        let trimmedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSubject.isEmpty else { return }
        let dateStamp = Self.dateStamp()

        if let existing = try relationshipCards().first(where: {
            $0.subject?.compare(trimmedSubject, options: .caseInsensitive) == .orderedSame
        }) {
            guard existing.contentMD.count < Self.maxCardChars else { return }
            let content = existing.contentMD + "\n- \(dateStamp): \(note)"
            try updateCard(id: existing.id, contentMD: content, source: .distilled)
        } else {
            let content = """
            # \(trimmedSubject)

            - \(dateStamp): \(note)
            """
            try insertCard(kind: .relationship, subject: trimmedSubject, contentMD: content, source: .distilled)
        }
    }

    /// Find the relationship card whose subject appears in the given text
    /// (window title + conversation excerpt). Case-insensitive contains match;
    /// good enough until embeddings arrive in M3.
    func matchRelationship(inText text: String) throws -> MemoryCard? {
        guard !text.isEmpty else { return nil }
        let haystack = text.lowercased()
        return try relationshipCards().first { card in
            guard let subject = card.subject?.lowercased(), subject.count >= 2 else { return false }
            return haystack.contains(subject)
        }
    }

    // MARK: - Generic card operations

    func updateCard(id: String, contentMD: String, source: MemoryCard.Source) throws {
        try openIfNeeded()
        let sql = "UPDATE memory_cards SET content_md = ?, source = ?, updated_at = ? WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError()
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, contentMD, -1, transientDestructor)
        sqlite3_bind_text(statement, 2, source.rawValue, -1, transientDestructor)
        sqlite3_bind_double(statement, 3, Date().timeIntervalSince1970)
        sqlite3_bind_text(statement, 4, id, -1, transientDestructor)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw databaseError() }
    }

    func deleteCard(id: String) throws {
        try openIfNeeded()
        let sql = "DELETE FROM memory_cards WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError()
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, id, -1, transientDestructor)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw databaseError() }
    }

    func deleteAll() throws {
        try openIfNeeded()
        try execute("DELETE FROM memory_cards;")
    }

    // MARK: - Internals

    private static let learnedSectionHeader = "## 学習した傾向"
    private static let maxCardChars = 6000

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func fetchCards(kind: MemoryCard.Kind) throws -> [MemoryCard] {
        try openIfNeeded()
        let sql = """
        SELECT id, kind, subject, content_md, source, created_at, updated_at
        FROM memory_cards
        WHERE kind = ?
        ORDER BY updated_at DESC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError()
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, kind.rawValue, -1, transientDestructor)

        var cards: [MemoryCard] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let id = string(from: statement, column: 0),
                let kindString = string(from: statement, column: 1),
                let kind = MemoryCard.Kind(rawValue: kindString),
                let contentMD = string(from: statement, column: 3),
                let sourceString = string(from: statement, column: 4),
                let source = MemoryCard.Source(rawValue: sourceString)
            else { continue }

            cards.append(
                MemoryCard(
                    id: id,
                    kind: kind,
                    subject: string(from: statement, column: 2),
                    contentMD: contentMD,
                    source: source,
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))
                )
            )
        }
        return cards
    }

    private func insertCard(
        kind: MemoryCard.Kind,
        subject: String?,
        contentMD: String,
        source: MemoryCard.Source
    ) throws {
        try openIfNeeded()
        let sql = """
        INSERT INTO memory_cards (id, kind, subject, content_md, source, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError()
        }
        defer { sqlite3_finalize(statement) }

        let now = Date().timeIntervalSince1970
        sqlite3_bind_text(statement, 1, UUID().uuidString, -1, transientDestructor)
        sqlite3_bind_text(statement, 2, kind.rawValue, -1, transientDestructor)
        if let subject {
            sqlite3_bind_text(statement, 3, subject, -1, transientDestructor)
        } else {
            sqlite3_bind_null(statement, 3)
        }
        sqlite3_bind_text(statement, 4, contentMD, -1, transientDestructor)
        sqlite3_bind_text(statement, 5, source.rawValue, -1, transientDestructor)
        sqlite3_bind_double(statement, 6, now)
        sqlite3_bind_double(statement, 7, now)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw databaseError() }
    }

    private func openIfNeeded() throws {
        guard database == nil else { return }

        let directoryURL = try applicationSupportDirectory()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let databaseURL = directoryURL.appendingPathComponent("memory.sqlite")
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &db, flags, nil) == SQLITE_OK else {
            if let db {
                sqlite3_close(db)
            }
            throw databaseError(database: db)
        }

        database = db
        try execute(
            """
            CREATE TABLE IF NOT EXISTS memory_cards (
                id TEXT PRIMARY KEY NOT NULL,
                kind TEXT NOT NULL,
                subject TEXT,
                content_md TEXT NOT NULL,
                source TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );
            """
        )
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw databaseError()
        }
    }

    private func string(from statement: OpaquePointer?, column: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: text)
    }

    private func applicationSupportDirectory() throws -> URL {
        guard let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        return root.appendingPathComponent("BombSquad", isDirectory: true)
    }

    private func databaseError(database: OpaquePointer? = nil) -> NSError {
        let db = database ?? self.database
        let message = sqlite3_errmsg(db).map { String(cString: $0) } ?? "Unknown SQLite error"
        return NSError(domain: "MemoryStore", code: Int(sqlite3_errcode(db)), userInfo: [
            NSLocalizedDescriptionKey: message
        ])
    }

    private var transientDestructor: sqlite3_destructor_type {
        unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)
    }
}
