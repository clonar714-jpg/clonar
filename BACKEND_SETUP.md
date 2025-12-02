# Clonar App Backend Setup

This document provides setup instructions for the Clonar app backend with Node.js, Python FastAPI, and PostgreSQL.

## Architecture

- **Node.js (Express)**: Main API Gateway on port 3000
- **Python (FastAPI)**: AI/Recommendations service on port 5000  
- **PostgreSQL**: Database on port 5432

## Environment Variables

Create a `.env` file in the root directory with the following variables:

```env
# Database Configuration
DB_HOST=postgres
DB_PORT=5432
DB_NAME=clonar_db
DB_USER=postgres
DB_PASSWORD=password

# SerpAPI Configuration (optional)
SERPAPI_KEY=your_serpapi_key_here
SERPAPI_ENDPOINT=https://serpapi.com/search.json

# Node.js Configuration
NODE_ENV=development

# Python Configuration
PYTHON_ENV=development
```

## API Endpoints

### Node.js API Gateway (Port 3000)

#### Products
- `GET /products` - Get all products
- `GET /products/:id` - Get single product

#### Wishlist
- `GET /wishlist?userId=:id` - Get user's wishlist
- `POST /wishlist` - Add item to wishlist
- `DELETE /wishlist/:id?userId=:id` - Remove item from wishlist

#### Wardrobe
- `GET /wardrobe?userId=:id` - Get user's wardrobe
- `POST /wardrobe` - Add item to wardrobe

#### Feed
- `GET /feed?userId=:id` - Get personalized feed with recommendations

#### Authentication
- `POST /signup` - Create new user account
- `POST /login` - Login user

### Python AI Service (Port 5000)

#### Recommendations
- `GET /recommendations?userId=:id` - Get personalized product recommendations

## Database Schema

### Tables
- **users**: id, name, email, password, created_at
- **products**: id, name, price, image_url, description, created_at
- **wishlist**: id, user_id, product_id, created_at
- **wardrobe**: id, user_id, product_id, created_at

## Running the Application

1. **Start all services with Docker Compose:**
   ```bash
   docker-compose up --build
   ```

2. **Access the services:**
   - Node.js API: http://localhost:3000
   - Python AI Service: http://localhost:5000
   - PostgreSQL: localhost:5432

3. **Test the API:**
   ```bash
   # Test Node.js API
   curl http://localhost:3000/products
   
   # Test Python recommendations
   curl http://localhost:5000/recommendations?userId=1
   ```

## Development

### Node.js Service
- Located in `./node/`
- Uses Express.js with PostgreSQL
- Auto-creates database tables on startup
- Includes sample product data

### Python Service  
- Located in `./python/`
- Uses FastAPI
- Currently returns mock recommendations
- Ready for ML model integration

### Database
- PostgreSQL 15
- Persistent data storage
- Health checks configured
- Auto-initialization on first run

## Next Steps

1. **ML Integration**: Replace mock recommendations with real ML models
2. **Vector Database**: Add Qdrant or Pinecone for embeddings
3. **Authentication**: Add JWT tokens for secure API access
4. **Caching**: Add Redis for improved performance
5. **Monitoring**: Add logging and metrics collection
