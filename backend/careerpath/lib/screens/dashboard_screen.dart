import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/career_chat_sheet.dart';
import 'role_detail_screen.dart';
import '../core/auth_gate.dart';
import 'onboarding_wizard_screen.dart';

class DashboardScreen extends StatefulWidget {
  final UserProfile userProfile;
  final List<JobRole> roles;
  final JobRole? selectedCareer;

  const DashboardScreen({
    super.key,
    required this.userProfile,
    required this.roles,
    this.selectedCareer,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late List<JobRole> _allRoles;
  late List<JobRole> _filteredRoles;
  final TextEditingController _searchCtrl = TextEditingController();
  String _selectedFilter = 'All'; // 'All', 'High Match (>=50%)', 'Low Gap'
  String? _profileImageUrl;
  bool _isUpdatingImage = false;
  JobRole? _selectedCareer;

  @override
  void initState() {
    super.initState();
    _allRoles = List.from(widget.roles);
    _filteredRoles = List.from(_allRoles);
    _selectedCareer = widget.selectedCareer ?? ApiService.cachedSelectedCareer;
    _loadProfileImage();

    // Re-use recommendations already fetched by session loader; only fetch if empty
    if (_allRoles.isEmpty) {
      _fetchFreshRecommendations();
    }
  }

  Future<void> _fetchFreshRecommendations() async {
    try {
      final recData = await ApiService.getRecommendations();
      final freshRoles = recData['roles'] as List<JobRole>?;
      final target = recData['selected_career'] as JobRole?;
      if (mounted) {
        setState(() {
          if (freshRoles != null && freshRoles.isNotEmpty) {
            _allRoles = freshRoles;
            _filterRoles();
          }
          if (target != null) {
            _selectedCareer = target;
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _loadProfileImage() async {
    try {
      final url = await ApiService.getProfileImageUrl();
      if (mounted && url != null) {
        setState(() {
          _profileImageUrl = url;
        });
      }
    } catch (_) {}
  }

  Future<void> _pickAndUploadProfileImage() async {
    if (_isUpdatingImage) return;

    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg'],
      );

      if (files.isEmpty) return;

      final file = files.first;
      final bytes = await file.readAsBytes();

      if (bytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not read the selected image file.'),
            backgroundColor: AppTheme.accentRose,
          ),
        );
        return;
      }

      setState(() => _isUpdatingImage = true);

      await ApiService.uploadProfileImage(bytes, file.name);
      final freshUrl = await ApiService.getProfileImageUrl();

      if (!mounted) return;
      setState(() {
        _profileImageUrl = freshUrl;
        _isUpdatingImage = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile picture updated successfully!'),
          backgroundColor: AppTheme.accentEmerald,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUpdatingImage = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to upload image: $e'),
          backgroundColor: AppTheme.accentRose,
        ),
      );
    }
  }

  Future<void> _deleteProfileImage() async {
    try {
      setState(() => _isUpdatingImage = true);
      await ApiService.deleteProfileImage();
      if (!mounted) return;
      setState(() {
        _profileImageUrl = null;
        _isUpdatingImage = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile picture removed.'),
          backgroundColor: AppTheme.textSecondary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUpdatingImage = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to remove image: $e'),
          backgroundColor: AppTheme.accentRose,
        ),
      );
    }
  }

  void _openProfileImageSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.borderLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Profile Picture',
                style: AppTheme.fontHeading(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: AppTheme.primaryIndigo),
                title: Text(_profileImageUrl == null ? 'Upload Photo' : 'Change Photo'),
                subtitle: const Text('PNG or JPEG, max 2 MB'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndUploadProfileImage();
                },
              ),
              if (_profileImageUrl != null)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: AppTheme.accentRose),
                  title: const Text('Remove Photo', style: TextStyle(color: AppTheme.accentRose)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _deleteProfileImage();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _filterRoles() {
    final query = _searchCtrl.text.toLowerCase().trim();
    setState(() {
      _filteredRoles = _allRoles.where((role) {
        final matchesQuery = query.isEmpty ||
            role.title.toLowerCase().contains(query) ||
            role.description.toLowerCase().contains(query) ||
            role.technicalSkills.any((s) => s.toLowerCase().contains(query));

        if (!matchesQuery) return false;

        if (_selectedFilter == 'High Match (>=50%)') {
          return role.readinessScore >= 50;
        } else if (_selectedFilter == 'Ready (>=70%)') {
          return role.readinessScore >= 70;
        }
        return true;
      }).toList();
    });
  }

  void _openAiChatSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CareerChatSheet(
        userProfile: widget.userProfile,
        onExploreRole: (roleTitle) {
          Navigator.pop(context);
          _searchCtrl.text = roleTitle;
          _filterRoles();
        },
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
    final maxScore = _allRoles.isNotEmpty
        ? _allRoles.map((r) => r.readinessScore).reduce((a, b) => a > b ? a : b)
        : 0;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.explore_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CareerPath',
                  style: AppTheme.fontHeading(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  'Career Readiness Dashboard',
                  style: AppTheme.fontBody(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Update Profile & Stage',
            icon: const Icon(Icons.tune_rounded, color: AppTheme.textSecondary),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => OnboardingWizardScreen(currentUser: widget.userProfile),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Sign Out',
            icon: const Icon(Icons.logout_rounded, color: AppTheme.textSecondary),
            onPressed: () async {
              await AuthService().signOut();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const AuthGate()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _fetchFreshRecommendations();
          await _loadProfileImage();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
          children: [
            // User Hero Banner
            _buildUserHeroBanner(maxScore),
            const SizedBox(height: 18),

            // Target Career Goal Card (if selected)
            if (_selectedCareer != null) ...[
              _buildSelectedCareerBanner(_selectedCareer!),
            ],

            // KPI Stat Cards Grid
            _buildKpiStatRow(maxScore),
            const SizedBox(height: 24),

            // Search & Filter Header
            Row(
              children: [
                Text(
                  'Role Explorer',
                  style: AppTheme.fontHeading(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryIndigo.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_filteredRoles.length} Roles',
                    style: AppTheme.fontBody(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryIndigo,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Search Bar
            TextField(
              controller: _searchCtrl,
              onChanged: (_) => _filterRoles(),
              decoration: InputDecoration(
                hintText: 'Search roles, skills, or keywords...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _filterRoles();
                        },
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 12),

            // Filter Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['All', 'Ready (>=70%)', 'High Match (>=50%)'].map((filter) {
                  final isSelected = _selectedFilter == filter;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(filter),
                      selected: isSelected,
                      selectedColor: AppTheme.primaryIndigo.withValues(alpha: 0.15),
                      backgroundColor: AppTheme.surfaceWhite,
                      side: BorderSide(
                        color: isSelected ? AppTheme.primaryIndigo : AppTheme.borderLight,
                      ),
                      labelStyle: AppTheme.fontBody(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? AppTheme.primaryIndigo : AppTheme.textSecondary,
                      ),
                      onSelected: (val) {
                        setState(() => _selectedFilter = filter);
                        _filterRoles();
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),

            // Roles List
            if (_filteredRoles.isEmpty)
              _buildEmptyState()
            else
              ..._filteredRoles.map((role) => _buildRoleCard(role)),
          ],
        ),
      ),

      // Floating AI Assistant Button
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: AppTheme.primaryGradient,
          borderRadius: BorderRadius.circular(30),
          boxShadow: AppTheme.glowShadow,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(30),
            onTap: _openAiChatSheet,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'CareerPath AI',
                    style: AppTheme.fontBody(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // Target Career Goal Card
  // -------------------------------------------------------------
  Widget _buildSelectedCareerBanner(JobRole targetRole) {
    final scoreColor = _getScoreColor(targetRole.readinessScore);
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryIndigo.withValues(alpha: 0.3)),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryIndigo.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.stars_rounded, color: AppTheme.primaryIndigo, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your Target Career Goal',
                      style: AppTheme.fontHeading(
                        fontSize: 12,
                        color: AppTheme.primaryIndigo,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      targetRole.title,
                      style: AppTheme.fontHeading(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: scoreColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${targetRole.readinessScore}% Match',
                  style: AppTheme.fontBody(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: scoreColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            targetRole.explanation ??
                'Review your customized skill gap analysis and roadmap to bridge your missing skills.',
            style: AppTheme.fontBody(fontSize: 12.5, color: AppTheme.textSecondary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RoleDetailScreen(role: targetRole, userProfile: widget.userProfile),
                  ),
                );
              },
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: const Text('View Action Roadmap & Skill Gap'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryIndigo,
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // User Hero Banner
  // -------------------------------------------------------------
  Widget _buildUserHeroBanner(int maxScore) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    InkWell(
                      onTap: _openProfileImageSheet,
                      borderRadius: BorderRadius.circular(24),
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: Colors.white.withValues(alpha: 0.25),
                            backgroundImage: _profileImageUrl != null ? NetworkImage(_profileImageUrl!) : null,
                            child: _profileImageUrl == null
                                ? Text(
                                    widget.userProfile.name.isNotEmpty
                                        ? widget.userProfile.name[0].toUpperCase()
                                        : 'S',
                                    style: AppTheme.fontHeading(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  )
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: AppTheme.primaryIndigo,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.camera_alt, size: 10, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hi, ${widget.userProfile.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.fontHeading(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Year ${widget.userProfile.academicYear} Student • ${widget.userProfile.interestDomain}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.fontBody(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified_rounded, size: 14, color: AppTheme.accentCyan),
                    const SizedBox(width: 4),
                    Text(
                      'O*NET Verified',
                      style: AppTheme.fontBody(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline_rounded, color: AppTheme.accentCyan, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Your top career match readiness is $maxScore%. Tap CareerPath AI below for real-time interview & roadmap guidance.',
                    style: AppTheme.fontBody(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // KPI Stat Cards Row
  // -------------------------------------------------------------
  Widget _buildKpiStatRow(int maxScore) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            title: 'Roles Found',
            value: '${_allRoles.length}',
            subtitle: 'O*NET database matches',
            icon: Icons.work_outline_rounded,
            color: AppTheme.primaryIndigo,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            title: 'Top Readiness',
            value: '$maxScore%',
            subtitle: 'Target role alignment',
            icon: Icons.speed_rounded,
            color: _getScoreColor(maxScore),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            title: 'Active Skills',
            value: '${widget.userProfile.skills.length}',
            subtitle: 'Verified capabilities',
            icon: Icons.check_circle_outline_rounded,
            color: AppTheme.secondaryTeal,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.fontBody(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(icon, size: 16, color: color),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppTheme.fontHeading(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: AppTheme.fontBody(fontSize: 10, color: AppTheme.textMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // Role Card with Readiness Score Progress Ring & In-Demand Badges
  // -------------------------------------------------------------
  Widget _buildRoleCard(JobRole role) {
    final scoreColor = _getScoreColor(role.readinessScore);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderLight),
        boxShadow: AppTheme.softShadow,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RoleDetailScreen(role: role, userProfile: widget.userProfile),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row: Title + Circular Readiness Ring
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          role.title,
                          style: AppTheme.fontHeading(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                role.onetCode,
                                style: AppTheme.fontBody(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              role.typicalEducation,
                              style: AppTheme.fontBody(fontSize: 11, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Readiness Score Progress Ring
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 52,
                        height: 52,
                        child: CircularProgressIndicator(
                          value: role.readinessScore / 100,
                          backgroundColor: scoreColor.withValues(alpha: 0.15),
                          valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                          strokeWidth: 4.5,
                        ),
                      ),
                      Text(
                        '${role.readinessScore}%',
                        style: AppTheme.fontHeading(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: scoreColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Description preview
              Text(
                role.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.fontBody(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 14),

              // In-Demand Skills Highlight Badge
              if (role.inDemandSkills.isNotEmpty) ...[
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.accentRose.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.local_fire_department_rounded, size: 13, color: AppTheme.accentRose),
                          const SizedBox(width: 4),
                          Text(
                            'In-Demand Tools:',
                            style: AppTheme.fontBody(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.accentRose,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        role.inDemandSkills.take(3).join(' • '),
                        style: AppTheme.fontBody(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],

              // Matched vs Missing Skill Badges
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ...role.matchedSkills.take(3).map((s) => _buildBadge(s, isMatched: true)),
                  ...role.missingSkills.take(3).map((s) => _buildBadge(s, isMatched: false)),
                  if (role.missingSkills.length > 3)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '+${role.missingSkills.length - 3} more',
                        style: AppTheme.fontBody(fontSize: 11, color: AppTheme.textMuted),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),

              // Action Footer
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${role.courses.length} Courses • ${role.internships.length} Openings',
                    style: AppTheme.fontBody(fontSize: 11.5, color: AppTheme.textSecondary),
                  ),
                  Row(
                    children: [
                      Text(
                        'View Roadmap',
                        style: AppTheme.fontBody(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryIndigo,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_rounded, size: 14, color: AppTheme.primaryIndigo),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String skill, {required bool isMatched}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isMatched ? AppTheme.accentEmerald.withValues(alpha: 0.12) : AppTheme.accentAmber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isMatched ? AppTheme.accentEmerald.withValues(alpha: 0.3) : AppTheme.accentAmber.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isMatched ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
            size: 11,
            color: isMatched ? AppTheme.accentEmerald : AppTheme.accentAmber,
          ),
          const SizedBox(width: 4),
          Text(
            skill,
            style: AppTheme.fontBody(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isMatched ? const Color(0xFF065F46) : const Color(0xFF92400E),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(40),
      alignment: Alignment.center,
      child: Column(
        children: [
          const Icon(Icons.search_off_rounded, size: 56, color: AppTheme.textMuted),
          const SizedBox(height: 12),
          Text(
            'No matching roles found',
            style: AppTheme.fontHeading(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Try adjusting your search keywords or clear filters.',
            style: AppTheme.fontBody(fontSize: 13, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}
