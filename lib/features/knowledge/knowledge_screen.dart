import 'package:flutter/material.dart';

import '../../core/services/knowledge_capsule.dart';

/// Offline Knowledge Capsule screen — searchable medical guidelines,
/// drug reference, patient education, and emergency contacts.
/// Works entirely offline — zero network required.
class KnowledgeScreen extends StatefulWidget {
  const KnowledgeScreen({super.key});

  @override
  State<KnowledgeScreen> createState() => _KnowledgeScreenState();
}

class _KnowledgeScreenState extends State<KnowledgeScreen>
    with SingleTickerProviderStateMixin {
  final _capsule = OfflineKnowledgeCapsule.instance;
  late TabController _tabs;
  final _searchController = TextEditingController();
  List<SearchResult> _searchResults = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch(String query) {
    if (query.trim().isEmpty) {
      setState(() { _searchResults = []; _isSearching = false; });
      return;
    }
    final results = _capsule.search(query);
    setState(() { _searchResults = results; _isSearching = true; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Knowledge Capsule'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(100),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearch,
                  decoration: InputDecoration(
                    hintText: 'Search guidelines, drugs, protocols...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _isSearching
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _onSearch('');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                ),
              ),
              TabBar(
                controller: _tabs,
                isScrollable: true,
                tabs: const [
                  Tab(text: 'Guidelines', icon: Icon(Icons.menu_book)),
                  Tab(text: 'Drugs', icon: Icon(Icons.medication)),
                  Tab(text: 'Patient Ed.', icon: Icon(Icons.school)),
                  Tab(text: 'Emergency', icon: Icon(Icons.emergency)),
                ],
              ),
            ],
          ),
        ),
      ),
      body: _isSearching ? _searchResultsView() : _tabsView(),
    );
  }

  Widget _searchResultsView() {
    if (_searchResults.isEmpty) {
      return const Center(
        child: Text('No results found', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _searchResults.length,
      itemBuilder: (ctx, i) {
        final r = _searchResults[i];
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.teal.shade100,
              child: Text(r.category[0], style: TextStyle(color: Colors.teal.shade800)),
            ),
            title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.snippet, maxLines: 2, overflow: TextOverflow.ellipsis),
                Text(r.source,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
              ],
            ),
            isThreeLine: true,
          ),
        );
      },
    );
  }

  Widget _tabsView() {
    return TabBarView(
      controller: _tabs,
      children: [
        _guidelinesTab(),
        _drugsTab(),
        _iecTab(),
        _emergencyTab(),
      ],
    );
  }

  // ────────────── GUIDELINES TAB ──────────────

  Widget _guidelinesTab() {
    final modules = _capsule.allModules;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final module in modules) ...[
          Card(
            color: Colors.teal.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.menu_book, color: Colors.teal),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(module.title,
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('Source: ${module.source}',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        Text('Updated: ${module.lastUpdated}',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          for (final section in module.sections)
            _expandableSection(section.title, section.content),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _expandableSection(String title, String content) {
    return Card(
      child: ExpansionTile(
        title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        childrenPadding: const EdgeInsets.all(16),
        children: [
          SelectableText(content, style: const TextStyle(fontSize: 13, height: 1.5)),
        ],
      ),
    );
  }

  // ──────────────── DRUGS TAB ────────────────

  Widget _drugsTab() {
    final drugs = OfflineKnowledgeCapsule.drugReference;
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: drugs.length,
      itemBuilder: (ctx, i) {
        final d = drugs[i];
        return Card(
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blue.shade100,
              child: const Icon(Icons.medication, color: Colors.blue, size: 20),
            ),
            title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(d.category, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            childrenPadding: const EdgeInsets.all(16),
            children: [
              _drugRow('Indication', d.indication),
              _drugRow('Dosage', d.dosage),
              _drugRow('Side Effects', d.sideEffects),
              _drugRow('Contraindications', d.contraindications),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: Colors.amber),
                    const SizedBox(width: 8),
                    Expanded(child: Text(d.note, style: const TextStyle(fontSize: 12))),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _drugRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.grey.shade700)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  // ──────────────── IEC TAB ────────────────

  Widget _iecTab() {
    final cards = OfflineKnowledgeCapsule.patientEducation;
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: cards.length,
      itemBuilder: (ctx, i) {
        final c = cards[i];
        final color = c.category == 'Oral Cancer'
            ? Colors.purple
            : c.category == 'Tuberculosis'
                ? Colors.orange
                : c.category == 'Prevention'
                    ? Colors.green
                    : Colors.blue;
        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: color.withValues(alpha: 0.3)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Chip(
                      label: Text(c.category,
                          style: TextStyle(fontSize: 11, color: color)),
                      backgroundColor: color.withValues(alpha: 0.1),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(c.title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                SelectableText(c.content,
                    style: const TextStyle(fontSize: 13, height: 1.5)),
              ],
            ),
          ),
        );
      },
    );
  }

  // ──────────────── EMERGENCY TAB ────────────────

  Widget _emergencyTab() {
    final contacts = OfflineKnowledgeCapsule.emergencyNumbers;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: Colors.red.shade50,
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.emergency, color: Colors.red, size: 32),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Emergency & Helpline Numbers\nAll numbers work across India',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final c in contacts)
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.red.shade100,
                child: const Icon(Icons.phone, color: Colors.red),
              ),
              title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: Text(c.number,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  )),
            ),
          ),
      ],
    );
  }
}
