const multer = require("multer");

const storage = multer.memoryStorage();

const fileFilter = (req, file, cb) => {
  // Accept only image formats
  if (file.mimetype && file.mimetype.startsWith("image/")) {
    cb(null, true);
  } else {
    cb(new Error("Only image files are allowed!"), false);
  }
};

const upload = multer({
  storage: storage,
  fileFilter: fileFilter,
  limits: {
    fileSize: 15 * 1024 * 1024, // 15MB max limit per image
  },
});

// Single chat image upload (form field: "image")
const uploadChatImage = upload.single("image");

// Multi chat images upload (form field: "images", up to 5)
const uploadChatImages = upload.array("images", 5);

module.exports = {
  uploadChatImage,
  uploadChatImages,
  uploadMiddleware: upload,
};
