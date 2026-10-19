import AppIntents
import CoreSpotlight

/// Shortcuts 参数解析 / Spotlight 重建索引。
struct TitleEntityQuery: EntityQuery, EntityStringQuery, IndexedEntityQuery {
    func entities(for identifiers: [TitleEntity.ID]) async throws -> [TitleEntity] {
        await IntentDataStore.shared.entities(for: identifiers)
    }

    func suggestedEntities() async throws -> [TitleEntity] {
        let entities = await IntentDataStore.shared.libraryEntities()
        return Array(entities.prefix(20))
    }

    func entities(matching string: String) async throws -> [TitleEntity] {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let entities = await IntentDataStore.shared.libraryEntities()
            return Array(entities.prefix(20))
        }

        let local = await IntentDataStore.shared.libraryEntities(matching: trimmed)
        let remote = (try? await IntentDataStore.shared.search(query: trimmed, mediaType: nil)) ?? []
        var seen = Set<String>()
        return (local + remote).filter { seen.insert($0.id).inserted }.prefix(20).map { $0 }
    }

    func reindexEntities(
        for identifiers: [TitleEntity.ID],
        indexDescription: CSSearchableIndexDescription
    ) async throws {
        let entities = await IntentDataStore.shared.entities(for: identifiers)
        try await CSSearchableIndex(name: SpotlightIndexer.indexName).indexAppEntities(entities)
    }

    func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        let entities = await IntentDataStore.shared.libraryEntities()
        try await CSSearchableIndex(name: SpotlightIndexer.indexName).indexAppEntities(entities)
    }
}
