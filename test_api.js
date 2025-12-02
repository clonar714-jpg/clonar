// Simple API test script for Clonar App Backend
// Run with: node test_api.js

const BASE_URL = 'http://localhost:3000';
const PYTHON_URL = 'http://localhost:5000';

async function testAPI() {
  console.log('🧪 Testing Clonar App Backend API...\n');

  try {
    // Test Node.js API health
    console.log('1. Testing Node.js API health...');
    const healthResponse = await fetch(`${BASE_URL}/`);
    const healthData = await healthResponse.json();
    console.log('✅ Node.js API:', healthData.message);

    // Test Python API health
    console.log('\n2. Testing Python API health...');
    const pythonResponse = await fetch(`${PYTHON_URL}/`);
    const pythonData = await pythonResponse.json();
    console.log('✅ Python API:', pythonData.message);

    // Test products endpoint
    console.log('\n3. Testing products endpoint...');
    const productsResponse = await fetch(`${BASE_URL}/products`);
    const productsData = await productsResponse.json();
    console.log(`✅ Products: Found ${productsData.products.length} products`);

    // Test user signup
    console.log('\n4. Testing user signup...');
    const signupResponse = await fetch(`${BASE_URL}/signup`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        name: 'Test User',
        email: 'test@example.com',
        password: 'password123'
      })
    });
    const signupData = await signupResponse.json();
    console.log('✅ Signup:', signupData.message);
    const userId = signupData.user.id;

    // Test user login
    console.log('\n5. Testing user login...');
    const loginResponse = await fetch(`${BASE_URL}/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: 'test@example.com',
        password: 'password123'
      })
    });
    const loginData = await loginResponse.json();
    console.log('✅ Login:', loginData.message);

    // Test wishlist operations
    console.log('\n6. Testing wishlist operations...');
    const addToWishlistResponse = await fetch(`${BASE_URL}/wishlist`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        userId: userId,
        productId: 1
      })
    });
    const wishlistData = await addToWishlistResponse.json();
    console.log('✅ Add to wishlist:', wishlistData.message);

    // Test wardrobe operations
    console.log('\n7. Testing wardrobe operations...');
    const addToWardrobeResponse = await fetch(`${BASE_URL}/wardrobe`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        userId: userId,
        productId: 2
      })
    });
    const wardrobeData = await addToWardrobeResponse.json();
    console.log('✅ Add to wardrobe:', wardrobeData.message);

    // Test feed endpoint
    console.log('\n8. Testing feed endpoint...');
    const feedResponse = await fetch(`${BASE_URL}/feed?userId=${userId}`);
    const feedData = await feedResponse.json();
    console.log(`✅ Feed: Found ${feedData.feed.length} products, personalized: ${feedData.personalized}`);

    // Test Python recommendations
    console.log('\n9. Testing Python recommendations...');
    const recommendationsResponse = await fetch(`${PYTHON_URL}/recommendations?userId=${userId}`);
    const recommendationsData = await recommendationsResponse.json();
    console.log(`✅ Recommendations: Found ${recommendationsData.recommendations.length} recommendations`);

    console.log('\n🎉 All tests passed! Backend is working correctly.');

  } catch (error) {
    console.error('❌ Test failed:', error.message);
    console.log('\n💡 Make sure to run: docker-compose up --build');
  }
}

testAPI();
