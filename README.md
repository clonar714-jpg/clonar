# Clonar: 🚀 An 8-Stage Agentic RAG Orchestrator for High-Precision Reasoning

This repository open-sources **Clonar**, a production-ready RAG (Retrieval-Augmented Generation) query pipeline designed to move beyond "naive RAG" with *explicit multihop reasoning*. From a user question to a grounded answer with citations, Clonar's Node.js backend implements an intelligent, iterative flow that redefines accuracy in AI-powered search.

**The Problem:** Most RAG systems are "one-shot," performing a single retrieval and synthesis pass, leading to hallucinations and insufficient answers for complex queries.  
**The Solution:** Clonar introduces an 8-stage agentic workflow that *reasons* before it retrieves, *clarifies* when necessary, and *critiques* its own output to ensure high-fidelity, grounded responses.

You do not need any frontend to use it. Run the Node backend and call the API with any HTTP client (curl, Postman, or your own app).

---

## 🎯 Key Architectural Highlights for Extraordinary Reasoning

Clonar's core innovation is its **8-Stage Reasoning Loop**. This isn't a simple concatenation of steps, but a dynamically conditioning, iterative process:

```mermaid
graph TD
    A[User Query] --> B(Query Rewrite);
    B --> C{Needs Clarification?};
    C -- Yes --> D[Return Clarification Questions];
    C -- No --> E(Filter Extraction);
    E --> F{Grounding Decision};

    F -- None --> G[LLM-only Answer];
    F -- Hybrid --> H[Web Overview + Synthesize];
    F -- Full --> I(Retrieval Plan);

    I --> J(Execute Retrieval Plan);
    J --> K(Merge and Rerank Chunks);
    K --> L(Quality Guidance);
    L --> M(First-Pass Synthesis);

    M --> N{Deep-Mode Critique};
    N -- No --> O[Second Pass Retrieval];
    N -- Yes --> P(Post-Processing);

    P --> Q[Grounded Answer + Citations];

    style A fill:#f9f,stroke:#333,stroke-width:2px;
    style C fill:#ccf,stroke:#333,stroke-width:2px;
    style F fill:#ccf,stroke:#333,stroke-width:2px;
    style N fill:#ccf,stroke:#333,stroke-width:2px;
    style Q fill:#afa,stroke:#333,stroke-width:2px;
