import '../../core/db/database_helper.dart';
import '../../core/utils/logger.dart';

/// Tracks locally-deployed AI model versions, integrity hashes,
/// and accuracy metrics.
///
/// Supports the federated learning workflow by recording when
/// models are updated from global aggregator broadcasts.
class ModelRegistry {
  ModelRegistry._();

  static final ModelRegistry instance = ModelRegistry._();
  static const _tag = 'ModelRegistry';

  /// Register initial bundled models on first launch.
  Future<void> registerBundledModels() async {
    final db = await DatabaseHelper.instance.database;
    final existing = await db.query('model_registry');

    if (existing.isNotEmpty) {
      Log.d('Models already registered (${existing.length})', tag: _tag);
      return;
    }

    final now = DateTime.now().toIso8601String();

    await db.insert('model_registry', {
      'id': 'model-oral-cancer-v1',
      'model_name': 'oral_cancer_efficientnetb0',
      'version': 1,
      'file_path': 'assets/models/oral_cancer_efficientnetb0.tflite',
      'hash': 'bundled-initial-hash',
      'accuracy': 0.9429,
      'updated_at': now,
      'source': 'bundled',
    });

    await db.insert('model_registry', {
      'id': 'model-tb-cough-v1',
      'model_name': 'tb_cough_classifier',
      'version': 1,
      'file_path': 'assets/models/tb_cough_classifier.tflite',
      'hash': 'bundled-initial-hash',
      'accuracy': 0.852,
      'updated_at': now,
      'source': 'bundled',
    });

    Log.i('Registered 2 bundled AI models', tag: _tag);
  }

  /// Get all registered models.
  Future<List<Map<String, dynamic>>> getAllModels() async {
    final db = await DatabaseHelper.instance.database;
    return db.query('model_registry', orderBy: 'model_name ASC');
  }

  /// Get a specific model by name.
  Future<Map<String, dynamic>?> getModel(String modelName) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'model_registry',
      where: 'model_name = ?',
      whereArgs: [modelName],
    );
    return rows.isNotEmpty ? rows.first : null;
  }
}
