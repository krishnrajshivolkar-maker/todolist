import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  // Device identity (No login required - persistent identifier)
  late String myDeviceId;
  String myDisplayName = 'Me';

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();

  final String baseUrl = 'https://todolist-o75o.onrender.com';

  List<dynamic> _messages = [];
  File? _selectedImage;
  bool _isLoading = false;
  bool _isSending = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _initDeviceIdentity();
    _fetchMessages();

    // Auto-sync messages every 3 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _fetchMessages(silent: true);
    });
  }

  // Generates or loads a random device identifier for this installation
  void _initDeviceIdentity() {
    // Generate a short 6-digit hex identifier
    final rand = Random();
    final randomHex = (rand.nextInt(0xFFFFFF) + 0x100000).toRadixString(16);
    myDeviceId = 'device_$randomHex';
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Fetch active messages from backend
  Future<void> _fetchMessages({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final uri = Uri.parse('$baseUrl/api/chat/messages?deviceId=$myDeviceId');
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted && data['success'] == true) {
          final List<dynamic> fetched = data['data'] ?? [];
          final bool shouldScroll = _messages.length != fetched.length;

          setState(() {
            _messages = fetched;
          });

          if (shouldScroll) {
            _scrollToBottom();
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching messages: $e');
    } finally {
      if (!silent && mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Pick an image from gallery or camera
  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (pickedFile != null && mounted) {
        setState(() {
          _selectedImage = File(pickedFile.path);
        });
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFB00020),
            content: Text(
              'Error selecting image: $e',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        );
      }
    }
  }

  // Send message (text and/or image)
  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty && _selectedImage == null) return;

    setState(() => _isSending = true);

    try {
      final uri = Uri.parse('$baseUrl/api/chat/send');
      final request = http.MultipartRequest('POST', uri);

      request.fields['senderId'] = myDeviceId;
      request.fields['senderName'] = myDisplayName;
      if (text.isNotEmpty) {
        request.fields['text'] = text;
      }

      if (_selectedImage != null) {
        request.files.add(
          await http.MultipartFile.fromPath('image', _selectedImage!.path),
        );
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 201) {
        _messageController.clear();
        setState(() {
          _selectedImage = null;
        });
        await _fetchMessages(silent: true);
        _scrollToBottom();
      } else {
        if (mounted) {
          String errorMessage = 'Server error (${response.statusCode})';
          try {
            final decoded = jsonDecode(response.body);
            if (decoded is Map && decoded.containsKey('message')) {
              errorMessage = decoded['message'].toString();
            }
          } catch (_) {
            if (response.body.contains('<pre>')) {
              final match = RegExp(r'<pre>(.*?)</pre>', dotAll: true).firstMatch(response.body);
              if (match != null) {
                errorMessage = match.group(1)?.trim() ?? errorMessage;
              }
            } else if (response.body.toLowerCase().contains('<!doctype')) {
              errorMessage = 'Server configuration error (missing environment variables on host)';
            }
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFFB00020),
              content: Text(
                'Failed to send: $errorMessage',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFB00020),
            content: Text(
              'Network error: $e',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Format 5-hour countdown timer
  String _formatExpiry(String? expireAtStr) {
    if (expireAtStr == null) return 'Unseen';
    final expireAt = DateTime.tryParse(expireAtStr);
    if (expireAt == null) return 'Active';

    final diff = expireAt.difference(DateTime.now());
    if (diff.isNegative) return 'Deleting';

    final hours = diff.inHours;
    final minutes = diff.inMinutes.remainder(60);
    return '${hours}h ${minutes}m left';
  }

  // Format timestamp (e.g. 10:45 AM)
  String _formatTime(String? dateStr) {
    if (dateStr == null) return '';
    final dt = DateTime.tryParse(dateStr)?.toLocal();
    if (dt == null) return '';
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  // Preview image full-screen
  void _openImagePreview(String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
            title: const Text(
              'Image Preview',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.network(
                url,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B141A), // Dark WhatsApp Background
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF1F2C34), // Dark WhatsApp Appbar
        titleSpacing: 0,
        title: Row(
          children: [
            const SizedBox(width: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/logo.png',
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 36,
                  height: 36,
                  color: const Color(0xFF00A884),
                  child: const Icon(Icons.chat, color: Colors.white, size: 20),
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Wechat',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Private Encrypted Room',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF8696A0),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Device identity pill (Allows switching if testing on one device)
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: PopupMenuButton<String>(
              color: const Color(0xFF233138),
              icon: const Icon(Icons.more_vert, color: Color(0xFFAEBAC1)),
              onSelected: (value) {
                if (value == 'switch_device') {
                  setState(() {
                    final rand = Random();
                    final randomHex = (rand.nextInt(0xFFFFFF) + 0x100000).toRadixString(16);
                    myDeviceId = 'device_$randomHex';
                    _messages = [];
                  });
                  _fetchMessages();
                } else if (value == 'clear_chat') {
                  _clearAllChat();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'switch_device',
                  child: Text(
                    'Simulate Other Device',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const PopupMenuItem(
                  value: 'clear_chat',
                  child: Text(
                    'Clear Chat',
                    style: TextStyle(
                      color: Color(0xFFEF5350),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Top Notice: 5-Hour Expiry reminder
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
            color: const Color(0xFF182229),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shield_outlined, size: 14, color: Color(0xFF00A884)),
                SizedBox(width: 8),
                Text(
                  'EPHEMERAL: CHATS & IMAGES SELF-DESTRUCT 5 HOURS AFTER SEEN',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: Color(0xFF00A884),
                  ),
                ),
              ],
            ),
          ),

          // Message list area
          Expanded(
            child: _isLoading && _messages.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF00A884),
                    ),
                  )
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: const BoxDecoration(
                                color: Color(0xFF1F2C34),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.lock_outline,
                                size: 36,
                                color: Color(0xFF8696A0),
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'NO ACTIVE MESSAGES',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                                color: Color(0xFFE9EDEF),
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Send a message or image to start chatting',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF8696A0),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          final isMe = msg['senderId'] == myDeviceId;
                          final hasImage = msg['imageUrl'] != null;
                          final isSeen = msg['isSeen'] == true;
                          final expireAt = msg['expireAt'];
                          final timeStr = _formatTime(msg['createdAt']);

                          return Align(
                            // Right for Me, Left for Them (WhatsApp style)
                            alignment: isMe
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 3),
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.78,
                              ),
                              decoration: BoxDecoration(
                                // Dark WhatsApp Green for Me, Dark Charcoal for Them
                                color: isMe
                                    ? const Color(0xFF005C4B)
                                    : const Color(0xFF202C33),
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(12),
                                  topRight: const Radius.circular(12),
                                  bottomLeft: Radius.circular(isMe ? 12 : 2),
                                  bottomRight: Radius.circular(isMe ? 2 : 12),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Image payload (ImageKit)
                                    if (hasImage) ...[
                                      GestureDetector(
                                        onTap: () =>
                                            _openImagePreview(msg['imageUrl']),
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: Stack(
                                            children: [
                                              Image.network(
                                                msg['imageUrl'],
                                                fit: BoxFit.cover,
                                                loadingBuilder: (context,
                                                    child, progress) {
                                                  if (progress == null) {
                                                    return child;
                                                  }
                                                  return Container(
                                                    height: 190,
                                                    color:
                                                        const Color(0xFF111B21),
                                                    child: const Center(
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color:
                                                            Color(0xFF00A884),
                                                      ),
                                                    ),
                                                  );
                                                },
                                                errorBuilder: (context, error,
                                                        stackTrace) =>
                                                    Container(
                                                  height: 80,
                                                  color:
                                                      const Color(0xFF182229),
                                                  padding:
                                                      const EdgeInsets.all(12),
                                                  child: const Row(
                                                    children: [
                                                      Icon(
                                                        Icons
                                                            .broken_image_outlined,
                                                        color:
                                                            Color(0xFFEF5350),
                                                      ),
                                                      SizedBox(width: 8),
                                                      Text(
                                                        'Image Expired / Deleted',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color:
                                                              Color(0xFFEF5350),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              Positioned(
                                                top: 6,
                                                right: 6,
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.all(4),
                                                  decoration: BoxDecoration(
                                                    color: Colors.black54,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            4),
                                                  ),
                                                  child: const Icon(
                                                    Icons.fullscreen,
                                                    size: 16,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                    ],

                                    // Text payload
                                    if ((msg['text'] ?? '')
                                        .toString()
                                        .isNotEmpty)
                                      Text(
                                        msg['text'],
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFFE9EDEF),
                                          letterSpacing: 0.2,
                                        ),
                                      ),

                                    const SizedBox(height: 4),

                                    // Timestamp, Seen & 5h Expiry Badge
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          timeStr,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF8696A0),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          isSeen
                                              ? 'Seen • ${_formatExpiry(expireAt)}'
                                              : 'Unseen',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            color: isSeen
                                                ? (isMe
                                                    ? const Color(0xFF53BDEB)
                                                    : const Color(0xFF00A884))
                                                : const Color(0xFF8696A0),
                                          ),
                                        ),
                                        if (isMe) ...[
                                          const SizedBox(width: 4),
                                          Icon(
                                            isSeen
                                                ? Icons.done_all
                                                : Icons.done,
                                            size: 14,
                                            color: isSeen
                                                ? const Color(0xFF53BDEB)
                                                : const Color(0xFF8696A0),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),

          // Selected photo preview banner
          if (_selectedImage != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: const Color(0xFF182229),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(
                      _selectedImage!,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PHOTO ATTACHED',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Uploads directly to ImageKit',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF8696A0),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFFEF5350)),
                    onPressed: () => setState(() => _selectedImage = null),
                  ),
                ],
              ),
            ),

          // Bottom Input Bar
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              color: const Color(0xFF202C33), // Dark Input Bar
              child: Row(
                children: [
                  // Camera button
                  IconButton(
                    icon: const Icon(Icons.camera_alt, color: Color(0xFF8696A0)),
                    onPressed: () => _pickImage(ImageSource.camera),
                  ),

                  // Gallery button
                  IconButton(
                    icon: const Icon(Icons.image, color: Color(0xFF8696A0)),
                    onPressed: () => _pickImage(ImageSource.gallery),
                  ),

                  // Message Input
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: const TextStyle(
                          color: Color(0xFF8696A0),
                          fontWeight: FontWeight.w600,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        filled: true,
                        fillColor: const Color(0xFF2A3942),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Send Action Button
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color(0xFF00A884),
                    child: _isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.send,
                                color: Colors.white, size: 20),
                            onPressed: _sendMessage,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Clear chat option
  Future<void> _clearAllChat() async {
    try {
      await http.delete(Uri.parse('$baseUrl/api/chat/clear'));
      setState(() {
        _messages = [];
      });
    } catch (_) {}
  }
}
