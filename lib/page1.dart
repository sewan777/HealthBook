import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login.dart';

class HealthApp extends StatelessWidget {
  const HealthApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.green,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const HealthAppHome(),
    );
  }
}

class Meal {
  String? id;
  String name;
  double weight;
  int calories;
  DateTime consumedTime;
  DateTime date;
  String? userId;
  File? image;

  Meal({
    this.id,
    required this.name,
    required this.weight,
    required this.calories,
    required this.consumedTime,
    required this.date,
    this.userId,
    this.image,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'weight': weight,
      'calories': calories,
      'consumed_time': consumedTime.toIso8601String(),
      'date': date.toIso8601String().split('T')[0],
      'user_id': userId,
    };
  }

  static Meal fromJson(Map<String, dynamic> json) {
    return Meal(
      id: json['id']?.toString(),
      name: json['name'] ?? '',
      weight: (json['weight'] ?? 0).toDouble(),
      calories: json['calories'] ?? 0,
      consumedTime: DateTime.parse(json['consumed_time']),
      date: DateTime.parse(json['date']),
      userId: json['user_id'],
    );
  }
}

class HealthAppHome extends StatefulWidget {
  const HealthAppHome({super.key});

  @override
  State<HealthAppHome> createState() => _HealthAppHomeState();
}

class _HealthAppHomeState extends State<HealthAppHome> {
  final ImagePicker _picker = ImagePicker();
  final SupabaseClient supabase = Supabase.instance.client;
  File? _selectedImage;
  DateTime _selectedDate = DateTime.now();
  int _calorieGoal = 2000;
  int _totalCaloriesConsumed = 0;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _calorieController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  List<Meal> _mealLogs = [];
  bool _isCalorieInputEnabled = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _timeController.text = _formatTime(DateTime.now());
    _loadMealsForDate();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _weightController.dispose();
    _calorieController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  String _formatTime(DateTime dateTime) {
    return "${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}";
  }

  Future<void> _loadMealsForDate() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final dateString = _selectedDate.toIso8601String().split('T')[0];

      final response = await supabase
          .from('meals')
          .select()
          .eq('user_id', user.id)
          .eq('date', dateString)
          .order('consumed_time');

      setState(() {
        _mealLogs = response.map<Meal>((json) => Meal.fromJson(json)).toList();
        _totalCaloriesConsumed = _mealLogs.fold(0, (sum, meal) => sum + meal.calories);
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading meals: $error')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _addMeal() async {
    String name = _nameController.text.trim();
    double weight = double.tryParse(_weightController.text) ?? 0;
    int calories = _isCalorieInputEnabled ? int.tryParse(_calorieController.text) ?? 0 : 0;

    if (name.isEmpty || weight <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter valid meal name and weight')),
      );
      return;
    }

    if (_isCalorieInputEnabled && calories <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter valid calories')),
      );
      return;
    }

    DateTime consumedTime;
    try {
      final timeParts = _timeController.text.split(':');
      if (timeParts.length != 2) throw const FormatException('Invalid time format');

      final hours = int.parse(timeParts[0]);
      final minutes = int.parse(timeParts[1]);

      consumedTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        hours,
        minutes,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter time in HH:MM format')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final meal = Meal(
        name: name,
        weight: weight,
        calories: calories,
        consumedTime: consumedTime,
        date: _selectedDate,
        userId: user.id,
        image: _selectedImage,
      );

      final response = await supabase
          .from('meals')
          .insert(meal.toJson())
          .select()
          .single();

      final savedMeal = Meal.fromJson(response);
      savedMeal.image = _selectedImage;

      setState(() {
        _mealLogs.add(savedMeal);
        _totalCaloriesConsumed += calories;
      });

      _nameController.clear();
      _weightController.clear();
      _calorieController.clear();
      _timeController.text = _formatTime(DateTime.now());
      _selectedImage = null;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Meal added successfully!')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding meal: $error')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteMeal(int index) async {
    final meal = _mealLogs[index];

    try {
      if (meal.id != null) {
        await supabase.from('meals').delete().eq('id', meal.id!);
      }

      setState(() {
        _totalCaloriesConsumed -= meal.calories;
        _mealLogs.removeAt(index);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Meal deleted successfully!')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting meal: $error')),
        );
      }
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (pickedDate != null && pickedDate != _selectedDate) {
      setState(() {
        _selectedDate = pickedDate;
      });
      await _loadMealsForDate();
    }
  }

  Future<void> _selectImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 600,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting image: $e')),
        );
      }
    }
  }

  Widget _buildCalendarSection() {
    return GestureDetector(
      onTap: () => _selectDate(context),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.green.shade700,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.calendar_today, color: Colors.white),
            const SizedBox(width: 10),
            Text(
              "${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}",
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalorieGoalBar() {
    double progress = _calorieGoal > 0 ? _totalCaloriesConsumed / _calorieGoal : 0;
    progress = progress.clamp(0.0, 1.0);

    return Column(
      children: [
        Text("Calorie Goal: $_calorieGoal kcal",
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Slider(
          value: _calorieGoal.toDouble(),
          min: 1000,
          max: 4000,
          divisions: 30,
          label: "$_calorieGoal kcal",
          onChanged: (value) {
            setState(() {
              _calorieGoal = value.toInt();
            });
          },
        ),
        LinearProgressIndicator(
          value: progress,
          backgroundColor: Colors.grey.shade300,
          color: progress > 1.0 ? Colors.red : Colors.green,
          minHeight: 10,
        ),
        const SizedBox(height: 5),
        Text(
          "Consumed: $_totalCaloriesConsumed kcal",
          style: TextStyle(
            fontSize: 16,
            color: _totalCaloriesConsumed > _calorieGoal ? Colors.red : Colors.black,
            fontWeight: _totalCaloriesConsumed > _calorieGoal ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildMealForm() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Add New Meal", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: "Meal Name",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.fastfood),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _weightController,
              decoration: const InputDecoration(
                labelText: "Weight (g)",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.scale),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Checkbox(
                  value: _isCalorieInputEnabled,
                  onChanged: (value) {
                    setState(() {
                      _isCalorieInputEnabled = value!;
                    });
                  },
                ),
                const Text("Manually enter calories")
              ],
            ),
            if (_isCalorieInputEnabled) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _calorieController,
                decoration: const InputDecoration(
                  labelText: "Calories",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.local_fire_department),
                ),
                keyboardType: TextInputType.number,
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _timeController,
              decoration: const InputDecoration(
                labelText: "Time (HH:MM)",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.access_time),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _selectImage,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text("Add Photo"),
                ),
                if (_selectedImage != null) ...[
                  const SizedBox(width: 10),
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      image: DecorationImage(
                        image: FileImage(_selectedImage!),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _addMeal,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("Add Meal", style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMealLogs() {
    if (_isLoading) {
      return const Expanded(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_mealLogs.isEmpty) {
      return const Expanded(
        child: Center(
          child: Text(
            "No meals logged for this date.\nAdd your first meal!",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
      );
    }

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Meals for ${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}",
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              itemCount: _mealLogs.length,
              itemBuilder: (context, index) {
                final meal = _mealLogs[index];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 5),
                  child: ListTile(
                    leading: meal.image != null
                        ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        meal.image!,
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                      ),
                    )
                        : const CircleAvatar(
                      backgroundColor: Colors.green,
                      child: Icon(Icons.fastfood, color: Colors.white),
                    ),
                    title: Text(
                      meal.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      "Weight: ${meal.weight}g\nCalories: ${meal.calories}\nTime: ${_formatTime(meal.consumedTime)}",
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _showDeleteConfirmation(index),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(int index) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Meal'),
          content: const Text('Are you sure you want to delete this meal?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteMeal(index);
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Healthbook"),
        backgroundColor: Colors.green.shade700,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await supabase.auth.signOut();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const LoginPage()),
                    (route) => false,
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildCalendarSection(),
            const SizedBox(height: 20),
            _buildCalorieGoalBar(),
            const SizedBox(height: 20),
            _buildMealForm(),
            const SizedBox(height: 20),
            _buildMealLogs(),
          ],
        ),
      ),
    );
  }
}
