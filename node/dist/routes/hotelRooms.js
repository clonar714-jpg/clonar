// src/routes/hotelRooms.ts
import express from "express";
import { RoomInventoryProvider } from "../services/roomsProvider";
const router = express.Router();
const roomsProvider = new RoomInventoryProvider();
/**
 * GET /api/hotels/:hotelId/rooms
 *
 * Fetch available rooms for a hotel with date and guest filters
 *
 * Query params:
 * - checkIn: ISO date string (required)
 * - checkOut: ISO date string (required)
 * - guests: number (required, default: 2)
 * - adults: number (optional)
 * - children: number (optional)
 */
router.get("/:hotelId/rooms", async (req, res) => {
    try {
        const { hotelId } = req.params;
        const { checkIn, checkOut, guests, adults, children } = req.query;
        // Validate required parameters
        if (!hotelId) {
            return res.status(400).json({ error: "Hotel ID is required" });
        }
        if (!checkIn || !checkOut) {
            return res.status(400).json({ error: "checkIn and checkOut dates are required" });
        }
        // Validate date format
        const checkInDate = new Date(checkIn);
        const checkOutDate = new Date(checkOut);
        if (isNaN(checkInDate.getTime()) || isNaN(checkOutDate.getTime())) {
            return res.status(400).json({ error: "Invalid date format. Use ISO date strings (YYYY-MM-DD)" });
        }
        if (checkOutDate <= checkInDate) {
            return res.status(400).json({ error: "checkOut date must be after checkIn date" });
        }
        // Parse guests (default to 2)
        const guestCount = guests ? parseInt(guests, 10) : 2;
        const adultCount = adults ? parseInt(adults, 10) : guestCount;
        const childCount = children ? parseInt(children, 10) : 0;
        if (isNaN(guestCount) || guestCount < 1) {
            return res.status(400).json({ error: "guests must be a positive number" });
        }
        // Build search params
        const searchParams = {
            hotelId,
            checkIn: checkIn,
            checkOut: checkOut,
            guests: guestCount,
            adults: adultCount,
            children: childCount,
        };
        console.log(`🏨 Fetching rooms for hotel ${hotelId}:`, searchParams);
        // Fetch rooms from provider
        const result = await roomsProvider.fetchRooms(searchParams);
        return res.json(result);
    }
    catch (err) {
        console.error("❌ Error fetching hotel rooms:", err.message);
        return res.status(500).json({
            error: "Failed to fetch hotel rooms",
            message: err.message
        });
    }
});
export default router;
