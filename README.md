# Clonar: 🚀 An 8-Stage Agentic RAG Orchestrator for High-Precision Reasoning

This repository open-sources **Clonar**, a production-ready RAG (Retrieval-Augmented Generation) query pipeline designed to move beyond "naive RAG" with *explicit multihop reasoning*. From a user question to a grounded answer with citations, Clonar's Node.js backend implements an intelligent, iterative flow that redefines accuracy in AI-powered search.

**The Problem:** Most RAG systems are "one-shot," performing a single retrieval and synthesis pass, leading to hallucinations and insufficient answers for complex queries.  
**The Solution:** Clonar introduces an 8-stage agentic workflow that *reasons* before it retrieves, *clarifies* when necessary, and *critiques* its own output to ensure high-fidelity, grounded responses.

You do not need any frontend to use it. Run the Node backend and call the API with any HTTP client (curl, Postman, or your own app).

---
## ⚠️ Current Status & Transparency

This is an **experimental RAG architecture** designed to explore multihop reasoning patterns. While the codebase implements a working 8-stage pipeline, it's important to note:

**What This Project Is:**
- A learning resource demonstrating agentic RAG workflow patterns
- A working implementation you can run, extend, and learn from
- An architectural exploration of query decomposition and iterative reasoning
- Open-source code inviting community validation and improvement

**What Has NOT Been Validated:**
- ❌ No formal benchmarks comparing 8-stage vs. standard RAG systems
- ❌ No A/B testing or quantitative performance metrics
- ❌ No peer-reviewed evaluation of accuracy improvements
- ❌ No production-scale stress testing or optimization data

The architecture is inspired by research on multi-step reasoning and agentic workflows, but the specific 8-stage design reflects architectural hypotheses rather than empirically proven superiority.

**Why Share This?**

Rather than claiming this is definitively "better," we're open-sourcing it as:
1. **Educational**: Learn patterns for query rewriting, clarification gates, grounding decisions, and critique loops
2. **Extensible**: Use as a foundation for your own RAG experiments
3. **Collaborative**: We welcome benchmarks, evaluations, and improvements from the community

**Contributions Welcome:**
- Benchmark comparisons (8-stage vs. naive RAG)
- Test suites and evaluation frameworks
- Performance optimizations
- Alternative reasoning strategies

If you implement evaluations or discover improvements, please open an issue or PR!

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
