import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

/// Bespoke "Phantom Vault" privacy color system
class VaultColors {
  // Base backgrounds
  static const Color background = Color(0xFF08090C); // Ultra-deep void obsidian
  static const Color surface = Color(0xFF0E1117); // Stealth graphite header/input
  static const Color surfaceBorder = Color(0xFF1A1F2C); // Fine structural border
  static const Color bannerBg = Color(0xFF10131E); // Top security strip

  // Cryptographic & Secret accents
  static const Color cyberViolet = Color(0xFF7C3AED); // Primary encryption signature
  static const Color violetLight = Color(0xFFA78BFA); // Seen / Active highlights
  static const Color cyanShield = Color(0xFF06B6D4); // Verified secrecy badge
  static const Color flameTimer = Color(0xFFFB923C); // 5-hour disappearing indicator
  static const Color errorRed = Color(0xFFEF4444); // Error / Deletion

  // Message Bubbles
  static const Color myBubble = Color(0xFF231640); // Midnight Royal Violet (Right)
  static const Color myBubbleBorder = Color(0xFF3F2773); // Fine Violet perimeter
  static const Color theirBubble = Color(0xFF131622); // Tactical Carbon Slate (Left)
  static const Color theirBubbleBorder = Color(0xFF212738); // Fine Carbon perimeter

  // Typography
  static const Color textPrimary = Color(0xFFF8FAFC); // Glacier White
  static const Color textSecondary = Color(0xFFCBD5E1); // Silver Mist
  static const Color textMuted = Color(0xFF64748B); // Titanium Slate
}

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  // Device identity (Zero login required - persistent identifier)
  late String myDeviceId;
  String myDisplayName = 'Vault Member';

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

  void _initDeviceIdentity() {
    final rand = Random();
    final randomHex = (rand.nextInt(0xFFFFFF) + 0x100000).toRadixString(16);
    myDeviceId = 'stealth_$randomHex';
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
            backgroundColor: VaultColors.errorRed,
            content: Text(
              'Error selecting image: $e',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
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
              errorMessage = 'Missing server environment variables';
            }
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: VaultColors.errorRed,
              content: Text(
                'Failed to send: $errorMessage',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: VaultColors.errorRed,
            content: Text(
              'Network error: $e',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
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
          backgroundColor: VaultColors.background,
          appBar: AppBar(
            backgroundColor: VaultColors.surface,
            iconTheme: const IconThemeData(color: VaultColors.textPrimary),
            title: const Text(
              'IMAGE VAULT',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
                color: VaultColors.textPrimary,
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
      backgroundColor: VaultColors.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: VaultColors.surface,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: VaultColors.surfaceBorder,
            height: 1,
          ),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            const SizedBox(width: 14),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: VaultColors.cyberViolet, width: 1.5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/logo.png',
                  width: 34,
                  height: 34,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: 34,
                    height: 34,
                    color: VaultColors.cyberViolet,
                    child: const Icon(Icons.shield, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Wechat',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                        color: VaultColors.textPrimary,
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(
                      Icons.lock_rounded,
                      size: 13,
                      color: VaultColors.cyberViolet,
                    ),
                  ],
                ),
                Text(
                  'STEALTH ENCRYPTED VAULT',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                    color: VaultColors.cyanShield,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            color: VaultColors.surface,
            icon: const Icon(Icons.more_vert, color: VaultColors.textSecondary),
            onSelected: (value) {
              if (value == 'switch_device') {
                setState(() {
                  final rand = Random();
                  final randomHex = (rand.nextInt(0xFFFFFF) + 0x100000).toRadixString(16);
                  myDeviceId = 'stealth_$randomHex';
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
                child: Row(
                  children: [
                    Icon(Icons.swap_horiz, size: 18, color: VaultColors.violetLight),
                    SizedBox(width: 10),
                    Text(
                      'Simulate Other Device',
                      style: TextStyle(
                        color: VaultColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clear_chat',
                child: Row(
                  children: [
                    Icon(Icons.delete_forever, size: 18, color: VaultColors.errorRed),
                    SizedBox(width: 10),
                    Text(
                      'Purge All Messages',
                      style: TextStyle(
                        color: VaultColors.errorRed,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Top Stealth Notice: 5-Hour Countdown reminder
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
            decoration: const BoxDecoration(
              color: VaultColors.bannerBg,
              border: Border(
                bottom: BorderSide(color: VaultColors.surfaceBorder, width: 1),
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.timer_outlined, size: 13, color: VaultColors.flameTimer),
                SizedBox(width: 8),
                Text(
                  'CONFIDENTIAL • DESTROYS 5 HOURS AFTER SEEN',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                    color: VaultColors.flameTimer,
                  ),
                ),
              ],
            ),
          ),

          // Message stream area
          Expanded(
            child: _isLoading && _messages.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(
                      color: VaultColors.cyberViolet,
                    ),
                  )
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: VaultColors.surface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: VaultColors.surfaceBorder,
                                  width: 1.5,
                                ),
                              ),
                              child: const Icon(
                                Icons.fingerprint,
                                size: 44,
                                color: VaultColors.violetLight,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'VAULT EMPTY',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                                color: VaultColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Messages & photos vanish 5 hours after viewing',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: VaultColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          final isMe = msg['senderId'] == myDeviceId;
                          final hasImage = msg['imageUrl'] != null;
                          final isSeen = msg['isSeen'] == true;
                          final expireAt = msg['expireAt'];
                          final timeStr = _formatTime(msg['createdAt']);

                          return Align(
                            // Right side for Me, Left side for Them
                            alignment: isMe
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.78,
                              ),
                              decoration: BoxDecoration(
                                // Midnight Royal Violet for Me, Tactical Slate for Them
                                color: isMe
                                    ? VaultColors.myBubble
                                    : VaultColors.theirBubble,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(14),
                                  topRight: const Radius.circular(14),
                                  bottomLeft: Radius.circular(isMe ? 14 : 2),
                                  bottomRight: Radius.circular(isMe ? 2 : 14),
                                ),
                                border: Border.all(
                                  color: isMe
                                      ? VaultColors.myBubbleBorder
                                      : VaultColors.theirBubbleBorder,
                                  width: 1.2,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(9),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Image Content (ImageKit)
                                    if (hasImage) ...[
                                      GestureDetector(
                                        onTap: () =>
                                            _openImagePreview(msg['imageUrl']),
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(10),
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
                                                    color: VaultColors.surface,
                                                    child: const Center(
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: VaultColors
                                                            .cyberViolet,
                                                      ),
                                                    ),
                                                  );
                                                },
                                                errorBuilder: (context, error,
                                                        stackTrace) =>
                                                    Container(
                                                  height: 80,
                                                  color: const Color(0xFF1B1115),
                                                  padding:
                                                      const EdgeInsets.all(12),
                                                  child: const Row(
                                                    children: [
                                                      Icon(
                                                        Icons.lock_clock,
                                                        color: VaultColors
                                                            .errorRed,
                                                      ),
                                                      SizedBox(width: 8),
                                                      Text(
                                                        'Expired / Purged from Vault',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: VaultColors
                                                              .errorRed,
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
                                                    color: Colors.black87,
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

                                    // Text Message Content
                                    if ((msg['text'] ?? '')
                                        .toString()
                                        .isNotEmpty)
                                      Text(
                                        msg['text'],
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: VaultColors.textPrimary,
                                          letterSpacing: 0.2,
                                          height: 1.3,
                                        ),
                                      ),

                                    const SizedBox(height: 5),

                                    // Footer: Timestamp & 5h Seen Expiry Status
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          timeStr,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: VaultColors.textMuted,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 1.5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isSeen
                                                ? VaultColors.flameTimer
                                                    .withValues(alpha: 0.15)
                                                : VaultColors.surfaceBorder,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            isSeen
                                                ? _formatExpiry(expireAt)
                                                : 'Delivered',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 0.3,
                                              color: isSeen
                                                  ? VaultColors.flameTimer
                                                  : VaultColors.textMuted,
                                            ),
                                          ),
                                        ),
                                        if (isMe) ...[
                                          const SizedBox(width: 5),
                                          Icon(
                                            isSeen
                                                ? Icons.done_all
                                                : Icons.done,
                                            size: 13,
                                            color: isSeen
                                                ? VaultColors.violetLight
                                                : VaultColors.textMuted,
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

          // Attached Image Preview tray
          if (_selectedImage != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: const BoxDecoration(
                color: VaultColors.surface,
                border: Border(
                  top: BorderSide(color: VaultColors.surfaceBorder, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: VaultColors.cyberViolet,
                        width: 1.2,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Image.file(
                        _selectedImage!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CONFIDENTIAL ATTACHMENT',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                            color: VaultColors.textPrimary,
                          ),
                        ),
                        Text(
                          'Uploads encrypted to ImageKit CDN',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: VaultColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: VaultColors.errorRed),
                    onPressed: () => setState(() => _selectedImage = null),
                  ),
                ],
              ),
            ),

          // Bottom Input Console
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: const BoxDecoration(
                color: VaultColors.surface,
                border: Border(
                  top: BorderSide(color: VaultColors.surfaceBorder, width: 1),
                ),
              ),
              child: Row(
                children: [
                  // Camera trigger
                  IconButton(
                    icon: const Icon(Icons.camera_alt_outlined,
                        color: VaultColors.violetLight),
                    onPressed: () => _pickImage(ImageSource.camera),
                  ),

                  // Image attachment trigger
                  IconButton(
                    icon: const Icon(Icons.add_photo_alternate_outlined,
                        color: VaultColors.violetLight),
                    onPressed: () => _pickImage(ImageSource.gallery),
                  ),

                  // Cryptographic Message Field
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(
                        color: VaultColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Type confidential message...',
                        hintStyle: const TextStyle(
                          color: VaultColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        filled: true,
                        fillColor: const Color(0xFF141823),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: const BorderSide(
                            color: VaultColors.surfaceBorder,
                            width: 1,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: const BorderSide(
                            color: VaultColors.surfaceBorder,
                            width: 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: const BorderSide(
                            color: VaultColors.cyberViolet,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // High-contrast Send Button
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: VaultColors.cyberViolet,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: VaultColors.cyberViolet.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _isSending
                        ? const Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.send_rounded,
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

  // Purge chat
  Future<void> _clearAllChat() async {
    try {
      await http.delete(Uri.parse('$baseUrl/api/chat/clear'));
      setState(() {
        _messages = [];
      });
    } catch (_) {}
  }
}
