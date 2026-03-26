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

flowchart TB
  subgraph entry["Client → API"]
    A["GET /api/query/stream\n(build QueryContext, session, memory)"]
  end

  A --> SP["runStreamPipeline"]

  subgraph SP["runStreamPipeline"]
    C{"Pipeline cache\nhit?"}
    C -->|yes| FAST["Replay summary + citations\n(skip classify / research / writer)"]
    C -->|no| P0["Progress: Understanding…\nclassify(ctx)"]
    P0 --> P0out["standaloneQuery, skipSearch,\nreasoningMode speed|balanced"]

    P0out --> BR{"skipSearch?"}
    BR -->|yes| EMPTY["retrieval = empty context\ncitations = []"]
    BR -->|no| RS["runResearcher\n(iterative LLM ↔ tools)"]

    subgraph RSsub["Researcher (agent loop)"]
      direction TB
      L1["LLM: tool calls or done"]
      L2["executeAction\n(web_search, shopping, hotels, …)"]
      L3["Append tool results\n→ next iteration"]
      L1 --> L2 --> L3 --> L1
    end

    RS --> RSsub
    EMPTY --> PKG
    RS --> PKG

    PKG{"citations\nlength > 0?"}
    PKG -->|yes| RERANK["runRetrievalPipelineWithSemanticRerank\n(embeddings + optional LTR + context string)"]
    PKG -->|no| RAW["Use retrieval.context as-is"]

    RERANK --> RD["onRetrievalDone\n(category, toolsUsed, citations)"]
    RAW --> RD

    RD --> WR["Progress: Writing…\nstreamCompletionNoToolsWithRetry\n(writer prompt + thread + user)"]

    WR --> FIN["onCitations + onDone\nsetCache(5m)"]
    FIN --> SUG["Background: generateSuggestions\n(LLM JSON)"]
  end

  FAST --> END["SSE complete"]
  SUG --> END
