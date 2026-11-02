import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

void main() {
  runApp(const DayMateApp());
}

class DayMateApp extends StatelessWidget {
  const DayMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'dayMate',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF167D78),
        ),
        useMaterial3: true,
      ),
      home: const DayMateHome(),
    );
  }
}

class DayMateHome extends StatefulWidget {
  const DayMateHome({super.key});

  @override
  State<DayMateHome> createState() => _DayMateHomeState();
}

class _DayMateHomeState extends State<DayMateHome> {
  int selectedTab = 0;
  bool isLoading = true;

  final List<Map<String, dynamic>> tasks = [];
  final List<Map<String, dynamic>> plans = [];
  final List<Map<String, dynamic>> notes = [];
  final List<Map<String, dynamic>> expenses = [];
  final List<Map<String, dynamic>> habits = [];

  final List<String> titles = [
    'Home',
    'Tasks',
    'Planner',
    'Notes',
    'Expenses',
    'Habits',
  ];

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
      tasks
        ..clear()
        ..addAll(readItems('tasks'));
      plans
        ..clear()
        ..addAll(readItems('plans'));
      notes
        ..clear()
        ..addAll(readItems('notes'));
      expenses
        ..clear()
        ..addAll(readItems('expenses'));
      habits
        ..clear()
        ..addAll(readItems('habits'));
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

  List<Map<String, dynamic>> currentItems() {
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

    final isExpense = selectedTab == 4;
    final isPlanner = selectedTab == 2;

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
                    hintText: isExpense ? 'e.g. Groceries' : 'Enter title',
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
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setDialogState(() => selectedDate = picked);
                      }
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

    if (isExpense) {
      item['amount'] = amount;
    }
    if (isPlanner) {
      item['date'] = DateFormat('yyyy-MM-dd').format(selectedDate);
    }

    setState(() {
      currentItems().add(item);
    });
    await saveData();
  }

  Future<void> deleteItem(int index) async {
    setState(() {
      currentItems().removeAt(index);
    });
    await saveData();
  }

  Future<void> toggleDone(int index, bool? value) async {
    setState(() {
      currentItems()[index]['done'] = value ?? false;
    });
    await saveData();
  }

  Widget buildItems() {
    final items = currentItems();

    if (items.isEmpty) {
      return const Center(
        child: Text('Nothing here yet. Tap + to add something.'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final title = item['title']?.toString() ?? '';
        final isCheckable = selectedTab == 1 || selectedTab == 5;
        final isDone = item['done'] == true;

        String subtitle = '';
        if (selectedTab == 2 && item['date'] != null) {
          final date = DateTime.tryParse(item['date'].toString());
          if (date != null) {
            subtitle = DateFormat('EEE, d MMM yyyy').format(date);
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
                        ? Icons.event_outlined
                        : selectedTab == 3
                            ? Icons.notes
                            : selectedTab == 4
                                ? Icons.currency_rupee
                                : Icons.circle_outlined,
                  ),
            title: Text(
              title,
              style: TextStyle(
                decoration:
                    isCheckable && isDone ? TextDecoration.lineThrough : null,
              ),
            ),
            subtitle: subtitle.isEmpty ? null : Text(subtitle),
            trailing: IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => deleteItem(index),
            ),
          ),
        );
      },
    );
  }

  Widget buildDashboard() {
    final completed = tasks.where((item) => item['done'] == true).length;
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
        const SizedBox(height: 6),
        const Text('A little progress every day adds up.'),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _StatCard(label: 'Tasks', value: '${tasks.length}'),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(label: 'Completed', value: '$completed'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _StatCard(label: 'Notes', value: '${notes.length}'),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(label: 'Habits', value: '${habits.length}'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _StatCard(
          label: 'Total expenses',
          value: '₹${totalExpenses.toStringAsFixed(2)}',
        ),
        const SizedBox(height: 24),
        Text('Today’s tasks', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (tasks.isEmpty)
          const Text('No tasks yet. Add your first task.')
        else
          ...tasks.take(5).map(
                (task) => Card(
                  child: ListTile(
                    leading: Icon(
                      task['done'] == true
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      color: const Color(0xFF167D78),
                    ),
                    title: Text(task['title']?.toString() ?? ''),
                  ),
                ),
              ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('dayMate · ${titles[selectedTab]}'),
        actions: [
          if (selectedTab != 0)
            IconButton(
              tooltip: 'Add',
              onPressed: addItem,
              icon: const Icon(Icons.add),
            ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : selectedTab == 0
              ? buildDashboard()
              : buildItems(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedTab,
        onDestinationSelected: (index) {
          setState(() => selectedTab = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.check_circle_outline),
            label: 'Tasks',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            label: 'Planner',
          ),
          NavigationDestination(
            icon: Icon(Icons.sticky_note_2_outlined),
            label: 'Notes',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            label: 'Expenses',
          ),
          NavigationDestination(
            icon: Icon(Icons.track_changes_outlined),
            label: 'Habits',
          ),
        ],
      ),
      floatingActionButton: selectedTab == 0
          ? FloatingActionButton.extended(
              onPressed: () => setState(() => selectedTab = 1),
              icon: const Icon(Icons.add),
              label: const Text('New task'),
            )
          : null,
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 4),
            Text(label),
          ],
        ),
      ),
    );
  }
}
