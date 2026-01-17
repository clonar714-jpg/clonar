import express from "express";
import { Request, Response } from "express";
import { db } from "../services/database";
import { getValidUserId } from "../utils/userIdHelper";

const router = express.Router();


router.get("/", async (req: Request, res: Response) => {
  try {
    const rawUserId = req.headers["user-id"] as string || "dev-user-id";
    const userId = getValidUserId(rawUserId);
    
    const { data, error } = await db.conversations()
      .select("id, title, created_at, updated_at")
      .eq("user_id", userId)
      .is("deleted_at", null)
      .order("updated_at", { ascending: false })
      .limit(50);
    
    if (error) {
      console.error("❌ Error fetching conversations:", error);
      return res.status(500).json({ 
        error: "Failed to fetch conversations",
        code: error.code || "UNKNOWN_ERROR"
      });
    }
    
    res.json({ conversations: data || [] });
  } catch (err: any) {
    console.error("❌ Unexpected error fetching conversations:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});


router.get("/:id", async (req: Request, res: Response) => {
  try {
    const conversationId = req.params.id;
    const rawUserId = req.headers["user-id"] as string || "dev-user-id";
    const userId = getValidUserId(rawUserId);
    
    if (!conversationId || conversationId.trim().length === 0) {
      return res.status(400).json({ error: "Invalid conversation ID" });
    }
    
    const { data: conversation, error: convError } = await db.conversations()
      .select("id, title, created_at, updated_at")
      .eq("id", conversationId)
      .eq("user_id", userId)
      .is("deleted_at", null)
      .single();
    
    if (convError || !conversation) {
      return res.status(404).json({ error: "Conversation not found" });
    }
    
    const { data: messages, error: msgError } = await db.conversationMessages()
      .select("*")
      .eq("conversation_id", conversationId)
      .order("created_at", { ascending: true });
    
    if (msgError) {
      console.error("❌ Error fetching messages:", msgError);
      return res.status(500).json({ error: "Failed to fetch messages" });
    }
    
    res.json({
      conversation,
      messages: messages || [],
    });
  } catch (err: any) {
    console.error("❌ Unexpected error:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});


router.post("/", async (req: Request, res: Response) => {
  console.log("🔥🔥🔥 POST /api/chats entered");
  
  
  let responseSent = false;
  const sendResponse = (status: number, data: any) => {
    if (responseSent) {
      console.warn("⚠️ Attempted to send response twice, ignoring second call");
      return;
    }
    responseSent = true;
    try {
      if (!res.headersSent) {
        res.status(status).json(data);
        console.log(`✅ Response sent: ${status}`);
      } else {
        console.warn("⚠️ Headers already sent, cannot send response");
      }
    } catch (err) {
      console.error("❌ Error sending response:", err);
    }
  };

  
  const timeoutId = setTimeout(() => {
    if (!responseSent) {
      console.error("❌❌❌ POST /api/chats TIMEOUT - No response sent after 3 seconds");
      sendResponse(500, { error: "Request timeout", message: "Database operation took too long" });
    }
  }, 3000);

  try {
    console.log("🔥🔥🔥 Extracting user ID from headers...");
    const rawUserId = req.headers["user-id"] as string || "dev-user-id";
    console.log(`🔥🔥🔥 Raw user ID: ${rawUserId}`);
    
    console.log("🔥🔥🔥 Resolving valid user ID...");
    const userId = getValidUserId(rawUserId);
    console.log(`🔥🔥🔥 User resolved: ${userId}`);
    
    console.log("🔥🔥🔥 Extracting title from body...");
    const { title } = req.body;
    console.log(`🔥🔥🔥 Title received: "${title}" (type: ${typeof title})`);
    
    if (!title || typeof title !== 'string' || title.trim().length === 0) {
      console.log("❌ Validation failed: Title is required and must be non-empty");
      clearTimeout(timeoutId);
      sendResponse(400, { error: "Title is required and must be non-empty" });
      return;
    }
    
    console.log("🔥🔥🔥 Creating chat in DB...");
    console.log(`🔥🔥🔥 Insert data: { user_id: "${userId}", title: "${title.trim().substring(0, 255)}" }`);
    
    
    const dbCall = db.conversations()
      .insert({
        user_id: userId,
        title: title.trim().substring(0, 255),
      })
      .select("id, title, created_at, updated_at")
      .single();
    
    
    const timeoutPromise = new Promise<{ data: null; error: { message: string; code: string } }>((resolve) => {
      setTimeout(() => {
        console.error("❌❌❌ Database operation TIMEOUT after 2 seconds");
        resolve({
          data: null,
          error: {
            message: "Database operation timeout after 2 seconds",
            code: "TIMEOUT"
          }
        });
      }, 2000);
    });
    

    let dbResult: { data: any; error: any };
    try {
      
      const dbPromise = Promise.resolve(dbCall).then((result: any) => {
        console.log("🔥🔥🔥 Database promise resolved");
        return { data: result.data, error: result.error };
      }).catch((err: any) => {
        console.error("🔥🔥🔥 Database promise rejected:", err);
        return { data: null, error: { message: err?.message || "Database error", code: err?.code || "UNKNOWN" } };
      });
      
      dbResult = await Promise.race([dbPromise, timeoutPromise]);
      console.log("🔥🔥🔥 Promise.race completed");
    } catch (raceError: any) {
      console.error("❌❌❌ Promise.race threw error:", raceError);
      clearTimeout(timeoutId);
      sendResponse(500, { 
        error: "Database error",
        message: raceError?.message || "An unexpected error occurred during database operation"
      });
      return;
    }
    
    clearTimeout(timeoutId);
    
    
    if (dbResult.error && dbResult.error.code === "TIMEOUT") {
      console.error("❌❌❌ Database operation timed out");
      sendResponse(500, { 
        error: "Database timeout",
        message: "Database operation took too long. Please try again."
      });
      return;
    }
    
    
    const { data, error } = dbResult;
    
    if (error) {
      console.error("❌ Error creating conversation:", error);
      console.error("❌ Error details:", JSON.stringify(error, null, 2));
      sendResponse(500, { 
        error: "Failed to create conversation",
        code: error.code || "UNKNOWN_ERROR",
        message: error.message || "Database error"
      });
      return;
    }
    
    if (!data) {
      console.error("❌ Database returned no data (but no error)");
      sendResponse(500, { 
        error: "Failed to create conversation",
        message: "Database returned no data"
      });
      return;
    }
    
    console.log("🔥🔥🔥 Chat created successfully");
    console.log(`🔥🔥🔥 Created conversation ID: ${data.id}`);
    console.log("🔥🔥🔥 Sending response...");
    
    sendResponse(201, { conversation: data });
    console.log("✅✅✅ POST /api/chats completed successfully");
  } catch (err: any) {
    clearTimeout(timeoutId);
    console.error("❌❌❌ Unexpected error creating conversation:", err);
    console.error("❌❌❌ Error type:", err?.constructor?.name);
    console.error("❌❌❌ Error message:", err?.message);
    console.error("❌❌❌ Error stack:", err?.stack);
    
    if (!responseSent) {
      sendResponse(500, { 
        error: "Internal server error",
        message: err?.message || "An unexpected error occurred"
      });
    } else {
      console.warn("⚠️ Response already sent, but error occurred after");
    }
  } finally {
    
    if (!responseSent) {
      console.error("❌❌❌ CRITICAL: No response sent in any code path!");
      try {
        if (!res.headersSent) {
          res.status(500).json({ 
            error: "Internal server error",
            message: "Request handler did not send a response"
          });
          console.log("✅ Emergency response sent");
        }
      } catch (finalErr) {
        console.error("❌❌❌ Failed to send emergency response:", finalErr);
      }
    }
  }
});


router.post("/:id/messages", async (req: Request, res: Response) => {
  try {
    const conversationId = req.params.id;
    const rawUserId = req.headers["user-id"] as string || "dev-user-id";
    const userId = getValidUserId(rawUserId);
    
    if (!conversationId || conversationId.trim().length === 0) {
      return res.status(400).json({ error: "Invalid conversation ID" });
    }
    
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!uuidRegex.test(conversationId)) {
      return res.status(400).json({ error: "Conversation ID must be a valid UUID" });
    }
    
    let { data: existingConv, error: convError } = await db.conversations()
      .select("id")
      .eq("id", conversationId)
      .eq("user_id", userId)
      .is("deleted_at", null)
      .single();
    
    if (convError || !existingConv) {
      const { query } = req.body;
      const title = (query as string)?.substring(0, 100) || "New Conversation";
      
      const { data: newConv, error: createError } = await db.conversations()
        .insert({
          id: conversationId,
          user_id: userId,
          title: title,
        })
          .select("id")
          .single();
        
        if (createError) {
        console.error(`❌ Error auto-creating conversation ${conversationId}:`, createError);
        return res.status(500).json({ 
          error: "Failed to create conversation",
          code: createError.code || "UNKNOWN_ERROR"
        });
      }
      
      existingConv = newConv;
    }
    
    const {
      query,
      summary,
      intent,
      cardType,
      cards,
      results,
      sections,
      answer,
      imageUrl,
      destinationImages, 
      sources, 
      followUpSuggestions, 
    } = req.body;
    
    if (!query || typeof query !== 'string' || query.trim().length === 0) {
      return res.status(400).json({ error: "Query is required and must be non-empty" });
    }
    
    const messageData: any = {
      conversation_id: existingConv.id,
      query: query.trim().substring(0, 1000),
      summary: summary && typeof summary === 'string' ? summary.substring(0, 5000) : null,
      intent: intent && typeof intent === 'string' ? intent.substring(0, 50) : null,
      card_type: cardType && typeof cardType === 'string' ? cardType.substring(0, 50) : null,
      cards: cards ? (typeof cards === 'string' ? cards : JSON.stringify(cards)).substring(0, 100000) : null,
      results: results ? (typeof results === 'string' ? results : JSON.stringify(results)).substring(0, 100000) : null,
      sections: sections ? (typeof sections === 'string' ? sections : JSON.stringify(sections)).substring(0, 100000) : null,
      answer: answer ? (typeof answer === 'string' ? answer : JSON.stringify(answer)).substring(0, 100000) : null,
    };
    
   
    if (sources) {
      messageData.sources = typeof sources === 'string' ? sources : JSON.stringify(sources);
      if (messageData.sources.length > 100000) messageData.sources = messageData.sources.substring(0, 100000);
    }
    if (followUpSuggestions) {
      messageData.follow_up_suggestions = typeof followUpSuggestions === 'string' ? followUpSuggestions : JSON.stringify(followUpSuggestions);
      if (messageData.follow_up_suggestions.length > 100000) messageData.follow_up_suggestions = messageData.follow_up_suggestions.substring(0, 100000);
    }
    
    if (imageUrl && typeof imageUrl === 'string') {
      messageData.image_url = imageUrl.substring(0, 500);
    }
    
    
    if (destinationImages && Array.isArray(destinationImages) && destinationImages.length > 0) {
      
      if (!messageData.results) {
        messageData.results = JSON.stringify({ destination_images: destinationImages });
      } else {
        try {
          const existingResults = typeof messageData.results === 'string' 
            ? JSON.parse(messageData.results) 
            : messageData.results;
          existingResults.destination_images = destinationImages;
          messageData.results = JSON.stringify(existingResults);
        } catch {
          
          messageData.results = JSON.stringify({ destination_images: destinationImages });
        }
      }
    }
    
    const { data, error } = await db.conversationMessages()
      .insert(messageData)
      .select()
      .single();
    
    if (error) {
      console.error("❌ Error creating message:", error);
      return res.status(500).json({ 
        error: "Failed to create message",
        code: error.code || "UNKNOWN_ERROR"
      });
    }
    
    Promise.resolve(
    db.conversations()
      .update({ updated_at: new Date().toISOString() })
        .eq("id", existingConv.id)
    ).catch((err: unknown) => {
      const error = err as { message?: string };
      console.warn("⚠️ Failed to update conversation timestamp:", error.message || err);
      });
    
    res.status(201).json({ 
      message: data,
      conversationId: existingConv.id
    });
  } catch (err: any) {
    console.error("❌ Unexpected error creating message:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});


router.put("/:id", async (req: Request, res: Response) => {
  try {
    const conversationId = req.params.id;
    const rawUserId = req.headers["user-id"] as string || "dev-user-id";
    const userId = getValidUserId(rawUserId);
    const { title } = req.body;
    
    if (!title || typeof title !== 'string' || title.trim().length === 0) {
      return res.status(400).json({ error: "Title is required and must be non-empty" });
    }
    
   
    const { data: conversation, error: convError } = await db.conversations()
      .select("id")
      .eq("id", conversationId)
      .eq("user_id", userId)
      .is("deleted_at", null)
      .single();
    
    if (convError || !conversation) {
      return res.status(404).json({ error: "Conversation not found" });
    }
    
    const { data, error } = await db.conversations()
      .update({
        title: title.trim().substring(0, 255),
        updated_at: new Date().toISOString(),
      })
      .eq("id", conversationId)
      .select("id, title, created_at, updated_at")
      .single();
    
    if (error) {
      console.error("❌ Error updating conversation:", error);
      return res.status(500).json({ error: "Failed to update conversation" });
    }
    
    res.json({ conversation: data });
  } catch (err: any) {
    console.error("❌ Unexpected error:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});


router.delete("/:id", async (req: Request, res: Response) => {
  try {
    const conversationId = req.params.id;
    const rawUserId = req.headers["user-id"] as string || "dev-user-id";
    const userId = getValidUserId(rawUserId);
    
   
    const { data: conversation, error: convError } = await db.conversations()
      .select("id")
      .eq("id", conversationId)
      .eq("user_id", userId)
      .is("deleted_at", null)
      .single();
    
    if (convError || !conversation) {
      return res.status(404).json({ error: "Conversation not found" });
    }
    
    
    const { error } = await db.conversations()
      .update({
        deleted_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq("id", conversationId);
    
    if (error) {
      console.error("❌ Error deleting conversation:", error);
      return res.status(500).json({ error: "Failed to delete conversation" });
    }
    
    res.json({ success: true });
  } catch (err: any) {
    console.error("❌ Unexpected error:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

export default router;
