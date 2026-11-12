import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../data/lathund_content.dart';
import '../providers/family_provider.dart';
import '../utils/layout.dart';
import '../utils/quick_add_parser.dart';

class LathundPage extends StatefulWidget {
  const LathundPage({super.key});

  @override
  State<LathundPage> createState() => _LathundPageState();
}

class _LathundPageState extends State<LathundPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _normalize(String s) {
    return foldName(s.toLowerCase().trim());
  }

  bool _matchesQuery(LathundEntry entry, String query) {
    final q = _normalize(query);
    if (q.isEmpty) return true;
    final f = _normalize(entry.fraga);
    final s = _normalize(entry.svar);
    final h = _normalize(entry.finnsHar);
    return f.contains(q) || s.contains(q) || h.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final dayColor = AppTheme.getDayAccentColor();
    final provider = context.watch<FamilyProvider>();
    final isParent = provider.currentUser?.isParent ?? false;
    final maxW = WindowSize.of(context).isExpanded
        ? WindowSize.settingsMaxWidth
        : 430.0;

    // Filtrera poster efter användarens roll
    final filteredCategories = <LathundKategori>[];
    for (final kat in lathundInnehall) {
      final validEntries = kat.poster.where((e) {
        if (!isParent && e.endastForaldrar) return false;
        return true;
      }).toList();

      if (validEntries.isNotEmpty) {
        filteredCategories.add(LathundKategori(
          emoji: kat.emoji,
          titel: kat.titel,
          poster: validEntries,
        ));
      }
    }

    // Sökresultat (platt lista)
    final flatSearchResults = <LathundEntry>[];
    if (_searchQuery.trim().isNotEmpty) {
      for (final kat in filteredCategories) {
        for (final entry in kat.poster) {
          if (_matchesQuery(entry, _searchQuery)) {
            flatSearchResults.add(entry);
          }
        }
      }
    }

    final isSearching = _searchQuery.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          color: AppTheme.getTextColor(),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Lathund 📖',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: Container(
            decoration: AppTheme.getBackground(),
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Så funkar La Familia',
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _buildSearchBar(dayColor),
                      ],
                    ),
                  ),
                ),
                if (isSearching)
                  if (flatSearchResults.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                        child: Center(
                          child: Column(
                            children: [
                              const Text('🔍', style: TextStyle(fontSize: 36)),
                              const SizedBox(height: 12),
                              Text(
                                'Inga träffar på "$_searchQuery"',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Prova att söka med ett annat ord.',
                                style: TextStyle(fontSize: 14, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final entry = flatSearchResults[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            child: _buildEntryCard(entry, dayColor),
                          );
                        },
                        childCount: flatSearchResults.length,
                      ),
                    )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final kat = filteredCategories[index];
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: _buildCategoryTile(kat, dayColor),
                        );
                      },
                      childCount: filteredCategories.length,
                    ),
                  ),
                SliverToBoxAdapter(
                  child: SizedBox(height: navSafeBottom(context).bottom + 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(Color dayColor) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (val) {
          setState(() {
            _searchQuery = val;
          });
        },
        decoration: InputDecoration(
          hintText: 'Sök i lathunden (t.ex. röst, middag, schema)…',
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
          prefixIcon: const Icon(Icons.search_rounded, color: Colors.grey),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, color: Colors.grey),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        ),
      ),
    );
  }

  Widget _buildCategoryTile(LathundKategori kat, Color dayColor) {
    return Container(
      decoration: AppTheme.cardDecoration(radius: 16),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          leading: Text(
            kat.emoji,
            style: const TextStyle(fontSize: 22),
          ),
          title: Text(
            kat.titel,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Text(
            '${kat.poster.length} ${kat.poster.length == 1 ? 'post' : 'poster'}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: kat.poster.map((e) => _buildEntryCard(e, dayColor)).toList(),
        ),
      ),
    );
  }

  Widget _buildEntryCard(LathundEntry entry, Color dayColor) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.emoji,
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.fraga,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1C2833),
                  ),
                ),
              ),
              if (entry.endastForaldrar) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: dayColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Föräldrar',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: dayColor,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            entry.svar,
            style: const TextStyle(
              fontSize: 15,
              height: 1.4,
              color: Color(0xFF2C3E50),
            ),
          ),
          if (entry.steg.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < entry.steg.length; i++)
                    Padding(
                      padding: EdgeInsets.only(bottom: i < entry.steg.length - 1 ? 4 : 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${i + 1}. ',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: dayColor,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              entry.steg[i],
                              style: const TextStyle(fontSize: 14, height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.place_outlined, size: 14, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Finns här: ${entry.finnsHar}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
