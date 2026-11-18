const ImageKit = require("imagekit");

let imagekit;

function getImageKit() {
  if (imagekit) return imagekit;
  const required = ["IMAGEKIT_PUBLIC_KEY", "IMAGEKIT_PRIVATE_KEY", "IMAGEKIT_URL_ENDPOINT"];
  const missing = required.filter((key) => !process.env[key]);
  if (missing.length) {
    throw new Error(`ImageKit is not configured: missing ${missing.join(", ")}`);
  }
  imagekit = new ImageKit({
    publicKey: process.env.IMAGEKIT_PUBLIC_KEY,
    privateKey: process.env.IMAGEKIT_PRIVATE_KEY,
    urlEndpoint: process.env.IMAGEKIT_URL_ENDPOINT,
  });
  return imagekit;
}

/**
 * Upload an image for the private chat
 * @param {Buffer} fileBuffer
 * @param {string} fileName
 * @returns {Promise<Object>} ImageKit upload result ({ fileId, url, thumbnailUrl, name })
 */
const uploadChatImage = async (fileBuffer, fileName) => {
  return getImageKit().upload({
    file: fileBuffer,
    fileName: fileName || `wechat_${Date.now()}`,
    useUniqueFileName: true,
    folder: "/wechat/images",
  });
};

/**
 * Delete an image from ImageKit by fileId
 * @param {string} fileId
 * @returns {Promise<Object>}
 */
const deleteChatImage = async (fileId) => {
  if (!fileId) return;
  return getImageKit().deleteFile(fileId);
};

module.exports = {
  getImageKit,
  uploadChatImage,
  deleteChatImage,
};
