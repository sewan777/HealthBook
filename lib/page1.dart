import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:table_calendar/table_calendar.dart';

class HealthApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.green,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: HealthAppHome(),
    );
  }
}

class Meal {
  String name;
  double weight;
  int calories;
  DateTime consumedTime;
  File? image;

  Meal({
    required this.name,
    required this.weight,
    required this.calories,
    required this.consumedTime,
    this.image,
  });
}

class HealthAppHome extends StatefulWidget {
  @override
  _HealthAppHomeState createState() => _HealthAppHomeState();
}

class _HealthAppHomeState extends State<HealthAppHome> {
  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;
  DateTime _selectedDate = DateTime.now();
  late DateTime _focusedDay;
  int _calorieGoal = 2000;
  int _totalCaloriesConsumed = 0;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _calorieController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  List<Meal> _mealLogs = [];
  bool _isCalorieInputEnabled = false;

  @override
  void initState() {
    super.initState();
    _focusedDay = DateTime.now();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _weightController.dispose();
    _calorieController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  void _addMeal() {
    String name = _nameController.text;
    double weight = double.tryParse(_weightController.text) ?? 0;
    int calories = _isCalorieInputEnabled ? int.tryParse(_calorieController.text) ?? 0 : 0;
    DateTime consumedTime = DateTime.parse(_timeController.text);

    if (name.isNotEmpty && weight > 0 && (!_isCalorieInputEnabled || calories > 0)) {
      setState(() {
        _mealLogs.add(Meal(
          name: name,
          weight: weight,
          calories: calories,
          consumedTime: consumedTime,
          image: _selectedImage,
        ));
        _totalCaloriesConsumed += calories;
      });

      _nameController.clear();
      _weightController.clear();
      _calorieController.clear();
      _timeController.clear();
      _selectedImage = null;
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
    }
  }

  Widget _buildCalendarSection() {
    return GestureDetector(
      onTap: () => _selectDate(context),
      child: Container(
        padding: EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.green.shade700,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          "${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}",
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }


  Widget _buildCalorieGoalBar() {
    return Column(
      children: [
        Text("Calorie Goal: $_calorieGoal kcal", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
          value: _totalCaloriesConsumed / _calorieGoal,
          backgroundColor: Colors.grey.shade300,
          color: Colors.green,
          minHeight: 10,
        ),
        Text("Consumed: $_totalCaloriesConsumed kcal", style: TextStyle(fontSize: 16)),
      ],
    );
  }


  Widget _buildMealForm() {
    return Column(
      children: [
        TextField(controller: _nameController, decoration: InputDecoration(labelText: "Meal Name")),
        TextField(controller: _weightController, decoration: InputDecoration(labelText: "Weight (g)"), keyboardType: TextInputType.number),
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
            Text("Manually enter calories")
          ],
        ),
        if (_isCalorieInputEnabled)
          TextField(controller: _calorieController, decoration: InputDecoration(labelText: "Calories"), keyboardType: TextInputType.number),
        TextField(controller: _timeController, decoration: InputDecoration(labelText: "Time (HH:MM)")),
        ElevatedButton(onPressed: _addMeal, child: Text("Add Meal"))
      ],
    );
  }

  Widget _buildMealLogs() {
    return Expanded(
      child: ListView.builder(
        itemCount: _mealLogs.length,
        itemBuilder: (context, index) {
          final meal = _mealLogs[index];
          return Card(
            margin: EdgeInsets.symmetric(vertical: 5),
            child: ListTile(
              leading: meal.image != null
                  ? Image.file(meal.image!, width: 50, height: 50, fit: BoxFit.cover)
                  : Icon(Icons.fastfood),
              title: Text(meal.name),
              subtitle: Text("Weight: \${meal.weight}g\nCalories: \${meal.calories}\nTime: \${meal.consumedTime}"),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Healthbook"),
        backgroundColor: Colors.green.shade700,
      ),
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            _buildCalendarSection(),
            SizedBox(height: 20),
            _buildCalorieGoalBar(),
            SizedBox(height: 20),
            _buildMealForm(),
            SizedBox(height: 20),
            _buildMealLogs(),
          ],
        ),
      ),
    );
  }
}
