import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:html/parser.dart'; // For HTML parsing
import 'package:charset_converter/charset_converter.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart'; // For file picker
import 'package:excel/excel.dart'; // For parsing .xlsx files
import 'dart:async'; // For timer
import 'package:permission_handler/permission_handler.dart'; // **For permissions**

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Naver Monitor',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const NaverMonitor(),
    );
  }
}

class NaverMonitor extends StatefulWidget {
  const NaverMonitor({super.key});

  @override
  State<NaverMonitor> createState() => _NaverMonitorState();
}

class _NaverMonitorState extends State<NaverMonitor> {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  List<Post> posts = []; // List to store fetched posts
  bool isLoading = false;
  bool isChecking = false; // To indicate if checking is ongoing
  Map<String, String> conditionTagMap = {}; // Map to store conditions and tags
  String feedbackMessage = ''; // For showing feedback message
  late Timer _timer; // Timer to refresh every 2-3 seconds

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
    requestPermission(); // Request notification permission** // **New change**
  }

  void _initializeNotifications() {
    const androidInitializationSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initializationSettings = InitializationSettings(
      android: androidInitializationSettings,
    );
    flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  Future<void> requestPermission() async {
    // **New change**
    var status = await Permission.notification.status;
    if (!status.isGranted) {
      await Permission.notification.request();
    }
  }

  Future<void> _fetchNaverNews() async {
    setState(() {
      isLoading = true;
      feedbackMessage = ''; // Clear feedback message
    });

    try {
      final response = await http.get(
        Uri.parse(
            'https://news.naver.com/main/list.naver?mode=LSD&mid=sec&sid1=001'),
        headers: {"User-Agent": "Mozilla/5.0"},
      );

      if (response.statusCode == 200) {
        // Detect and decode Korean character encoding
        final decodedBody =
            await CharsetConverter.decode("EUC-KR", response.bodyBytes);

        final document = parse(decodedBody);
        final items = document.querySelectorAll('ul.type06 li, ul.type07 li');

        final List<Post> fetchedPosts = items.map((item) {
          final title = item.querySelector('dt > a')?.text.trim() ?? '';
          final description = item.querySelector('dd')?.text.trim() ?? '';
          return Post(title: title, description: description);
        }).toList();

        bool matchFound = false;

        // Compare with conditions from the Excel file
        for (var post in fetchedPosts) {
          for (var condition in conditionTagMap.keys) {
            if (_evaluateCondition(condition, post)) {
              matchFound = true;
              final tag = conditionTagMap[condition];
              _showNotification(
                  // **New change**
                  'Keyword Found!',
                  '$tag\n${post.title}\n${post.description}');

              _showNotification(
                  'Keyword Found!', '$tag\n${post.title}\n${post.description}');

              setState(() {
                feedbackMessage =
                    'Match found for condition: $condition\nTag: $tag\nPost Title: ${post.title}\nPost Description: ${post.description}';
              });
              break; // Stop checking when a match is found
            }
          }
          if (matchFound) break; // Break the loop if a match is found
        }

        // Update feedback message if no match found
        if (!matchFound) {
          setState(() {
            feedbackMessage = 'No matches found. Refreshing...';
          });
        }

        setState(() {
          posts = fetchedPosts; // Update posts to display in ListView
        });
      } else {
        print("Failed to fetch data: ${response.statusCode}");
      }
    } catch (e) {
      print("Error fetching data: $e");
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  bool _evaluateCondition(String condition, Post post) {
    try {
      final logicPattern = RegExp(r'\b(AND|OR|[\(\)])\b');
      final tokens =
          condition.split(logicPattern).map((e) => e.trim()).toList();

      bool result = false;
      String operation = "OR"; // Default operation

      for (var token in tokens) {
        if (token.isEmpty) continue;
        if (token == 'AND' || token == 'OR') {
          operation = token;
        } else if (token.startsWith('(') && token.endsWith(')')) {
          final nested = token.substring(1, token.length - 1);
          final nestedResult = _evaluateCondition(nested, post);
          result = _applyLogic(result, nestedResult, operation);
        } else {
          final containsToken =
              post.title.contains(token) || post.description.contains(token);
          result = _applyLogic(result, containsToken, operation);
        }
      }
      return result;
    } catch (e) {
      print("Error evaluating condition: $condition");
      return false;
    }
  }

  bool _applyLogic(bool current, bool next, String operation) {
    if (operation == 'AND') {
      return current && next;
    } else {
      return current || next; // Default OR logic
    }
  }

  // Show local notification
  Future<void> _showNotification(String title, String body) async {
    // **New change**
    const androidDetails = AndroidNotificationDetails(
      'keyword_channel', // Channel ID
      'Keyword Alerts', // Channel Name
      importance:
          Importance.high, // High importance to show in the notification bar
      priority: Priority.high, // High priority for the notification
    );
    const notificationDetails = NotificationDetails(android: androidDetails);

    await flutterLocalNotificationsPlugin.show(
      0, // Notification ID
      title, // Title of the notification
      body, // Body of the notification
      notificationDetails, // Notification details
    );
  }

  // Select an Excel file
  Future<void> _selectExcelFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (result != null) {
      final path = result.files.single.path;
      if (path != null) {
        final bytes = await File(path).readAsBytes();
        var excel = Excel.decodeBytes(bytes);
        var sheet = excel.tables['Sheet1'];
        Map<String, String> conditionMap = {};
        for (var row in sheet?.rows ?? []) {
          if (row.length >= 2) {
            final condition = row[0]?.value.toString().trim();
            final tag = row[1]?.value.toString().trim();
            if (condition != null && tag != null) {
              conditionMap[condition] = tag;
            }
          }
        }
        setState(() {
          conditionTagMap = conditionMap; // Store condition-tag mapping
        });
      }
    }
  }

  // Start checking process every 2-3 seconds
  void _startChecking() {
    setState(() {
      isChecking = true;
    });
    // Start a timer that triggers every 3 seconds
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (isChecking) {
        _fetchNaverNews();
      } else {
        _timer.cancel(); // Stop checking if process is stopped
      }
    });
  }

  // Stop checking
  void _stopChecking() {
    setState(() {
      isChecking = false;
    });
    _timer.cancel();
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Naver News Checker"),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Excel file selection and control buttons in the top section
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                ElevatedButton(
                  onPressed: _selectExcelFile,
                  child: const Text('Select Excel File'),
                ),
                const SizedBox(height: 5),
                ElevatedButton(
                  onPressed: isChecking ? _stopChecking : _startChecking,
                  child: Text(isChecking ? 'Stop Checking' : 'Start Checking'),
                ),
                const SizedBox(height: 5),
              ],
            ),
          ),
          // Middle section: Post list, wrapped in a stateful widget for refreshing only this part
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : PostsListView(posts: posts),
          ),
          // Bottom section: Feedback message, wrapped in a stateful widget for refreshing only this part
          BottomFeedbackSection(feedbackMessage: feedbackMessage),
        ],
      ),
    );
  }
}

class PostsListView extends StatelessWidget {
  final List<Post> posts;

  const PostsListView({super.key, required this.posts});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: posts.length,
      itemBuilder: (context, index) {
        final post = posts[index];
        return ListTile(
          title: Text(post.title),
          subtitle: Text(post.description),
        );
      },
    );
  }
}

class BottomFeedbackSection extends StatelessWidget {
  final String feedbackMessage;

  const BottomFeedbackSection({super.key, required this.feedbackMessage});

  @override
  Widget build(BuildContext context) {
    print(feedbackMessage);
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.2),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      padding: const EdgeInsets.all(16.0),
      child: Text(
        feedbackMessage,
        style: const TextStyle(fontSize: 16.0),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class Post {
  final String title;
  final String description;

  Post({required this.title, required this.description});
}
