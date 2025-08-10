import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
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

class FoodApiService {
  static const String baseUrl = 'https://api.nal.usda.gov/fdc/v1';
  static const String apiKey = '9bTqtDZkbwnUprdSXmtiqMc9ikJX6NnYH70jAvE9'; // You can use DEMO_KEY for testing or get your own free API key

  static Future<List<FoodItem>> searchFood(String query) async {
    if (query.trim().isEmpty) return [];

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/foods/search?api_key=$apiKey&query=${Uri.encodeComponent(query)}&pageSize=10'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final foods = data['foods'] as List;

        return foods.map<FoodItem>((food) {
          // Extract calories per 100g from nutrients
          double caloriesPer100g = 0;
          if (food['foodNutrients'] != null) {
            for (var nutrient in food['foodNutrients']) {
              if (nutrient['nutrientName']?.toString().toLowerCase().contains('energy') == true ||
                  nutrient['nutrientNumber'] == 208) { // Energy nutrient number
                caloriesPer100g = (nutrient['value'] ?? 0).toDouble();
                break;
              }
            }
          }

          return FoodItem(
            name: food['description'] ?? 'Unknown Food',
            caloriesPer100g: caloriesPer100g,
            fdcId: food['fdcId']?.toString() ?? '',
          );
        }).where((item) => item.caloriesPer100g > 0).toList();
      } else {
        throw Exception('Failed to search foods: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error searching foods: $e');
    }
  }
}

class FoodItem {
  final String name;
  final double caloriesPer100g;
  final String fdcId;

  FoodItem({
    required this.name,
    required this.caloriesPer100g,
    required this.fdcId,
  });

  int calculateCalories(double weightInGrams) {
    return ((caloriesPer100g * weightInGrams) / 100).round();
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

  // New variables for API integration
  List<FoodItem> _foodSuggestions = [];
  FoodItem? _selectedFood;
  bool _isSearchingFood = false;
  int _calculatedCalories = 0;

  @override
  void initState() {
    super.initState();
    _timeController.text = _formatTime(DateTime.now());
    _loadMealsForDate();

    // Listen to food name changes for API search
    _nameController.addListener(_onFoodNameChanged);
    _weightController.addListener(_onWeightChanged);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _weightController.dispose();
    _calorieController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  void _onFoodNameChanged() {
    final query = _nameController.text.trim();
    if (query.isNotEmpty && query.length >= 3) {
      _searchFood(query);
    } else {
      setState(() {
        _foodSuggestions.clear();
        _selectedFood = null;
        _calculatedCalories = 0;
      });
    }
  }

  void _onWeightChanged() {
    if (_selectedFood != null) {
      final weight = double.tryParse(_weightController.text) ?? 0;
      if (weight > 0) {
        setState(() {
          _calculatedCalories = _selectedFood!.calculateCalories(weight);
        });
      } else {
        setState(() {
          _calculatedCalories = 0;
        });
      }
    }
  }

  Future<void> _searchFood(String query) async {
    setState(() {
      _isSearchingFood = true;
    });

    try {
      final foods = await FoodApiService.searchFood(query);
      if (mounted) {
        setState(() {
          _foodSuggestions = foods;
          _isSearchingFood = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearchingFood = false;
          _foodSuggestions.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error searching food: $e')),
        );
      }
    }
  }

  void _selectFood(FoodItem food) {
    setState(() {
      _selectedFood = food;
      _nameController.text = food.name;
      _foodSuggestions.clear();

      // Calculate calories if weight is already entered
      final weight = double.tryParse(_weightController.text) ?? 0;
      if (weight > 0) {
        _calculatedCalories = food.calculateCalories(weight);
      }
    });
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
    int calories;

    if (name.isEmpty || weight <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter valid meal name and weight')),
      );
      return;
    }

    // Use calculated calories if available, otherwise use manual input
    if (!_isCalorieInputEnabled && _calculatedCalories > 0) {
      calories = _calculatedCalories;
    } else if (_isCalorieInputEnabled) {
      calories = int.tryParse(_calorieController.text) ?? 0;
      if (calories <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter valid calories')),
        );
        return;
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not calculate calories automatically. Please enable manual calorie input.')),
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
      _selectedFood = null;
      _calculatedCalories = 0;
      _foodSuggestions.clear();

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

  Future<void> _selectImageFromSource(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
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

  void _showImageSourceDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            'Select Image Source',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: const Text('Choose how you want to add a photo to your meal:'),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _selectImageFromSource(ImageSource.camera);
              },
              icon: const Icon(Icons.camera_alt, color: Colors.blue),
              label: const Text(
                'Camera',
                style: TextStyle(color: Colors.blue, fontSize: 16),
              ),
            ),
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _selectImageFromSource(ImageSource.gallery);
              },
              icon: const Icon(Icons.photo_library, color: Colors.green),
              label: const Text(
                'Gallery',
                style: TextStyle(color: Colors.green, fontSize: 16),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _selectImage() async {
    _showImageSourceDialog();
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
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Add New Meal", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),

            // Food name field with suggestions
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: "Meal Name",
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.fastfood),
                    suffixIcon: _isSearchingFood
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: Padding(
                        padding: EdgeInsets.all(12.0),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                        : null,
                  ),
                ),

                // Food suggestions dropdown
                if (_foodSuggestions.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _foodSuggestions.length > 5 ? 5 : _foodSuggestions.length,
                      itemBuilder: (context, index) {
                        final food = _foodSuggestions[index];
                        return ListTile(
                          dense: true,
                          title: Text(
                            food.name,
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: Text(
                            '${food.caloriesPer100g.toStringAsFixed(1)} cal/100g',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                          onTap: () => _selectFood(food),
                        );
                      },
                    ),
                  ),
                ],
              ],
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

            // Show calculated calories
            if (_calculatedCalories > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calculate, color: Colors.green.shade700),
                    const SizedBox(width: 8),
                    Text(
                      "Estimated Calories: $_calculatedCalories kcal",
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],

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

            // Show selected image preview
            if (_selectedImage != null) ...[
              Row(
                children: [
                  const Text(
                    "Selected Photo:",
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green, width: 2),
                      image: DecorationImage(
                        image: FileImage(_selectedImage!),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _selectedImage = null;
                      });
                    },
                    icon: const Icon(Icons.close),
                    iconSize: 20,
                    color: Colors.red,
                    tooltip: 'Remove Photo',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.red.shade50,
                      shape: const CircleBorder(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
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
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_mealLogs.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(
          child: Text(
            "No meals logged for this date.\nAdd your first meal!",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          "Meals for ${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}",
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
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
      ],
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 100),
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
      bottomNavigationBar: BottomAppBar(
        height: 80,
        color: Colors.white,
        elevation: 8,
        shape: const CircularNotchedRectangle(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.home),
                iconSize: 28,
                color: Colors.green.shade700,
                tooltip: 'Home',
              ),
              IconButton(
                onPressed: () => _selectDate(context),
                icon: const Icon(Icons.calendar_today),
                iconSize: 28,
                color: Colors.grey.shade600,
                tooltip: 'Select Date',
              ),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.pink.shade400, Colors.orange.shade400],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.pink.shade200,
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: IconButton(
                  onPressed: _showImageSourceDialog,
                  icon: const Icon(Icons.camera_alt),
                  iconSize: 30,
                  color: Colors.white,
                  tooltip: 'Add Photo',
                ),
              ),
              IconButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Analytics feature coming soon!')),
                  );
                },
                icon: const Icon(Icons.analytics),
                iconSize: 28,
                color: Colors.grey.shade600,
                tooltip: 'Analytics',
              ),
              IconButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Profile feature coming soon!')),
                  );
                },
                icon: const Icon(Icons.person),
                iconSize: 28,
                color: Colors.grey.shade600,
                tooltip: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
