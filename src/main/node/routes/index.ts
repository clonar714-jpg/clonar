/** Route aggregator. */
import express from 'express';
import queryRoutes from './query';
const router = express.Router();
router.use('/query', queryRoutes);
export default router;
