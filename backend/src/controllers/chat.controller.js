const Message = require("../models/message.model");
const { uploadChatImage, deleteChatImage } = require("../storage/imagekit.service");

// Five hours in milliseconds
const FIVE_HOURS_MS = 5 * 60 * 60 * 1000;

/**
 * Clean up expired messages and delete their ImageKit cloud files
 */
async function cleanupExpiredMessages() {
  try {
    const now = new Date();
    const expiredMessages = await Message.find({
      expireAt: { $ne: null, $lte: now },
    });

    for (const msg of expiredMessages) {
      if (msg.imageFileId) {
        try {
          await deleteChatImage(msg.imageFileId);
        } catch (err) {
          console.error(`Failed to delete ImageKit image ${msg.imageFileId}:`, err.message);
        }
      }
    }

    if (expiredMessages.length > 0) {
      await Message.deleteMany({ _id: { $in: expiredMessages.map((m) => m._id) } });
    }
  } catch (error) {
    console.error("Error during expired message cleanup:", error.message);
  }
}

/**
 * Send a message (text and/or image)
 * Route: POST /api/chat/send
 */
async function sendMessage(req, res) {
  try {
    const { senderId, senderName, text } = req.body;

    if (!senderId) {
      return res.status(400).json({
        success: false,
        message: "senderId (Device ID) is required",
      });
    }

    let imageUrl = null;
    let imageFileId = null;

    if (req.file) {
      const uploadResult = await uploadChatImage(req.file.buffer, req.file.originalname);
      imageUrl = uploadResult.url;
      imageFileId = uploadResult.fileId;
    }

    if (!text && !imageUrl) {
      return res.status(400).json({
        success: false,
        message: "Message must contain text or an image",
      });
    }

    const newMessage = await Message.create({
      senderId: senderId.trim(),
      senderName: (senderName || "User").trim(),
      text: text ? text.trim() : "",
      imageUrl,
      imageFileId,
      isSeen: false,
      seenAt: null,
      expireAt: null, // Will start 5-hour countdown once seen by other person
    });

    return res.status(201).json({
      success: true,
      message: "Message sent",
      data: newMessage,
    });
  } catch (error) {
    console.error("Error in sendMessage:", error);
    return res.status(500).json({
      success: false,
      message: error.message || "Failed to send message",
    });
  }
}

/**
 * Get active messages
 * When other user views messages, marks unseen messages as seen
 * and starts the 5-hour self-destruct timer on both message and image.
 * Route: GET /api/chat/messages?deviceId=xyz
 */
async function getMessages(req, res) {
  try {
    const { deviceId } = req.query;
    const now = new Date();

    // Trigger cleanup of any expired items
    await cleanupExpiredMessages();

    // Fetch active non-expired messages
    const query = {
      $or: [{ expireAt: null }, { expireAt: { $gt: now } }],
    };

    const messages = await Message.find(query).sort({ createdAt: 1 });

    // If deviceId is provided, mark messages sent by OTHERS as seen
    if (deviceId) {
      const unseenIds = messages
        .filter((m) => m.senderId !== deviceId && !m.isSeen)
        .map((m) => m._id);

      if (unseenIds.length > 0) {
        const seenTime = new Date();
        const expireTime = new Date(seenTime.getTime() + FIVE_HOURS_MS);

        await Message.updateMany(
          { _id: { $in: unseenIds } },
          {
            $set: {
              isSeen: true,
              seenAt: seenTime,
              expireAt: expireTime,
            },
          }
        );

        messages.forEach((m) => {
          if (unseenIds.some((id) => id.equals(m._id))) {
            m.isSeen = true;
            m.seenAt = seenTime;
            m.expireAt = expireTime;
          }
        });
      }
    }

    return res.status(200).json({
      success: true,
      count: messages.length,
      data: messages,
    });
  } catch (error) {
    console.error("Error in getMessages:", error);
    return res.status(500).json({
      success: false,
      message: error.message || "Failed to fetch messages",
    });
  }
}

/**
 * Clear all chat messages and delete images from ImageKit
 * Route: DELETE /api/chat/clear
 */
async function clearChat(req, res) {
  try {
    const allMessages = await Message.find({});
    for (const msg of allMessages) {
      if (msg.imageFileId) {
        try {
          await deleteChatImage(msg.imageFileId);
        } catch (_) {}
      }
    }
    await Message.deleteMany({});
    return res.status(200).json({
      success: true,
      message: "Chat cleared successfully",
    });
  } catch (error) {
    return res.status(500).json({
      success: false,
      message: error.message || "Failed to clear chat",
    });
  }
}

module.exports = {
  sendMessage,
  getMessages,
  clearChat,
  cleanupExpiredMessages,
};
