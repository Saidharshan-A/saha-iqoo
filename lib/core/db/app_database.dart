import 'dart:async';

/// Lightweight in-memory database engine for SAHA.
///
/// Mimics the sqflite [Database] API surface (insert, query, update,
/// delete, rawQuery, rawUpdate, execute, transaction) so that the
/// entire app can run on **Web / Chrome** for hackathon demos without
/// any native SQLite binary.
///
/// When building for Android, this can be swapped for real sqflite
/// by modifying [DatabaseHelper] to call `openDatabase()` instead.
///
/// Supports:
///   - CREATE TABLE / CREATE INDEX (registers table names)
///   - INSERT with optional conflict-replace
///   - SELECT with WHERE (=, !=, <, LIKE), AND / OR, ORDER BY, LIMIT
///   - UPDATE / DELETE with WHERE
///   - COUNT(*) and SUM() aggregate rawQuery
///   - Transactions (executed sequentially, no rollback)
class AppDatabase {
  AppDatabase();

  final Map<String, List<Map<String, dynamic>>> _tables = {};
  final Map<String, int> _autoIncrements = {};
  bool isOpen = true;

  // ── DDL ──────────────────────────────────────────────────────

  Future<void> execute(String sql) async {
    final upper = sql.toUpperCase().trim();
    if (upper.startsWith('CREATE TABLE')) {
      final match = RegExp(
        r'CREATE\s+TABLE\s+(\w+)',
        caseSensitive: false,
      ).firstMatch(sql);
      if (match != null) {
        _tables.putIfAbsent(match.group(1)!, () => []);
      }
    }
    // CREATE INDEX — no-op in memory
  }

  // ── INSERT ───────────────────────────────────────────────────

  Future<int> insert(
    String table,
    Map<String, dynamic> values, {
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    _tables.putIfAbsent(table, () => []);
    final row = Map<String, dynamic>.from(values);

    // Auto-increment when 'id' is absent or null (e.g. sync_queue)
    final hasId = row.containsKey('id') && row['id'] != null;

    if (!hasId) {
      _autoIncrements[table] = (_autoIncrements[table] ?? 0) + 1;
      row['id'] = _autoIncrements[table];
    }

    // REPLACE: remove existing row with same id first
    if (conflictAlgorithm == ConflictAlgorithm.replace) {
      _tables[table]!.removeWhere((r) => r['id'] == row['id']);
    }

    _tables[table]!.add(row);
    return row['id'] is int ? row['id'] as int : _tables[table]!.length;
  }

  // ── QUERY ────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> query(
    String table, {
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
  }) async {
    var results = List<Map<String, dynamic>>.from(
      _tables[table] ?? [],
    );

    if (where != null) {
      results = results
          .where((row) => _evaluateWhere(row, where, whereArgs))
          .toList();
    }

    if (orderBy != null) {
      results = _applyOrderBy(results, orderBy);
    }

    if (limit != null && limit < results.length) {
      results = results.sublist(0, limit);
    }

    // Return deep copies so callers can't mutate internal state
    return results.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  // ── UPDATE ───────────────────────────────────────────────────

  Future<int> update(
    String table,
    Map<String, dynamic> values, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    int count = 0;
    for (final row in _tables[table] ?? <Map<String, dynamic>>[]) {
      if (where == null || _evaluateWhere(row, where, whereArgs)) {
        row.addAll(values);
        count++;
      }
    }
    return count;
  }

  // ── DELETE ───────────────────────────────────────────────────

  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final rows = _tables[table] ?? [];
    final before = rows.length;
    if (where != null) {
      rows.removeWhere((row) => _evaluateWhere(row, where, whereArgs));
    } else {
      rows.clear();
    }
    return before - rows.length;
  }

  // ── RAW QUERIES ──────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    final upper = sql.toUpperCase().trim();

    // ── COUNT(*) ─────────────────────────────────────────────
    if (upper.contains('COUNT(*)')) {
      final tableMatch = RegExp(
        r'FROM\s+(\w+)',
        caseSensitive: false,
      ).firstMatch(sql);
      if (tableMatch != null) {
        final table = tableMatch.group(1)!;
        var rows = List<Map<String, dynamic>>.from(_tables[table] ?? []);

        final whereClause = _extractInlineWhere(sql);
        if (whereClause != null) {
          rows = rows
              .where((r) => _evaluateWhere(r, whereClause, arguments))
              .toList();
        }
        return [
          {'cnt': rows.length}
        ];
      }
    }

    // ── SUM(column) ──────────────────────────────────────────
    if (upper.contains('SUM(')) {
      final sumMatch = RegExp(
        r'SUM\((\w+)\)',
        caseSensitive: false,
      ).firstMatch(sql);
      final tableMatch = RegExp(
        r'FROM\s+(\w+)',
        caseSensitive: false,
      ).firstMatch(sql);
      if (sumMatch != null && tableMatch != null) {
        final col = sumMatch.group(1)!;
        final table = tableMatch.group(1)!;
        var rows = List<Map<String, dynamic>>.from(_tables[table] ?? []);

        final whereClause = _extractInlineWhere(sql);
        if (whereClause != null) {
          rows = rows
              .where((r) => _evaluateWhere(r, whereClause, arguments))
              .toList();
        }

        double total = 0;
        for (final row in rows) {
          total += (row[col] as num?)?.toDouble() ?? 0;
        }
        return [
          {'total': total}
        ];
      }
    }

    return [];
  }

  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) async {
    // Handle: UPDATE table SET col = col + N WHERE key = ?
    final match = RegExp(
      r'UPDATE\s+(\w+)\s+SET\s+(\w+)\s*=\s*\w+\s*\+\s*(\d+)\s+WHERE\s+(\w+)\s*=\s*\?',
      caseSensitive: false,
    ).firstMatch(sql);

    if (match != null && arguments != null && arguments.isNotEmpty) {
      final table = match.group(1)!;
      final col = match.group(2)!;
      final increment = int.parse(match.group(3)!);
      final whereCol = match.group(4)!;
      final whereVal = arguments[0];

      int count = 0;
      for (final row in _tables[table] ?? <Map<String, dynamic>>[]) {
        if (_matchValue(row[whereCol], whereVal)) {
          row[col] = ((row[col] as int?) ?? 0) + increment;
          count++;
        }
      }
      return count;
    }
    return 0;
  }

  // ── TRANSACTION ──────────────────────────────────────────────

  Future<T> transaction<T>(Future<T> Function(AppDatabase txn) action) async {
    // In-memory: execute sequentially (no rollback)
    return action(this);
  }

  Future<void> close() async {
    isOpen = false;
  }

  // ═══════════════════════════════════════════════════════════
  // ── WHERE EVALUATOR ──────────────────────────────────────
  // ═══════════════════════════════════════════════════════════

  /// Evaluates a WHERE clause against a single row.
  ///
  /// First substitutes all `?` placeholders with actual argument
  /// values (quoted for strings), then evaluates the expression
  /// tree supporting AND / OR / comparison operators.
  bool _evaluateWhere(
    Map<String, dynamic> row,
    String where,
    List<Object?>? args,
  ) {
    // Pre-substitute ? placeholders with actual values
    var processed = where;
    if (args != null) {
      for (final arg in args) {
        if (arg is String) {
          processed = processed.replaceFirst('?', "'$arg'");
        } else {
          processed = processed.replaceFirst('?', arg.toString());
        }
      }
    }
    return _evalExpr(row, processed);
  }

  bool _evalExpr(Map<String, dynamic> row, String expr) {
    // OR has lower precedence — split first
    final orParts = _splitByKeyword(expr, 'OR');
    if (orParts.length > 1) {
      return orParts.any((part) => _evalExpr(row, part.trim()));
    }

    // AND
    final andParts = _splitByKeyword(expr, 'AND');
    if (andParts.length > 1) {
      return andParts.every((part) => _evalExpr(row, part.trim()));
    }

    // Single condition
    return _evalCondition(row, expr.trim());
  }

  bool _evalCondition(Map<String, dynamic> row, String cond) {
    // column LIKE 'pattern'
    final likeMatch = RegExp(
      r"(\w+)\s+LIKE\s+'([^']*)'",
      caseSensitive: false,
    ).firstMatch(cond);
    if (likeMatch != null) {
      final col = likeMatch.group(1)!;
      final pattern = likeMatch.group(2)!;
      final value = row[col]?.toString() ?? '';
      final search = pattern.replaceAll('%', '');
      return value.toLowerCase().contains(search.toLowerCase());
    }

    // column != 'string'
    final neqStrMatch = RegExp(r"(\w+)\s*!=\s*'([^']*)'").firstMatch(cond);
    if (neqStrMatch != null) {
      final col = neqStrMatch.group(1)!;
      final val = neqStrMatch.group(2)!;
      return row[col]?.toString() != val;
    }

    // column = 'string'
    final eqStrMatch = RegExp(r"(\w+)\s*=\s*'([^']*)'").firstMatch(cond);
    if (eqStrMatch != null) {
      final col = eqStrMatch.group(1)!;
      final val = eqStrMatch.group(2)!;
      return row[col]?.toString() == val;
    }

    // column >= 'string'
    final geStrMatch = RegExp(r"(\w+)\s*>=\s*'([^']*)'").firstMatch(cond);
    if (geStrMatch != null) {
      final col = geStrMatch.group(1)!;
      final val = geStrMatch.group(2)!;
      return (row[col]?.toString() ?? '').compareTo(val) >= 0;
    }

    // column > 'string'
    final gtStrMatch = RegExp(r"(\w+)\s*>\s*'([^']*)'").firstMatch(cond);
    if (gtStrMatch != null) {
      final col = gtStrMatch.group(1)!;
      final val = gtStrMatch.group(2)!;
      return (row[col]?.toString() ?? '').compareTo(val) > 0;
    }

    // column <= 'string'
    final leStrMatch = RegExp(r"(\w+)\s*<=\s*'([^']*)'").firstMatch(cond);
    if (leStrMatch != null) {
      final col = leStrMatch.group(1)!;
      final val = leStrMatch.group(2)!;
      return (row[col]?.toString() ?? '').compareTo(val) <= 0;
    }

    // column < 'string'
    final ltStrMatch = RegExp(r"(\w+)\s*<\s*'([^']*)'").firstMatch(cond);
    if (ltStrMatch != null) {
      final col = ltStrMatch.group(1)!;
      final val = ltStrMatch.group(2)!;
      return (row[col]?.toString() ?? '').compareTo(val) < 0;
    }

    // column >= number
    final geNumMatch = RegExp(r'(\w+)\s*>=\s*(\d+(?:\.\d+)?)').firstMatch(cond);
    if (geNumMatch != null) {
      final col = geNumMatch.group(1)!;
      final val = num.parse(geNumMatch.group(2)!);
      final rowVal = row[col];
      if (rowVal is num) return rowVal >= val;
      return false;
    }

    // column > number
    final gtNumMatch = RegExp(r'(\w+)\s*>\s*(\d+(?:\.\d+)?)').firstMatch(cond);
    if (gtNumMatch != null) {
      final col = gtNumMatch.group(1)!;
      final val = num.parse(gtNumMatch.group(2)!);
      final rowVal = row[col];
      if (rowVal is num) return rowVal > val;
      return false;
    }

    // column <= number
    final leNumMatch = RegExp(r'(\w+)\s*<=\s*(\d+(?:\.\d+)?)').firstMatch(cond);
    if (leNumMatch != null) {
      final col = leNumMatch.group(1)!;
      final val = num.parse(leNumMatch.group(2)!);
      final rowVal = row[col];
      if (rowVal is num) return rowVal <= val;
      return false;
    }

    // column < number
    final ltMatch = RegExp(r'(\w+)\s*<\s*(\d+(?:\.\d+)?)').firstMatch(cond);
    if (ltMatch != null) {
      final col = ltMatch.group(1)!;
      final val = num.parse(ltMatch.group(2)!);
      final rowVal = row[col];
      if (rowVal is num) return rowVal < val;
      return false;
    }

    // column = number
    final eqNumMatch = RegExp(r'(\w+)\s*=\s*(\d+)$').firstMatch(cond);
    if (eqNumMatch != null) {
      final col = eqNumMatch.group(1)!;
      final val = int.parse(eqNumMatch.group(2)!);
      return _matchValue(row[col], val);
    }

    return true; // Unknown condition treated as pass
  }

  // ── Helpers ────────────────────────────────────────────────

  bool _matchValue(dynamic rowVal, dynamic argVal) {
    if (rowVal == argVal) return true;
    return rowVal?.toString() == argVal?.toString();
  }

  String? _extractInlineWhere(String sql) {
    final match = RegExp(
      r'WHERE\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(sql);
    return match?.group(1);
  }

  /// Splits an expression by a keyword (AND / OR), respecting
  /// that the keyword must be surrounded by whitespace.
  List<String> _splitByKeyword(String expr, String keyword) {
    return expr.split(
      RegExp('\\s+$keyword\\s+', caseSensitive: false),
    );
  }

  List<Map<String, dynamic>> _applyOrderBy(
    List<Map<String, dynamic>> rows,
    String orderBy,
  ) {
    final parts = orderBy.split(',').map((s) => s.trim()).toList();

    rows.sort((a, b) {
      for (final part in parts) {
        final tokens = part.split(RegExp(r'\s+'));
        final col = tokens[0];
        final desc = tokens.length > 1 && tokens[1].toUpperCase() == 'DESC';

        final va = a[col];
        final vb = b[col];

        int cmp;
        if (va == null && vb == null) {
          cmp = 0;
        } else if (va == null) {
          cmp = -1;
        } else if (vb == null) {
          cmp = 1;
        } else if (va is num && vb is num) {
          cmp = va.compareTo(vb);
        } else {
          cmp = va.toString().compareTo(vb.toString());
        }

        if (desc) cmp = -cmp;
        if (cmp != 0) return cmp;
      }
      return 0;
    });

    return rows;
  }
}

/// Conflict algorithm for INSERT operations.
enum ConflictAlgorithm {
  /// Roll back the current transaction on conflict.
  rollback,

  /// Abort the current statement on conflict.
  abort,

  /// Fail with an error on conflict.
  fail,

  /// Ignore the conflicting row.
  ignore,

  /// Replace the existing row with the new one.
  replace,
}
