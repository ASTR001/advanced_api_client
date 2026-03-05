import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:advanced_api_client/advanced_api_client.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  /// This bse URL for GET ALL, GET ONE, POST, PUT, PATCH, DELETE, LIST WITH PAGINATION
  // https://api.restful-api.dev
  /// This bse URL for LOGIN, REFRESH TOKEN, GET PROFILE, and OTHERS
  // https://api.escuelajs.co/api/v1

  await AdvancedApiClient.initialize(
    config: ApiConfig(
      baseUrl: "https://api.restful-api.dev",
      refreshConfig: RefreshConfig(
        path: "/auth/refresh-token",
        method: "POST",
        bodyBuilder: () async {
          // get latest user_id from SharedPreferences
          final prefs = await SharedPreferences.getInstance();
          final userId = prefs.getString("user_id") ?? "";
          return {
            "from_source": 1,
            "user_id": userId,
          };
        },
        tokenParser: (data) => data["data"]["token"],
      ),
      interceptors: [],
      enableLogs: kDebugMode,
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String result = "";
  bool isLoading = false;

  bool isUploading = false;
  double uploadProgress = 0.0;
  String? currentUploadId;

  void setLoading(bool value) {
    setState(() => isLoading = value);
  }

  // ===========================
  // RESTFUL API CRUD
  // ===========================

  Future<void> getAllObjects() async {
    setLoading(true);

    try {
      final response = await AdvancedApiClient.instance.get(
        endpoint: "/objects",
        withToken: false,
      );

      result = "All Objects:\n$response";
    } catch (e) {
      result = "Error:\n$e";
    }

    setLoading(false);
  }

  Future<void> getSingleObject() async {
    setLoading(true);

    try {
      final response = await AdvancedApiClient.instance.get(
        endpoint: "/objects/7",
        withToken: false,
      );

      result = "Single Object:\n$response";
    } catch (e) {
      result = "Error:\n$e";
    }

    setLoading(false);
  }

  Future<void> createObject() async {
    setLoading(true);

    try {
      final response = await AdvancedApiClient.instance.post(
        endpoint: "/objects",
        withToken: false,
        body: {
          "name": "Apple MacBook Pro 16",
          "data": {
            "year": 2019,
            "price": 1849.99,
            "CPU model": "Intel Core i9",
            "Hard disk size": "1 TB"
          }
        },
      );

      result = "Created:\n$response";
    } catch (e) {
      result = "Error:\n$e";
    }

    setLoading(false);
  }

  Future<void> updateObject() async {
    setLoading(true);

    try {
      final response = await AdvancedApiClient.instance.put(
        endpoint: "/objects/7",
        withToken: false,
        body: {
          "name": "Apple MacBook Pro 16",
          "data": {
            "year": 2019,
            "price": 2049.99,
            "CPU model": "Intel Core i9",
            "Hard disk size": "1 TB",
            "color": "silver"
          }
        },
      );

      result = "Updated:\n$response";
    } catch (e) {
      result = "Error:\n$e";
    }

    setLoading(false);
  }

  Future<void> patchObject() async {
    setLoading(true);

    try {
      final response = await AdvancedApiClient.instance.patch(
        endpoint: "/objects/7",
        withToken: false,
        body: {"name": "Apple MacBook Pro 16 (Updated Name)"},
      );

      result = "Patched:\n$response";
    } catch (e) {
      result = "Error:\n$e";
    }

    setLoading(false);
  }

  Future<void> deleteObject() async {
    setLoading(true);

    try {
      final response = await AdvancedApiClient.instance.delete(
        endpoint: "/objects/6",
        withToken: false,
      );

      result = "Deleted:\n$response";
    } catch (e) {
      result = "Error:\n$e";
    }

    setLoading(false);
  }

  // ===========================
  // LOGIN
  // ===========================

  Future<void> login() async {
    setLoading(true);

    try {
      final response = await AdvancedApiClient.instance.post(
        endpoint: "/auth/super_admin/login",
        withToken: false,
        body: {
          "email": "raju@gmail.com",
          "password": "SAdmin@123#",
          "from_source": 1
        },
      );

      final accessToken = response["data"]["token"];
      final userId = response["data"]["uuid"];

      // Save token to package
      await AdvancedApiClient.instance.tokenStorage.saveToken(accessToken);

      // Save userId in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("user_id", userId);

      result = "Login Success\nAccess Token Saved";
    } catch (e) {
      result = "Login Error:\n$e";
    }

    setLoading(false);
  }

  // ===========================
  // GET PROFILE
  // ===========================

  Future<void> getProfile() async {
    setLoading(true);

    try {
      final response = await AdvancedApiClient.instance.get(
        endpoint: "/auth/profile",
        withToken: true, // VERY IMPORTANT
      );

      result = "Profile:\n$response";
    } catch (e) {
      result = "Profile Error:\n$e";
    }

    setLoading(false);
  }

  // ===========================
  // SINGLE FILE UPLOAD
  // ===========================

  Future<void> uploadFile() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile == null) return;

    currentUploadId = AdvancedApiClient.instance.createUploadTask();

    setState(() {
      isUploading = true;
      uploadProgress = 0;
    });

    try {
      final response = await AdvancedApiClient.instance.uploadFile(
        endpoint: "/common/file-upload/image",
        files: {
          "image": [pickedFile.path],
        },
        uploadId: currentUploadId,
        onProgress: (sent, total) {
          setState(() {
            uploadProgress = total > 0 ? sent / total : 0;
          });
        },
      );

      setState(() {
        result = response["message"] ?? "Upload successful";
      });
    } catch (e) {
      setState(() {
        result = "Upload Error: $e";
      });
    } finally {
      setState(() {
        isUploading = false;
        uploadProgress = 0;
        currentUploadId = null;
      });
    }
  }

  // ===========================
  // MULTI FILE UPLOAD
  // ===========================

  Future<void> uploadMultipleImages() async {
    try {
      final picker = ImagePicker();
      final List<XFile> pickedFiles = await picker.pickMultiImage();

      if (pickedFiles.isEmpty) return;

      currentUploadId = AdvancedApiClient.instance.createUploadTask();

      setState(() {
        isUploading = true;
        uploadProgress = 0;
      });

      final filePaths = pickedFiles.map((e) => e.path).toList();

      final response = await AdvancedApiClient.instance.uploadFile(
        endpoint: "/common/file-upload/image",
        files: {
          "image": filePaths,
        },
        withToken: true,
        uploadId: currentUploadId,
        onProgress: (sent, total) {
          setState(() {
            uploadProgress = total > 0 ? sent / total : 0;
          });
        },
      );

      setState(() {
        result = response["message"] ?? "Upload successful";
      });
    } catch (e) {
      setState(() {
        result = "Upload Error:\n$e";
      });
    } finally {
      setState(() {
        isUploading = false;
        uploadProgress = 0;
        currentUploadId = null;
      });
    }
  }

  // ===========================
  // CANCEL UPLOAD
  // ===========================
  void cancelUpload() {
    if (currentUploadId != null) {
      AdvancedApiClient.instance.cancelUpload(currentUploadId!);
    }
  }

  // ===========================
  // LOGOUT (Clear Token)
  // ===========================

  Future<void> logout() async {
    setLoading(true);

    try {
      await AdvancedApiClient.instance.terminateSession();

      result = "Logged out successfully.\nToken cleared & requests cancelled.";
    } catch (e) {
      result = "Logout Error:\n$e";
    }

    setLoading(false);
  }

  // ===========================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Advanced API Client Demo")),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                    onPressed: getAllObjects, child: const Text("GET ALL")),
                ElevatedButton(
                    onPressed: getSingleObject, child: const Text("GET ONE")),
                ElevatedButton(
                    onPressed: createObject, child: const Text("POST")),
                ElevatedButton(
                    onPressed: updateObject, child: const Text("PUT")),
                ElevatedButton(
                    onPressed: patchObject, child: const Text("PATCH")),
                ElevatedButton(
                    onPressed: deleteObject, child: const Text("DELETE")),
                ElevatedButton(onPressed: login, child: const Text("LOGIN")),
                ElevatedButton(
                  onPressed: getProfile,
                  child: const Text("GET PROFILE"),
                ),
                ElevatedButton(
                    onPressed: uploadFile, child: const Text("UPLOAD")),
                ElevatedButton(
                  onPressed: uploadMultipleImages,
                  child: const Text("UPLOAD MULTIPLE"),
                ),
                ElevatedButton(
                  onPressed: logout,
                  child: const Text("LOGOUT"),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => PaginatedObjectsScreen()),
                    );
                  },
                  child: const Text("LIST WITH PAGINATION"),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (isLoading) const CircularProgressIndicator(),
            if (isUploading)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    LinearProgressIndicator(value: uploadProgress),
                    const SizedBox(height: 8),
                    Text("${(uploadProgress * 100).toStringAsFixed(0)} %"),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: cancelUpload,
                      child: const Text("Cancel Upload"),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                child: Text(result),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PaginatedObjectsScreen extends StatefulWidget {
  const PaginatedObjectsScreen({super.key});

  @override
  State<PaginatedObjectsScreen> createState() => _PaginatedObjectsScreenState();
}

class _PaginatedObjectsScreenState extends State<PaginatedObjectsScreen> {
  final ScrollController _scrollController = ScrollController();

  List<dynamic> objects = [];
  int currentPage = 0;
  bool isLoading = false;
  bool isFetchingMore = false;
  String error = "";

  @override
  void initState() {
    super.initState();
    fetchObjects(page: 0);

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 200 &&
          !isFetchingMore) {
        fetchObjects(page: currentPage + 1);
      }
    });
  }

  Future<void> fetchObjects({required int page}) async {
    const int limit = 10;

    if (page == 0) {
      setState(() {
        isLoading = true;
        error = "";
      });
    } else {
      setState(() {
        isFetchingMore = true;
      });
    }

    try {
      final data = await AdvancedApiClient.instance.get(
        endpoint: "/products",
        query: {"limit": limit, "offset": page},
        withToken: false,
      );

      // If response is a List directly
      final items =
          data is List ? data : (data["data"] as List<dynamic>? ?? []);

      setState(() {
        currentPage = page;

        if (page == 0) {
          objects = items;
        } else {
          objects.addAll(items);
        }
      });
    } catch (e) {
      setState(() {
        error = e.toString();
      });
    } finally {
      setState(() {
        isLoading = false;
        isFetchingMore = false;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Advanced API Client")),
      body: isLoading && objects.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : error.isNotEmpty
              ? Center(child: Text("Error: $error"))
              : RefreshIndicator(
                  onRefresh: () => fetchObjects(page: 0),
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: objects.length + 1, // +1 for bottom loader
                    itemBuilder: (context, index) {
                      if (index < objects.length) {
                        final obj = objects[index];
                        final title = obj["title"] ?? "No Title";
                        final price = obj["price"]?.toString() ?? "N/A";
                        final category =
                            obj["category"]?["name"] ?? "No Category";
                        final imageUrl =
                            (obj["images"] is List && obj["images"].isNotEmpty)
                                ? obj["images"][0]
                                : null;

                        return Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          child: ListTile(
                            leading: imageUrl != null
                                ? Image.network(
                                    imageUrl,
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover,
                                  )
                                : const Icon(Icons.image),
                            title: Text(title),
                            subtitle:
                                Text("Category: $category\nPrice: \$$price"),
                          ),
                        );
                      } else {
                        return isFetchingMore
                            ? const Padding(
                                padding: EdgeInsets.all(16),
                                child:
                                    Center(child: CircularProgressIndicator()),
                              )
                            : const SizedBox.shrink();
                      }
                    },
                  ),
                ),
    );
  }
}
