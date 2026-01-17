
import express from "express";
import { handleDetailRequest } from "../agent/detail.handler";

const router = express.Router();


router.post("/", handleDetailRequest);

export default router;
