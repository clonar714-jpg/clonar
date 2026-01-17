# Clonar 🔍

An agentic AI research system that addresses fundamental limitations in existing AI search architectures by implementing an evidence-first, iterative research methodology. Unlike systems that generate answers from static knowledge bases or single-pass web queries, Clonar employs a multi-phase agent workflow that dynamically adapts research depth, routes queries to specialized tools based on intent classification, and synthesizes answers with verifiable source citations. The system is architected as a mobile-first Android application, intentionally designed to demonstrate that sophisticated agentic AI research can be delivered effectively on resource-constrained mobile platforms with proper architectural separation between client and server components.

## Overview

This project implements an agentic AI research system with adaptive iteration depth, intent-aware tool routing, and evidence-first answer synthesis. The multi-phase architecture (classification → research → synthesis → answer) dynamically adjusts research depth (2-25 iterations) based on query complexity. Unlike systems that attach sources after generation, this system tracks evidence during research and embeds citations in answers. The mobile-first Android design demonstrates that sophisticated agent workflows can run effectively on resource-constrained platforms through proper architectural separation. The backend is platform-agnostic; the Flutter frontend handles streaming, state management, and Android lifecycle constraints. Key contributions include the adaptive research engine, pluggable provider architecture, and mobile-optimized SSE streaming implementation.



## Architecture

The system implements a multi-phase agent workflow with clear separation of concerns:

**Phase 1: Classification**
The query is analyzed to determine intent, required search sources, and widget needs. This classification happens before any research begins, enabling efficient tool routing.

**Phase 2: Iterative Research**
Based on classification results, the agent performs iterative research using appropriate tools (web search, academic search, discussion search, file search). The research depth adapts to the selected optimization mode (speed/balanced/quality), with reasoning loops that evaluate information sufficiency.

**Phase 3: Evidence Synthesis**
Research findings are synthesized with source extraction. Evidence is tracked and organized before answer generation begins, ensuring all claims can be attributed to specific sources.

**Phase 4: Answer Generation**
The final answer is generated with embedded citations, structured sections, and follow-up suggestions based on answer coverage analysis.

The system consists of three main components:

1. **Agent System** (`node/src/agent/`) - Core research and answer generation engine
   - Query classification and intent detection
   - Iterative research with tool-based actions
   - Evidence extraction and source tracking
   - Answer synthesis with source attribution
   - Follow-up suggestion generation based on answer coverage

2. **Backend API** (`node/src/routes/`) - Express.js REST API
   - `/api/chat` - Main streaming chat endpoint with SSE
   - `/api/autocomplete` - Query autocomplete suggestions
   - `/api/chats` - Chat history management
   - Session management and reconnection support

3. **Flutter Frontend** (`lib/`) - Android mobile application
   - Main search interface with query input
   - Answer display with follow-up suggestions
   - Riverpod-based state management for agent state
   - Real-time streaming UI updates via SSE
   - Chat history management and persistence
   - Android lifecycle-aware state persistence
   - Communicates with backend API via HTTP/SSE

## Features

**Research Modes**
- **Speed Mode** - Quick answers with minimal research iterations (2 iterations)
- **Balanced Mode** - Default mode for everyday queries (6 iterations)
- **Quality Mode** - Deep research with comprehensive coverage (up to 25 iterations)

**Search Capabilities**
- **Web Search** - Powered by SearxNG for privacy-focused web research
- **Academic Search** - Search scholarly articles and research papers
- **Discussion Search** - Find opinions and discussions from forums and communities
- **File Search** - Upload documents and ask questions about their content

**Smart Features**
- **Streaming Responses** - Real-time answer generation via Server-Sent Events (SSE)
- **Follow-up Suggestions** - Intelligent follow-up questions based on answer coverage
- **Chat History** - Persistent conversation history with cloud sync
- **Source Citations** - Every answer includes cited sources for verification
- **Query Classification** - Automatic intent detection to route queries to the right search type

**LLM Support**
- OpenAI (GPT-4, GPT-3.5)
- Custom OpenAI-compatible APIs
- Extensible provider system for adding new models

## Academic & Industry Relevance

This project contributes to several active research and industry areas:

**Agentic AI Systems**
The multi-phase agent architecture demonstrates patterns for building systems that can autonomously plan, execute research, and synthesize findings. The adaptive iteration depth and reasoning loop implementation contribute to research on agentic AI system design.

**Retrieval-Augmented Generation (RAG)**
The system implements RAG principles with dynamic retrieval (iterative research) rather than static knowledge bases. The evidence-first synthesis approach ensures answers are grounded in retrieved information rather than model hallucinations.

**Responsible AI with Citations**
The mandatory source citation system addresses concerns about AI-generated content verifiability. Every answer includes traceable sources, enabling users to verify claims and understand information provenance.

**Mobile-First AI Design**
The project demonstrates that sophisticated AI systems can be effectively delivered on mobile platforms through proper architectural design. This contributes to research on mobile AI architectures and streaming protocols for resource-constrained devices.

**Tool-Using AI Systems**
The system implements a tool registry and routing system that enables the agent to select appropriate tools based on query classification. This contributes to research on tool-using AI systems and multi-tool coordination.

## Installation

### Prerequisites

**Backend:**
- Node.js 18+ and npm
- SearxNG instance running on a server (backend dependency, not mobile)
- OpenAI API key (or compatible provider)

**Android App:**
- Flutter SDK 3.0+
- Android Studio or VS Code with Flutter extensions
- Android device or emulator

### Backend Setup

1. Clone the repository:
```bash
git clone <repository-url>
cd clonar
```

2. Navigate to the Node.js backend:
```bash
cd node
```

3. Install dependencies:
```bash
npm install
```

4. Create a `.env` file in the `node` directory:
```env
OPENAI_API_KEY=your_api_key_here
SEARXNG_URL=http://localhost:8080
PORT=4000
DATABASE_URL=your_database_url
```

5. Start the development server:
```bash
npm run dev
```

The API will be available at `http://localhost:4000`.

### Android App Setup

1. Navigate to the project root (where `pubspec.yaml` is located):
```bash
cd clonar
```

2. Install Flutter dependencies:
```bash
flutter pub get
```

3. Update the API base URL in `lib/core/api_client.dart` to point to your backend server:
```dart
// Update the baseUrl to your backend server address
// For local development: 'http://10.0.2.2:4000' (Android emulator)
// For production: 'https://your-backend-domain.com'
```

4. Connect an Android device or start an emulator, then run:
```bash
flutter run
```

**Note:** The Android app communicates with the backend API over HTTP. SearxNG runs on the backend server, not on the mobile device.

## Configuration

### SearxNG Setup (Backend Only)

SearxNG runs on your backend server, not on the Android device. The backend makes HTTP requests to SearxNG to perform web searches. You can:

- Run your own SearxNG instance on the same server as the backend
- Use a public SearxNG instance (not recommended for privacy)
- Deploy SearxNG separately and configure the backend to connect to it

**Backend Configuration:**
Set the `SEARXNG_URL` environment variable in your backend `.env` file:
```env
SEARXNG_URL=http://localhost:8080
```

**SearxNG Requirements:**
- JSON format enabled in SearxNG settings
- Wolfram Alpha search engine enabled (for calculations)
- Accessible from your backend server (not from mobile devices)

### LLM Provider Configuration

The agent supports multiple LLM providers through a plugin system. Configure providers in the backend settings or via environment variables.

## API Usage

### Streaming Chat Endpoint

```bash
POST /api/chat
Content-Type: application/json

{
  "message": {
    "messageId": "msg_123",
    "chatId": "chat_456",
    "content": "best hotels in Paris"
  },
  "chatId": "chat_456",
  "optimizationMode": "balanced",
  "sources": ["web"],
  "chatModel": {
    "key": "gpt-4",
    "providerId": "openai"
  },
  "embeddingModel": {
    "key": "text-embedding-3-small",
    "providerId": "openai"
  },
  "history": []
}
```

The response is a Server-Sent Events (SSE) stream with events:
- `start` - Research begins
- `research` - Research progress updates
- `answer` - Answer chunks (streaming)
- `done` - Research complete
- `error` - Error occurred

### Chat History

```bash
GET /api/chats
# Returns list of user's chat conversations

GET /api/chats/:chatId
# Returns messages for a specific conversation
```

## Development

### Project Structure

```
clonar/
├── node/                 # Backend (Node.js/Express)
│   ├── src/
│   │   ├── agent/        # Agent system core
│   │   ├── routes/       # API endpoints (chat, chats, autocomplete, reconnect)
│   │   ├── services/     # Business logic (search, query generation)
│   │   ├── models/       # LLM provider abstractions
│   │   ├── followup/     # Follow-up suggestion system
│   │   ├── config/       # Configuration management
│   │   └── db/           # Database schema and migrations
│   └── package.json
├── lib/                  # Frontend (Flutter)
│   ├── screens/
│   │   ├── ShopScreen.dart           # Query input screen
│   │   └── ClonarAnswerScreen.dart   # Answer display screen
│   ├── widgets/
│   │   ├── ClonarAnswerWidget.dart   # Answer rendering
│   │   ├── SessionRenderer.dart     # Session rendering
│   │   └── ResearchActivityWidget.dart # Research progress
│   ├── providers/        # Riverpod state management (11 providers)
│   ├── services/         # API clients and services
│   ├── models/           # Data models
│   ├── core/             # Core utilities
│   └── theme/            # App theme
└── README.md
```

### Key Components

**Agent System** (`node/src/agent/APISearchAgent.ts`)
- Manages research sessions and streaming
- Coordinates classification, research, and answer generation
- Handles tool-based actions (web search, scraping, etc.)

**Research Engine** (`node/src/agent/prompts/researcher.ts`)
- Iterative research with reasoning loops
- Mode-specific iteration limits and strategies
- Tool selection based on query classification

**Frontend State** (`lib/providers/agent_provider.dart`)
- Manages agent state and streaming
- Handles session history
- Coordinates UI updates during streaming

## Troubleshooting

**Streaming Not Working**
- Ensure SSE headers are properly set in the backend
- Check that the Android app is using the correct API base URL in `api_client.dart`
- For Android emulator, use `http://10.0.2.2:4000` to access localhost backend
- For physical device, use your computer's local IP address (e.g., `http://192.168.1.100:4000`)
- Verify network connectivity between Android device and backend server

**Search Results Empty**
- Verify SearxNG is running on your backend server and accessible from the backend
- Check that `SEARXNG_URL` is correctly configured in backend `.env`
- Verify SearxNG configuration (JSON format enabled)
- Review backend logs for search errors
- Note: SearxNG runs on the backend, not on the Android device

**LLM Provider Issues**
- Confirm API keys are correctly set in environment variables
- Check provider configuration in backend settings
- Verify model names match your provider's available models

## Future Enhancements

The following features are planned for future releases:

- **Context-Aware Widgets** - Interactive widgets for weather, stocks, calculations, Shopping and other quick lookups that appear when relevant to the query
- **Enhanced Search Sources** - Additional search integrations (Tavily, Exa, etc.) for improved research coverage
- **Custom Agent Configuration** - Ability to create and configure custom agent behaviors and workflows
- **Advanced Caching** - Smarter caching strategies with query-based expiry and LRU eviction
- **Multi-language Support** - Support for queries and answers in multiple languages

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

## License

This project is open source. See LICENSE file for details.
