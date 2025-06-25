import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:easy_localization/easy_localization.dart';
import 'dart:developer' as developer;
import 'dart:async';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    developer.log("Background task executed: $task");
    
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      int currentSteps = prefs.getInt('today_steps') ?? 0;
      int currentTime = DateTime.now().millisecondsSinceEpoch;
      
      String today = DateTime.now().toIso8601String().split('T')[0];
      String lastDay = prefs.getString('last_day') ?? '';
      
      if (today != lastDay) {
        await prefs.setInt('today_steps', 0);
        await prefs.setString('last_day', today);
        await prefs.setInt('daily_reset_steps', currentSteps);
        developer.log("Daily reset performed");
      }
      
      await prefs.setInt('last_background_steps', currentSteps);
      await prefs.setInt('last_sync_timestamp', currentTime);
      developer.log("Steps synced in background: $currentSteps");
    } catch (e) {
      developer.log("Error in background task: $e");
    }
    
    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  
  await Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: false,
  );
  
  await Workmanager().registerPeriodicTask(
    "step-counter-background",
    "step-counter-task",
    frequency: const Duration(minutes: 15),
    constraints: Constraints(
      networkType: NetworkType.not_required,
      requiresBatteryNotLow: false,
      requiresCharging: false,
      requiresDeviceIdle: false,
      requiresStorageNotLow: false,
    ),
  );
  
  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('tr')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      child: const StepCounterApp(),
    ),
  );
}

class StepCounterApp extends StatelessWidget {
  const StepCounterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'app_title'.tr(),
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        fontFamily: 'System',
        useMaterial3: true,
      ),
      home: const StepCounterHome(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class StepCounterHome extends StatefulWidget {
  const StepCounterHome({super.key});

  @override
  State<StepCounterHome> createState() => _StepCounterHomeState();
}

class _StepCounterHomeState extends State<StepCounterHome> 
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late Stream<StepCount> _stepCountStream;
  late Stream<PedestrianStatus> _pedestrianStatusStream;
  String _status = '?';
  int _dailyGoal = 10000;
  int _todaySteps = 0;
  int _sessionSteps = 0;
  int _baseStepCount = 0;
  bool _isWalking = false;
  bool _backgroundServiceRunning = false;
  bool _isInitialized = false;
  late AnimationController _walkingController;
  late AnimationController _progressController;
  late Animation<double> _walkingAnimation;
  late Animation<double> _progressAnimation;
  Timer? _syncTimer;
  StreamSubscription<StepCount>? _stepCountSubscription;
  StreamSubscription<PedestrianStatus>? _statusSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _walkingController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _progressController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _walkingAnimation = Tween<double>(
      begin: 1.0,
      end: 1.05,
    ).animate(CurvedAnimation(
      parent: _walkingController,
      curve: Curves.easeInOut,
    ));
    
    _progressAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _progressController,
      curve: Curves.easeOut,
    ));
    
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _loadSavedSteps();
    await _checkDailyReset();
    await _initPlatformState();
    await _startBackgroundService();
    _startPeriodicSync();
    
    setState(() {
      _isInitialized = true;
    });
  }

  Future<void> _checkDailyReset() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String today = DateTime.now().toIso8601String().split('T')[0];
    String lastDay = prefs.getString('last_day') ?? '';
    
    if (today != lastDay) {
      await prefs.setInt('today_steps', 0);
      await prefs.setString('last_day', today);
      await prefs.setInt('daily_reset_steps', _sessionSteps);
      _todaySteps = 0;
      _sessionSteps = 0;
      developer.log("Daily reset performed");
    }
  }

  void _startPeriodicSync() {
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _saveSteps();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.resumed:
        developer.log("App resumed - refreshing steps");
        _loadSavedSteps();
        _checkDailyReset();
        break;
      case AppLifecycleState.paused:
        developer.log("App paused - saving current steps");
        _saveSteps();
        break;
      case AppLifecycleState.detached:
        developer.log("App detached");
        _saveSteps();
        break;
      case AppLifecycleState.inactive:
        developer.log("App inactive");
        break;
      case AppLifecycleState.hidden:
        developer.log("App hidden");
        break;
    }
  }

  Future<void> _startBackgroundService() async {
    try {
      await Workmanager().registerPeriodicTask(
        "step-counter-periodic",
        "periodic-step-task",
        frequency: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.not_required,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
      );
      
      setState(() {
        _backgroundServiceRunning = true;
      });
      developer.log("Background service started successfully");
    } catch (e) {
      developer.log("Error starting background service: $e");
      setState(() {
        _backgroundServiceRunning = false;
      });
    }
  }

  Future<void> _loadSavedSteps() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _todaySteps = prefs.getInt('today_steps') ?? 0;
        _dailyGoal = prefs.getInt('daily_goal') ?? 10000;
        _baseStepCount = prefs.getInt('base_step_count') ?? 0;
      });
      _updateProgressAnimation();
    }
  }

  void _updateProgressAnimation() {
    _progressController.animateTo(progressPercentage);
  }

  Future<void> _saveSteps() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt('today_steps', _todaySteps);
    await prefs.setInt('base_step_count', _baseStepCount);
    await prefs.setInt('last_background_steps', _todaySteps);
    await prefs.setInt('last_sync_timestamp', DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> _initPlatformState() async {
    await _checkPermissions();
    
    try {
      _pedestrianStatusStream = Pedometer.pedestrianStatusStream;
      _statusSubscription = _pedestrianStatusStream.listen(
        onPedestrianStatusChanged,
        onError: onPedestrianStatusError,
        onDone: () => developer.log("Pedestrian status stream closed"),
        cancelOnError: false,
      );

      _stepCountStream = Pedometer.stepCountStream;
      _stepCountSubscription = _stepCountStream.listen(
        onStepCount,
        onError: onStepCountError,
        onDone: () => developer.log("Step count stream closed"),
        cancelOnError: false,
      );
      
      developer.log("Pedometer streams initialized successfully");
    } catch (e) {
      developer.log("Error initializing pedometer: $e");
    }
  }

  Future<void> _checkPermissions() async {
    var activityPermission = await Permission.activityRecognition.request();
    var notificationPermission = await Permission.notification.request();
    
    if (activityPermission.isGranted) {
      developer.log('Activity recognition permission granted');
    } else {
      developer.log('Activity recognition permission denied');
      _showPermissionDialog();
    }
    
    if (notificationPermission.isGranted) {
      developer.log('Notification permission granted');
    } else {
      developer.log('Notification permission denied');
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('permission_required'.tr()),
        content: Text('permission_message'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('cancel'.tr()),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: Text('settings'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _resetStepCounter() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt('base_step_count', 0);
    await prefs.setInt('today_steps', 0);
    
    setState(() {
      _baseStepCount = 0;
      _todaySteps = 0;
    });
    
    _updateProgressAnimation();
    developer.log("Step counter reset");
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('step_counter_reset'.tr()),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _refreshStepCounter() async {
    await _loadSavedSteps();
    await _checkDailyReset();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('step_counter_refreshed'.tr()),
          duration: const Duration(seconds: 2),
        ),
      );
    }
    
    developer.log("Step counter refreshed - Today: $_todaySteps, Base: $_baseStepCount");
  }

  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.language_rounded,
                  color: Color(0xFF4F46E5),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'language'.tr(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2D3748),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Text('🇺🇸', style: TextStyle(fontSize: 24)),
                title: Text('english'.tr()),
                trailing: context.locale.languageCode == 'en' 
                  ? const Icon(Icons.check, color: Color(0xFF4F46E5))
                  : null,
                onTap: () {
                  context.setLocale(const Locale('en'));
                  Navigator.of(dialogContext).pop();
                },
              ),
              ListTile(
                leading: const Text('🇹🇷', style: TextStyle(fontSize: 24)),
                title: Text('turkish'.tr()),
                trailing: context.locale.languageCode == 'tr' 
                  ? const Icon(Icons.check, color: Color(0xFF4F46E5))
                  : null,
                onTap: () {
                  context.setLocale(const Locale('tr'));
                  Navigator.of(dialogContext).pop();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void onStepCount(StepCount event) {
    if (!mounted || !_isInitialized) return;
    
    try {
      if (_baseStepCount == 0) {
        _baseStepCount = event.steps;
        SharedPreferences.getInstance().then((prefs) {
          prefs.setInt('base_step_count', _baseStepCount);
        });
      }
      
      int newSteps = event.steps - _baseStepCount;
      
      if (newSteps >= 0 && newSteps != _todaySteps) {
        setState(() {
          _todaySteps = newSteps;
        });
        _updateProgressAnimation();
        
        if (_todaySteps % 100 == 0) {
          _saveSteps();
        }
      }
      
      developer.log("Step count updated: Total=${event.steps}, Today=$_todaySteps, Base=$_baseStepCount");
    } catch (e) {
      developer.log("Error processing step count: $e");
    }
  }

  void onPedestrianStatusChanged(PedestrianStatus event) {
    if (!mounted) return;
    
    setState(() {
      _status = event.status;
      _isWalking = event.status == 'walking';
      
      if (_isWalking) {
        _walkingController.repeat(reverse: true);
      } else {
        _walkingController.stop();
        _walkingController.reset();
      }
    });
    
    developer.log("Pedestrian status changed: ${event.status}");
  }

  void onPedestrianStatusError(Object error) {
    developer.log("Pedestrian status error: $error");
    if (mounted) {
      setState(() {
        _status = 'Sensor unavailable';
      });
    }
  }

  void onStepCountError(Object error) {
    developer.log("Step count error: $error");
    if (mounted) {
      setState(() {
        
      });
    }
  }

  double get progressPercentage => (_todaySteps / _dailyGoal).clamp(0.0, 1.0);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _walkingController.dispose();
    _progressController.dispose();
    _syncTimer?.cancel();
    _stepCountSubscription?.cancel();
    _statusSubscription?.cancel();
    _saveSteps();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'initializing_step_counter'.tr(),
                style: const TextStyle(
                  fontSize: 16,
                  color: Color(0xFF2D3748),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await _loadSavedSteps();
            await _checkDailyReset();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 30),
                _buildMainStepCard(),
                const SizedBox(height: 30),
                _buildGoalCard(),
                const SizedBox(height: 25),
                _buildStatsCards(),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
                          Row(
                children: [
                  Text(
                    'hello'.tr(),
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _backgroundServiceRunning ? Colors.green : Colors.orange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _backgroundServiceRunning ? Icons.check_circle : Icons.warning,
                          color: Colors.white,
                          size: 12,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _backgroundServiceRunning ? 'active'.tr() : 'inactive'.tr(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 4),
            const Text(
              'Pacelt',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D3748),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton(
                onPressed: _showLanguageDialog,
                icon: const Icon(
                  Icons.language_rounded,
                  color: Color(0xFF4F46E5),
                  size: 24,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton(
                onPressed: _showSettingsDialog,
                icon: const Icon(
                  Icons.settings_rounded,
                  color: Color(0xFF4F46E5),
                  size: 24,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMainStepCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF667EEA),
            Color(0xFF764BA2),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF667EEA).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _walkingAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _walkingAnimation.value,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.15),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: SizedBox(
                          width: 160,
                          height: 160,
                          child: AnimatedBuilder(
                            animation: _progressAnimation,
                            builder: (context, child) {
                              return CircularProgressIndicator(
                                value: _progressAnimation.value,
                                strokeWidth: 10,
                                backgroundColor: Colors.white.withValues(alpha: 0.2),
                                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                strokeCap: StrokeCap.round,
                              );
                            },
                          ),
                        ),
                      ),
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _isWalking 
                                ? Icons.directions_walk_rounded 
                                : Icons.accessibility_new_rounded,
                              color: Colors.white,
                              size: 36,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$_todaySteps',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'steps'.tr(),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 16,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _getStatusColor(_status),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _getStatusText(_status),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  _backgroundServiceRunning ? Icons.cloud_done : Icons.cloud_off,
                  color: Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  'background'.tr(),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalCard() {
    final isCompleted = progressPercentage >= 1.0;
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isCompleted ? 'congratulations'.tr() : 'daily_goal'.tr(),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isCompleted ? Colors.green[600] : Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$_dailyGoal ${'steps'.tr()}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D3748),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isCompleted 
                    ? Colors.green[50] 
                    : const Color(0xFF4F46E5).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isCompleted ? Icons.check_circle_rounded : Icons.flag_rounded,
                  size: 24,
                  color: isCompleted ? Colors.green[600] : const Color(0xFF4F46E5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'progress'.tr(),
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              Text(
                '${(progressPercentage * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isCompleted ? Colors.green[600] : const Color(0xFF4F46E5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            height: 8,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(4),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progressPercentage,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isCompleted
                      ? [Colors.green[400]!, Colors.green[600]!]
                      : [const Color(0xFF4F46E5), const Color(0xFF667EEA)],
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          if (!isCompleted) ...[
            const SizedBox(height: 12),
            Text(
              '${_dailyGoal - _todaySteps} ${'steps_remaining'.tr()}',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatsCards() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'statistics'.tr(),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2D3748),
          ),
        ),
        const SizedBox(height: 16),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.2,
          children: [
            _buildStatCard(
              'calories'.tr(),
              '${(_todaySteps * 0.04).toInt()}',
              'cal'.tr(),
              Icons.local_fire_department_rounded,
              Colors.orange,
            ),
            _buildStatCard(
              'distance'.tr(),
              (_todaySteps * 0.0008).toStringAsFixed(1),
              'km'.tr(),
              Icons.straighten_rounded,
              Colors.purple,
            ),
            _buildStatCard(
              'duration'.tr(),
              '${(_todaySteps * 0.01).toInt()}',
              'min'.tr(),
              Icons.timer_rounded,
              Colors.blue,
            ),
            _buildStatCard(
              'average'.tr(),
              '${(_todaySteps / 24).toInt()}',
              'steps_hour'.tr(),
              Icons.speed_rounded,
              Colors.green,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, String unit, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 20,
              color: color,
            ),
          ),
          const Spacer(),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D3748),
                ),
              ),
              const SizedBox(width: 2),
              Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: Text(
                  unit,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'walking':
        return 'walking'.tr();
      case 'stopped':
        return 'stopped'.tr();
      case 'unknown':
        return 'unknown'.tr();
      case 'Sensor unavailable':
        return 'sensor_error'.tr();
      default:
        return 'initializing'.tr();
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'walking':
        return Colors.green;
      case 'stopped':
        return Colors.orange;
      case 'Sensor unavailable':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  void _showSettingsDialog() {
    TextEditingController goalController = TextEditingController(
      text: _dailyGoal.toString(),
    );

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.flag_rounded,
                  color: Color(0xFF4F46E5),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'daily_goal'.tr(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2D3748),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: goalController,
                keyboardType: TextInputType.number,
                style: const TextStyle(
                  fontSize: 16,
                  color: Color(0xFF2D3748),
                ),
                decoration: InputDecoration(
                  labelText: 'target_steps_per_day'.tr(),
                  labelStyle: TextStyle(color: Colors.grey[600]),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 16),
                              Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _backgroundServiceRunning ? Colors.green[50] : Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _backgroundServiceRunning ? Colors.green[200]! : Colors.orange[200]!,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _backgroundServiceRunning ? Icons.check_circle : Icons.warning,
                        color: _backgroundServiceRunning ? Colors.green[600] : Colors.orange[600],
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _backgroundServiceRunning 
                            ? 'background_tracking_active'.tr()
                            : 'background_tracking_setup'.tr(),
                          style: TextStyle(
                            color: _backgroundServiceRunning ? Colors.green[700] : Colors.orange[700],
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange[400],
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: _resetStepCounter,
                        child: Text('reset_counter'.tr()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[400],
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: _refreshStepCounter,
                        child: Text('refresh'.tr()),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'cancel'.tr(),
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              onPressed: () async {
                int newGoal = int.tryParse(goalController.text) ?? _dailyGoal;
                if (mounted) {
                  setState(() {
                    _dailyGoal = newGoal;
                  });
                  _updateProgressAnimation();
                }
                SharedPreferences prefs = await SharedPreferences.getInstance();
                await prefs.setInt('daily_goal', newGoal);
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: Text('save'.tr()),
            ),
          ],
        );
      },
    );
  }
}
