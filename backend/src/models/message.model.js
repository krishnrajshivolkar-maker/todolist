const mongoose = require("mongoose");

const messageSchema = new mongoose.Schema(
  {
    senderId: {
      type: String,
      required: [true, "Sender device ID is required"],
      trim: true,
      index: true,
    },
    senderName: {
      type: String,
      default: "User",
      trim: true,
    },
    text: {
      type: String,
      default: "",
      trim: true,
    },
    imageUrl: {
      type: String,
      default: null,
    },
    imageFileId: {
      type: String,
      default: null,
    },
    isSeen: {
      type: Boolean,
      default: false,
      index: true,
    },
    seenAt: {
      type: Date,
      default: null,
    },
    // MongoDB TTL Index: Document will be auto-deleted once current time >= expireAt
    expireAt: {
      type: Date,
      default: null,
    },
  },
  {
    timestamps: true,
  }
);

// TTL Index: automatically removes message 0 seconds after reaching expireAt
messageSchema.index({ expireAt: 1 }, { expireAfterSeconds: 0 });
messageSchema.index({ createdAt: 1 });

const Message = mongoose.model("Message", messageSchema);

module.exports = Message;
