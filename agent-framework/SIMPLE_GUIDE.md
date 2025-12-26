# Simple Guide: How to Install and Use the Agentic Framework

This guide is written in simple language for people who are not technical experts. We'll explain everything step by step.

## 📖 What is This?

The Agentic Framework is like a smart assistant that can answer questions by searching the internet and providing helpful answers. Think of it like having a research assistant that:

- Reads your questions
- Searches the web for information
- Summarizes the findings
- Gives you a clear, organized answer

## ✅ What You Need Before Starting

Before you begin, make sure you have:

1. **A computer** (Windows, Mac, or Linux)
2. **Node.js installed** - This is free software that lets you run the framework
   - Download from: https://nodejs.org/
   - Choose the "LTS" version (it's the most stable)
   - Install it like any other program
3. **An OpenAI API Key** - This is like a password that lets the framework use AI
   - Sign up at: https://platform.openai.com/
   - Create an API key in your account settings
   - Keep this key safe - you'll need it later
4. **A text editor** - Any simple text editor works (Notepad on Windows, TextEdit on Mac, or VS Code)

## 📥 Step 1: Download the Framework

1. Download or copy the framework files to a folder on your computer
2. For example, create a folder called `agent-framework` on your Desktop
3. Put all the framework files inside this folder

## 🔧 Step 2: Install the Framework

### On Windows:

1. Open the Command Prompt:
   - Press the Windows key
   - Type "cmd" and press Enter
   - A black window will open

2. Navigate to your framework folder:
   - Type: `cd Desktop\agent-framework` (or wherever you put the files)
   - Press Enter

3. Install the required software:
   - Type: `npm install`
   - Press Enter
   - Wait for it to finish (this may take a few minutes)
   - You'll see lots of text scrolling - that's normal!

### On Mac or Linux:

1. Open Terminal:
   - On Mac: Press Cmd + Space, type "Terminal", press Enter
   - On Linux: Press Ctrl + Alt + T

2. Navigate to your framework folder:
   - Type: `cd ~/Desktop/agent-framework` (or wherever you put the files)
   - Press Enter

3. Install the required software:
   - Type: `npm install`
   - Press Enter
   - Wait for it to finish

## ⚙️ Step 3: Set Up Your API Key

1. In your framework folder, find a file called `.env.example`
2. Copy this file and rename the copy to `.env` (remove the `.example` part)
3. Open the `.env` file with a text editor
4. Find the line that says: `OPENAI_API_KEY=your_openai_api_key_here`
5. Replace `your_openai_api_key_here` with your actual OpenAI API key
6. Save the file

**Important:** Never share your API key with anyone! It's like a password.

## 🚀 Step 4: Start the Framework

1. Make sure you're still in the Command Prompt or Terminal
2. Make sure you're in the framework folder (use `cd` command if needed)
3. Type: `npm run dev`
4. Press Enter

You should see a message like:
```
🚀 Agent Framework server running on http://localhost:4000
```

This means it's working! The framework is now running and ready to answer questions.

**Note:** Keep this window open while you're using the framework. If you close it, the framework will stop.

## 💬 Step 5: How to Use It

The framework is now running and waiting for questions. You can ask it questions in two ways:

### Method 1: Using a Web Browser (Easiest)

1. Open your web browser (Chrome, Firefox, Safari, etc.)
2. Go to: `http://localhost:4000/health`
3. You should see: `{"status":"OK","timestamp":"..."}`
4. This confirms the framework is working!

### Method 2: Using a Tool Like Postman or curl

**Using curl (in a new Terminal/Command Prompt window):**

```bash
curl -X POST http://localhost:4000/api/agent \
  -H "Content-Type: application/json" \
  -d "{\"query\": \"What is artificial intelligence?\"}"
```

**What this does:**
- Sends a question: "What is artificial intelligence?"
- The framework searches the web
- Returns a detailed answer

**Using Postman (easier for beginners):**

1. Download Postman from: https://www.postman.com/downloads/
2. Open Postman
3. Create a new request:
   - Method: POST
   - URL: `http://localhost:4000/api/agent`
   - Headers: Add `Content-Type` with value `application/json`
   - Body: Select "raw" and "JSON", then type:
     ```json
     {
       "query": "What is artificial intelligence?",
       "stream": false
     }
     ```
4. Click "Send"
5. Wait a few seconds
6. You'll see the answer appear below!

## 🧪 Step 6: How to Test It

Testing means checking if everything works correctly. Here are simple tests you can do:

### Test 1: Check if the Framework is Running

1. Open your browser
2. Go to: `http://localhost:4000/health`
3. **Expected result:** You should see `{"status":"OK",...}`
4. **If it doesn't work:** The framework might not be running. Go back to Step 4.

### Test 2: Ask a Simple Question

1. Use Postman or curl (see Method 2 above)
2. Ask: "What is the weather like?"
3. **Expected result:** You should get a detailed answer about weather
4. **If it doesn't work:** Check your API key in the `.env` file

### Test 3: Ask a Follow-up Question

1. First, ask: "Tell me about Paris"
2. Then ask: "What are the best restaurants there?"
3. **Expected result:** The second answer should reference Paris from the first question
4. **If it doesn't work:** Check that you're sending conversation history (see advanced usage below)

### Test 4: Test Streaming (Real-time Answers)

1. In Postman, set `"stream": true` in your request
2. Ask a question
3. **Expected result:** You should see the answer appear word by word, like someone is typing
4. **If it doesn't work:** Make sure you're viewing the response as "stream" in Postman

## 📝 Example Questions to Try

Here are some good questions to test with:

- "What is machine learning?"
- "Explain how photosynthesis works"
- "What are the best practices for time management?"
- "Tell me about the history of the internet"
- "What are the benefits of exercise?"

## 🔍 Understanding the Response

When you ask a question, you'll get back a response that looks like this:

```json
{
  "success": true,
  "summary": "A brief summary of the answer",
  "answer": "The full detailed answer...",
  "sections": [
    {
      "title": "Section Title",
      "content": "Content of this section"
    }
  ],
  "sources": [
    {
      "title": "Source Title",
      "url": "https://example.com"
    }
  ],
  "followUpSuggestions": [
    "Related question 1",
    "Related question 2"
  ]
}
```

**What each part means:**
- **success**: Whether the request worked (should be `true`)
- **summary**: A short version of the answer
- **answer**: The complete answer to your question
- **sections**: The answer broken into organized parts
- **sources**: Where the information came from (websites)
- **followUpSuggestions**: Related questions you might want to ask next

## 🛠️ Troubleshooting (Fixing Problems)

### Problem: "Cannot find module" error

**Solution:**
- Make sure you ran `npm install` in Step 2
- Make sure you're in the correct folder

### Problem: "Missing OPENAI_API_KEY" error

**Solution:**
- Check that you created the `.env` file (not `.env.example`)
- Make sure your API key is in the `.env` file
- Make sure there are no extra spaces around the `=` sign

### Problem: Framework won't start

**Solution:**
- Make sure Node.js is installed (type `node --version` in terminal)
- Make sure you're in the correct folder
- Check for error messages - they usually tell you what's wrong

### Problem: "Port 4000 already in use"

**Solution:**
- Another program is using port 4000
- Close other programs that might be using it
- Or change the port in your `.env` file: `PORT=4001`

### Problem: Answers are slow or not appearing

**Solution:**
- This is normal! The framework needs to search the web and process information
- Simple questions: 2-5 seconds
- Complex questions: 5-15 seconds
- If it takes longer than 30 seconds, check your internet connection

### Problem: Getting errors when asking questions

**Solution:**
- Check that the framework is still running (Step 4)
- Check your internet connection
- Make sure your API key is valid and has credits
- Try a simpler question first

## 📚 Advanced Usage (Optional)

### Asking Follow-up Questions

To ask follow-up questions that remember the conversation:

```json
{
  "query": "What are the best restaurants in Paris?",
  "conversationHistory": [
    {
      "query": "Tell me about Paris",
      "summary": "Paris is the capital of France..."
    }
  ],
  "stream": false
}
```

### Using Streaming (Real-time Answers)

Set `"stream": true` to see answers appear in real-time:

```json
{
  "query": "Explain quantum computing",
  "stream": true
}
```

## 🎉 Success Checklist

You've successfully set up the framework if:

- ✅ Node.js is installed
- ✅ You ran `npm install` successfully
- ✅ You created the `.env` file with your API key
- ✅ The framework starts without errors (`npm run dev`)
- ✅ The health check works (`http://localhost:4000/health`)
- ✅ You can ask questions and get answers

## 🆘 Getting Help

If you're stuck:

1. **Check the error messages** - They usually tell you what's wrong
2. **Read the main README.md** - It has more technical details
3. **Check your setup** - Make sure you followed all steps
4. **Try the troubleshooting section** above

## 📞 Common Questions

**Q: Do I need to be online?**
A: Yes, the framework needs internet to search the web and use AI.

**Q: Is it free?**
A: The framework itself is free, but you need an OpenAI API key which has usage costs.

**Q: Can I use it without coding?**
A: Yes! This guide is for non-technical people. You just need to follow the steps.

**Q: How much does it cost?**
A: OpenAI charges based on usage. Simple questions cost a few cents. Check OpenAI's pricing.

**Q: Can I stop the framework?**
A: Yes, just close the terminal/command prompt window or press Ctrl+C.

**Q: Do I need to restart it every time?**
A: Yes, if you close it, you need to run `npm run dev` again to start it.

## 🎓 Next Steps

Once you have it working:

1. Try different types of questions
2. Experiment with streaming vs non-streaming
3. Try follow-up questions
4. Read the main README.md for more advanced features
5. Check out the examples in the `examples/` folder (if available)

## ✨ Congratulations!

You've successfully installed and tested the Agentic Framework! You can now use it to answer questions by searching the web and providing intelligent answers.

Remember:
- Keep the framework running while you use it
- Keep your API key secret
- Have fun exploring what it can do!

---

**Need more help?** Check the main README.md file for technical details, or review the troubleshooting section above.

