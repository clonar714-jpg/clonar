import express, { Request, Response } from "express";

const router = express.Router();


router.get("/", (req: Request, res: Response) => {
  res.json({ message: "Geocode route is working!", method: "GET" });
});


router.post("/", async (req: Request, res: Response) => {
  console.log('📍 Geocode POST route hit!', { body: req.body, url: req.url, method: req.method });
  try {
    const { address } = req.body;

    if (!address || typeof address !== 'string' || address.trim().length === 0) {
      return res.status(400).json({ error: "Address is required" });
    }

    const apiKey = process.env.GOOGLE_MAPS_BACKEND_KEY;
    
    if (!apiKey) {
      console.warn("⚠️ GOOGLE_MAPS_BACKEND_KEY not configured");
      return res.status(500).json({ 
        error: "Google Maps API key not configured",
        message: "Please add GOOGLE_MAPS_BACKEND_KEY to your .env file"
      });
    }
    
    console.log(`🔑 Using GOOGLE_MAPS_BACKEND_KEY (length: ${apiKey.length}, starts with: ${apiKey.substring(0, 10)}...)`);

    
    const geocodeUrl = `https://maps.googleapis.com/maps/api/geocode/json?address=${encodeURIComponent(address)}&key=${apiKey}`;
    console.log(`🌍 Geocoding URL: ${geocodeUrl.substring(0, 100)}...`);

    const response = await fetch(geocodeUrl);
    
    if (!response.ok) {
      console.error(`❌ Google Maps API HTTP error: ${response.status} ${response.statusText}`);
      throw new Error(`Google Maps API error: ${response.status} ${response.statusText}`);
    }

    const data = await response.json();
    console.log(`🌍 Geocoding API response status: ${data.status}`);

    if (data.status === 'OK' && data.results && data.results.length > 0) {
      const location = data.results[0].geometry.location;
      console.log(`✅ Geocoded successfully: ${location.lat}, ${location.lng}`);
      res.json({
        latitude: location.lat,
        longitude: location.lng,
        formatted_address: data.results[0].formatted_address,
      });
    } else {
      console.warn(`⚠️ Geocoding failed - Status: ${data.status}, Error: ${data.error_message || 'Unknown error'}`);
      
      res.status(200).json({ 
        error: "Address not found",
        status: data.status,
        error_message: data.error_message || 'Unknown error',
        latitude: null,
        longitude: null,
      });
    }
  } catch (error: any) {
    console.error("❌ Geocoding error:", error);
    res.status(500).json({ 
      error: "Failed to geocode address",
      message: error.message 
    });
  }
});

export default router;

