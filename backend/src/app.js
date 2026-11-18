const express = require("express");
const cookieParser = require("cookie-parser");
const cors = require("cors");

require("dotenv").config();

const app = express();

app.use(cors({
    origin: true,
    credentials: true,
    methods: ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"]
}));

app.use(express.json());
app.use(cookieParser());
app.use(express.urlencoded({ extended: true }));

const chatRoutes = require("./routes/chat.route");
const { cleanupExpiredMessages } = require("./controllers/chat.controller");

app.use("/api/chat", chatRoutes);

// Periodic cleanup for expired messages and ImageKit media (runs every 10 minutes)
const cleanupInterval = setInterval(() => {
    cleanupExpiredMessages();
}, 10 * 60 * 1000);
if (cleanupInterval.unref) {
    cleanupInterval.unref();
}

app.get("/health", (req, res) => {
    res.status(200).json({ message: "Server is running", timestamp: new Date().toISOString() });
});

// 404 handler
app.use((req, res) => {
    res.status(404).json({ message: "Route not found" });
});

module.exports = app;
