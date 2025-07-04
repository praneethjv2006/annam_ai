import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  final String baseUrl =
      'https://d0e54366x3.execute-api.us-east-1.amazonaws.com/dev';
  final _uuid = Uuid();

  /// Get authentication token from Cognito
  Future<String> _getAuthToken() async {
    try {
      final session = await Amplify.Auth.fetchAuthSession();
      if (session is CognitoAuthSession) {
        final token = session.userPoolTokensResult.value.accessToken.raw;
        return token;
      }
    } catch (e) {
      print('Error getting auth token: $e');
      throw Exception('Failed to get authentication token');
    }
    throw Exception('No valid authentication token found');
  }

  /// Create user with comprehensive data storage
  Future<void> createUser({
    required String userId,
    required String username,
    required String email,
    required String name,
  }) async {
    try {
      final token = await _getAuthToken();
      final userData = {
        'userId': userId,
        'username': username,
        'email': email,
        'name': name,
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
        'userType': 'farmer',
        'isActive': true,
        'profileComplete': false,
        'totalCropsUploaded': 0,
        'lastLoginAt': DateTime.now().toIso8601String(),
        'location': null,
        'farmSize': null,
        'phoneNumber': null,
        'address': null,
      };

      final response = await http.post(
        Uri.parse('$baseUrl/users'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode(userData),
      );

      if (response.statusCode == 201) {
        print('User created successfully in database');
      } else {
        print(
          'Failed to create user: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      print('Error creating user in database: $e');
      // For development, we'll log errors but not throw to prevent sign-up failure
    }
  }

  /// Update user's last login timestamp
  Future<void> updateUserLastLogin() async {
    try {
      final token = await _getAuthToken();
      final userId = await _getCurrentUserId();

      if (userId != null) {
        final updateData = {
          'lastLoginAt': DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
        };

        final response = await http.patch(
          Uri.parse('$baseUrl/users/$userId'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: json.encode(updateData),
        );

        if (response.statusCode == 200) {
          print('User last login updated successfully');
        }
      }
    } catch (e) {
      print('Error updating user last login: $e');
    }
  }

  /// Save crop data with comprehensive information
  Future<void> saveCropData({
    required String farmerName,
    required String userType,
    required String location,
    required double? temperature,
    required String cropType,
    required String plantingDate,
    required String imagePath,
    String? additionalNotes,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      final token = await _getAuthToken();
      final userId = await _getCurrentUserId();
      final username = await _getCurrentUsername();

      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final cropData = {
        'cropId': _uuid.v4(),
        'userId': userId,
        'username': username ?? 'unknown',
        'farmerName': farmerName,
        'userType': userType,
        'location': location,
        'temperature': temperature,
        'cropType': cropType,
        'plantingDate': plantingDate,
        'imagePath': imagePath,
        'additionalNotes': additionalNotes ?? '',
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
        'status': 'active',
        'analysisStatus': 'pending',
        'uploadedAt': DateTime.now().toIso8601String(),
        'season': _getCurrentSeason(),
        'additionalData': additionalData ?? {},
      };

      final response = await http.post(
        Uri.parse('$baseUrl/crops'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode(cropData),
      );

      if (response.statusCode == 201) {
        print('Crop data saved successfully');
        // Update user's crop count
        await _updateUserCropCount(userId);
      } else {
        throw Exception(
          'Failed to save crop data: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      print('Error saving crop data: $e');
      throw Exception('Failed to save crop data: ${e.toString()}');
    }
  }

  /// Update user's crop count
  Future<void> _updateUserCropCount(String userId) async {
    try {
      final token = await _getAuthToken();
      final updateData = {
        'lastActivityAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
        'incrementCropCount': true,
      };

      final response = await http.patch(
        Uri.parse('$baseUrl/users/$userId/increment-crop-count'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode(updateData),
      );

      if (response.statusCode == 200) {
        print('User crop count updated successfully');
      }
    } catch (e) {
      print('Error updating user crop count: $e');
    }
  }

  /// Get user crops with pagination
  Future<List<Map<String, dynamic>>> getUserCrops({
    int limit = 20,
    String? lastCropId,
  }) async {
    try {
      final token = await _getAuthToken();
      final userId = await _getCurrentUserId();

      if (userId == null) {
        throw Exception('User not authenticated');
      }

      String url = '$baseUrl/crops/user/$userId?limit=$limit';
      if (lastCropId != null) {
        url += '&lastCropId=$lastCropId';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData is List) {
          return responseData.cast<Map<String, dynamic>>();
        } else if (responseData is Map && responseData.containsKey('crops')) {
          return List<Map<String, dynamic>>.from(responseData['crops']);
        }
        return [];
      } else {
        throw Exception(
          'Failed to fetch crops: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      print('Error fetching user crops: $e');
      throw Exception('Failed to fetch user crops: ${e.toString()}');
    }
  }

  /// Get user profile data
  Future<Map<String, dynamic>?> getUserProfile() async {
    try {
      final token = await _getAuthToken();
      final userId = await _getCurrentUserId();

      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final response = await http.get(
        Uri.parse('$baseUrl/users/$userId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 404) {
        return null; // User not found in database
      } else {
        throw Exception(
          'Failed to fetch user profile: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      print('Error fetching user profile: $e');
      return null;
    }
  }

  /// Update user profile
  Future<void> updateUserProfile({
    required String name,
    String? phone,
    String? address,
    String? farmSize,
    String? userType,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      final token = await _getAuthToken();
      final userId = await _getCurrentUserId();

      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final updateData = {
        'name': name,
        'phone': phone,
        'address': address,
        'farmSize': farmSize,
        'userType': userType ?? 'farmer',
        'updatedAt': DateTime.now().toIso8601String(),
        'profileComplete': true,
        'additionalData': additionalData ?? {},
      };

      final response = await http.patch(
        Uri.parse('$baseUrl/users/$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode(updateData),
      );

      if (response.statusCode == 200) {
        print('User profile updated successfully');
      } else {
        throw Exception(
          'Failed to update user profile: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      print('Error updating user profile: $e');
      throw Exception('Failed to update profile: ${e.toString()}');
    }
  }

  /// Get current season based on date
  String _getCurrentSeason() {
    final now = DateTime.now();
    final month = now.month;

    if (month >= 3 && month <= 5) {
      return 'Spring';
    } else if (month >= 6 && month <= 8) {
      return 'Summer';
    } else if (month >= 9 && month <= 11) {
      return 'Autumn';
    } else {
      return 'Winter';
    }
  }

  /// Get current user ID
  Future<String?> _getCurrentUserId() async {
    try {
      final user = await Amplify.Auth.getCurrentUser();
      return user.userId;
    } catch (e) {
      print('Error getting current user ID: $e');
      return null;
    }
  }

  /// Get current username
  Future<String?> _getCurrentUsername() async {
    try {
      final user = await Amplify.Auth.getCurrentUser();
      return user.username;
    } catch (e) {
      print('Error getting current username: $e');
      return null;
    }
  }

  /// Delete crop data
  Future<void> deleteCropData(String cropId) async {
    try {
      final token = await _getAuthToken();
      final userId = await _getCurrentUserId();

      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final response = await http.delete(
        Uri.parse('$baseUrl/crops/$cropId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        print('Crop data deleted successfully');
      } else {
        throw Exception(
          'Failed to delete crop data: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      print('Error deleting crop data: $e');
      throw Exception('Failed to delete crop data: ${e.toString()}');
    }
  }

  /// Get crop analytics/statistics
  Future<Map<String, dynamic>?> getCropAnalytics() async {
    try {
      final token = await _getAuthToken();
      final userId = await _getCurrentUserId();

      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final response = await http.get(
        Uri.parse('$baseUrl/crops/analytics/$userId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception(
          'Failed to fetch analytics: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      print('Error fetching crop analytics: $e');
      return null;
    }
  }
}
