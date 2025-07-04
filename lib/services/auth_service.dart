import 'dart:convert';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  /// Enhanced Sign Up with proper backend integration
  Future<void> signUp({
    required String username,
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      final userAttributes = {
        AuthUserAttributeKey.email: email,
        AuthUserAttributeKey.name: name,
        AuthUserAttributeKey.preferredUsername: username,
      };

      final result = await Amplify.Auth.signUp(
        username: email, // Use email as username for Cognito
        password: password,
        options: SignUpOptions(userAttributes: userAttributes),
      );

      // Store additional user data in database
      if (result.isSignUpComplete ||
          result.nextStep.signUpStep == AuthSignUpStep.confirmSignUp) {
        await DatabaseService().createUser(
          userId: result.userId ?? email,
          username: username,
          email: email,
          name: name,
        );
      }
    } on AuthException catch (e) {
      throw Exception(e.message);
    } catch (e) {
      throw Exception('Sign up failed: ${e.toString()}');
    }
  }

  /// Enhanced Sign In supporting email/phone
  Future<void> signIn({
    required String emailOrPhone,
    required String password,
  }) async {
    try {
      final result = await Amplify.Auth.signIn(
        username: emailOrPhone, // Cognito will handle email/phone automatically
        password: password,
      );

      if (result.isSignedIn) {
        // Save login state locally
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isLoggedIn', true);
        await prefs.setString('loginIdentifier', emailOrPhone);

        // Get and save user attributes
        final userAttributes = await getCurrentUserAttributes();
        if (userAttributes != null) {
          await prefs.setString('userEmail', userAttributes['email'] ?? '');
          await prefs.setString('userName', userAttributes['name'] ?? '');
          await prefs.setString(
            'username',
            userAttributes['preferred_username'] ?? '',
          );
        }

        // Update last login in database
        await DatabaseService().updateUserLastLogin();
      }
    } on AuthException catch (e) {
      throw Exception(e.message);
    } catch (e) {
      throw Exception('Sign in failed: ${e.toString()}');
    }
  }

  /// Enhanced Sign Out
  Future<void> signOut() async {
    try {
      await Amplify.Auth.signOut();
      // Clear local storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } on AuthException catch (e) {
      throw Exception(e.message);
    } catch (e) {
      throw Exception('Sign out failed: ${e.toString()}');
    }
  }

  /// Check if user is signed in
  Future<bool> isSignedIn() async {
    try {
      final result = await Amplify.Auth.fetchAuthSession();
      return result.isSignedIn;
    } catch (e) {
      return false;
    }
  }

  /// Get current user ID
  Future<String?> getCurrentUserId() async {
    try {
      final user = await Amplify.Auth.getCurrentUser();
      return user.userId;
    } catch (e) {
      return null;
    }
  }

  /// Get current username
  Future<String?> getCurrentUsername() async {
    try {
      final user = await Amplify.Auth.getCurrentUser();
      return user.username;
    } catch (e) {
      // Fallback to local storage
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('username');
    }
  }

  /// Get current user attributes
  Future<Map<String, String>?> getCurrentUserAttributes() async {
    try {
      final attributes = await Amplify.Auth.fetchUserAttributes();
      return {
        for (var attr in attributes) attr.userAttributeKey.key: attr.value,
      };
    } catch (e) {
      return null;
    }
  }

  /// Get cached user info from local storage
  Future<Map<String, String?>> getCachedUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'username': prefs.getString('username'),
      'email': prefs.getString('userEmail'),
      'name': prefs.getString('userName'),
      'loginIdentifier': prefs.getString('loginIdentifier'),
    };
  }

  /// Update user attributes
  Future<void> updateUserAttributes({
    String? name,
    String? email,
    String? phone,
  }) async {
    try {
      final attributesToUpdate = <AuthUserAttribute>[];

      if (name != null) {
        attributesToUpdate.add(
          AuthUserAttribute(
            userAttributeKey: AuthUserAttributeKey.name,
            value: name,
          ),
        );
      }

      if (email != null) {
        attributesToUpdate.add(
          AuthUserAttribute(
            userAttributeKey: AuthUserAttributeKey.email,
            value: email,
          ),
        );
      }

      if (phone != null) {
        attributesToUpdate.add(
          AuthUserAttribute(
            userAttributeKey: AuthUserAttributeKey.phoneNumber,
            value: phone,
          ),
        );
      }

      if (attributesToUpdate.isNotEmpty) {
        await Amplify.Auth.updateUserAttributes(attributes: attributesToUpdate);
      }
    } on AuthException catch (e) {
      throw Exception(e.message);
    } catch (e) {
      throw Exception('Failed to update user attributes: ${e.toString()}');
    }
  }

  /// Confirm sign up with verification code
  Future<void> confirmSignUp({
    required String username,
    required String confirmationCode,
  }) async {
    try {
      await Amplify.Auth.confirmSignUp(
        username: username,
        confirmationCode: confirmationCode,
      );
    } on AuthException catch (e) {
      throw Exception(e.message);
    } catch (e) {
      throw Exception('Confirmation failed: ${e.toString()}');
    }
  }

  /// Reset password
  Future<void> resetPassword({required String username}) async {
    try {
      await Amplify.Auth.resetPassword(username: username);
    } on AuthException catch (e) {
      throw Exception(e.message);
    } catch (e) {
      throw Exception('Password reset failed: ${e.toString()}');
    }
  }
}
