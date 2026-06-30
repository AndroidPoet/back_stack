import 'dart:convert';

import 'package:back_stack/back_stack.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────────────────────
// A real Pokédex on PokeAPI, navigated by back_stack.
//
// Navigation is the whole point of this file and it's ~6 lines: a `NavStack` of
// two typed destinations, rendered by `NavListDetail` so the SAME stack is a
// grid+detail on a wide window and a grid → pushed detail (with a Hero
// shared-element transition on the sprite) on a phone. You write it once.
// ─────────────────────────────────────────────────────────────────────────────

sealed class PokeKey extends NavKey {
  const PokeKey();
}

class Pokedex extends PokeKey {
  const Pokedex();
}

class PokemonView extends PokeKey {
  const PokemonView(this.id, this.name);
  final int id;
  final String name;
}

void main() => runApp(const PokedexApp());

class PokedexApp extends StatefulWidget {
  const PokedexApp({super.key});
  @override
  State<PokedexApp> createState() => _PokedexAppState();
}

class _PokedexAppState extends State<PokedexApp> {
  // THE STACK. Start on the grid.
  final stack = NavStack<PokeKey>.of(const Pokedex());

  @override
  void dispose() {
    stack.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'back_stack Pokédex',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF4F46E5), // calm indigo app accent
        useMaterial3: true,
      ),
      // ONE adaptive display over the ONE stack. That's the app shell.
      home: NavListDetail<PokeKey>(
        stack: stack,
        breakpoint: 720,
        listPaneWidth: 420,
        isDetail: (key) => key is PokemonView,
        list: (context, key) => const GridScreen(),
        detail: (context, key) => DetailScreen(pokemon: key as PokemonView),
        placeholder: (context) => const _Hint(),
      ),
    );
  }
}

// ── Data ─────────────────────────────────────────────────────────────────────
String artwork(int id) =>
    'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/'
    'other/official-artwork/$id.png';

class Mon {
  const Mon(this.id, this.name);
  final int id;
  final String name;
}

/// First 151. Cached after the first fetch so tab/back doesn't refetch.
Future<List<Mon>>? _listCache;
Future<List<Mon>> fetchList() => _listCache ??= () async {
  final res = await http.get(
    Uri.parse('https://pokeapi.co/api/v2/pokemon?limit=151'),
  );
  final results = (jsonDecode(res.body) as Map)['results'] as List;
  return [
    for (var i = 0; i < results.length; i++)
      Mon(i + 1, (results[i] as Map)['name'] as String),
  ];
}();

Future<Map<String, dynamic>> fetchDetail(int id) async {
  final res = await http.get(
    Uri.parse('https://pokeapi.co/api/v2/pokemon/$id'),
  );
  return jsonDecode(res.body) as Map<String, dynamic>;
}

// ── Grid (list pane / phone home) ────────────────────────────────────────────
class GridScreen extends StatelessWidget {
  const GridScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final stack = BackStack.of<PokeKey>(context, listen: true);
    final openId = stack.current is PokemonView
        ? (stack.current as PokemonView).id
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Pokédex')),
      body: FutureBuilder<List<Mon>>(
        future: fetchList(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data!;
          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              childAspectRatio: 0.86,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final mon = list[i];
              return _MonCard(
                mon: mon,
                selected: mon.id == openId,
                // Navigate = push a typed value onto the list.
                onTap: () => BackStack.of<PokeKey>(
                  context,
                ).push(PokemonView(mon.id, mon.name)),
              );
            },
          );
        },
      ),
    );
  }
}

class _MonCard extends StatelessWidget {
  const _MonCard({
    required this.mon,
    required this.selected,
    required this.onTap,
  });
  final Mon mon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: selected ? 4 : 0,
      color: selected
          ? const Color(0xFFEAE9FB)
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: selected
            ? const BorderSide(color: Color(0xFF4F46E5), width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            Expanded(
              child: _Sprite(id: mon.id, hero: !_wide(context)),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                '#${mon.id.toString().padLeft(3, '0')}  ${_cap(mon.name)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Detail (detail pane / phone pushed page) ─────────────────────────────────
class DetailScreen extends StatelessWidget {
  const DetailScreen({super.key, required this.pokemon});
  final PokemonView pokemon;

  @override
  Widget build(BuildContext context) {
    final canPop = BackStack.of<PokeKey>(context).canPop;
    return Scaffold(
      appBar: AppBar(
        title: Text(_cap(pokemon.name)),
        leading: canPop
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => BackStack.of<PokeKey>(context).pop(),
              )
            : null,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: fetchDetail(pokemon.id),
        builder: (context, snap) {
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              SizedBox(
                height: 220,
                child: _Sprite(id: pokemon.id, hero: !_wide(context)),
              ),
              Center(
                child: Text(
                  '#${pokemon.id.toString().padLeft(3, '0')}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 16),
              if (!snap.hasData)
                const Center(child: CircularProgressIndicator())
              else ...[
                Wrap(
                  spacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final t in _types(snap.data!))
                      Chip(
                        label: Text(
                          _cap(t),
                          style: const TextStyle(color: Colors.white),
                        ),
                        backgroundColor: _typeColor(t),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                for (final s in _stats(snap.data!))
                  _StatBar(label: s.$1, value: s.$2),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _StatBar extends StatelessWidget {
  const _StatBar({required this.label, required this.value});
  final String label;
  final int value;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text(label)),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (value / 180).clamp(0.0, 1.0),
                minHeight: 10,
                backgroundColor: const Color(0xFFE8E8F0),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(width: 32, child: Text('$value', textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}

// ── Shared widgets ───────────────────────────────────────────────────────────
class _Sprite extends StatelessWidget {
  const _Sprite({required this.id, required this.hero});
  final int id;
  final bool hero;

  @override
  Widget build(BuildContext context) {
    final image = Image.network(
      artwork(id),
      fit: BoxFit.contain,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      errorBuilder: (context, _, _) =>
          const Icon(Icons.catching_pokemon, size: 48, color: Colors.grey),
    );
    // Hero only in single-pane mode: in two-pane the same sprite is on screen
    // twice (grid + detail), which would collide on one Hero tag.
    return hero ? Hero(tag: 'mon-$id', child: image) : image;
  }
}

class _Hint extends StatelessWidget {
  const _Hint();
  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Color(0xFFF6F6FB),
    child: Center(
      child: Text('Choose a Pokémon  ›', style: TextStyle(color: Colors.grey)),
    ),
  );
}

// ── helpers ──────────────────────────────────────────────────────────────────
bool _wide(BuildContext context) => MediaQuery.sizeOf(context).width >= 720;

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

List<String> _types(Map<String, dynamic> d) => [
  for (final t in (d['types'] as List)) (t['type'] as Map)['name'] as String,
];

List<(String, int)> _stats(Map<String, dynamic> d) => [
  for (final s in (d['stats'] as List))
    (
      _cap(((s['stat'] as Map)['name'] as String).replaceAll('-', ' ')),
      s['base_stat'] as int,
    ),
];

Color _typeColor(String type) => switch (type) {
  'grass' => const Color(0xFF4CAF50),
  'poison' => const Color(0xFF9C5BD0),
  'fire' => const Color(0xFFEB7B34),
  'water' => const Color(0xFF3B82F6),
  'electric' => const Color(0xFFE3B505),
  'bug' => const Color(0xFF8FB91D),
  'normal' => const Color(0xFF9AA0A6),
  'flying' => const Color(0xFF6FA8DC),
  'ground' => const Color(0xFFB8865B),
  'fairy' => const Color(0xFFD96BA0),
  'psychic' => const Color(0xFFE0529C),
  'rock' => const Color(0xFFB0A060),
  'ice' => const Color(0xFF6FD1D1),
  'ghost' => const Color(0xFF6B5B95),
  'dragon' => const Color(0xFF6A4DE0),
  'fighting' => const Color(0xFFC0552B),
  _ => const Color(0xFF777777),
};
