import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uni_links/uni_links.dart';

enum Provider { google, facebook }

extension ProviderExt on Provider {
  String get name {
    switch (this) {
      case Provider.google:
        return "Google";
      case Provider.facebook:
        return "Facebook";
        break;
      default:
        throw "Provider null!";
    }
  }
}

class UserCognito {
  final String idToken;
  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final String tokenType;

  UserCognito._(
      {this.idToken,
      this.accessToken,
      this.refreshToken,
      this.expiresIn,
      this.tokenType});

  factory UserCognito.fromJson(Map<String, dynamic> json) => UserCognito._(
      idToken: json['id_token'],
      accessToken: json['access_token'],
      refreshToken: json['refresh_token'],
      expiresIn: json['expires_in'],
      tokenType: json['token_type']);

  Map<String, dynamic> toJson() => {
        "id_token": idToken,
        "access_token": accessToken,
        "refresh_token": refreshToken,
        "expires_in": expiresIn,
        "token_type": tokenType
      };
  @override
  String toString() =>
      "idToken: $idToken\nrefreshToken:$refreshToken\nexpiresIn:$expiresIn";
}

class Auth {
  final String app;
  final String client;
  final String redirectURL;
  final _client = Dio();

  Auth({this.app, this.client, this.redirectURL}) {
    _client.options.baseUrl = "https://$app/oauth2";
    _client.options.contentType = Headers.formUrlEncodedContentType;
  }
  Future<UserCognito> login({Provider provider}) async {
    final code = await _getCode(provider: provider);
    final token = await _getToken(code);
    final user = UserCognito.fromJson(token);
    _saveSession(user);
    return UserCognito.fromJson(token);
  }

  Future<Map<String, dynamic>> _getToken(String code) async {
    try {
      final response = await _client.post("/token", data: {
        "grant_type": "authorization_code",
        "client_id": client,
        "code": code,
        "redirect_uri": redirectURL
      });
      return response.data;
    } catch (e) {
      throw e;
    }
  }

  Future<String> _getCode({Provider provider}) async {
    final buffer = StringBuffer();
    buffer.write("https://$app/oauth2/authorize?");
    final map = {
      "identity_provider": provider.name,
      "redirect_uri": redirectURL,
      "response_type": "CODE",
      "client_id": client,
      "scope":
          "aws.cognito.signin.user.admin%20email%20openid%20phone%20profile"
    };
    map.forEach((key, value) {
      buffer.write("$key=$value&");
    });
    final url = buffer.toString().substring(0, buffer.toString().length - 1);

    if (await canLaunch(url)) {
      await launch(url);
    } else {
      throw 'Could not launch $url';
    }

    var stream = getUriLinksStream();
    await for (var item in stream) {
      if (stream != null) {
        return item.queryParameters['code'];
      }
    }
  }

  Future<void> _saveSession(UserCognito user) async {
    final storage = await SharedPreferences.getInstance();
    await storage.setString("cognito_aws", jsonEncode(user.toJson()));
  }

  Future<UserCognito> currentUser() async {
    final storage = await SharedPreferences.getInstance();
    final user = await storage.get("cognito_aws");
    if (user != null) {
      return UserCognito.fromJson(jsonDecode(user));
    } else {
      return null;
    }
  }

  Future<void> logout() async {
    final storage = await SharedPreferences.getInstance();
    await storage.remove("cognito_aws");
  }

  Future<String> refreshToken() async {
    final user = await currentUser();
    try {
      final response = await _client.post("/token", data: {
        "grant_type": "refresh_token",
        "client_id": client,
        "code": user.refreshToken,
      });
      final newUser = UserCognito.fromJson(response.data);
      await _saveSession(newUser);
      return newUser.idToken;
    } catch (e) {
      throw e;
    }
  }
}
