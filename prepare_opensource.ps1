# prepare_opensource.ps1
# Only the files listed in this script are open-sourced (staged). Nothing else.
# This list is the agentic framework: query pipeline, orchestration, vertical agents, types, and supporting code.

Write-Host "Preparing open-source release (only files listed below)..." -ForegroundColor Green

# --- Backend: explicit file list (only these are open-sourced) ---
$backendFiles = @(
    # Types (framework)
    "node/src/types/core.ts",
    "node/src/types/verticals.ts",
    # Pipeline core
    "node/src/services/query-understanding.ts",
    "node/src/services/orchestrator.ts",
    "node/src/services/orchestrator-stream.ts",
    "node/src/services/critique-agent.ts",
    "node/src/services/planner-agent.ts",
    "node/src/services/cache.ts",
    "node/src/services/logger.ts",
    "node/src/services/llm-client.ts",
    "node/src/services/llm-main.ts",
    "node/src/services/llm-small.ts",
    "node/src/services/model-router.ts",
    "node/src/services/prompt-templates.ts",
    "node/src/services/rerank.ts",
    "node/src/services/dedup-utils.ts",
    "node/src/services/searchService.ts",
    # Vertical agents
    "node/src/services/vertical/product-agent.ts",
    "node/src/services/vertical/hotel-agent.ts",
    "node/src/services/vertical/flight-agent.ts",
    "node/src/services/vertical/movie-agent.ts",
    # UI decision (hints)
    "node/src/services/ui_decision/genericUiDecision.ts",
    "node/src/services/ui_decision/productUiDecision.ts",
    "node/src/services/ui_decision/hotelUiDecision.ts",
    "node/src/services/ui_decision/flightUiDecision.ts",
    "node/src/services/ui_decision/movieUiDecision.ts",
    # Providers (interfaces + web; no sql-*, no *-retriever-hybrid)
    "node/src/services/providers/retrieval-types.ts",
    "node/src/services/providers/retrieval-vector-utils.ts",
    "node/src/services/providers/web/perplexity-web.ts",
    "node/src/services/providers/web/simple-embedder.ts",
    "node/src/services/providers/catalog/catalog-provider.ts",
    "node/src/services/providers/catalog/product-retriever.ts",
    "node/src/services/providers/hotels/hotel-provider.ts",
    "node/src/services/providers/hotels/hotel-retriever.ts",
    "node/src/services/providers/flights/flight-provider.ts",
    "node/src/services/providers/flights/flight-retriever.ts",
    "node/src/services/providers/movies/movie-provider.ts",
    "node/src/services/providers/movies/movie-retriever.ts",
    # Middleware (framework-only)
    "node/src/middleware/correlation.ts",
    "node/src/middleware/errorHandler.ts",
    "node/src/middleware/notFoundHandler.ts",
    "node/src/middleware/rate-limit-query.ts",
    "node/src/middleware/validation.ts",
    # Utils
    "node/src/utils/agentConfigHelper.ts",
    "node/src/utils/clientConfig.ts",
    "node/src/utils/errorResponse.ts",
    "node/src/utils/formatHistory.ts",
    "node/src/utils/serverUtils.ts",
    # Models (LLM/embedding)
    "node/src/models/base/embedding.ts",
    "node/src/models/base/llm.ts",
    "node/src/models/base/provider.ts",
    "node/src/models/embeddings/openai.ts",
    "node/src/models/llms/openai.ts",
    "node/src/models/providers/openai.ts",
    "node/src/models/providers/registry.ts",
    "node/src/models/providers.ts",
    "node/src/models/registry.ts",
    "node/src/models/types.ts",
    # Config
    "node/src/config/accessors.ts",
    "node/src/config/configManager.ts",
    "node/src/config/index.ts",
    "node/src/config/serverRegistry.ts",
    "node/src/config/types.ts",
    # Agent
    "node/src/agent/detail.handler.ts",
    "node/src/agent/types.ts",
    # Memory
    "node/src/memory/sessionMemory.ts",
    "node/src/memory/SessionStore.ts",
    "node/src/memory/InMemorySessionStore.ts",
    "node/src/memory/RedisSessionStore.ts",
    # Stability
    "node/src/stability/errorHandlers.ts",
    "node/src/stability/memoryFlush.ts",
    # Embeddings
    "node/src/embeddings/embeddingClient.ts",
    # Node root
    "node/package.json",
    "node/tsconfig.json"
)

# --- Docs ---
$docFiles = @(
    "docs/QUERY_FLOW_STORY.md",
    "docs/PERPLEXITY_FLOW_GAP_ANALYSIS.md",
    "docs/PIPELINE_VS_PERPLEXITY.md"
)

# --- Root ---
$rootFiles = @(
    "README.md"
)

# --- Optional frontend (set $true to include) ---
$includeFrontend = $false
$frontendFiles = @(
    "lib/screens/ShopScreen.dart",
    "lib/screens/ClonarAnswerScreen.dart",
    "lib/widgets/ClonarAnswerWidget.dart",
    "lib/widgets/ResearchActivityWidget.dart",
    "lib/providers/agent_provider.dart",
    "lib/providers/display_content_provider.dart",
    "lib/providers/follow_up_controller_provider.dart",
    "lib/services/AgentService.dart",
    "lib/services/api_client.dart",
    "lib/models/Product.dart",
    "lib/main.dart"
)

# --- Stage backend (only files in the list) ---
Write-Host "`nAdding backend files..." -ForegroundColor Cyan
foreach ($file in $backendFiles) {
    if (Test-Path $file) {
        git add $file
        Write-Host "  $file" -ForegroundColor Gray
    } else {
        Write-Host "  $file (not found)" -ForegroundColor Yellow
    }
}

# --- Stage docs ---
Write-Host "`nAdding docs..." -ForegroundColor Cyan
foreach ($file in $docFiles) {
    if (Test-Path $file) {
        git add $file
        Write-Host "  $file" -ForegroundColor Gray
    } else {
        Write-Host "  $file (not found)" -ForegroundColor Yellow
    }
}

# --- Stage root ---
Write-Host "`nAdding root..." -ForegroundColor Cyan
foreach ($file in $rootFiles) {
    if (Test-Path $file) {
        git add $file
        Write-Host "  $file" -ForegroundColor Gray
    } else {
        Write-Host "  $file (not found)" -ForegroundColor Yellow
    }
}

# --- Optional frontend ---
if ($includeFrontend) {
    Write-Host "`nAdding frontend..." -ForegroundColor Cyan
    foreach ($file in $frontendFiles) {
        if (Test-Path $file) {
            git add $file
            Write-Host "  $file" -ForegroundColor Gray
        } else {
            Write-Host "  $file (not found)" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "`nSkipping frontend (set `$includeFrontend = `$true to include)." -ForegroundColor DarkGray
}

# --- Script self ---
if (Test-Path "prepare_opensource.ps1") {
    git add prepare_opensource.ps1
    Write-Host "`n  prepare_opensource.ps1" -ForegroundColor Gray
}

Write-Host "`nDone. Only the files listed above were staged for open-source." -ForegroundColor Green
Write-Host "Next: git status, then commit and push." -ForegroundColor Yellow
