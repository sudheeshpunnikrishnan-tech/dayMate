import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

final notifications = FlutterLocalNotificationsPlugin();

Future<void> initializeNotifications() async {
  tz.initializeTimeZones();

  final localTimezone = await FlutterTimezone.getLocalTimezone();
  tz.setLocalLocation(tz.getLocation(localTimezone.name));

  const settings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  );

  await notifications.initialize(settings);

  final android = notifications.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await android?.requestNotificationsPermission();
}

Future<void> scheduleReminder({
  required int id,
  required String title,
  required DateTime dateTime,
}) async {
  if (!dateTime.isAfter(DateTime.now())) return;

  await notifications.zonedSchedule(
    id,
    'dayMate reminder',
    title,
    tz.TZDateTime.from(dateTime, tz.local),
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'daymate_reminders',
        'dayMate reminders',
        channelDescription: 'Planner reminders from dayMate',
        importance: Importance.high,
        priority: Priority.high,
      ),
    ),
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeNotifications();
  runApp(const DayMateApp());
}

class DayMateApp extends StatefulWidget {
  const DayMateApp({super.key});

  @override
  State<DayMateApp> createState() => _DayMateAppState();
}

class _DayMateAppState extends State<DayMateApp> {
  ThemeMode themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    loadTheme();
  }

  Future<void> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('isDarkTheme') ?? false;
    if (mounted) {
      setState(() => themeMode = isDark ? ThemeMode.dark : ThemeMode.light);
    }
  }

  Future<void> toggleTheme() async {
    final isDark = themeMode != ThemeMode.dark;
    setState(() => themeMode = isDark ? ThemeMode.dark : ThemeMode.light);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkTheme', isDark);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'dayMate',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF167D78),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF64C9BE),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: DayMateHome(
        isDark: themeMode == ThemeMode.dark,
        onThemeToggle: toggleTheme,
      ),
    );
  }
}

class DayMateHome extends StatefulWidget {
  const DayMateHome({
    super.key,
    required this.isDark,
    required this.onThemeToggle,
  });

  final bool isDark;
  final VoidCallback onThemeToggle;

  @override
  State<DayMateHome> createState() => _DayMateHomeState();
}

class _DayMateHomeState extends State<DayMateHome> {
  int selectedTab = 0;
  bool isLoading = true;

  final tasks = <Map<String, dynamic>>[];
  final plans = <Map<String, dynamic>>[];
  final notes = <Map<String, dynamic>>[];
  final expenses = <Map<String, dynamic>>[];
  final habits = <Map<String, dynamic>>[];

  final titles = ['Home', 'Tasks', 'Planner', 'Notes', 'Expenses', 'Habits'];

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    final prefs = await SharedPreferences.getInstance();

    List<Map<String, dynamic>> readItems(String key) {
      final raw = prefs.getString(key);
      if (raw == null) return [];
      try {
        return (jsonDecode(raw) as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      } catch (_) {
        return [];
      }
    }

    if (!mounted) return;
    setState(() {
      tasks.addAll(readItems('tasks'));
      plans.addAll(readItems('plans'));
      notes.addAll(readItems('notes'));
      expenses.addAll(readItems('expenses'));
      habits.addAll(readItems('habits'));
      isLoading = false;
    });
  }

  Future<void> saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tasks', jsonEncode(tasks));
    await prefs.setString('plans', jsonEncode(plans));
    await prefs.setString('notes', jsonEncode(notes));
    await prefs.setString('expenses', jsonEncode(expenses));
    await prefs.setString('habits', jsonEncode(habits));
  }

  List<Map<String, dynamic>> selectedItems() {
    switch (selectedTab) {
      case 1:
        return tasks;
      case 2:
        return plans;
      case 3:
        return notes;
      case 4:
        return expenses;
      case 5:
        return habits;
      default:
        return tasks;
    }
  }

  Future<void> addItem() async {
    final titleController = TextEditingController();
    final amountController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    TimeOfDay selectedTime = TimeOfDay.now();
    bool addReminder = true;

    final isPlanner = selectedTab == 2;
    final isExpense = selectedTab == 4;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Add ${titles[selectedTab]}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: isExpense ? 'Expense description' : 'Title',
                  ),
                  textCapitalization: TextCapitalization.sentences,
                ),
                if (isExpense) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      prefixText: '₹ ',
                    ),
                  ),
                ],
                if (isPlanner) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_month),
                    label: Text(DateFormat('EEE, d MMM yyyy').format(selectedDate)),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 1),
                        ),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setDialogState(() => selectedDate = picked);
                      }
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.access_time),
                    label: Text(selectedTime.format(context)),
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: selectedTime,
                      );
                      if (picked != null) {
                        setDialogState(() => selectedTime = picked);
                      }
                    },
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Notify me'),
                    value: addReminder,
                    onChanged: (value) {
                      setDialogState(() => addReminder = value ?? false);
                    },
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    final title = titleController.text.trim();
    final amount = double.tryParse(amountController.text.trim()) ?? 0;
    titleController.dispose();
    amountController.dispose();

    if (result != true || title.isEmpty) return;

    final item = <String, dynamic>{
      'title': title,
      'done': false,
      'createdAt': DateTime.now().toIso8601String(),
    };

    if (isExpense) item['amount'] = amount;

    if (isPlanner) {
      final dateTime = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        selectedTime.hour,
        selectedTime.minute,
      );

      item['dateTime'] = dateTime.toIso8601String();
      item['reminder'] = addReminder;

      if (addReminder && dateTime.isAfter(DateTime.now())) {
        final id = dateTime.millisecondsSinceEpoch.remainder(2147483647);
        await scheduleReminder(id: id, title: title, dateTime: dateTime);
      }
    }

    setState(() => selectedItems().add(item));
    await saveData();
  }

  Future<void> deleteItem(int index) async {
    final items = selectedItems();
    final item = items[index];

    if (selectedTab == 2 && item['dateTime'] != null) {
      final dateTime = DateTime.tryParse(item['dateTime'].toString());
      if (dateTime != null) {
        final id = dateTime.millisecondsSinceEpoch.remainder(2147483647);
        await notifications.cancel(id);
      }
    }

    setState(() => items.removeAt(index));
    await saveData();
  }

  Future<void> toggleDone(int index, bool? value) async {
    setState(() => selectedItems()[index]['done'] = value ?? false);
    await saveData();
  }

  Widget buildItems() {
    final items = selectedItems();
    if (items.isEmpty) {
      return const Center(child: Text('Nothing here yet. Tap + to add.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final isCheckable = selectedTab == 1 || selectedTab == 5;
        final isDone = item['done'] == true;
        String subtitle = '';

        if (selectedTab == 2 && item['dateTime'] != null) {
          final dateTime = DateTime.tryParse(item['dateTime'].toString());
          if (dateTime != null) {
            subtitle = DateFormat('EEE, d MMM · h:mm a').format(dateTime);
            if (item['reminder'] == true) subtitle += ' · Reminder set';
          }
        } else if (selectedTab == 4) {
          final amount = (item['amount'] as num?)?.toDouble() ?? 0;
          subtitle = '₹${amount.toStringAsFixed(2)}';
        }

        return Card(
          child: ListTile(
            leading: isCheckable
                ? Checkbox(
                    value: isDone,
                    onChanged: (value) => toggleDone(index, value),
                  )
                : Icon(
                    selectedTab == 2
                        ? Icons.event
                        : selectedTab == 3
                            ? Icons.notes
                            : selectedTab == 4
                                ? Icons.currency_rupee
                                : Icons.circle_outlined,
                  ),
            title: Text(
              item['title']?.toString() ?? '',
              style: TextStyle(
                decoration: isCheckable && isDone
                    ? TextDecoration.lineThrough
                    : null,
              ),
            ),
            subtitle: subtitle.isEmpty ? null : Text(subtitle),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => deleteItem(index),
            ),
          ),
        );
      },
    );
  }

  Widget dashboard() {
    final totalExpenses = expenses.fold<double>(
      0,
      (sum, item) => sum + ((item['amount'] as num?)?.toDouble() ?? 0),
    );

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Your day, organized.',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Text('Tasks: ${tasks.length}   Notes: ${notes.length}'),
        Text('Habits: ${habits.length}   Planner: ${plans.length}'),
        const SizedBox(height: 8),
        Text('Expenses: ₹${totalExpenses.toStringAsFixed(2)}'),
        const SizedBox(height: 20),
        const Text('Add a task from the Tasks tab using +.'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('dayMate · ${titles[selectedTab]}'),
        actions: [
          IconButton(
            tooltip: widget.isDark ? 'Switch to light theme' : 'Switch to dark theme',
            onPressed: widget.onThemeToggle,
            icon: Icon(widget.isDark ? Icons.light_mode : Icons.dark_mode),
          ),
          if (selectedTab != 0)
            IconButton(
              onPressed: addItem,
              icon: const Icon(Icons.add),
              tooltip: 'Add',
            ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : selectedTab == 0
              ? dashboard()
              : buildItems(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedTab,
        onDestinationSelected: (index) => setState(() => selectedTab = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.check_circle_outline), label: 'Tasks'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), label: 'Planner'),
          NavigationDestination(icon: Icon(Icons.sticky_note_2_outlined), label: 'Notes'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), label: 'Expenses'),
          NavigationDestination(icon: Icon(Icons.track_changes_outlined), label: 'Habits'),
        ],
      ),
    );
  }
}
