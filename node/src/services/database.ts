import { createClient } from "@supabase/supabase-js";

// Lazy-load environment variables to ensure dotenv.config() has run
const getSupabaseUrl = () => {
  const url = process.env.SUPABASE_URL;
  if (!url) {
    throw new Error("❌ Missing SUPABASE_URL in .env");
  }
  return url;
};

const getSupabaseKey = () => {
  const key = process.env.SUPABASE_ANON_KEY;
  if (!key) {
    throw new Error("❌ Missing SUPABASE_ANON_KEY in .env");
  }
  return key;
};

const getServiceKey = () => {
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) {
    throw new Error("❌ Missing SUPABASE_SERVICE_ROLE_KEY in .env");
  }
  return key;
};

// ✅ Fresh clients (no global cache)
export const supabase = () => createClient(getSupabaseUrl(), getSupabaseKey());
export const supabaseAdmin = () => createClient(getSupabaseUrl(), getServiceKey());

// ✅ Always return a new connection
export const db = {
  users: () => supabaseAdmin().from("users"),
  personas: () => supabaseAdmin().from("personas"),
  personaItems: () => supabaseAdmin().from("persona_items"),
  collages: () => supabaseAdmin().from("collages"),
  collageItems: () => supabaseAdmin().from("collage_items"),
  storage: () => supabaseAdmin().storage,
};

export const connectDatabase = async () => {
  try {
    // Get env vars (will throw if missing)
    const supabaseUrl = getSupabaseUrl();
    const serviceKey = getServiceKey();
    
    // First, test basic connectivity to Supabase URL
    console.log(`🔍 Testing connection to: ${supabaseUrl}`);
    
    // Add timeout and better error handling
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 10000); // 10 second timeout
    
    try {
      // Test basic connectivity first
      const healthCheck = await fetch(`${supabaseUrl}/rest/v1/`, {
        method: 'HEAD',
        signal: controller.signal,
        headers: {
          'apikey': serviceKey,
          'Authorization': `Bearer ${serviceKey}`
        }
      });
      
      clearTimeout(timeoutId);
      
      if (!healthCheck.ok) {
        throw new Error(`Supabase returned status ${healthCheck.status}: ${healthCheck.statusText}`);
      }
      
      console.log("✅ Supabase URL is reachable");
    } catch (fetchErr: any) {
      clearTimeout(timeoutId);
      
      // Log full error details for debugging
      console.error("   Raw error details:", {
        name: fetchErr.name,
        message: fetchErr.message,
        code: fetchErr.code,
        cause: fetchErr.cause,
        errno: fetchErr.errno,
        syscall: fetchErr.syscall,
        hostname: fetchErr.hostname,
        stack: fetchErr.stack?.split('\n').slice(0, 3).join('\n')
      });
      
      if (fetchErr.name === 'AbortError') {
        throw new Error('Connection timeout: Supabase URL did not respond within 10 seconds. Check if your Supabase project is paused or your network connection.');
      }
      
      // Check various error codes and causes
      const errorCode = fetchErr.code || fetchErr.cause?.code || fetchErr.errno;
      const errorMessage = fetchErr.message || fetchErr.cause?.message || 'Unknown error';
      
      if (errorCode === 'ENOTFOUND' || errorCode === 'EAI_AGAIN') {
        throw new Error(`DNS resolution failed: Cannot resolve Supabase hostname. Check your internet connection and DNS settings.\n\nError: ${errorMessage}`);
      }
      
      if (errorCode === 'ECONNREFUSED') {
        throw new Error(`Connection refused: Supabase server is not accepting connections. Your project might be paused.\n\nTo fix: Go to https://supabase.com/dashboard and restore your project.\n\nError: ${errorMessage}`);
      }
      
      if (errorCode === 'ETIMEDOUT' || errorCode === 'ECONNRESET') {
        throw new Error(`Connection timeout/reset: Unable to establish connection to Supabase. Check firewall settings or try again later.\n\nError: ${errorMessage}`);
      }
      
      if (errorMessage.includes('certificate') || errorMessage.includes('SSL') || errorMessage.includes('TLS')) {
        throw new Error(`SSL/TLS certificate error: ${errorMessage}\n\nThis might be a proxy or firewall issue.`);
      }
      
      // Generic error with all available info
      throw new Error(`Network error connecting to Supabase.\n\nError: ${errorMessage}\nCode: ${errorCode || 'unknown'}\n\nPossible causes:\n  - Supabase project is paused (check dashboard)\n  - Network connectivity issues\n  - Firewall/proxy blocking connection\n  - Incorrect SUPABASE_URL`);
    }
    
    // Now test the actual database query
    const { error } = await supabaseAdmin().from("users").select("id").limit(1);
    if (error) {
      throw new Error(`Database query failed: ${error.message} (Code: ${error.code || 'unknown'})`);
    }
    
    console.log("✅ Connected to Supabase database successfully");
  } catch (err: any) {
    console.error("❌ Supabase connection failed:");
    console.error("   Message:", err.message);
    if (err.details) console.error("   Details:", err.details);
    if (err.hint) console.error("   Hint:", err.hint);
    if (err.code) console.error("   Code:", err.code);
    throw err;
  }
};