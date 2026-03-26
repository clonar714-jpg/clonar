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

flowchart TB
  subgraph entry ["Client to API"]
    A["GET /api/query/stream <br/> (build QueryContext, session, memory)"]
  end

  A --> SP

  subgraph SP ["runStreamPipeline"]
    C{"Pipeline cache hit?"}
    C -->|yes| FAST["Replay summary + citations <br/> (skip classify/research/writer)"]
    C -->|no| P0["Progress: Understanding... <br/> classify(ctx)"]
    
    P0 --> P0out["standaloneQuery, skipSearch, <br/> reasoningMode: speed/balanced"]

    P0out --> BR{"skipSearch?"}
    BR -->|yes| EMPTY["retrieval = empty context <br/> citations = []"]
    BR -->|no| RS["runResearcher <br/> (iterative LLM + tools)"]

    subgraph RSsub ["Researcher agent loop"]
      direction TB
      L1["LLM: tool calls or done"]
      L2["executeAction <br/> (web_search, shopping, etc)"]
      L3["Append tool results <br/> to next iteration"]
      L1 --> L2 --> L3 --> L1
    end

    RS --> RSsub
    RSsub --> PKG
    EMPTY --> PKG

    PKG{"citations length > 0?"}
    PKG -->|yes| RERANK["runRetrievalPipeline <br/> with Semantic Rerank"]
    PKG -->|no| RAW["Use retrieval.context as-is"]

    RERANK --> RD["onRetrievalDone <br/> (category, tools, citations)"]
    RAW --> RD

    RD --> WR["Progress: Writing... <br/> streamCompletionNoToolsWithRetry"]

    WR --> FIN["onCitations + onDone <br/> setCache(5m)"]
    FIN --> SUG["Background: generateSuggestions"]
  end

  FAST --> END["SSE complete"]
  SUG --> END
