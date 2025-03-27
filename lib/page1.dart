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
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _calorieController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  List<Meal> _mealLogs = [];

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

  // Opens the camera and handles permissions
  Future<void> _openCamera() async {
    PermissionStatus status = await Permission.camera.request();
    if (status.isGranted) {
      final XFile? image = await _picker.pickImage(source: ImageSource.camera);
      if (image != null) {
        setState(() => _selectedImage = File(image.path));
      }
    } else {
      _handlePermissionDenied(status);
    }
  }

  // Opens the gallery and handles permissions
  Future<void> _openGallery() async {
    PermissionStatus status = await Permission.photos.request();
    if (status.isGranted) {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        setState(() => _selectedImage = File(image.path));
      }
    } else {
      _handlePermissionDenied(status);
    }
  }

  // Handles permission denial and provides user feedback
  void _handlePermissionDenied(PermissionStatus status) {
    if (status.isDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Permission is required for this feature")),
      );
    } else if (status.isPermanentlyDenied) {
      openAppSettings();
    }
  }

  // Add a new meal to the logs
  void _addMeal() {
    String name = _nameController.text;
    double weight = double.tryParse(_weightController.text) ?? 0;
    int calories = int.tryParse(_calorieController.text) ?? 0;
    DateTime consumedTime = DateTime.parse(_timeController.text);

    if (name.isNotEmpty && weight > 0 && calories > 0) {
      setState(() {
        _mealLogs.add(Meal(
          name: name,
          weight: weight,
          calories: calories,
          consumedTime: consumedTime,
          image: _selectedImage,
        ));
      });

      // Clear input fields
      _nameController.clear();
      _weightController.clear();
      _calorieController.clear();
      _timeController.clear();
      _selectedImage = null;
    }
  }

  // Displays the calendar for date selection
  void _showCalendarPopup() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          child: Padding(
            padding: EdgeInsets.all(15),
            child: TableCalendar(
              focusedDay: _focusedDay,
              selectedDayPredicate: (day) => isSameDay(day, _selectedDate),
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDate = selectedDay;
                  _focusedDay = focusedDay;
                });
                Navigator.pop(context);
              },
              firstDay: DateTime(2020),
              lastDay: DateTime(2100),
            ),
          ),
        );
      },
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
            _buildMealForm(),
            SizedBox(height: 20),
            _buildMealLogs(),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomAppBar(),
      floatingActionButton: _buildFloatingActionButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  // Calendar Section
  Widget _buildCalendarSection() {
    return GestureDetector(
      onTap: _showCalendarPopup,
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

  // Meal Input Form
  Widget _buildMealForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _nameController,
          decoration: InputDecoration(labelText: "Food Name"),
        ),
        TextField(
          controller: _weightController,
          decoration: InputDecoration(labelText: "Weight (g)"),
          keyboardType: TextInputType.number,
        ),
        TextField(
          controller: _calorieController,
          decoration: InputDecoration(labelText: "Calories"),
          keyboardType: TextInputType.number,
        ),
        TextField(
          controller: _timeController,
          decoration: InputDecoration(labelText: "Consumed Time (YYYY-MM-DD HH:MM)"),
          keyboardType: TextInputType.datetime,
        ),
        ElevatedButton(
          onPressed: _addMeal,
          child: Text("Add Meal"),
        ),
      ],
    );
  }

  // Display the list of meals logged by the user
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
              subtitle: Text("Weight: ${meal.weight}g\nCalories: ${meal.calories}\nTime: ${meal.consumedTime}"),
            ),
          );
        },
      ),
    );
  }

  // Bottom App Bar
  Widget _buildBottomAppBar() {
    return BottomAppBar(
      color: Colors.green.shade700,
      shape: CircularNotchedRectangle(),
      notchMargin: 6,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: Icon(Icons.photo_library, color: Colors.white),
            onPressed: _openGallery,
          ),
          SizedBox(width: 48),
        ],
      ),
    );
  }

  // Floating Action Button
  Widget _buildFloatingActionButton() {
    return FloatingActionButton(
      backgroundColor: Colors.green.shade700,
      child: Icon(Icons.camera_alt, color: Colors.white),
      onPressed: _openCamera,
    );
  }
}
