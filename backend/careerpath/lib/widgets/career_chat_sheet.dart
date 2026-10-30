import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class CareerChatSheet extends StatefulWidget {
  final UserProfile userProfile;
  final Function(String roleTitle)? onExploreRole;

  const CareerChatSheet({
    super.key,
    required this.userProfile,
    this.onExploreRole,
  });

  @override
  State<CareerChatSheet> createState() => _CareerChatSheetState();
}

class _CareerChatSheetState extends State<CareerChatSheet> with TickerProviderStateMixin {
  final List<ChatMessage> _messages = [];
  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  bool _isAiThinking = false;

  late List<String> _quickChips;

  @override
  void initState() {
    super.initState();
    _quickChips = [
      'What should I learn in Year ${widget.userProfile.academicYear}?',
      'Which jobs fit Java & Python?',
      'How do I become a Data Scientist?',
      'Top skills for Software Engineer?',
      'Tips for 3rd year internships?',
    ];

    // Seed initial greeting message
    _messages.add(
      ChatMessage(
        id: 'msg_welcome',
        text: '👋 **Hello ${widget.userProfile.name}!** I am your **CareerPath AI Advisor**.\n\n'
            'I have indexed your profile (**Year ${widget.userProfile.academicYear} • ${widget.userProfile.interestDomain}** with **${widget.userProfile.skills.length} skills**) against 900+ O*NET career roles.\n\n'
            'How can I guide your career journey today? You can ask me what to learn next, how to close skill gaps, or test job matching!',
        isUser: false,
        timestamp: DateTime.now(),
        quickReplies: _quickChips,
      ),
    );
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
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

  Future<void> _sendMessage(String text) async {
    final query = text.trim();
    if (query.isEmpty) return;

    _textCtrl.clear();
    final userMsg = ChatMessage(
      id: 'usr_${DateTime.now().millisecondsSinceEpoch}',
      text: query,
      isUser: true,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMsg);
      _isAiThinking = true;
    });
    _scrollToBottom();

    try {
      final res = await ApiService.careerChat(
        message: query,
        profile: widget.userProfile,
      );

      final replyText = res['reply'] as String? ?? 'I reviewed your query against the O*NET database.';
      final suggestedRoles = res['suggested_roles'] as List<dynamic>?;
      final quickReplies = (res['quick_replies'] as List<dynamic>?)?.map((e) => e.toString()).toList();

      final aiMsg = ChatMessage(
        id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
        text: replyText,
        isUser: false,
        timestamp: DateTime.now(),
        suggestedRoles: suggestedRoles,
        quickReplies: quickReplies,
      );

      if (!mounted) return;
      setState(() {
        _messages.add(aiMsg);
        _isAiThinking = false;
        if (quickReplies != null && quickReplies.isNotEmpty) {
          _quickChips = quickReplies;
        }
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isAiThinking = false;
        _messages.add(
          ChatMessage(
            id: 'err_${DateTime.now().millisecondsSinceEpoch}',
            text: '⚠️ Unable to connect to CareerPath AI service: $e. Please verify the backend is running.',
            isUser: false,
            timestamp: DateTime.now(),
          ),
        );
      });
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: AppTheme.backgroundLight,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: AppTheme.borderLight,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 8, 16, 14),
            decoration: const BoxDecoration(
              color: AppTheme.surfaceWhite,
              border: Border(bottom: BorderSide(color: AppTheme.borderLight)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    shape: BoxShape.circle,
                    boxShadow: AppTheme.glowShadow,
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'CareerPath AI Advisor',
                            style: AppTheme.fontHeading(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.accentEmerald.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: AppTheme.accentEmerald,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Online',
                                  style: AppTheme.fontBody(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.accentEmerald,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Year ${widget.userProfile.academicYear} • ${widget.userProfile.interestDomain} • ${widget.userProfile.skills.length} skills',
                        style: AppTheme.fontBody(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppTheme.textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Messages View
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              itemCount: _messages.length + (_isAiThinking ? 1 : 0),
              itemBuilder: (context, i) {
                if (i == _messages.length && _isAiThinking) {
                  return _buildTypingIndicator();
                }
                return _buildMessageBubble(_messages[i]);
              },
            ),
          ),

          // Quick Suggestion Chips
          if (_quickChips.isNotEmpty)
            Container(
              height: 44,
              margin: const EdgeInsets.only(bottom: 6),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _quickChips.length,
                separatorBuilder: (ctx, i) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final chipText = _quickChips[index];
                  return ActionChip(
                    avatar: const Icon(Icons.lightbulb_outline_rounded, size: 14, color: AppTheme.primaryIndigo),
                    label: Text(chipText),
                    labelStyle: AppTheme.fontBody(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryIndigo,
                    ),
                    backgroundColor: AppTheme.surfaceWhite,
                    side: BorderSide(color: AppTheme.primaryIndigo.withValues(alpha: 0.3)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    onPressed: () => _sendMessage(chipText),
                  );
                },
              ),
            ),

          // Input Bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceWhite,
              border: const Border(top: BorderSide(color: AppTheme.borderLight)),
              boxShadow: AppTheme.softShadow,
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppTheme.borderLight),
                      ),
                      child: TextField(
                        controller: _textCtrl,
                        textInputAction: TextInputAction.send,
                        onSubmitted: _sendMessage,
                        decoration: InputDecoration(
                          hintText: 'Ask CareerPath AI about skills, roles, roadmaps...',
                          hintStyle: AppTheme.fontBody(fontSize: 13, color: AppTheme.textMuted),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      shape: BoxShape.circle,
                      boxShadow: AppTheme.glowShadow,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
                      onPressed: () => _sendMessage(_textCtrl.text),
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

  // -------------------------------------------------------------
  // Message Bubble
  // -------------------------------------------------------------
  Widget _buildMessageBubble(ChatMessage msg) {
    if (msg.isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(4),
                  ),
                  boxShadow: AppTheme.softShadow,
                ),
                child: Text(
                  msg.text,
                  style: AppTheme.fontBody(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // AI Message Bubble
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: AppTheme.heroGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceWhite,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(18),
                    ),
                    border: Border.all(color: AppTheme.borderLight),
                    boxShadow: AppTheme.softShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _formatFormattedText(msg.text),
                      // Mini suggested roles cards if returned
                      if (msg.suggestedRoles != null && msg.suggestedRoles!.isNotEmpty) ...[
                        const Divider(height: 24),
                        Text(
                          'Suggested Roles from O*NET Database:',
                          style: AppTheme.fontBody(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...msg.suggestedRoles!.take(2).map((roleData) {
                          final title = roleData['title'] ?? 'Role';
                          final score = roleData['readiness_score'] ?? 0;
                          final missing = (roleData['missing_skills'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppTheme.borderLight),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        style: AppTheme.fontBody(fontWeight: FontWeight.w700, fontSize: 13),
                                      ),
                                      if (missing.isNotEmpty)
                                        Text(
                                          'Focus on: ${missing.take(2).join(", ")}',
                                          style: AppTheme.fontBody(fontSize: 11, color: AppTheme.textSecondary),
                                        ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: score >= 60
                                        ? AppTheme.accentEmerald.withValues(alpha: 0.15)
                                        : AppTheme.primaryIndigo.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '$score% Match',
                                    style: AppTheme.fontBody(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11,
                                      color: score >= 60 ? AppTheme.accentEmerald : AppTheme.primaryIndigo,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Simple Markdown Parser (Bold, Bullets, Headers)
  Widget _formatFormattedText(String text) {
    final lines = text.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        if (line.trim().isEmpty) return const SizedBox(height: 6);

        // Header
        if (line.startsWith('## ') || line.startsWith('### ')) {
          return Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              line.replaceAll('#', '').trim(),
              style: AppTheme.fontHeading(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: AppTheme.textPrimary,
              ),
            ),
          );
        }

        // Bullet point
        if (line.trim().startsWith('• ') || line.trim().startsWith('- ')) {
          final cleanLine = line.trim().substring(2);
          return Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('• ', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryIndigo)),
                Expanded(
                  child: _parseBoldText(cleanLine),
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: _parseBoldText(line),
        );
      }).toList(),
    );
  }

  Widget _parseBoldText(String text) {
    final parts = text.split('**');
    if (parts.length <= 1) {
      return Text(
        text,
        style: AppTheme.fontBody(fontSize: 13.5, height: 1.45, color: AppTheme.textPrimary),
      );
    }

    return RichText(
      text: TextSpan(
        style: AppTheme.fontBody(fontSize: 13.5, height: 1.45, color: AppTheme.textPrimary),
        children: List.generate(parts.length, (idx) {
          final isBold = idx.isOdd;
          return TextSpan(
            text: parts[idx],
            style: isBold
                ? const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary)
                : const TextStyle(fontWeight: FontWeight.w400),
          );
        }),
      ),
    );
  }

  // -------------------------------------------------------------
  // Animated Typing Indicator
  // -------------------------------------------------------------
  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: AppTheme.heroGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceWhite,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderLight),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'CareerPath AI is analyzing O*NET roles',
                  style: AppTheme.fontBody(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 8),
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryIndigo),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
