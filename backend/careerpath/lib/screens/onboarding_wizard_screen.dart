import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'dashboard_screen.dart';

class OnboardingWizardScreen extends StatefulWidget {
  final UserProfile currentUser;
  const OnboardingWizardScreen({super.key, required this.currentUser});

  @override
  State<OnboardingWizardScreen> createState() => _OnboardingWizardScreenState();
}

class _OnboardingWizardScreenState extends State<OnboardingWizardScreen> {
  final _pageController = PageController();
  int _currentStep = 0;
  bool _loading = false;

  // Step 1 State: Profile & Year
  late TextEditingController _nameController;
  late int _selectedYear;

  // Step 2 State: Domain Track
  late String _selectedDomain;

  // Step 3 State: Skills
  final Set<String> _selectedSkills = {};
  final TextEditingController _customSkillController = TextEditingController();
  String? _resumeStatusMessage;
  bool _isUploadingResume = false;

  final List<String> _domainOptions = [
    'Software',
    'Data',
    'Cloud & DevOps',
    'Cybersecurity',
    'Mechanical',
    'Civil',
    'Electronics',
    'Enterprising',
  ];

  final Map<String, IconData> _domainIcons = {
    'Software': Icons.code_rounded,
    'Data': Icons.insights_rounded,
    'Cloud & DevOps': Icons.cloud_done_rounded,
    'Cybersecurity': Icons.security_rounded,
    'Mechanical': Icons.precision_manufacturing_rounded,
    'Civil': Icons.architecture_rounded,
    'Electronics': Icons.memory_rounded,
    'Enterprising': Icons.trending_up_rounded,
  };

  final List<String> _allStarterSkills = [
    'Python', 'Java', 'C++', 'SQL', 'Git', 'Docker', 'AWS', 'Kubernetes',
    'React', 'Flutter', 'Node.js', 'Linux', 'Machine Learning', 'Data Analysis',
    'Power BI', 'AutoCAD', 'SolidWorks', 'MATLAB', 'Cybersecurity', 'HTML/CSS',
    'TypeScript', 'Spring Boot', 'FastAPI', 'MongoDB', 'PostgreSQL'
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentUser.name);
    _selectedYear = widget.currentUser.academicYear;
    _selectedDomain = widget.currentUser.interestDomain;
    _selectedSkills.addAll(widget.currentUser.skills);
    if (_selectedSkills.isEmpty) {
      _selectedSkills.add('Python');
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _customSkillController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _completeOnboardingAndAnalyze();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _completeOnboardingAndAnalyze() async {
    if (_loading) return; // Prevent duplicate submissions
    setState(() => _loading = true);

    final updatedProfile = widget.currentUser.copyWith(
      name: _nameController.text.trim().isEmpty ? 'Student' : _nameController.text.trim(),
      academicYear: _selectedYear,
      interestDomain: _selectedDomain,
      skills: _selectedSkills.toList(),
      onboardingCompleted: true,
    );

    try {
      // 1. Save profile to Supabase database through FastAPI
      final savedProfile = await ApiService.saveStudentProfile(updatedProfile);

      // 2. Fetch career recommendations
      final roles = await ApiService.recommendRoles(savedProfile);
      if (!mounted) return;
      setState(() => _loading = false);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DashboardScreen(
            userProfile: savedProfile,
            roles: roles,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save profile or load roadmap: $e'),
          backgroundColor: AppTheme.accentRose,
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: _completeOnboardingAndAnalyze,
          ),
        ),
      );
    }
  }

  // Quick Resume Text Dialog
  void _openResumeTextExtractor() {
    final textCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.document_scanner_rounded, color: AppTheme.primaryIndigo),
            const SizedBox(width: 10),
            Text('Quick Resume Skill Scanner', style: AppTheme.fontHeading(fontWeight: FontWeight.w700)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Paste your resume text, bio, or skills list below. Our parser will instantly cross-reference O*NET database skills:',
              style: AppTheme.fontBody(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textCtrl,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: 'e.g. Computer Science student skilled in Python, Java, SQL, Git, Docker, and AWS...',
                hintStyle: AppTheme.fontBody(fontSize: 13, color: AppTheme.textMuted),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: const Text('Scan & Extract'),
            onPressed: () {
              final text = textCtrl.text.toLowerCase();
              final extracted = _allStarterSkills
                  .where((s) => text.contains(s.toLowerCase()))
                  .toList();

              Navigator.pop(ctx);
              setState(() {
                _selectedSkills.addAll(extracted);
                _resumeStatusMessage = extracted.isNotEmpty
                    ? 'Found ${extracted.length} skills from resume!'
                    : 'No matching starter skills detected in text.';
              });
            },
          ),
        ],
      ),
    );
  }

  // Stage 4: Pick and Upload PDF Resume with PyMuPDF Extraction & Skill Confirmation
  Future<void> _pickAndUploadResumePdf() async {
    if (_isUploadingResume) return;

    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (files.isEmpty) return;

      final file = files.first;
      final bytes = await file.readAsBytes();

      if (bytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not read the selected PDF resume.'),
            backgroundColor: AppTheme.accentRose,
          ),
        );
        return;
      }

      setState(() {
        _isUploadingResume = true;
      });

      final res = await ApiService.uploadResume(bytes, file.name);
      final List<dynamic> extracted = (res['extracted_skills'] as List<dynamic>?) ?? [];
      final extractedSkills = extracted.map((e) => e.toString()).toList();

      if (!mounted) return;
      setState(() {
        _isUploadingResume = false;
      });

      if (extractedSkills.isNotEmpty) {
        _showSkillReviewDialog(extractedSkills, file.name);
      } else {
        setState(() {
          _resumeStatusMessage = 'Uploaded "${file.name}" to private storage. No matching starter skills detected.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploadingResume = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Resume upload failed: $e'),
          backgroundColor: AppTheme.accentRose,
        ),
      );
    }
  }

  void _showSkillReviewDialog(List<String> detectedSkills, String filename) {
    final Set<String> confirmedSkills = Set.from(detectedSkills);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: AppTheme.primaryIndigo),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Review Extracted Skills',
                      style: AppTheme.fontHeading(fontWeight: FontWeight.w700, fontSize: 18),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Found ${detectedSkills.length} skills in $filename. Select which skills to confirm for your career profile:',
                      style: AppTheme.fontBody(fontSize: 13, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: detectedSkills.map((skill) {
                            final isSelected = confirmedSkills.contains(skill);
                            return FilterChip(
                              label: Text(skill),
                              selected: isSelected,
                              selectedColor: AppTheme.primaryIndigo.withValues(alpha: 0.15),
                              checkmarkColor: AppTheme.primaryIndigo,
                              labelStyle: TextStyle(
                                color: isSelected ? AppTheme.primaryIndigo : AppTheme.textPrimary,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                              onSelected: (selected) {
                                setDialogState(() {
                                  if (selected) {
                                    confirmedSkills.add(skill);
                                  } else {
                                    confirmedSkills.remove(skill);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Skip'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _selectedSkills.addAll(confirmedSkills);
                      _resumeStatusMessage = 'Uploaded "$filename" • ${confirmedSkills.length} skills confirmed!';
                    });
                  },
                  child: Text('Confirm (${confirmedSkills.length})'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Career Roadmap Wizard',
          style: AppTheme.fontHeading(fontWeight: FontWeight.w700),
        ),
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.primaryIndigo.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Step ${_currentStep + 1} of 3',
                  style: AppTheme.fontBody(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryIndigo,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Step Progress Bar
          LinearProgressIndicator(
            value: (_currentStep + 1) / 3,
            backgroundColor: AppTheme.borderLight,
            valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryIndigo),
            minHeight: 4,
          ),

          // Interactive Step Content
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (idx) => setState(() => _currentStep = idx),
              children: [
                _buildStepOneProfile(),
                _buildStepTwoDomain(),
                _buildStepThreeSkills(),
              ],
            ),
          ),

          // Bottom Action Bar
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.surfaceWhite,
              border: const Border(top: BorderSide(color: AppTheme.borderLight)),
              boxShadow: AppTheme.softShadow,
            ),
            child: Row(
              children: [
                if (_currentStep > 0)
                  OutlinedButton.icon(
                    onPressed: _prevStep,
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: const Text('Back'),
                  )
                else
                  const SizedBox(width: 80),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _loading ? null : _nextStep,
                  icon: _loading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Icon(
                          _currentStep == 2 ? Icons.rocket_launch_rounded : Icons.arrow_forward_rounded,
                          size: 18,
                        ),
                  label: Text(
                    _currentStep == 2
                        ? (_loading ? 'Analyzing Roles...' : 'Build Roadmap & Dashboard')
                        : 'Continue',
                    style: AppTheme.fontBody(fontWeight: FontWeight.w600),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: _currentStep == 2 ? AppTheme.secondaryTeal : AppTheme.primaryIndigo,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
  // STEP 1: Name & Academic Year
  // -------------------------------------------------------------
  Widget _buildStepOneProfile() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Let\'s Personalize Your Plan',
          style: AppTheme.fontHeading(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Enter your details so we can tailor the roadmap to your current stage.',
          style: AppTheme.fontBody(color: AppTheme.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 24),
        TextFormField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Your Full Name',
            prefixIcon: Icon(Icons.person_outline_rounded),
            hintText: 'e.g. Alex Chen',
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'Current Academic Year',
          style: AppTheme.fontHeading(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        ...List.generate(4, (index) {
          final yearNum = index + 1;
          final isSelected = _selectedYear == yearNum;
          final yearTitles = [
            'Year 1: Foundation & Exploration',
            'Year 2: Core Tooling & Frameworks',
            'Year 3: Internships & Gap Closure',
            'Final Year: Placement Prep & Capstones',
          ];
          final yearSubtitles = [
            'Algorithmic foundations, basic programming, hackathon participation.',
            'OOP, DBMS, full-stack frameworks, Git, and active GitHub projects.',
            'System design, cloud fundamentals, resume building, internship hunting.',
            'Mock interviews, ATS resume targeting, system architecture, pre-placement offers.',
          ];

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              onTap: () => setState(() => _selectedYear = yearNum),
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primaryIndigo.withValues(alpha: 0.05) : AppTheme.surfaceWhite,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? AppTheme.primaryIndigo : AppTheme.borderLight,
                    width: isSelected ? 2 : 1,
                  ),
                  boxShadow: isSelected ? AppTheme.softShadow : null,
                ),
                child: Row(
                  children: [
                    Container(
                      height: 40,
                      width: 40,
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.primaryIndigo : const Color(0xFFF1F5F9),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '$yearNum',
                          style: AppTheme.fontBody(
                            fontWeight: FontWeight.w700,
                            color: isSelected ? Colors.white : AppTheme.textSecondary,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            yearTitles[index],
                            style: AppTheme.fontBody(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: isSelected ? AppTheme.primaryIndigo : AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            yearSubtitles[index],
                            style: AppTheme.fontBody(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isSelected)
                      const Icon(Icons.check_circle_rounded, color: AppTheme.primaryIndigo, size: 22),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  // -------------------------------------------------------------
  // STEP 2: Target Domain
  // -------------------------------------------------------------
  Widget _buildStepTwoDomain() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Choose Your Target Career Track',
          style: AppTheme.fontHeading(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Select the industry domain you are most excited to build your career in.',
          style: AppTheme.fontBody(color: AppTheme.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 24),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.4,
          ),
          itemCount: _domainOptions.length,
          itemBuilder: (context, i) {
            final domain = _domainOptions[i];
            final isSelected = _selectedDomain == domain;
            final icon = _domainIcons[domain] ?? Icons.explore_rounded;

            return InkWell(
              onTap: () => setState(() => _selectedDomain = domain),
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primaryIndigo.withValues(alpha: 0.06) : AppTheme.surfaceWhite,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? AppTheme.primaryIndigo : AppTheme.borderLight,
                    width: isSelected ? 2 : 1,
                  ),
                  boxShadow: isSelected ? AppTheme.softShadow : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      size: 28,
                      color: isSelected ? AppTheme.primaryIndigo : AppTheme.textSecondary,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      domain,
                      textAlign: TextAlign.center,
                      style: AppTheme.fontBody(
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                        fontSize: 13,
                        color: isSelected ? AppTheme.primaryIndigo : AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // -------------------------------------------------------------
  // STEP 3: Current Skills & Resume Extraction
  // -------------------------------------------------------------
  Widget _buildStepThreeSkills() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Inventory Your Skills',
          style: AppTheme.fontHeading(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Select what you already know. We match these against 900+ O*NET industry roles to compute your exact readiness score.',
          style: AppTheme.fontBody(color: AppTheme.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 18),

        // Quick Scan Action Box
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: AppTheme.cardAccentGradient,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: AppTheme.softShadow,
                    ),
                    child: const Icon(Icons.document_scanner_outlined, color: AppTheme.primaryIndigo, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Have a resume ready?',
                          style: AppTheme.fontBody(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.textPrimary),
                        ),
                        Text(
                          'Upload your PDF resume to private cloud storage to auto-extract skills.',
                          style: AppTheme.fontBody(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isUploadingResume ? null : _pickAndUploadResumePdf,
                      icon: _isUploadingResume
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.upload_file_rounded, size: 16),
                      label: Text(_isUploadingResume ? 'Uploading...' : 'Upload PDF Resume'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: _openResumeTextExtractor,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    child: const Text('Paste Text', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        ),

        if (_resumeStatusMessage != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.accentEmerald.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline, size: 16, color: AppTheme.accentEmerald),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _resumeStatusMessage!,
                    style: AppTheme.fontBody(color: AppTheme.accentEmerald, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Selected Skills (${_selectedSkills.length})',
              style: AppTheme.fontBody(fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.textPrimary),
            ),
            Text(
              'Tap to toggle',
              style: AppTheme.fontBody(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 12),

        Wrap(
          spacing: 8,
          runSpacing: 10,
          children: _allStarterSkills.map((skill) {
            final isSelected = _selectedSkills.contains(skill);
            return FilterChip(
              label: Text(skill),
              selected: isSelected,
              showCheckmark: true,
              checkmarkColor: Colors.white,
              selectedColor: AppTheme.primaryIndigo,
              backgroundColor: AppTheme.surfaceWhite,
              labelStyle: AppTheme.fontBody(
                color: isSelected ? Colors.white : AppTheme.textPrimary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                fontSize: 13,
              ),
              side: BorderSide(
                color: isSelected ? AppTheme.primaryIndigo : AppTheme.borderLight,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              onSelected: (val) {
                setState(() {
                  if (val) {
                    _selectedSkills.add(skill);
                  } else {
                    _selectedSkills.remove(skill);
                  }
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }
}
