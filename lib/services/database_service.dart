import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_api/amplify_api.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:uuid/uuid.dart';

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
        return session.userPoolTokensResult.value.accessToken.raw;
      }
    } catch (e) {
      print('Error getting auth token: $e');
      throw Exception('Failed to get authentication token');
    }
    throw Exception('No valid authentication token found');
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

  /// Determine current season
  String _getCurrentSeason() {
    final now = DateTime.now();
    final m = now.month;
    if (m >= 3 && m <= 5) return 'Spring';
    if (m >= 6 && m <= 8) return 'Summer';
    if (m >= 9 && m <= 11) return 'Autumn';
    return 'Winter';
  }

  /// Create user with comprehensive data storage
  Future<void> createUser({
    required String userId,
    required String username,
    required String email,
    required String name,
  }) async {
    final now = DateTime.now().toIso8601String();
    final userData = {
      'userId': userId,
      'username': username,
      'email': email,
      'name': name,
      'createdAt': now,
      'updatedAt': now,
      'userType': 'farmer',
      'isActive': true,
      'profileComplete': false,
      'totalCropsUploaded': 0,
      'lastLoginAt': now,
      'location': null,
      'farmSize': null,
      'phoneNumber': null,
      'address': null,
    };

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/users'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode(userData),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        print('User created successfully in database');
      } else {
        print(
          'Failed to create user: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      print('Error creating user in database: $e');
    }
  }

  /// Ensure user exists in database (called during sign in)
  Future<void> ensureUserExists({
    required String userId,
    required String username,
    required String email,
    required String name,
  }) async {
    try {
      final existingUser = await getUserProfile();
      if (existingUser == null) {
        await createUser(
          userId: userId,
          username: username,
          email: email,
          name: name,
        );
      }
    } catch (e) {
      print('Error ensuring user exists: $e');
      await createUser(
        userId: userId,
        username: username,
        email: email,
        name: name,
      );
    }
  }

  /// Update user's last login timestamp
  Future<void> updateUserLastLogin() async {
    final token = await _getAuthToken();
    final userId = await _getCurrentUserId();
    if (userId == null) return;

    final now = DateTime.now().toIso8601String();
    final updateData = {'lastLoginAt': now, 'updatedAt': now};

    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/users/$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode(updateData),
      );
      if (response.statusCode == 200) {
        print('User last login updated successfully');
      } else {
        print('Failed to update last login: ${response.statusCode}');
      }
    } catch (e) {
      print('Error updating user last login: $e');
    }
  }

  /// Delete user profile
  Future<void> deleteUserProfile() async {
    final token = await _getAuthToken();
    final userId = await _getCurrentUserId();
    if (userId == null) return;

    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/users/$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        print('User profile deleted successfully');
      }
    } catch (e) {
      print('Error deleting user profile: $e');
    }
  }

  /// Save crop data with Amplify REST API (handles SigV4 & CORS)
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
    final now = DateTime.now().toIso8601String();
    final userId = await _getCurrentUserId();
    if (userId == null) throw Exception('User not authenticated');

    final username = await _getCurrentUsername() ?? 'unknown';
    final payload = {
      'cropId': _uuid.v4(),
      'userId': userId,
      'username': username,
      'farmerName': farmerName,
      'userType': userType,
      'location': location,
      'temperature': temperature,
      'cropType': cropType,
      'plantingDate': plantingDate,
      'imagePath': imagePath,
      'additionalNotes': additionalNotes ?? '',
      'createdAt': now,
      'updatedAt': now,
      'status': 'active',
      'analysisStatus': 'pending',
      'uploadedAt': now,
      'season': _getCurrentSeason(),
      'additionalData': additionalData ?? {},
    };

    try {
      final restOperation = Amplify.API.post(
        '/crops123456',
        apiName: 'annamai',
        body: HttpPayload.json(payload),
        headers: {'Content-Type': 'application/json'},
      );
      final response = await restOperation.response;

      if (response.statusCode == 200 || response.statusCode == 201) {
        print('Crop data saved via Amplify.API');
        await _updateUserCropCount(userId);
      } else {
        throw Exception(
          'Amplify.API failed: ${response.statusCode} – ${response.body}',
        );
      }
    } catch (e) {
      print('Error saving crop data: $e');
      rethrow;
    }
  }

  /// Update user's crop count
  Future<void> _updateUserCropCount(String userId) async {
    final token = await _getAuthToken();
    final now = DateTime.now().toIso8601String();
    final updateData = {
      'lastActivityAt': now,
      'updatedAt': now,
      'incrementCropCount': true,
    };

    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/users/$userId/increment-crop-count'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
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
    final token = await _getAuthToken();
    final userId = await _getCurrentUserId();
    if (userId == null) throw Exception('User not authenticated');

    var url = '$baseUrl/crops/user/$userId?limit=$limit';
    if (lastCropId != null) url += '&lastCropId=$lastCropId';

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List) {
          return List<Map<String, dynamic>>.from(data);
        } else if (data is Map && data.containsKey('crops')) {
          return List<Map<String, dynamic>>.from(data['crops']);
        }
        return [];
      } else {
        throw Exception(
          'Failed to fetch crops: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      print('Error fetching user crops: $e');
      rethrow;
    }
  }

  /// Get user profile data
  Future<Map<String, dynamic>?> getUserProfile() async {
    final token = await _getAuthToken();
    final userId = await _getCurrentUserId();
    if (userId == null) throw Exception('User not authenticated');

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/users/$userId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else if (response.statusCode == 404) {
        return null;
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
    final token = await _getAuthToken();
    final userId = await _getCurrentUserId();
    if (userId == null) throw Exception('User not authenticated');

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

    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/users/$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
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
      rethrow;
    }
  }

  /// Delete crop data
  Future<void> deleteCropData(String cropId) async {
    final token = await _getAuthToken();
    final userId = await _getCurrentUserId();
    if (userId == null) throw Exception('User not authenticated');

    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/crops/$cropId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
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
      rethrow;
    }
  }

  /// Get crop analytics/statistics
  Future<Map<String, dynamic>?> getCropAnalytics() async {
    final token = await _getAuthToken();
    final userId = await _getCurrentUserId();
    if (userId == null) throw Exception('User not authenticated');

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/crops/analytics/$userId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
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
