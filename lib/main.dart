import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'dart:convert';

final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initializeNotifications();
  runApp(const DayMateApp());
}

Future<void> _initializeNotifications() async {
  tz.initializeTimeZones();

  // flutter_timezone version in this project returns a String.
  final String localTimezone = await FlutterTimezone.getLocalTimezone();
  tz.setLocalLocation(tz.getLocation(localTimezone));

  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings settings =
      InitializationSettings(android: androidSettings);

  await notifications.initialize(settings);

  final androidPlugin =
      notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  await androidPlugin?.requestNotificationsPermission();
}

class DayMateApp extends StatefulWidget {
  const DayMateApp({super.key});

  @override
  State<DayMateApp> createState() => _DayMateAppState();
}

class _DayMateAppState extends State<DayMateApp> {
  bool darkMode = false;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => darkMode = prefs.getBool('darkMode') ?? false);
  }

  Future<void> _toggleTheme(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('darkMode', value);
    setState(() => darkMode = value);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DayMate',
      debugShowCheckedModeBanner: false,
      themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: HomePage(
        darkMode: darkMode,
        onThemeChanged: _toggleTheme,
      ),
    );
  }
}

class PlannerItem {
  PlannerItem({
    required this.id,
    required this.title,
    required this.dateTime,
    this.reminder = false,
    this.done = false,
  });

  final int id;
  String title;
  DateTime dateTime;
  bool reminder;
  bool done;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'dateTime': dateTime.toIso8601String(),
        'reminder': reminder,
        'done': done,
      };

  factory PlannerItem.fromJson(Map<String, dynamic> json) => PlannerItem(
        id: json['id'],
        title: json['title'],
        dateTime: DateTime.parse(json['dateTime']),
        reminder: json['reminder'] ?? false,
        done: json['done'] ?? false,
      );
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.darkMode,
    required this.onThemeChanged,
  });

  final bool darkMode;
  final ValueChanged<bool> onThemeChanged;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int selectedTab = 0;
  final List<PlannerItem> planner = [];
  final List<String> notes = [];
  final List<String> habits = [];
  final List<Map<String, dynamic>> expenses = [];

  final titleController = TextEditingController();
  final noteController = TextEditingController();
  final expenseController = TextEditingController();

  DateTime selectedDate = DateTime.now();
  bool reminderEnabled = true;
  double expenseTotal = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    titleController.dispose();
    noteController.dispose();
    expenseController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();

    final savedPlanner = prefs.getString('planner');
    if (savedPlanner != null) {
      final List<dynamic> decoded = jsonDecode(savedPlanner);
      planner.addAll(decoded.map((e) => PlannerItem.fromJson(e)));
    }

    notes.addAll(prefs.getStringList('notes') ?? []);
    habits.addAll(prefs.getStringList('habits') ?? []);

    final savedExpenses = prefs.getString('expenses');
    if (savedExpenses != null) {
      expenses.addAll(
        List<Map<String, dynamic>>.from(jsonDecode(savedExpenses)),
      );
    }

    _calculateExpenses();
    if (mounted) setState(() {});
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'planner',
      jsonEncode(planner.map((e) => e.toJson()).toList()),
    );
    await prefs.setStringList('notes', notes);
    await prefs.setStringList('habits', habits);
    await prefs.setString('expenses', jsonEncode(expenses));
  }

  void _calculateExpenses() {
    expenseTotal = expenses.fold<double>(
      0,
      (sum, item) => sum + (item['amount'] as num).toDouble(),
    );
  }

  Future<void> _addPlannerItem() async {
    final title = titleController.text.trim();
    if (title.isEmpty) return;

    final item = PlannerItem(
      id: DateTime.now().millisecondsSinceEpoch,
      title: title,
      dateTime: selectedDate,
      reminder: reminderEnabled,
    );

    setState(() {
      planner.add(item);
      titleController.clear();
    });

    await _saveData();

    if (item.reminder) {
      await _scheduleReminder(item);
    }
  }

  Future<void> _scheduleReminder(PlannerItem item) async {
    if (item.dateTime.isBefore(DateTime.now())) return;

    await notifications.zonedSchedule(
      item.id,
      'DayMate Reminder',
      item.title,
      tz.TZDateTime.from(item.dateTime, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'daymate_reminders',
          'DayMate reminders',
          channelDescription: 'Planner reminders',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: item.id.toString(),
    );
  }

  Future<void> _deletePlannerItem(PlannerItem item) async {
    await notifications.cancel(item.id);
    setState(() => planner.removeWhere((e) => e.id == item.id));
    await _saveData();
  }

  Future<void> _addNote() async {
    final text = noteController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      notes.add(text);
      noteController.clear();
    });
    await _saveData();
  }

  Future<void> _addExpense() async {
    final amount = double.tryParse(expenseController.text.trim());
    if (amount == null || amount <= 0) return;

    setState(() {
      expenses.add({
        'title': 'Expense',
        'amount': amount,
        'date': DateTime.now().toIso8601String(),
      });
      expenseController.clear();
      _calculateExpenses();
    });
    await _saveData();
  }

  Future<void> _addHabit() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add habit'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Habit name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (value != null && value.isNotEmpty) {
      setState(() => habits.add(value));
      await _saveData();
    }
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(selectedDate),
    );
    if (time == null) return;

    setState(() {
      selectedDate = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _plannerPage(),
      _notesPage(),
      _expensesPage(),
      _habitsPage(),
      _settingsPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('DayMate'),
        actions: [
          IconButton(
            tooltip: widget.darkMode ? 'Light theme' : 'Dark theme',
            icon: Icon(widget.darkMode ? Icons.light_mode : Icons.dark_mode),
            onPressed: () => widget.onThemeChanged(!widget.darkMode),
          ),
        ],
      ),
      body: pages[selectedTab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedTab,
        onDestinationSelected: (index) => setState(() => selectedTab = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.event_note), label: 'Planner'),
          NavigationDestination(icon: Icon(Icons.note_alt), label: 'Notes'),
          NavigationDestination(icon: Icon(Icons.wallet), label: 'Expenses'),
          NavigationDestination(icon: Icon(Icons.check_circle), label: 'Habits'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }

  Widget _plannerPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: titleController,
          decoration: const InputDecoration(
            labelText: 'Planner item',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _pickDateTime,
          icon: const Icon(Icons.calendar_month),
          label: Text(
            '${selectedDate.day}/${selectedDate.month}/${selectedDate.year} '
            '${TimeOfDay.fromDateTime(selectedDate).format(context)}',
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Reminder notification'),
          value: reminderEnabled,
          onChanged: (value) => setState(() => reminderEnabled = value),
        ),
        FilledButton(
          onPressed: _addPlannerItem,
          child: const Text('Add planner item'),
        ),
        const SizedBox(height: 16),
        if (planner.isEmpty) const Text('No planner items yet.'),
        ...planner.map(
          (item) => Card(
            child: ListTile(
              title: Text(
                item.title,
                style: TextStyle(
                  decoration: item.done ? TextDecoration.lineThrough : null,
                ),
              ),
              subtitle: Text(
                '${item.dateTime.day}/${item.dateTime.month}/${item.dateTime.year} '
                '${TimeOfDay.fromDateTime(item.dateTime).format(context)}'
                '${item.reminder ? ' • Reminder on' : ''}',
              ),
              leading: Checkbox(
                value: item.done,
                onChanged: (value) async {
                  setState(() => item.done = value ?? false);
                  await _saveData();
                },
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _deletePlannerItem(item),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _notesPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: noteController,
          decoration: const InputDecoration(
            labelText: 'Write a note',
            border: OutlineInputBorder(),
          ),
          minLines: 2,
          maxLines: 4,
        ),
        const SizedBox(height: 10),
        FilledButton(onPressed: _addNote, child: const Text('Save note')),
        const SizedBox(height: 12),
        ...notes.asMap().entries.map(
          (entry) => Card(
            child: ListTile(
              title: Text(entry.value),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  setState(() => notes.removeAt(entry.key));
                  await _saveData();
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _expensesPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            title: const Text('Total expenses'),
            subtitle: Text('₹${expenseTotal.toStringAsFixed(2)}'),
          ),
        ),
        TextField(
          controller: expenseController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Amount (₹)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton(onPressed: _addExpense, child: const Text('Add expense')),
        ...expenses.asMap().entries.map(
          (entry) => ListTile(
            title: const Text('Expense'),
            trailing: Text('₹${(entry.value['amount'] as num).toStringAsFixed(2)}'),
          ),
        ),
      ],
    );
  }

  Widget _habitsPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton.icon(
          onPressed: _addHabit,
          icon: const Icon(Icons.add),
          label: const Text('Add habit'),
        ),
        ...habits.asMap().entries.map(
          (entry) => Card(
            child: ListTile(
              title: Text(entry.value),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  setState(() => habits.removeAt(entry.key));
                  await _saveData();
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _settingsPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SwitchListTile(
          title: const Text('Dark theme'),
          subtitle: const Text('Switch between light and dark appearance'),
          value: widget.darkMode,
          onChanged: widget.onThemeChanged,
        ),
        const ListTile(
          leading: Icon(Icons.notifications_active_outlined),
          title: Text('Planner reminders'),
          subtitle: Text('Enable reminders when adding planner items'),
        ),
      ],
    );
  }
}
