import { Router } from 'express';
import { submitFeedback, getFeedback } from '@/controllers/feedback.controller';

const router = Router();

router.post('/', submitFeedback);
router.get('/:sessionId', getFeedback);

export default router;
