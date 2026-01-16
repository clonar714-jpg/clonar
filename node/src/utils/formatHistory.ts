/**
 * Format chat history as string for LLM prompts
 */
export default function formatChatHistoryAsString(chatHistory: any[]): string {
  if (!chatHistory || chatHistory.length === 0) {
    return '';
  }

  return chatHistory
    .map((msg, index) => {
      if (msg.role === 'user' || msg.query) {
        const query = msg.query || msg.content || '';
        return `User: ${query}`;
      } else if (msg.role === 'assistant' || msg.answer || msg.summary) {
        const answer = msg.answer || msg.summary || msg.content || '';
        return `Assistant: ${answer}`;
      }
      return '';
    })
    .filter(Boolean)
    .join('\n');
}

