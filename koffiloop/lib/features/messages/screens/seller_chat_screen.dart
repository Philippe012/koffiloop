import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:koffiloop/core/theme/app_theme.dart';

class SellerChatScreen extends StatefulWidget {
  final String customerId;
  final String shopId;
  final String customerName;        
  final String? customerPhotoURL;   

  const SellerChatScreen({
    super.key,
    required this.customerId,
    required this.shopId,
    this.customerName = 'Customer', 
    this.customerPhotoURL,
  });

  @override
  State<SellerChatScreen> createState() => _SellerChatScreenState();
}

class _SellerChatScreenState extends State<SellerChatScreen> {
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  bool _sending = false;

  String _displayName = 'Customer'; 
  bool _nameLoading = true;

  String get _convId {
    final parts = [widget.customerId, widget.shopId]..sort();
    return parts.join('_');
  }

  @override
  void initState() {
    super.initState();
    _loadCustomerName(); 
  }

  Future<void> _loadCustomerName() async {
    try {
      // First, try the passed name (fast path)
      if (widget.customerName != 'Customer' && widget.customerName.isNotEmpty) {
        setState(() {
          _displayName = widget.customerName;
          _nameLoading = false;
        });
        return;
      }

    final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.customerId)
          .get();
      
      if (mounted && doc.exists) {
        final name = doc.data()?['displayName'] as String?;
        if (name != null && name.isNotEmpty) {
          setState(() {
            _displayName = name;
            _nameLoading = false;
          });
        }
      }
    } catch (_) {
      // Keep fallback 'Customer' on error
    } finally {
      if (mounted && _nameLoading) {
        setState(() => _nameLoading = false);
      }
    }
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    _msgCtrl.clear();

    final now = FieldValue.serverTimestamp();
    try {
      
      String shopName = 'Café'; 
      try {
        final shopDoc = await FirebaseFirestore.instance
            .collection('shops')
            .doc(widget.shopId) 
            .get();
        if (shopDoc.exists && shopDoc.data()?['name'] != null) {
          shopName = shopDoc.data()!['name'] as String;
        }
      } catch (_) {
        // Keep fallback if fetch fails
      }



      await FirebaseFirestore.instance
          .collection('conversations')
          .doc(_convId)
          .set({
        'customerId': widget.customerId,
        'shopId': widget.shopId,
        'customerName': _displayName,
        'shopName': shopName,
        'participants': [widget.customerId, widget.shopId],
        'lastMessage': text,
        'lastMessageAt': now,
        'lastSenderId': widget.shopId,
      }, SetOptions(merge: true));

      await FirebaseFirestore.instance
          .collection('conversations')
          .doc(_convId)
          .collection('messages')
          .add({
        'text': text,
        'senderId': widget.shopId,
        'createdAt': now,
        'type': 'text',
      });

      _scrollToBottom();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppTheme.darkBackground : AppTheme.background,
      appBar: AppBar(
        backgroundColor:
            isDark ? AppTheme.darkSurface : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 18,
            color: isDark
                ? AppTheme.darkTextPrimary
                : AppTheme.textPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.secondary.withValues(alpha: 0.12),
              ),
              child: widget.customerPhotoURL != null &&
                      widget.customerPhotoURL!.isNotEmpty
                  ? ClipOval(
                      child: Image.network(widget.customerPhotoURL!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                              Icons.person_rounded,
                              color: AppTheme.primary,
                              size: 18)),
                    )
                  : const Icon(Icons.person_rounded,
                      color: AppTheme.primary, size: 18),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _nameLoading
                    ? Container(
                        width: 80,
                        height: 14,
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppTheme.darkDivider
                              : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      )
                    : Text(
                        _displayName,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Georgia',
                          color: isDark
                              ? AppTheme.darkTextPrimary
                              : AppTheme.textPrimary,
                        ),
                      ),
                Text(
                  'Reply as your café',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? AppTheme.darkTextSecondary.withValues(alpha: 0.8)
                        : AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('conversations')
                  .doc(_convId)
                  .collection('messages')
                  .orderBy('createdAt')
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                        color: AppTheme.primary),
                  );
                }

                final docs = snap.data?.docs ?? [];

                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      'No messages yet',
                      style: TextStyle(
                        color: isDark
                            ? AppTheme.darkTextSecondary
                            : AppTheme.textSecondary,
                      ),
                    ),
                  );
                }

                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _scrollToBottom());

                return ListView.builder(
                  controller: _scrollCtrl,
                  padding:
                      const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final data =
                        docs[i].data() as Map<String, dynamic>;
                    final isMe =
                        data['senderId'] == widget.shopId;
                    final ts = data['createdAt'] as Timestamp?;
                    final timeStr =
                        ts != null ? _formatTime(ts.toDate()) : '';

                    return _Bubble(
                      text: data['text'] ?? '',
                      isMe: isMe,
                      time: timeStr,
                      isDark: isDark,
                    );
                  },
                );
              },
            ),
          ),
          _buildInputBar(isDark),
        ],
      ),
    );
  }

  Widget _buildInputBar(bool isDark) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: 8,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? AppTheme.darkDivider : Colors.grey.shade100,
            width: 0.5,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [

            if (true)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: IconButton(
                  icon: Icon(
                    Icons.attach_file_rounded,
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : Colors.grey.shade500,
                    size: 22,
                  ),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Attachment feature coming soon!'),
                      ),
                    );
                  },
                  tooltip: 'Attach',
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
              ),
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.darkCard
                        : AppTheme.background,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isDark
                          ? AppTheme.darkDivider
                          : Colors.grey.shade200,
                    ),
                  ),
                  child: TextField(
                    controller: _msgCtrl,
                    maxLines: null,
                    minLines: 1,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: isDark
                          ? AppTheme.darkTextPrimary
                          : AppTheme.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? AppTheme.darkTextSecondary.withValues(alpha: 0.7)
                            : Colors.grey.shade400,
                      ),
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    onSubmitted: (_) => _send(),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _msgCtrl.text.trim().isEmpty || _sending ? null : _send,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _msgCtrl.text.trim().isEmpty || _sending
                      ? (isDark
                          ? AppTheme.darkDivider
                          : Colors.grey.shade300)
                      : AppTheme.primary,
                  shape: BoxShape.circle,
                  boxShadow: (_msgCtrl.text.trim().isEmpty || _sending)
                      ? []
                      : [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                ),
                child: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Icon(
                        Icons.send_rounded,
                        color: _msgCtrl.text.trim().isEmpty
                            ? (isDark
                                ? AppTheme.darkTextSecondary
                                : Colors.grey.shade400)
                            : Colors.white,
                        size: 20,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  
  String _formatTime(DateTime dt) {
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m ${dt.hour < 12 ? 'AM' : 'PM'}';
    }
  }

class _Bubble extends StatelessWidget {
  final String text;
  final bool isMe;
  final String time;
  final bool isDark;

  const _Bubble({
    required this.text,
    required this.isMe,
    required this.time,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe)
            Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(right: 8, bottom: 2),
              decoration: BoxDecoration(
                color: AppTheme.secondary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_rounded,
                  color: AppTheme.primary, size: 14),
            ),
          Flexible(
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  constraints: BoxConstraints(
                    maxWidth:
                        MediaQuery.of(context).size.width * 0.68,
                  ),
                  decoration: BoxDecoration(
                    color: isMe
                        ? AppTheme.primary
                        : (isDark
                            ? AppTheme.darkCard
                            : Colors.white),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft:
                          Radius.circular(isMe ? 18 : 4),
                      bottomRight:
                          Radius.circular(isMe ? 4 : 18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black
                            .withValues(alpha: 0.06),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: isMe
                          ? Colors.white
                          : (isDark
                              ? AppTheme.darkTextPrimary
                              : AppTheme.textPrimary),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : Colors.grey.shade400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}