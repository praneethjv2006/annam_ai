import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'dart:convert';
import 'camera_screen.dart';
import 'auth_screen.dart';
import 'dart:io';
import '../services/auth_service.dart';
import '../services/database_service.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _formKey = GlobalKey<FormState>();

  // Form controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _plantingDateController = TextEditingController();
  final TextEditingController _additionalNotesController =
      TextEditingController();

  // User info
  String _userName = '';
  String _userEmail = '';
  String _username = '';

  // User type selection
  String _selectedUserType = 'Farmer';

  // Location and weather data
  String _currentLocation = 'Detecting location...';
  double? _currentTemperature;
  Position? _currentPosition;
  bool _isLoadingLocation = false;
  bool _isLoadingWeather = false;

  // Form data
  String? _selectedCropType;
  File? _capturedImage;
  DateTime? _selectedPlantingDate;
  bool _isSubmitting = false;

  // Dropdown options
  final List<String> _cropTypes = [
    'Wheat',
    'Rice',
    'Maize',
    'Cotton',
    'Sugarcane',
    'Soybean',
    'Mustard',
    'Barley',
    'Gram',
    'Tomato',
    'Potato',
    'Onion',
    'Other',
  ];

  final List<String> _userTypes = [
    'Farmer',
    'Agricultural Expert',
    'Researcher',
    'Student',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _getCurrentLocationAndWeather();
  }

  /// Load user information
  Future<void> _loadUserInfo() async {
    try {
      final userInfo = await AuthService().getCachedUserInfo();
      final userAttributes = await AuthService().getCurrentUserAttributes();

      setState(() {
        _username = userInfo['username'] ?? '';
        _userEmail = userInfo['email'] ?? userAttributes?['email'] ?? '';
        _userName = userInfo['name'] ?? userAttributes?['name'] ?? 'User';
        _nameController.text = _userName;
      });
    } catch (e) {
      print('Error loading user info: $e');
    }
  }

  /// Get current location and weather
  Future<void> _getCurrentLocationAndWeather() async {
    setState(() {
      _isLoadingLocation = true;
      _isLoadingWeather = true;
    });

    try {
      // Request location permission
      var permission = await Permission.location.request();
      if (permission != PermissionStatus.granted) {
        setState(() {
          _currentLocation = 'Location permission denied';
          _isLoadingLocation = false;
          _isLoadingWeather = false;
        });
        return;
      }

      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _currentLocation = 'Location services are disabled';
          _isLoadingLocation = false;
          _isLoadingWeather = false;
        });
        return;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentPosition = position;
        _currentLocation =
            '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
        _isLoadingLocation = false;
      });

      // Get weather data
      await _getWeatherData(position.latitude, position.longitude);
    } catch (e) {
      setState(() {
        _currentLocation = 'Error getting location: $e';
        _isLoadingLocation = false;
        _isLoadingWeather = false;
      });
    }
  }

  /// Get weather data from API
  Future<void> _getWeatherData(double latitude, double longitude) async {
    setState(() => _isLoadingWeather = true);

    try {
      final apiKey = 'YOUR_OPENWEATHERMAP_API_KEY';
      final url =
          'https://api.openweathermap.org/data/2.5/weather?lat=$latitude&lon=$longitude&units=metric&appid=$apiKey';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _currentTemperature = data['main']['temp']?.toDouble();
          _isLoadingWeather = false;
        });
      } else {
        setState(() {
          _currentTemperature = null;
          _isLoadingWeather = false;
        });
      }
    } catch (e) {
      setState(() {
        _currentTemperature = null;
        _isLoadingWeather = false;
      });
    }
  }

  /// Open camera to capture image
  Future<void> _captureImage() async {
    try {
      final File? image = await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => CameraScreen()),
      );

      if (image != null) {
        setState(() {
          _capturedImage = image;
        });
      }
    } catch (e) {
      _showErrorDialog('Camera Error', 'Failed to capture image: $e');
    }
  }

  /// Select planting date
  Future<void> _selectPlantingDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            primaryColor: Color(0xFF2E7D32),
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: Color(0xFF2E7D32)),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedPlantingDate) {
      setState(() {
        _selectedPlantingDate = picked;
        _plantingDateController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  /// Submit form data
  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    if (_capturedImage == null) {
      _showErrorDialog(
        'Image Required',
        'Please capture an image of your crop.',
      );
      return;
    }

    if (_selectedPlantingDate == null) {
      _showErrorDialog('Date Required', 'Please select the planting date.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // Prepare crop data
      final cropData = {
        'farmerName': _nameController.text.trim(),
        'userType': _selectedUserType,
        'location': _currentLocation,
        'temperature': _currentTemperature,
        'cropType': _selectedCropType!,
        'plantingDate': _plantingDateController.text,
        'imagePath': _capturedImage!.path,
        'additionalNotes': _additionalNotesController.text.trim(),
        'gpsCoordinates': _currentPosition != null
            ? '${_currentPosition!.latitude},${_currentPosition!.longitude}'
            : null,
        'weather': _currentTemperature != null
            ? {'temperature': _currentTemperature, 'unit': 'Celsius'}
            : null,
      };

      // Save to database
      await DatabaseService().saveCropData(
        farmerName: _nameController.text.trim(),
        userType: _selectedUserType,
        location: _currentLocation,
        temperature: _currentTemperature,
        cropType: _selectedCropType!,
        plantingDate: _plantingDateController.text,
        imagePath: _capturedImage!.path,
        additionalNotes: _additionalNotesController.text.trim(),
        additionalData: {
          'gpsCoordinates': _currentPosition != null
              ? '${_currentPosition!.latitude},${_currentPosition!.longitude}'
              : null,
          'weather': _currentTemperature != null
              ? {'temperature': _currentTemperature, 'unit': 'Celsius'}
              : null,
          'deviceInfo': {
            'platform': 'mobile',
            'timestamp': DateTime.now().toIso8601String(),
          },
        },
      );

      _showSuccessDialog(
        'Data Submitted Successfully',
        'Your crop data has been saved for AI analysis.',
      );

      _resetForm();
    } catch (e) {
      _showErrorDialog('Submission Failed', 'Failed to submit data: $e');
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  /// Reset form data
  void _resetForm() {
    setState(() {
      _selectedCropType = null;
      _capturedImage = null;
      _selectedPlantingDate = null;
      _plantingDateController.clear();
      _additionalNotesController.clear();
    });
  }

  /// Show profile menu
  void _showProfileMenu() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildProfileBottomSheet(),
    );
  }

  /// Build profile bottom sheet
  Widget _buildProfileBottomSheet() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              children: [
                // Profile Header
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF2E7D32), Color(0xFF4CAF50)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: Icon(Icons.person, size: 40, color: Colors.white),
                ),
                SizedBox(height: 16),

                Text(
                  _userName.isNotEmpty ? _userName : 'User',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2E7D32),
                  ),
                ),
                SizedBox(height: 4),

                Text(
                  _userEmail.isNotEmpty ? _userEmail : 'No email',
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),

                if (_username.isNotEmpty) ...[
                  SizedBox(height: 4),
                  Text(
                    '@$_username',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                ],

                SizedBox(height: 32),

                // Profile Options
                _buildProfileOption(
                  icon: Icons.edit,
                  title: 'Edit Profile',
                  onTap: () {
                    Navigator.pop(context);
                    _showEditProfileDialog();
                  },
                ),
                SizedBox(height: 16),

                _buildProfileOption(
                  icon: Icons.history,
                  title: 'My Crops',
                  onTap: () {
                    Navigator.pop(context);
                    _showMyCropsDialog();
                  },
                ),
                SizedBox(height: 16),

                _buildProfileOption(
                  icon: Icons.settings,
                  title: 'Settings',
                  onTap: () {
                    Navigator.pop(context);
                    _showInfoDialog(
                      'Settings',
                      'Settings feature will be available soon.',
                    );
                  },
                ),
                SizedBox(height: 16),

                _buildProfileOption(
                  icon: Icons.help_outline,
                  title: 'Help & Support',
                  onTap: () {
                    Navigator.pop(context);
                    _showInfoDialog(
                      'Help & Support',
                      'For support, please contact: admin@annam.ai',
                    );
                  },
                ),
                SizedBox(height: 24),

                // Logout Button
                Container(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _logout(),
                    icon: Icon(Icons.logout, size: 20),
                    label: Text(
                      'LOGOUT',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                  ),
                ),
                SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build profile option
  Widget _buildProfileOption({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Color(0xFFE0E0E0)),
        ),
        child: Row(
          children: [
            Icon(icon, color: Color(0xFF2E7D32), size: 24),
            SizedBox(width: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.grey[800],
              ),
            ),
            Spacer(),
            Icon(Icons.arrow_forward_ios, color: Colors.grey[400], size: 16),
          ],
        ),
      ),
    );
  }

  /// Show edit profile dialog
  void _showEditProfileDialog() {
    final nameController = TextEditingController(text: _userName);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Edit Profile',
          style: TextStyle(
            color: Color(0xFF2E7D32),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'Full Name',
                prefixIcon: Icon(Icons.person, color: Color(0xFF2E7D32)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Color(0xFF2E7D32)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showInfoDialog(
                'Profile Update',
                'Profile update functionality will be available soon.',
              );
            },
            child: Text(
              'Save',
              style: TextStyle(
                color: Color(0xFF2E7D32),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Show my crops dialog
  void _showMyCropsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'My Crops',
          style: TextStyle(
            color: Color(0xFF2E7D32),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Crop history and analytics will be available soon.',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'OK',
              style: TextStyle(
                color: Color(0xFF2E7D32),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Logout function
  Future<void> _logout() async {
    try {
      await AuthService().signOut();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => AuthScreen()),
        (route) => false,
      );
    } catch (e) {
      _showErrorDialog('Logout Failed', 'Failed to logout. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.agriculture, size: 28),
            SizedBox(width: 10),
            Text(
              'ANNAM.AI',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ],
        ),
        backgroundColor: Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _getCurrentLocationAndWeather,
            tooltip: 'Refresh Location & Weather',
          ),
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: _showProfileMenu,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF4CAF50), Color(0xFF66BB6A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(Icons.person, color: Colors.white, size: 24),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Welcome Section
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF2E7D32), Color(0xFF4CAF50)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome back, ${_userName.isNotEmpty ? _userName.split(' ').first : 'User'}!',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Collect agricultural data for AI analysis',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 24),

              // Location and Weather Section
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Color(0xFFE0E0E0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Location & Weather',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2E7D32),
                      ),
                    ),
                    SizedBox(height: 12),

                    Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          color: Color(0xFF2E7D32),
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _isLoadingLocation
                                ? 'Getting location...'
                                : _currentLocation,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),

                    Row(
                      children: [
                        Icon(
                          Icons.thermostat,
                          color: Color(0xFF2E7D32),
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          _isLoadingWeather
                              ? 'Getting weather...'
                              : _currentTemperature != null
                              ? '${_currentTemperature!.toStringAsFixed(1)}°C'
                              : 'Weather unavailable',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: 24),

              // Farmer Information Section
              Text(
                'Farmer Information',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2E7D32),
                ),
              ),
              SizedBox(height: 16),

              // Name Field
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  prefixIcon: Icon(Icons.person, color: Color(0xFF2E7D32)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Color(0xFF2E7D32), width: 2),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your full name';
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),

              // User Type Dropdown
              DropdownButtonFormField<String>(
                value: _selectedUserType,
                decoration: InputDecoration(
                  labelText: 'User Type',
                  prefixIcon: Icon(Icons.work, color: Color(0xFF2E7D32)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Color(0xFF2E7D32), width: 2),
                  ),
                ),
                items: _userTypes.map((String type) {
                  return DropdownMenuItem<String>(
                    value: type,
                    child: Text(type),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedUserType = newValue!;
                  });
                },
              ),
              SizedBox(height: 24),

              // Crop Information Section
              Text(
                'Crop Information',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2E7D32),
                ),
              ),
              SizedBox(height: 16),

              // Crop Type Dropdown
              DropdownButtonFormField<String>(
                value: _selectedCropType,
                decoration: InputDecoration(
                  labelText: 'Crop Type',
                  prefixIcon: Icon(Icons.grass, color: Color(0xFF2E7D32)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Color(0xFF2E7D32), width: 2),
                  ),
                ),
                items: _cropTypes.map((String crop) {
                  return DropdownMenuItem<String>(
                    value: crop,
                    child: Text(crop),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedCropType = newValue;
                  });
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please select a crop type';
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),

              // Planting Date Field
              TextFormField(
                controller: _plantingDateController,
                decoration: InputDecoration(
                  labelText: 'Planting Date',
                  prefixIcon: Icon(
                    Icons.calendar_today,
                    color: Color(0xFF2E7D32),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(Icons.date_range, color: Color(0xFF2E7D32)),
                    onPressed: _selectPlantingDate,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Color(0xFF2E7D32), width: 2),
                  ),
                ),
                readOnly: true,
                onTap: _selectPlantingDate,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please select planting date';
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),

              // Additional Notes Field
              TextFormField(
                controller: _additionalNotesController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Additional Notes (Optional)',
                  prefixIcon: Icon(Icons.note, color: Color(0xFF2E7D32)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Color(0xFF2E7D32), width: 2),
                  ),
                ),
              ),
              SizedBox(height: 24),

              // Image Capture Section
              Text(
                'Crop Image',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2E7D32),
                ),
              ),
              SizedBox(height: 16),

              // Image Capture Button
              Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  color: Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _capturedImage != null
                        ? Color(0xFF2E7D32)
                        : Color(0xFFE0E0E0),
                    width: 2,
                  ),
                ),
                child: _capturedImage != null
                    ? Stack(
                        children: [
                          Container(
                            width: double.infinity,
                            height: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              image: DecorationImage(
                                image: FileImage(_capturedImage!),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: GestureDetector(
                              onTap: () =>
                                  setState(() => _capturedImage = null),
                              child: Container(
                                padding: EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : InkWell(
                        onTap: _captureImage,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.camera_alt,
                              size: 48,
                              color: Color(0xFF2E7D32),
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Tap to Capture Crop Image',
                              style: TextStyle(
                                fontSize: 16,
                                color: Color(0xFF2E7D32),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Required for AI analysis',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              SizedBox(height: 32),

              // Submit Button
              Container(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitForm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: _isSubmitting
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation(
                                  Colors.white,
                                ),
                                strokeWidth: 2,
                              ),
                            ),
                            SizedBox(width: 12),
                            Text(
                              'SUBMITTING...',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          'SUBMIT CROP DATA',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  /// Show error dialog
  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text(title, style: TextStyle(color: Colors.red, fontSize: 18)),
          ],
        ),
        content: Text(message, style: TextStyle(fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'OK',
              style: TextStyle(
                color: Color(0xFF2E7D32),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Show success dialog
  void _showSuccessDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              color: Color(0xFF2E7D32),
              size: 24,
            ),
            SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(color: Color(0xFF2E7D32), fontSize: 18),
            ),
          ],
        ),
        content: Text(message, style: TextStyle(fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'OK',
              style: TextStyle(
                color: Color(0xFF2E7D32),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Show info dialog
  void _showInfoDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.info_outline, color: Color(0xFF2E7D32), size: 24),
            SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(color: Color(0xFF2E7D32), fontSize: 18),
            ),
          ],
        ),
        content: Text(message, style: TextStyle(fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'OK',
              style: TextStyle(
                color: Color(0xFF2E7D32),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _plantingDateController.dispose();
    _additionalNotesController.dispose();
    super.dispose();
  }
}
