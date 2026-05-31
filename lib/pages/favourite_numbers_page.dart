import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FavouriteNumber {
  final String id;
  final String number;

  const FavouriteNumber({required this.id, required this.number});
}

class FavouriteNumbersPage extends StatefulWidget {
  const FavouriteNumbersPage({super.key});

  @override
  State<FavouriteNumbersPage> createState() => _FavouriteNumbersPageState();
}

class _FavouriteNumbersPageState extends State<FavouriteNumbersPage> {
  final List<FavouriteNumber> _favoriteNumbers = <FavouriteNumber>[];
  final _numberController = TextEditingController();
  bool _isLoading = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() {
        _loadError = 'Not signed in.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final rows = await Supabase.instance.client
          .from('favourite_numbers')
          .select('id, number')
          .eq('user_id', user.id)
          .order('created_at');

      final list = (rows as List)
          .map(
            (r) => FavouriteNumber(
              id: r['id'].toString(),
              number: r['number'].toString(),
            ),
          )
          .toList(growable: false);

      if (!mounted) return;
      setState(() {
        _favoriteNumbers
          ..clear()
          ..addAll(list);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Failed to load favorites: $e';
      });
    }
  }

  String? _normalizeNumber(String raw) {
    final trimmed = raw.trim();
    if (!RegExp(r'^\d{2,4}$').hasMatch(trimmed)) return null;
    return trimmed;
  }

  Future<void> _addNumber() async {
    final normalized = _normalizeNumber(_numberController.text);
    if (normalized == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter a number')));
      return;
    }

    if (_favoriteNumbers.any((f) => f.number == normalized)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This number is already in your favorites'),
        ),
      );
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Not signed in.')));
      return;
    }

    try {
      final inserted = await Supabase.instance.client
          .from('favourite_numbers')
          .insert({'user_id': user.id, 'number': normalized})
          .select('id, number')
          .single();

      if (!mounted) return;
      setState(() {
        _favoriteNumbers.add(
          FavouriteNumber(
            id: inserted['id'].toString(),
            number: inserted['number'].toString(),
          ),
        );
      });
      _numberController.clear();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      final msg = e.message.toLowerCase();
      if (msg.contains('duplicate') || msg.contains('unique')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This number is already in your favorites'),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save: ${e.message}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    }
  }

  Future<void> _removeNumber(FavouriteNumber fav) async {
    try {
      await Supabase.instance.client
          .from('favourite_numbers')
          .delete()
          .eq('id', fav.id);

      if (!mounted) return;
      setState(() {
        _favoriteNumbers.removeWhere((f) => f.id == fav.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${fav.number} removed from favorites')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to remove: $e')));
    }
  }

  @override
  void dispose() {
    _numberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        title: const Text('Favourite Numbers'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Text(
              'Your Lucky Numbers',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_isLoading)
              const LinearProgressIndicator(minHeight: 2)
            else if (_loadError != null)
              Text(
                _loadError!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _numberController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Add a number (2-4 digits)',
                hintText: 'e.g. 07, 123, 9999',
                prefixIcon: const Icon(Icons.format_list_numbered_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                ),
              ),
              onSubmitted: (_) => _addNumber(),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: _addNumber,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Number'),
            ),
            const SizedBox(height: 28),
            if (_favoriteNumbers.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.favorite_border_rounded,
                          size: 40,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No favorite numbers yet',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Add your lucky numbers above to get started',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Numbers (${_favoriteNumbers.length})',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: _favoriteNumbers.map(_buildNumberChip).toList(),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lightbulb_outline_rounded,
                          color: Theme.of(
                            context,
                          ).colorScheme.onTertiaryContainer,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Your favorite numbers are saved and will be highlighted in results.',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onTertiaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberChip(FavouriteNumber fav) {
    return Chip(
      label: Text(
        fav.number,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onPrimary,
        ),
      ),
      backgroundColor: Theme.of(context).colorScheme.primary,
      onDeleted: () => _removeNumber(fav),
      deleteIcon: Icon(
        Icons.close,
        color: Theme.of(context).colorScheme.onPrimary,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }
}
