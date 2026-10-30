import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/career_chat_sheet.dart';

class RoleDetailScreen extends StatefulWidget {
  final JobRole role;
  final UserProfile userProfile;

  const RoleDetailScreen({
    super.key,
    required this.role,
    required this.userProfile,
  });

  @override
  State<RoleDetailScreen> createState() => _RoleDetailScreenState();
}

class _RoleDetailScreenState extends State<RoleDetailScreen> {
  bool _isTargetCareer = false;
  bool _isSavingSelection = false;

  @override
  void initState() {
    super.initState();
    _checkIfTargetCareer();
  }

  Future<void> _checkIfTargetCareer() async {
    try {
      final selected = await ApiService.getSelectedCareer();
      if (mounted && selected != null) {
        final onet = selected['onet_code']?.toString();
        final rid = selected['role_id']?.toString();
        if (onet == widget.role.onetCode ||
            (widget.role.roleId != null && rid == widget.role.roleId.toString())) {
          setState(() => _isTargetCareer = true);
        }
      }
    } catch (_) {}
  }

  Future<void> _toggleTargetCareer() async {
    if (_isSavingSelection) return;
    setState(() => _isSavingSelection = true);
    try {
      await ApiService.setSelectedCareer(widget.role.onetCode);
      if (!mounted) return;
      setState(() {
        _isTargetCareer = true;
        _isSavingSelection = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved "${widget.role.title}" as your Target Career!'),
          backgroundColor: AppTheme.accentEmerald,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSavingSelection = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to set target career: $e'),
          backgroundColor: AppTheme.accentRose,
        ),
      );
    }
  }

  Future<void> _openUrl(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _openChatWithRoleContext(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CareerChatSheet(
        userProfile: widget.userProfile,
      ),
    );
  }

  Color _getScoreColor(int score) {
    if (score >= 70) return AppTheme.accentEmerald;
    if (score >= 45) return AppTheme.secondaryTeal;
    return AppTheme.accentAmber;
  }

  @override
  Widget build(BuildContext context) {
    final scoreColor = _getScoreColor(widget.role.readinessScore);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.role.title,
            style: AppTheme.fontHeading(fontWeight: FontWeight.w700, fontSize: 17),
          ),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppTheme.primaryIndigo,
            unselectedLabelColor: AppTheme.textSecondary,
            indicatorColor: AppTheme.primaryIndigo,
            indicatorWeight: 3,
            labelStyle: AppTheme.fontBody(fontWeight: FontWeight.w700, fontSize: 13),
            unselectedLabelStyle: AppTheme.fontBody(fontWeight: FontWeight.w500, fontSize: 13),
            tabs: const [
              Tab(icon: Icon(Icons.timeline_rounded, size: 18), text: 'Skills & Gap Analysis'),
              Tab(icon: Icon(Icons.school_rounded, size: 18), text: 'Courses & Certs'),
              Tab(icon: Icon(Icons.work_rounded, size: 18), text: 'Internships'),
              Tab(icon: Icon(Icons.quiz_rounded, size: 18), text: 'Interview Qs'),
            ],
          ),
        ),
        body: Column(
          children: [
            // Top Overview Card
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceWhite,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.borderLight),
                boxShadow: AppTheme.softShadow,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.role.description,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.fontBody(
                                  fontSize: 12.5, color: AppTheme.textSecondary, height: 1.4),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Typical Education: ${widget.role.typicalEducation} • O*NET ${widget.role.onetCode}',
                              style: AppTheme.fontBody(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primaryIndigo,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 58,
                            height: 58,
                            child: CircularProgressIndicator(
                              value: widget.role.readinessScore / 100,
                              backgroundColor: scoreColor.withValues(alpha: 0.15),
                              valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                              strokeWidth: 5,
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${widget.role.readinessScore}%',
                                style: AppTheme.fontHeading(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  color: scoreColor,
                                ),
                              ),
                              Text(
                                'Match',
                                style: AppTheme.fontBody(fontSize: 9, color: AppTheme.textMuted),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Set as Target Career Action Button
                  SizedBox(
                    width: double.infinity,
                    child: _isTargetCareer
                        ? OutlinedButton.icon(
                            onPressed: null,
                            icon: const Icon(Icons.check_circle_rounded,
                                color: AppTheme.accentEmerald, size: 18),
                            label: const Text('Target Career Selected',
                                style: TextStyle(
                                    color: AppTheme.accentEmerald, fontWeight: FontWeight.bold)),
                          )
                        : FilledButton.icon(
                            onPressed: _isSavingSelection ? null : _toggleTargetCareer,
                            icon: _isSavingSelection
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.bookmark_add_rounded, size: 18),
                            label: Text(
                                _isSavingSelection ? 'Saving Selection...' : 'Set as Target Career'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.primaryIndigo,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                  ),
                ],
              ),
            ),

            // Tab Views
            Expanded(
              child: TabBarView(
                children: [
                  _buildSkillsRoadmapTab(),
                  _buildCoursesTab(),
                  _buildInternshipsTab(),
                  _buildInterviewQsTab(),
                ],
              ),
            ),
          ],
        ),

        // FAB to ask AI advisor about this role
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openChatWithRoleContext(context),
          backgroundColor: AppTheme.primaryIndigo,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.auto_awesome_rounded, size: 18),
          label: Text('Ask CareerPath AI',
              style: AppTheme.fontBody(fontWeight: FontWeight.w600, fontSize: 13)),
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 1: Skills & Skill Gap Analysis
  // -------------------------------------------------------------
  Widget _buildSkillsRoadmapTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      children: [
        // Match Explanation Banner
        if (widget.role.explanation != null && widget.role.explanation!.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryIndigo.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primaryIndigo.withValues(alpha: 0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.analytics_rounded, size: 20, color: AppTheme.primaryIndigo),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.role.explanation!,
                    style: AppTheme.fontBody(
                        fontSize: 13, color: AppTheme.textPrimary, height: 1.4, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Priority Next Skills
        if (widget.role.recommendedNextSkills.isNotEmpty) ...[
          Text(
            'Recommended Next Skills to Learn (Priority Order)',
            style: AppTheme.fontHeading(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.role.recommendedNextSkills.asMap().entries.map((entry) {
              final idx = entry.key;
              final skill = entry.value;
              return Chip(
                avatar: CircleAvatar(
                  radius: 10,
                  backgroundColor: AppTheme.primaryIndigo,
                  child: Text('${idx + 1}',
                      style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                label: Text(skill),
                backgroundColor: AppTheme.primaryIndigo.withValues(alpha: 0.1),
                labelStyle: AppTheme.fontBody(
                    fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryIndigo),
                side: BorderSide(color: AppTheme.primaryIndigo.withValues(alpha: 0.2)),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
        ],

        // Missing Skills (To Gain)
        Text(
          'Missing Skills & Tools (${widget.role.missingSkills.length})',
          style: AppTheme.fontHeading(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: widget.role.missingSkills.isEmpty
              ? [Text('All required technical skills matched!', style: AppTheme.fontBody(color: AppTheme.accentEmerald))]
              : widget.role.missingSkills.map((s) {
                  return Chip(
                    avatar: const Icon(Icons.add_circle_outline, size: 14, color: Color(0xFF92400E)),
                    label: Text(s),
                    backgroundColor: const Color(0xFFFEF3C7),
                    labelStyle: AppTheme.fontBody(
                        fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF92400E)),
                    side: const BorderSide(color: Color(0xFFFDE68A)),
                  );
                }).toList(),
        ),
        const SizedBox(height: 20),

        // Matched Skills
        Text(
          'Skills You Already Master (${widget.role.matchedSkills.length})',
          style: AppTheme.fontHeading(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: widget.role.matchedSkills.isEmpty
              ? [
                  Text('No direct skill matches yet. Complete Year 1-2 courses!',
                      style: AppTheme.fontBody(color: AppTheme.textMuted))
                ]
              : widget.role.matchedSkills.map((s) {
                  return Chip(
                    avatar: const Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF065F46)),
                    label: Text(s),
                    backgroundColor: const Color(0xFFD1FAE5),
                    labelStyle: AppTheme.fontBody(
                        fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF065F46)),
                    side: const BorderSide(color: Color(0xFFA7F3D0)),
                  );
                }).toList(),
        ),
        const SizedBox(height: 20),

        // Essential Core Skills
        if (widget.role.essentialSkills.isNotEmpty) ...[
          Text(
            'Foundational Core Competencies',
            style: AppTheme.fontHeading(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.role.essentialSkills.map((s) {
              return Chip(
                label: Text(s),
                backgroundColor: const Color(0xFFF1F5F9),
                labelStyle: AppTheme.fontBody(fontSize: 12, color: AppTheme.textSecondary),
                side: const BorderSide(color: AppTheme.borderLight),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
        ],

        // Year-Aware Roadmap Timeline
        const Divider(height: 28),
        Text(
          'Year ${widget.userProfile.academicYear} Action Roadmap',
          style: AppTheme.fontHeading(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 10),
        ...widget.role.roadmap.asMap().entries.map((entry) {
          final idx = entry.key;
          final step = entry.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceWhite,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderLight),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: AppTheme.primaryIndigo.withValues(alpha: 0.12),
                  child: Text(
                    '${idx + 1}',
                    style: AppTheme.fontBody(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryIndigo,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    step,
                    style: AppTheme.fontBody(fontSize: 13, color: AppTheme.textPrimary, height: 1.4),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // -------------------------------------------------------------
  // TAB 2: Courses & Certifications
  // -------------------------------------------------------------
  Widget _buildCoursesTab() {
    if (widget.role.courses.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.school_outlined, size: 48, color: AppTheme.textMuted),
              const SizedBox(height: 12),
              Text('No Courses Currently Listed', style: AppTheme.fontHeading(fontSize: 16)),
              const SizedBox(height: 6),
              Text(
                'Explore Coursera or edX for verified courses matching this role.',
                textAlign: TextAlign.center,
                style: AppTheme.fontBody(fontSize: 13, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: widget.role.courses.length,
      itemBuilder: (context, i) {
        final c = widget.role.courses[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surfaceWhite,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.borderLight),
            boxShadow: AppTheme.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryIndigo.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.school_rounded, color: AppTheme.primaryIndigo, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.courseTitle,
                          style: AppTheme.fontHeading(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Platform: ${c.platform}',
                          style: AppTheme.fontBody(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                        if (c.certification.isNotEmpty)
                          Text(
                            'Cred: ${c.certification}',
                            style: AppTheme.fontBody(
                                fontSize: 12, color: AppTheme.primaryIndigo, fontWeight: FontWeight.w600),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (c.searchUrl.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _openUrl(c.searchUrl),
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Search & Enroll on Coursera'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // -------------------------------------------------------------
  // TAB 3: Internships
  // -------------------------------------------------------------
  Widget _buildInternshipsTab() {
    if (widget.role.internships.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.work_outline_rounded, size: 48, color: AppTheme.textMuted),
              const SizedBox(height: 12),
              Text('No Openings Currently Listed', style: AppTheme.fontHeading(fontSize: 16)),
              const SizedBox(height: 6),
              Text(
                'Check LinkedIn Jobs or Wellfound for live internships in this domain.',
                textAlign: TextAlign.center,
                style: AppTheme.fontBody(fontSize: 13, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: widget.role.internships.length,
      itemBuilder: (context, i) {
        final intern = widget.role.internships[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surfaceWhite,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.borderLight),
            boxShadow: AppTheme.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryTeal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.work_rounded, color: AppTheme.secondaryTeal, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          intern.role,
                          style: AppTheme.fontHeading(fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        Text(
                          intern.type,
                          style: AppTheme.fontBody(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                        if (intern.source != null)
                          Text(
                            'Source: ${intern.source}',
                            style: AppTheme.fontBody(fontSize: 11, color: AppTheme.textMuted),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (intern.applyUrl.isNotEmpty) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _openUrl(intern.applyUrl),
                    icon: const Icon(Icons.launch_rounded, size: 16),
                    label: const Text('Find Openings on LinkedIn'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.secondaryTeal,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // -------------------------------------------------------------
  // TAB 4: Interview Questions
  // -------------------------------------------------------------
  Widget _buildInterviewQsTab() {
    if (widget.role.interviewQuestions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.quiz_outlined, size: 48, color: AppTheme.textMuted),
              const SizedBox(height: 12),
              Text('Interview Questions Pending', style: AppTheme.fontHeading(fontSize: 16)),
              const SizedBox(height: 6),
              Text(
                'Practice technical questions using foundational role skills.',
                textAlign: TextAlign.center,
                style: AppTheme.fontBody(fontSize: 13, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: widget.role.interviewQuestions.length,
      itemBuilder: (context, i) {
        final q = widget.role.interviewQuestions[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surfaceWhite,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.borderLight),
            boxShadow: AppTheme.softShadow,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryIndigo.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Q${i + 1}',
                  style: AppTheme.fontBody(
                      fontWeight: FontWeight.w800, color: AppTheme.primaryIndigo, fontSize: 12),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      q,
                      style: AppTheme.fontBody(
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                          height: 1.4,
                          color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tip: Structure your response using the STAR method (Situation, Task, Action, Result). Highlight technical metrics.',
                      style: AppTheme.fontBody(
                          fontSize: 11.5, color: AppTheme.textMuted, fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
