import express from "express";
import fetch from "node-fetch";
import pkg from "pg";
import dotenv from "dotenv";
import bcrypt from "bcrypt";

// Load environment variables
dotenv.config();

const { Pool } = pkg;
const app = express();
const PORT = 3000;

// Database connection
const pool = new Pool({
  user: process.env.DB_USER || 'postgres',
  host: process.env.DB_HOST || 'postgres',
  database: process.env.DB_NAME || 'clonar_db',
  password: process.env.DB_PASSWORD || 'password',
  port: process.env.DB_PORT || 5432,
});

// Middleware to parse JSON bodies
app.use(express.json());

// Health check endpoint
app.get("/", (req, res) => {
  res.json({ message: "Clonar App API Gateway 🚀", status: "healthy" });
});

// Initialize database tables
async function initializeDatabase() {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        email VARCHAR(255) UNIQUE NOT NULL,
        password VARCHAR(255) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS products (
        id SERIAL PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        price DECIMAL(10,2) NOT NULL,
        discount_price DECIMAL(10,2),
        image_url VARCHAR(500),
        description TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS wishlist (
        id SERIAL PRIMARY KEY,
        user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
        product_id INTEGER REFERENCES products(id) ON DELETE CASCADE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(user_id, product_id)
      )
    `);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS wardrobe (
        id SERIAL PRIMARY KEY,
        user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
        product_id INTEGER REFERENCES products(id) ON DELETE CASCADE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(user_id, product_id)
      )
    `);

    // Insert sample products if they don't exist
    const productCount = await pool.query("SELECT COUNT(*) FROM products");
    if (parseInt(productCount.rows[0].count) === 0) {
      await pool.query(`
        INSERT INTO products (name, price, discount_price, image_url, description) VALUES
        ('RAY-BAN Aviator Sunglasses', 191.00, 153.00, 'https://images.unsplash.com/photo-1542291026-7eec264c27ff?w=300&h=300&fit=crop', 'Classic aviator sunglasses with premium lenses and durable metal frame'),
        ('Nike Women''s Dunk Low', 120.00, NULL, 'https://images.unsplash.com/photo-1606107557195-0e29a4b5b4aa?w=300&h=300&fit=crop', 'The iconic Dunk Low silhouette redesigned for women'),
        ('Apple AirPods Pro (2nd Generation)', 249.00, 199.00, 'https://images.unsplash.com/photo-1606220945770-b5b6c2c55bf1?w=300&h=300&fit=crop', 'AirPods Pro feature Active Noise Cancellation for immersive sound'),
        ('Samsung Galaxy S24 Ultra', 1199.99, NULL, 'https://images.unsplash.com/photo-1511707171634-5f897ff02aa9?w=300&h=300&fit=crop', 'The Samsung Galaxy S24 Ultra features a 6.8-inch Dynamic AMOLED 2X display'),
        ('MacBook Pro 14-inch M3', 1599.00, 1299.00, 'https://images.unsplash.com/photo-1517336714731-489689fd1ca8?w=300&h=300&fit=crop', 'The MacBook Pro 14-inch with M3 chip delivers exceptional performance')
      `);
    }

    console.log("Database initialized successfully");
  } catch (err) {
    console.error("Database initialization error:", err);
  }
}

// PRODUCTS ENDPOINTS
// GET /products - return all products
app.get("/products", async (req, res) => {
  try {
    const result = await pool.query("SELECT * FROM products ORDER BY created_at DESC");
    // Transform the data to match the expected format
    const products = result.rows.map(row => ({
      id: row.id,
      title: row.name,
      description: row.description || '',
      price: parseFloat(row.price),
      discountPrice: row.discount_price ? parseFloat(row.discount_price) : null,
      source: 'Clonar Store',
      rating: 4.5, // Default rating
      images: row.image_url ? [row.image_url] : [],
    }));
    res.json({ products });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "Failed to fetch products" });
  }
});

// GET /products/:id - return single product
app.get("/products/:id", async (req, res) => {
  try {
    const { id } = req.params;
    const result = await pool.query("SELECT * FROM products WHERE id = $1", [id]);
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: "Product not found" });
    }
    
    const row = result.rows[0];
    const product = {
      id: row.id,
      title: row.name,
      description: row.description || '',
      price: parseFloat(row.price),
      discountPrice: row.discount_price ? parseFloat(row.discount_price) : null,
      source: 'Clonar Store',
      rating: 4.5, // Default rating
      images: row.image_url ? [row.image_url] : [],
    };
    
    res.json({ product });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "Failed to fetch product" });
  }
});

// WISHLIST ENDPOINTS
// GET /wishlist?userId=:id - return wishlist items
app.get("/wishlist", async (req, res) => {
  try {
    const { userId } = req.query;
    if (!userId) {
      return res.status(400).json({ error: "userId is required" });
    }

    const result = await pool.query(`
      SELECT p.*, w.created_at as added_at 
      FROM products p 
      JOIN wishlist w ON p.id = w.product_id 
      WHERE w.user_id = $1 
      ORDER BY w.created_at DESC
    `, [userId]);

    res.json({ wishlist: result.rows });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "Failed to fetch wishlist" });
  }
});

// POST /wishlist - add item to wishlist
app.post("/wishlist", async (req, res) => {
  try {
    const { userId, productId } = req.body;
    if (!userId || !productId) {
      return res.status(400).json({ error: "userId and productId are required" });
    }

    const result = await pool.query(`
      INSERT INTO wishlist (user_id, product_id) 
      VALUES ($1, $2) 
      ON CONFLICT (user_id, product_id) DO NOTHING
      RETURNING *
    `, [userId, productId]);

    res.json({ message: "Item added to wishlist", item: result.rows[0] });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "Failed to add item to wishlist" });
  }
});

// DELETE /wishlist/:id - remove item from wishlist
app.delete("/wishlist/:id", async (req, res) => {
  try {
    const { id } = req.params;
    const { userId } = req.query;
    
    if (!userId) {
      return res.status(400).json({ error: "userId is required" });
    }

    const result = await pool.query(`
      DELETE FROM wishlist 
      WHERE id = $1 AND user_id = $2 
      RETURNING *
    `, [id, userId]);

    if (result.rows.length === 0) {
      return res.status(404).json({ error: "Wishlist item not found" });
    }

    res.json({ message: "Item removed from wishlist" });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "Failed to remove item from wishlist" });
  }
});

// WARDROBE ENDPOINTS
// GET /wardrobe?userId=:id - return wardrobe items
app.get("/wardrobe", async (req, res) => {
  try {
    const { userId } = req.query;
    if (!userId) {
      return res.status(400).json({ error: "userId is required" });
    }

    const result = await pool.query(`
      SELECT p.*, w.created_at as added_at 
      FROM products p 
      JOIN wardrobe w ON p.id = w.product_id 
      WHERE w.user_id = $1 
      ORDER BY w.created_at DESC
    `, [userId]);

    res.json({ wardrobe: result.rows });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "Failed to fetch wardrobe" });
  }
});

// POST /wardrobe - add item to wardrobe
app.post("/wardrobe", async (req, res) => {
  try {
    const { userId, productId } = req.body;
    if (!userId || !productId) {
      return res.status(400).json({ error: "userId and productId are required" });
    }

    const result = await pool.query(`
      INSERT INTO wardrobe (user_id, product_id) 
      VALUES ($1, $2) 
      ON CONFLICT (user_id, product_id) DO NOTHING
      RETURNING *
    `, [userId, productId]);

    res.json({ message: "Item added to wardrobe", item: result.rows[0] });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "Failed to add item to wardrobe" });
  }
});

// FEED ENDPOINTS
// GET /feed?userId=:id - return basic feed (all products for now)
app.get("/feed", async (req, res) => {
  try {
    const { userId } = req.query;
    if (!userId) {
      return res.status(400).json({ error: "userId is required" });
    }

    // For now, return all products. Later this will call Python service for recommendations
    const result = await pool.query("SELECT * FROM products ORDER BY created_at DESC");
    
    // Try to get personalized recommendations from Python service
    try {
      const recommendationsResponse = await fetch(`http://python:5000/recommendations?userId=${userId}`);
      if (recommendationsResponse.ok) {
        const recommendations = await recommendationsResponse.json();
        return res.json({ 
          feed: result.rows, 
          recommendations: recommendations.recommendations || [],
          personalized: true 
        });
      }
    } catch (err) {
      console.log("Python service unavailable, returning basic feed");
    }

    res.json({ feed: result.rows, personalized: false });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "Failed to fetch feed" });
  }
});

// AUTH ENDPOINTS
// POST /signup - create account
app.post("/signup", async (req, res) => {
  try {
    const { name, email, password } = req.body;
    
    if (!name || !email || !password) {
      return res.status(400).json({ error: "Name, email, and password are required" });
    }

    // Check if user already exists
    const existingUser = await pool.query("SELECT id FROM users WHERE email = $1", [email]);
    if (existingUser.rows.length > 0) {
      return res.status(409).json({ error: "User already exists" });
    }

    // Hash password
    const saltRounds = 10;
    const hashedPassword = await bcrypt.hash(password, saltRounds);

    // Create user
    const result = await pool.query(`
      INSERT INTO users (name, email, password) 
      VALUES ($1, $2, $3) 
      RETURNING id, name, email, created_at
    `, [name, email, hashedPassword]);

    res.status(201).json({ 
      message: "User created successfully", 
      user: result.rows[0] 
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "Failed to create user" });
  }
});

// POST /login - login user
app.post("/login", async (req, res) => {
  try {
    const { email, password } = req.body;
    
    if (!email || !password) {
      return res.status(400).json({ error: "Email and password are required" });
    }

    // Find user
    const result = await pool.query("SELECT * FROM users WHERE email = $1", [email]);
    if (result.rows.length === 0) {
      return res.status(401).json({ error: "Invalid credentials" });
    }

    const user = result.rows[0];

    // Verify password
    const isValidPassword = await bcrypt.compare(password, user.password);
    if (!isValidPassword) {
      return res.status(401).json({ error: "Invalid credentials" });
    }

    // Return user without password
    const { password: _, ...userWithoutPassword } = user;
    res.json({ 
      message: "Login successful", 
      user: userWithoutPassword 
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "Failed to login" });
  }
});

// Call Python API (legacy endpoint)
app.get("/python", async (req, res) => {
  try {
    const response = await fetch("http://python:5000/");
    const data = await response.json();
    res.json(data);
  } catch (err) {
    console.error(err);
    res.json({ "error": "Python service unavailable" });
  }
});

// Call Python SerpAPI search (legacy endpoint)
app.post("/search", async (req, res) => {
  try {
    const response = await fetch("http://python:5000/search", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(req.body),
    });
    const data = await response.json();
    res.json(data);
  } catch (err) {
    res.status(500).json({ error: "Failed to contact Python service" });
  }
});

// Initialize database and start server
initializeDatabase().then(() => {
app.listen(PORT, () => {
    console.log(`Node.js API Gateway running on http://localhost:${PORT}`);
  });
});
