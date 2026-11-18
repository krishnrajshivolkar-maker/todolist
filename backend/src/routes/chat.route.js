const express = require("express");
const router = express.Router();
const { uploadChatImage } = require("../middleware/upload.middleware");
const {
  sendMessage,
  getMessages,
  clearChat,
} = require("../controllers/chat.controller");

// Send message (supports optional image upload)
router.post("/send", uploadChatImage, sendMessage);

// Get chat messages (marks messages as seen for deviceId)
router.get("/messages", getMessages);

// Clear chat
router.delete("/clear", clearChat);

module.exports = router;
