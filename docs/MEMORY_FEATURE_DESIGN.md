# Talkie Memory Feature Design

> Enable users to ask questions of their voice memo history using semantic search and AI-powered retrieval.

## Overview

The Memory feature allows Talkie to act as a personal knowledge base, letting users query their transcribed voice memos with natural language questions like:

- "What did I say about the marketing budget last week?"
- "Summarize all my thoughts on Project Apollo"
- "When did I mention calling John back?"

This document presents two implementation approaches with different tradeoffs.

---

## Option 1: Local Vector Store with Core Data

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         macOS Talkie                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────┐  │
│  │  VoiceMemo   │───▶│  Chunker     │───▶│  EmbeddingChunk  │  │
│  │  (transcript)│    │  (500 tokens)│    │  (Core Data)     │  │
│  └──────────────┘    └──────────────┘    └──────────────────┘  │
│                                                   │             │
│                                                   ▼             │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────┐  │
│  │  User Query  │───▶│  Embed Query │───▶│  Cosine Search   │  │
│  │  "What did I │    │  (same model)│    │  (in-memory)     │  │
│  │   say about" │    └──────────────┘    └──────────────────┘  │
│  └──────────────┘                                 │             │
│                                                   ▼             │
│                                          ┌──────────────────┐  │
│                                          │  LLM Generation  │  │
│                                          │  (answer query)  │  │
│                                          └──────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ CloudKit Sync
                              ▼
                    ┌──────────────────┐
                    │    iOS Talkie    │
                    │  (query only)    │
                    └──────────────────┘
```

### Data Model Changes

Add to `talkie.xcdatamodel`:

```xml
<!-- EmbeddingChunk: Stores vector embeddings for transcript chunks -->
<entity name="EmbeddingChunk" representedClassName="EmbeddingChunk" syncable="YES">
    <attribute name="id" attributeType="UUID" usesScalarValueType="NO"/>
    <attribute name="content" attributeType="String"/>
    <attribute name="embedding" attributeType="Binary"/>
    <attribute name="chunkIndex" attributeType="Integer 32" defaultValueString="0"/>
    <attribute name="tokenCount" attributeType="Integer 32" defaultValueString="0"/>
    <attribute name="embeddingModel" attributeType="String"/>
    <attribute name="embeddingDimensions" attributeType="Integer 32" defaultValueString="1536"/>
    <attribute name="createdAt" attributeType="Date"/>
    <relationship name="memo" optional="YES" maxCount="1" deletionRule="Nullify"
                  destinationEntity="VoiceMemo" inverseName="embeddingChunks"/>
</entity>

<!-- Update VoiceMemo with inverse relationship -->
<relationship name="embeddingChunks" optional="YES" toMany="YES" deletionRule="Cascade"
              destinationEntity="EmbeddingChunk" inverseName="memo"/>
```

### New Services

#### EmbeddingService.swift

```swift
protocol EmbeddingProvider {
    var modelId: String { get }
    var dimensions: Int { get }
    func embed(texts: [String]) async throws -> [[Float]]
}

class OpenAIEmbeddingProvider: EmbeddingProvider {
    let modelId = "text-embedding-3-small"
    let dimensions = 1536

    func embed(texts: [String]) async throws -> [[Float]] {
        // Call OpenAI embeddings API
        // POST https://api.openai.com/v1/embeddings
    }
}

class MLXEmbeddingProvider: EmbeddingProvider {
    let modelId = "bge-small-en-v1.5"
    let dimensions = 384

    func embed(texts: [String]) async throws -> [[Float]] {
        // Run local MLX model
    }
}
```

#### ChunkingService.swift

```swift
struct TextChunk {
    let content: String
    let index: Int
    let tokenCount: Int
    let startOffset: Int
    let endOffset: Int
}

class ChunkingService {
    let targetTokens: Int = 500
    let overlapTokens: Int = 50

    func chunk(text: String) -> [TextChunk] {
        // Split on sentence boundaries
        // Maintain overlap for context continuity
        // Return chunks with metadata
    }
}
```

#### MemoryService.swift

```swift
class MemoryService {
    private let embeddingProvider: EmbeddingProvider
    private let chunkingService: ChunkingService
    private let context: NSManagedObjectContext

    /// Index a memo's transcript into embedding chunks
    func indexMemo(_ memo: VoiceMemo) async throws {
        guard let transcript = memo.currentTranscript else { return }

        // Delete existing chunks for this memo
        let existing = memo.embeddingChunks ?? []
        existing.forEach { context.delete($0) }

        // Chunk the transcript
        let chunks = chunkingService.chunk(text: transcript)

        // Generate embeddings in batch
        let embeddings = try await embeddingProvider.embed(
            texts: chunks.map { $0.content }
        )

        // Store chunks with embeddings
        for (chunk, embedding) in zip(chunks, embeddings) {
            let entity = EmbeddingChunk(context: context)
            entity.id = UUID()
            entity.content = chunk.content
            entity.embedding = embedding.toData()
            entity.chunkIndex = Int32(chunk.index)
            entity.tokenCount = Int32(chunk.tokenCount)
            entity.embeddingModel = embeddingProvider.modelId
            entity.embeddingDimensions = Int32(embeddingProvider.dimensions)
            entity.createdAt = Date()
            entity.memo = memo
        }

        try context.save()
    }

    /// Query memory with semantic search
    func query(
        question: String,
        topK: Int = 5,
        dateRange: ClosedRange<Date>? = nil
    ) async throws -> [MemoryResult] {
        // Embed the question
        let queryEmbedding = try await embeddingProvider.embed(texts: [question]).first!

        // Fetch all chunks (with optional date filter)
        let request = EmbeddingChunk.fetchRequest()
        if let range = dateRange {
            request.predicate = NSPredicate(
                format: "memo.createdAt >= %@ AND memo.createdAt <= %@",
                range.lowerBound as NSDate,
                range.upperBound as NSDate
            )
        }
        let chunks = try context.fetch(request)

        // Compute similarities
        let scored = chunks.map { chunk -> (EmbeddingChunk, Float) in
            let embedding = chunk.embedding!.toFloatArray()
            let similarity = cosineSimilarity(queryEmbedding, embedding)
            return (chunk, similarity)
        }

        // Return top-k results
        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(topK)
            .map { MemoryResult(chunk: $0.0, score: $0.1) }
    }
}

struct MemoryResult {
    let chunk: EmbeddingChunk
    let score: Float

    var memo: VoiceMemo { chunk.memo! }
    var content: String { chunk.content }
}
```

### Workflow Integration

Add new step type to `WorkflowDefinition.swift`:

```swift
enum WorkflowStepType: String, Codable {
    // ... existing types ...
    case memoryQuery = "Memory Query"
}

struct MemoryQueryConfig: Codable {
    let query: String           // Supports {{variables}}
    let topK: Int?              // Default: 5
    let dateRangeDays: Int?     // Optional: limit to last N days
    let includeMetadata: Bool?  // Include memo title, date in results
}
```

Example workflow using memory:

```json
{
  "slug": "ask-memory",
  "name": "Ask My Memory",
  "description": "Query past voice memos to answer questions",
  "icon": "brain",
  "color": "purple",
  "steps": [
    {
      "id": "search",
      "type": "Memory Query",
      "config": {
        "query": "{{TRANSCRIPT}}",
        "topK": 5,
        "includeMetadata": true
      }
    },
    {
      "id": "answer",
      "type": "LLM Generation",
      "config": {
        "systemPrompt": "You are a helpful assistant with access to the user's voice memo history. Answer their question based on the retrieved context. If the context doesn't contain relevant information, say so.",
        "prompt": "Question: {{TRANSCRIPT}}\n\nRelevant context from past memos:\n{{search}}",
        "costTier": "balanced"
      }
    }
  ]
}
```

### Background Indexing

Add to `AutoRunProcessor.swift`:

```swift
extension AutoRunProcessor {
    /// Index memos that don't have embeddings yet
    func indexPendingMemos() async {
        let request = VoiceMemo.fetchRequest()
        request.predicate = NSPredicate(
            format: "transcription != nil AND embeddingChunks.@count == 0"
        )

        let pending = try? context.fetch(request)

        for memo in pending ?? [] {
            do {
                try await memoryService.indexMemo(memo)
                AppLogger.memory.info("Indexed memo: \(memo.title ?? "Untitled")")
            } catch {
                AppLogger.memory.error("Failed to index memo: \(error)")
            }
        }
    }
}
```

### Performance Considerations

| Memo Count | Chunk Count (~3/memo) | Memory for Embeddings | Query Time |
|------------|----------------------|----------------------|------------|
| 100        | 300                  | ~1.8 MB              | <10ms      |
| 1,000      | 3,000                | ~18 MB               | <50ms      |
| 10,000     | 30,000               | ~180 MB              | ~500ms     |
| 50,000     | 150,000              | ~900 MB              | ~2-3s      |

For >10K memos, consider:
- Lazy loading embeddings (fetch on demand)
- SQLite FTS5 for keyword pre-filtering before vector search
- Approximate nearest neighbor (HNSW index)

### Pros & Cons

**Pros:**
- Fully self-contained, no external dependencies
- Works offline with local MLX embedding model
- Data stays on device / in user's iCloud
- Syncs via existing CloudKit infrastructure
- Integrates naturally with workflow system

**Cons:**
- Scales to ~10K memos before performance degrades
- Larger Core Data store (embeddings are ~6KB per chunk)
- Initial backfill takes time (API rate limits, cost)
- No hybrid search (keyword + semantic) without additional work

---

## Option 2: External RAG Service via MCP

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         macOS Talkie                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐         ┌──────────────────────────────────┐ │
│  │  VoiceMemo   │────────▶│  MCP Client                      │ │
│  │  (on sync)   │         │  (calls mcp-memory server)       │ │
│  └──────────────┘         └──────────────────────────────────┘ │
│                                        │                        │
│                                        │ stdio/SSE              │
│                                        ▼                        │
│                           ┌──────────────────────────────────┐ │
│                           │  mcp-memory-server               │ │
│                           │  (Node.js process)               │ │
│                           └──────────────────────────────────┘ │
│                                        │                        │
└────────────────────────────────────────│────────────────────────┘
                                         │
                                         ▼
                            ┌──────────────────────────────────┐
                            │  Vector Database                 │
                            │  (Pinecone / ChromaDB / Weaviate)│
                            └──────────────────────────────────┘
```

### MCP Server Implementation

Create `mcp-talkie-memory/` as a new package:

```typescript
// src/index.ts
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { Pinecone } from "@pinecone-database/pinecone";
import OpenAI from "openai";

const server = new Server({
  name: "talkie-memory",
  version: "1.0.0",
}, {
  capabilities: { tools: {} }
});

const pinecone = new Pinecone({ apiKey: process.env.PINECONE_API_KEY });
const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
const index = pinecone.index("talkie-memories");

// Tool: Index a memo
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  if (request.params.name === "index_memo") {
    const { memoId, title, transcript, createdAt } = request.params.arguments;

    // Chunk the transcript
    const chunks = chunkText(transcript, 500, 50);

    // Generate embeddings
    const embeddings = await openai.embeddings.create({
      model: "text-embedding-3-small",
      input: chunks.map(c => c.content)
    });

    // Upsert to Pinecone
    const vectors = chunks.map((chunk, i) => ({
      id: `${memoId}-${i}`,
      values: embeddings.data[i].embedding,
      metadata: {
        memoId,
        title,
        content: chunk.content,
        chunkIndex: i,
        createdAt
      }
    }));

    await index.upsert(vectors);

    return { content: [{ type: "text", text: `Indexed ${chunks.length} chunks` }] };
  }

  if (request.params.name === "query_memory") {
    const { question, topK = 5, dateFilter } = request.params.arguments;

    // Embed the question
    const queryEmbedding = await openai.embeddings.create({
      model: "text-embedding-3-small",
      input: question
    });

    // Query Pinecone
    const results = await index.query({
      vector: queryEmbedding.data[0].embedding,
      topK,
      includeMetadata: true,
      filter: dateFilter ? { createdAt: { $gte: dateFilter } } : undefined
    });

    // Format results
    const context = results.matches.map(m => ({
      memoId: m.metadata.memoId,
      title: m.metadata.title,
      content: m.metadata.content,
      date: m.metadata.createdAt,
      score: m.score
    }));

    return { content: [{ type: "text", text: JSON.stringify(context, null, 2) }] };
  }
});

// Tool definitions
server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "index_memo",
      description: "Index a voice memo transcript for semantic search",
      inputSchema: {
        type: "object",
        properties: {
          memoId: { type: "string", description: "Unique memo identifier" },
          title: { type: "string", description: "Memo title" },
          transcript: { type: "string", description: "Full transcript text" },
          createdAt: { type: "string", description: "ISO date string" }
        },
        required: ["memoId", "transcript", "createdAt"]
      }
    },
    {
      name: "query_memory",
      description: "Search past memos with semantic similarity",
      inputSchema: {
        type: "object",
        properties: {
          question: { type: "string", description: "Natural language query" },
          topK: { type: "number", description: "Number of results (default 5)" },
          dateFilter: { type: "string", description: "ISO date - only include after" }
        },
        required: ["question"]
      }
    }
  ]
}));

const transport = new StdioServerTransport();
await server.connect(transport);
```

### Talkie MCP Client Integration

Add `MCPClient.swift` to macOS app:

```swift
class MCPClient: ObservableObject {
    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?

    func connect(serverPath: String) async throws {
        process = Process()
        process?.executableURL = URL(fileURLWithPath: "/usr/local/bin/node")
        process?.arguments = [serverPath]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process?.standardInput = stdinPipe
        process?.standardOutput = stdoutPipe

        stdin = stdinPipe.fileHandleForWriting
        stdout = stdoutPipe.fileHandleForReading

        try process?.run()
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> String {
        let request = [
            "jsonrpc": "2.0",
            "id": UUID().uuidString,
            "method": "tools/call",
            "params": [
                "name": name,
                "arguments": arguments
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: request)
        stdin?.write(data + "\n".data(using: .utf8)!)

        // Read response...
        let response = try await readResponse()
        return response
    }
}
```

### Workflow Step: MCP Tool

Add to `WorkflowDefinition.swift`:

```swift
enum WorkflowStepType: String, Codable {
    // ... existing types ...
    case mcpTool = "MCP Tool"
}

struct MCPToolConfig: Codable {
    let server: String      // MCP server identifier
    let tool: String        // Tool name to call
    let arguments: [String: AnyCodable]  // Tool arguments (supports {{variables}})
}
```

Example workflow:

```json
{
  "slug": "ask-memory-mcp",
  "name": "Ask My Memory (MCP)",
  "steps": [
    {
      "id": "search",
      "type": "MCP Tool",
      "config": {
        "server": "talkie-memory",
        "tool": "query_memory",
        "arguments": {
          "question": "{{TRANSCRIPT}}",
          "topK": 5
        }
      }
    },
    {
      "id": "answer",
      "type": "LLM Generation",
      "config": {
        "prompt": "Based on these past memos:\n{{search}}\n\nAnswer: {{TRANSCRIPT}}"
      }
    }
  ]
}
```

### Vector Database Options

| Database | Hosting | Free Tier | Latency | Best For |
|----------|---------|-----------|---------|----------|
| **Pinecone** | Managed | 100K vectors | ~50ms | Production, zero maintenance |
| **ChromaDB** | Self-hosted | Unlimited | ~10ms | Privacy, local development |
| **Weaviate** | Both | 1M vectors | ~30ms | Hybrid search (keyword + vector) |
| **Qdrant** | Both | Unlimited | ~20ms | Filtering, payloads |

### Pros & Cons

**Pros:**
- Scales to millions of memos
- Optimized vector search (sub-50ms queries)
- Advanced features: hybrid search, metadata filtering, clustering
- MCP is a standard protocol (reusable across apps)
- Separates storage from app logic

**Cons:**
- Requires external service or self-hosting
- Network latency for every query
- Data leaves the device (privacy concern)
- Additional infrastructure to maintain
- More complex setup for users

---

## Comparison Matrix

| Aspect | Option 1: Local Core Data | Option 2: External MCP |
|--------|---------------------------|------------------------|
| **Scale** | ~10K memos | Millions |
| **Query Latency** | 10-500ms (depends on count) | 20-50ms (consistent) |
| **Privacy** | On-device only | Data on external server |
| **Offline Support** | Yes (with local embeddings) | No |
| **Setup Complexity** | Low (built-in) | Medium (MCP server + DB) |
| **Maintenance** | None | Server updates, DB costs |
| **Sync** | Via CloudKit (automatic) | Manual or webhook |
| **Hybrid Search** | Additional work | Built-in (Weaviate) |
| **Cost** | Embedding API calls only | API + hosting |

---

## Recommendation

### For Initial Release: Option 1 (Local Core Data)

Start with the local approach because:
1. Simpler to ship and maintain
2. Privacy-first (data never leaves device)
3. Works offline
4. Sufficient for most users (<10K memos)
5. Leverages existing CloudKit sync

### Future Enhancement: Hybrid Approach

Add Option 2 as an optional "power user" feature:
1. Default to local Core Data
2. Settings toggle: "Use cloud memory service"
3. If enabled, sync to external vector DB
4. Benefits of both: offline fallback + scalable cloud

---

## Implementation Phases

### Phase 1: Core Infrastructure
- Add `EmbeddingChunk` entity to Core Data model
- Implement `EmbeddingService` with OpenAI provider
- Implement `ChunkingService` with sentence-boundary splitting
- Add background indexing to `AutoRunProcessor`

### Phase 2: Query Interface
- Implement `MemoryService.query()` with cosine similarity
- Add `Memory Query` workflow step type
- Create "Ask My Memory" starter workflow
- Add memory query UI in macOS app

### Phase 3: iOS Integration
- Sync embeddings via CloudKit
- Add query interface to iOS app
- Optimize for mobile (lazy loading, pagination)

### Phase 4: Enhancements
- Local MLX embedding model option
- Hybrid search (keyword + semantic)
- Topic clustering and auto-tagging
- Memory insights dashboard

---

## Open Questions

1. **Embedding Model**: OpenAI `text-embedding-3-small` (1536d) vs local `bge-small` (384d)?
2. **Chunk Size**: 500 tokens with 50 overlap, or dynamic based on content?
3. **Re-indexing**: When transcript is updated, re-embed? Or version embeddings?
4. **iOS Queries**: Should iOS send queries to macOS, or query locally?
5. **Cost Management**: Rate limit embedding calls? Batch processing window?

---

## Appendix: Embedding Storage Format

```swift
extension Array where Element == Float {
    func toData() -> Data {
        return self.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }
}

extension Data {
    func toFloatArray() -> [Float] {
        return self.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
    }
}
```

Binary storage: 1536 floats × 4 bytes = 6,144 bytes per chunk (~6KB).
