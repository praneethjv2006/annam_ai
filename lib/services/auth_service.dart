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

      // Store additional user data in database after successful signup
      if (result.isSignUpComplete) {
        // User is confirmed and signed up
        await _storeUserData(result.userId ?? email, username, email, name);
      } else if (result.nextStep.signUpStep == AuthSignUpStep.confirmSignUp) {
        // User needs to confirm email - store data temporarily
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('pending_userId', result.userId ?? email);
        await prefs.setString('pending_username', username);
        await prefs.setString('pending_email', email);
        await prefs.setString('pending_name', name);
      }
    } on AuthException catch (e) {
      throw Exception(e.message);
    } catch (e) {
      throw Exception('Sign up failed: ${e.toString()}');
    }
  }

  /// Store user data in database
  Future<void> _storeUserData(
    String userId,
    String username,
    String email,
    String name,
  ) async {
    try {
      await DatabaseService().createUser(
        userId: userId,
        username: username,
        email: email,
        name: name,
      );

      // Clear any pending data
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pending_userId');
      await prefs.remove('pending_username');
      await prefs.remove('pending_email');
      await prefs.remove('pending_name');
    } catch (e) {
      print('Error storing user data: $e');
      // Don't throw here as signup was successful
    }
  }

  /// Confirm sign up with verification code
  Future<void> confirmSignUp({
    required String username,
    required String confirmationCode,
  }) async {
    try {
      final result = await Amplify.Auth.confirmSignUp(
        username: username,
        confirmationCode: confirmationCode,
      );

      if (result.isSignUpComplete) {
        // Now store the user data in database
        final prefs = await SharedPreferences.getInstance();
        final userId = prefs.getString('pending_userId') ?? username;
        final pendingUsername = prefs.getString('pending_username') ?? '';
        final pendingEmail = prefs.getString('pending_email') ?? username;
        final pendingName = prefs.getString('pending_name') ?? '';

        await _storeUserData(
          userId,
          pendingUsername,
          pendingEmail,
          pendingName,
        );
      }
    } on AuthException catch (e) {
      throw Exception(e.message);
    } catch (e) {
      throw Exception('Confirmation failed: ${e.toString()}');
    }
  }

  /// Enhanced Sign In supporting email/phone
  Future<void> signIn({
    required String emailOrPhone,
    required String password,
  }) async {
    try {
      final result = await Amplify.Auth.signIn(
        username: emailOrPhone,
        password: password,
      );

      if (result.isSignedIn) {
        await _handleSuccessfulSignIn(emailOrPhone);
      } else if (result.nextStep.signInStep == AuthSignInStep.confirmSignUp) {
        throw Exception('Please verify your email address before signing in.');
      } else {
        throw Exception('Sign in incomplete. Please try again.');
      }
    } on AuthException catch (e) {
      throw Exception(e.message);
    } catch (e) {
      throw Exception('Sign in failed: ${e.toString()}');
    }
  }

  /// Handle successful sign in
  Future<void> _handleSuccessfulSignIn(String emailOrPhone) async {
    try {
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

        // Ensure user exists in database
        final userId = await getCurrentUserId();
        if (userId != null) {
          await DatabaseService().ensureUserExists(
            userId: userId,
            username: userAttributes['preferred_username'] ?? '',
            email: userAttributes['email'] ?? '',
            name: userAttributes['name'] ?? '',
          );

          // Update last login
          await DatabaseService().updateUserLastLogin();
        }
      }
    } catch (e) {
      print('Error handling successful sign in: $e');
      // Don't throw here as sign in was successful
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
