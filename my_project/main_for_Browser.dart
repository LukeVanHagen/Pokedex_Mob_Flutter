import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import 'dart:math';

// ===================================================================
// 1. ESTILIZAÇÃO E CONSTANTES DE TEMA
// ===================================================================

class FireRedTheme {
  static const Color background = Color(0xFFF8F8F8);
  static const Color screenBackground = Color(0xFF9BBC0F);
  static const Color screenBorder = Color(0xFF000000);
  static const Color pokedexBody = Color(0xFFCE3941);
  static const Color darkText = Color(0xFF1F1F1F);
  static const Color lightText = Color(0xFFF8F8F8);
  static const Color blueButton = Color(0xFF3B5998);
  static const Color pcBoxBackground = Color(0xFF3A5A9A);
  static const Color pcBoxCell = Color(0xFF829FE7);
  static const Color pcBoxCellHighlight = Color(0xFFC0D1F7);
}

class BoxTheme {
  final String label;
  final IconData icon;
  BoxTheme(this.label, this.icon);
}

// ===================================================================
// 2. PONTO DE ENTRADA DA APLICAÇÃO (MAIN)
// ===================================================================

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (context) => PokemonProvider(),
      child: const MyApp(),
    ),
  );
}

// ===================================================================
// 3. WIDGET RAIZ DA APLICAÇÃO (MyApp)
// ===================================================================

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pokédex Fire Red',
      theme: ThemeData(
        scaffoldBackgroundColor: FireRedTheme.background,
        textTheme: GoogleFonts.pressStart2pTextTheme(),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      home: const MainNavigator(),
    );
  }
}

// ===================================================================
// 4. MODELO DE DADOS (Pokemon) - Inalterado
// ===================================================================
class Pokemon {
  final int id;
  final String name;
  String nickname;
  final String imageUrl;

  Pokemon({required this.id, required this.name, this.nickname = '', required this.imageUrl});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'nickname': nickname, 'imageUrl': imageUrl};
  factory Pokemon.fromJson(Map<String, dynamic> json) => Pokemon(id: json['id'], name: json['name'], nickname: json['nickname'] ?? json['name'], imageUrl: json['imageUrl']);
  factory Pokemon.fromApiJson(Map<String, dynamic> json) {
    final officialArtwork = json['sprites']?['other']?['official-artwork']?['front_default'];
    return Pokemon(id: json['id'], name: json['name'], imageUrl: officialArtwork ?? json['sprites']?['front_default'] ?? 'https://via.placeholder.com/150');
  }
}

// ===================================================================
// 5. PERSISTÊNCIA, API E PROVIDER - Inalterados
// ===================================================================

class WebPersistenceService {
  static const _key = 'captured_pokemons_v3_multi_box';
  Future<void> savePokemons(List<Pokemon?> pokemons) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> pokemonJsonList = pokemons.map((p) => p == null ? 'null' : jsonEncode(p.toJson())).toList();
    await prefs.setStringList(_key, pokemonJsonList);
  }
  Future<List<Pokemon?>> loadPokemons() async {
    final prefs = await SharedPreferences.getInstance();
    final pokemonJsonList = prefs.getStringList(_key);
    if (pokemonJsonList == null) return List.filled(240, null);
    return pokemonJsonList.map((jsonString) => jsonString == 'null' ? null : Pokemon.fromJson(jsonDecode(jsonString))).toList();
  }
}

class ApiService {
  final String _baseUrl = "https://pokeapi.co/api/v2/pokemon/";
  Future<Pokemon> fetchRandomPokemon() async {
    final randomId = Random().nextInt(151) + 1;
    final response = await http.get(Uri.parse('$_baseUrl$randomId'));
    if (response.statusCode == 200) {
      return Pokemon.fromApiJson(json.decode(response.body));
    } else { throw Exception('Falha ao carregar Pokémon.'); }
  }
}

class PokemonProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  final WebPersistenceService _persistenceService = WebPersistenceService();
  Pokemon? _currentPokemon;
  List<Pokemon?> _allPokemons = List.filled(240, null);
  int _currentBoxIndex = 0;
  bool _isLoading = true;
  String? _errorMessage;

  Pokemon? get currentPokemon => _currentPokemon;
  List<Pokemon?> get allPokemons => _allPokemons;
  int get currentBoxIndex => _currentBoxIndex;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  final List<BoxTheme> boxThemes = [BoxTheme("BOX 1", Icons.catching_pokemon), BoxTheme("FOGO", Icons.local_fire_department), BoxTheme("ÁGUA", Icons.water_drop), BoxTheme("PLANTA", Icons.grass), BoxTheme("ELÉTRICO", Icons.bolt), BoxTheme("PSI", Icons.psychology), BoxTheme("ROCHA", Icons.terrain), BoxTheme("FAVORITOS", Icons.star)];

  PokemonProvider() { loadCapturedPokemons(); fetchNewPokemon(); }
  void selectBox(int index) { if (index >= 0 && index < 8) { _currentBoxIndex = index; notifyListeners(); } }
  Future<void> fetchNewPokemon() async { _isLoading = true; _errorMessage = null; notifyListeners(); try { _currentPokemon = await _apiService.fetchRandomPokemon(); } catch (e) { _errorMessage = 'Falha ao buscar Pokémon:\n$e'; } _isLoading = false; notifyListeners(); }
  Future<void> loadCapturedPokemons() async { _allPokemons = await _persistenceService.loadPokemons(); notifyListeners(); }
  Future<void> captureCurrentPokemon() async { if (_currentPokemon != null) { int? emptySlot = _allPokemons.indexWhere((p) => p == null); if (emptySlot != -1) { _allPokemons[emptySlot] = _currentPokemon; await _persistenceService.savePokemons(_allPokemons); notifyListeners(); } } await fetchNewPokemon(); }
  Future<void> reorderCapturedPokemon(int oldAbsoluteIndex, int newAbsoluteIndex) async { if (oldAbsoluteIndex < 0 || oldAbsoluteIndex >= 240 || newAbsoluteIndex < 0 || newAbsoluteIndex >= 240) return; final Pokemon? temp = _allPokemons[newAbsoluteIndex]; _allPokemons[newAbsoluteIndex] = _allPokemons[oldAbsoluteIndex]; _allPokemons[oldAbsoluteIndex] = temp; await _persistenceService.savePokemons(_allPokemons); notifyListeners(); }
  Future<void> updatePokemonNickname(int pokemonId, String newNickname) async { final pokemonIndex = _allPokemons.indexWhere((p) => p?.id == pokemonId); if(pokemonIndex != -1) { final pokemon = _allPokemons[pokemonIndex]!; pokemon.nickname = newNickname.isEmpty ? pokemon.name : newNickname; await _persistenceService.savePokemons(_allPokemons); } notifyListeners(); }
  Future<void> releasePokemon(int absoluteIndex) async { if (absoluteIndex >= 0 && absoluteIndex < 240) { _allPokemons[absoluteIndex] = null; await _persistenceService.savePokemons(_allPokemons); notifyListeners(); } }
}

// ===================================================================
// 6. WIDGETS DE UI (MainNavigator, HomeScreen) - Inalterados
// ===================================================================
class PixelButton extends StatelessWidget {
  final String text; final VoidCallback onPressed; final Color backgroundColor; final Color textColor;
  const PixelButton({super.key, required this.text, required this.onPressed, this.backgroundColor = FireRedTheme.blueButton, this.textColor = FireRedTheme.lightText});
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onPressed, child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), decoration: BoxDecoration(color: backgroundColor, border: Border.all(color: FireRedTheme.darkText, width: 2)), child: Text(text, style: GoogleFonts.pressStart2p(color: textColor, fontSize: 10))));
}
class MainNavigator extends StatefulWidget { const MainNavigator({super.key}); @override State<MainNavigator> createState() => _MainNavigatorState(); }
class _MainNavigatorState extends State<MainNavigator> { int _selectedIndex = 0; static const List<Widget> _widgetOptions = [HomeScreen(), PokedexScreen()]; @override Widget build(BuildContext context) => Scaffold(body: IndexedStack(index: _selectedIndex, children: _widgetOptions), bottomNavigationBar: Container(decoration: const BoxDecoration(color: FireRedTheme.pokedexBody, border: Border(top: BorderSide(color: FireRedTheme.darkText, width: 3))), child: BottomNavigationBar(items: const <BottomNavigationBarItem>[BottomNavigationBarItem(icon: Icon(Icons.public), label: 'ENCONTRAR'), BottomNavigationBarItem(icon: Icon(Icons.computer), label: 'PC DO BILL')], currentIndex: _selectedIndex, onTap: (index) => setState(() => _selectedIndex = index), backgroundColor: Colors.transparent, elevation: 0, selectedItemColor: Colors.white, unselectedItemColor: Colors.white.withOpacity(0.6), selectedLabelStyle: GoogleFonts.pressStart2p(fontSize: 8), unselectedLabelStyle: GoogleFonts.pressStart2p(fontSize: 8)))); }
class HomeScreen extends StatelessWidget { const HomeScreen({super.key}); @override Widget build(BuildContext context) => Scaffold(body: Container(width: double.infinity, height: double.infinity, color: FireRedTheme.pokedexBody, padding: const EdgeInsets.all(20.0), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: FireRedTheme.screenBackground, border: Border.all(color: FireRedTheme.screenBorder, width: 4), borderRadius: const BorderRadius.only(topLeft: Radius.circular(10), topRight: Radius.circular(10), bottomLeft: Radius.circular(10), bottomRight: Radius.circular(50))), child: Consumer<PokemonProvider>(builder: (context, provider, child) {if (provider.isLoading) {return const SizedBox(height: 180, child: Center(child: CircularProgressIndicator(color: FireRedTheme.darkText)));} if (provider.errorMessage != null) {return SizedBox(height: 180, child: Center(child: Text(provider.errorMessage!, textAlign: TextAlign.center)));} final pokemon = provider.currentPokemon!; return Column(children: [SizedBox(height: 150, child: Image.network(pokemon.imageUrl, fit: BoxFit.contain, filterQuality: FilterQuality.none, errorBuilder: (c, e, s) => const Icon(Icons.error_outline, size: 60, color: FireRedTheme.darkText))), Container(width: double.infinity, padding: const EdgeInsets.all(8), margin: const EdgeInsets.only(top: 8), color: FireRedTheme.background, child: Text('${pokemon.id.toString().padLeft(3, '0')} - ${pokemon.name.toUpperCase()}', textAlign: TextAlign.center))]);})), const SizedBox(height: 30), Consumer<PokemonProvider>(builder: (context, provider, child) {return Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [PixelButton(text: 'PULAR', onPressed: provider.fetchNewPokemon, backgroundColor: Colors.grey.shade700), PixelButton(text: 'CAPTURAR', onPressed: provider.captureCurrentPokemon)]);})]))); }

// ===================================================================
// 7. TELA DA POKEDEX (PokedexScreen) - Grande Refatoração
// ===================================================================

class PokedexScreen extends StatefulWidget {
  const PokedexScreen({super.key});

  @override
  State<PokedexScreen> createState() => _PokedexScreenState();
}

class _PokedexScreenState extends State<PokedexScreen> {
  // Timer para controlar a troca de abas ao arrastar
  Timer? _hoverTimer;

  void _startHoverTimer(int boxIndex) {
    // Cancela qualquer timer anterior para evitar trocas múltiplas
    _hoverTimer?.cancel();
    _hoverTimer = Timer(const Duration(milliseconds: 600), () {
      Provider.of<PokemonProvider>(context, listen: false).selectBox(boxIndex);
    });
  }

  void _cancelHoverTimer() {
    _hoverTimer?.cancel();
  }

  @override
  void dispose() {
    _hoverTimer?.cancel();
    super.dispose();
  }

  Future<void> _showEditNicknameDialog(BuildContext context, Pokemon pokemon) async {
    final provider = Provider.of<PokemonProvider>(context, listen: false);
    final controller = TextEditingController(text: pokemon.nickname == pokemon.name ? '' : pokemon.nickname);
    return showDialog<void>(context: context, barrierDismissible: false, builder: (BuildContext dialogContext) => Dialog(backgroundColor: Colors.transparent, child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: FireRedTheme.blueButton, border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(4)), child: Column(mainAxisSize: MainAxisSize.min, children: [Text('Dar um apelido para ${pokemon.name.toUpperCase()}?', style: GoogleFonts.pressStart2p(fontSize: 10, color: Colors.white, height: 1.5), textAlign: TextAlign.center), const SizedBox(height: 16), TextField(controller: controller, autofocus: true, maxLength: 10, textAlign: TextAlign.center, style: GoogleFonts.pressStart2p(fontSize: 12, color: FireRedTheme.darkText), decoration: InputDecoration(hintText: 'APELIDO', filled: true, fillColor: Colors.white, border: const OutlineInputBorder(borderSide: BorderSide.none), counterText: '')), const SizedBox(height: 16), Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [PixelButton(text: "CANCELAR", onPressed: () => Navigator.of(dialogContext).pop(), backgroundColor: FireRedTheme.pokedexBody), PixelButton(text: "OK", onPressed: () {provider.updatePokemonNickname(pokemon.id, controller.text.trim()); Navigator.of(dialogContext).pop();}, backgroundColor: Colors.green.shade700)])]))));
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PokemonProvider>(context);
    final currentBoxStart = provider.currentBoxIndex * 30;

    return Scaffold(
      backgroundColor: FireRedTheme.pcBoxBackground,
      appBar: AppBar(
        title: Text('PC de Armazenamento', style: GoogleFonts.pressStart2p(fontSize: 12)),
        backgroundColor: FireRedTheme.darkText, foregroundColor: FireRedTheme.lightText, centerTitle: true,
      ),
      body: Column(
        children: [
          // PAINEL DE ABAS AGORA COM DETECÇÃO DE ARRASTO
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            color: FireRedTheme.darkText.withOpacity(0.5),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(provider.boxThemes.length, (index) {
                  final theme = provider.boxThemes[index];
                  final isSelected = provider.currentBoxIndex == index;
                  
                  // CADA ABA AGORA É UM DragTarget
                  return DragTarget<Map<String, int>>(
                    builder: (context, candidateData, rejectedData) {
                      final isBeingHovered = candidateData.isNotEmpty;
                      return GestureDetector(
                        onTap: () => provider.selectBox(index),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: isSelected ? FireRedTheme.pcBoxBackground : (isBeingHovered ? Colors.white.withOpacity(0.3) : Colors.transparent),
                            border: isSelected ? const Border(bottom: BorderSide(color: FireRedTheme.pcBoxCellHighlight, width: 3)) : null,
                          ),
                          child: Row(children: [
                            Icon(theme.icon, color: Colors.white, size: 16),
                            const SizedBox(width: 8),
                            Text(theme.label, style: GoogleFonts.pressStart2p(fontSize: 10, color: Colors.white)),
                          ]),
                        ),
                      );
                    },
                    onMove: (_) => _startHoverTimer(index),
                    onLeave: (_) => _cancelHoverTimer(),
                    onAccept: (data) { /* Não faz nada ao soltar na aba, a troca é no hover */},
                  );
                }),
              ),
            ),
          ),
          
          // GRADE DE POKÉMON RESPONSIVA E SEM ROLAGEM
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              // LAYOUTBUILDER PARA TORNAR A GRADE RESPONSIVA
              child: LayoutBuilder(
                builder: (context, constraints) {
                  double cellWidth = (constraints.maxWidth - (5 * 8)) / 6; // 6 colunas, 5 espaçamentos
                  double cellHeight = (constraints.maxHeight - (4 * 8)) / 5; // 5 linhas, 4 espaçamentos
                  double aspectRatio = cellWidth / cellHeight;
                  
                  return GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 6, crossAxisSpacing: 8, mainAxisSpacing: 8,
                      childAspectRatio: aspectRatio,
                    ),
                    itemCount: 30,
                    itemBuilder: (context, relativeIndex) {
                      final absoluteIndex = currentBoxStart + relativeIndex;
                      final pokemon = provider.allPokemons[absoluteIndex];

                      return DragTarget<Map<String, int>>(
                        builder: (context, candidateData, rejectedData) {
                          return Container(
                            decoration: BoxDecoration(
                              color: candidateData.isNotEmpty ? FireRedTheme.pcBoxCellHighlight : FireRedTheme.pcBoxCell,
                              border: Border.all(color: FireRedTheme.pcBoxBackground, width: 2),
                            ),
                            child: pokemon == null ? null
                              : Draggable<Map<String, int>>(
                                  data: {'id': pokemon.id, 'index': absoluteIndex},
                                  feedback: Image.network(pokemon.imageUrl, height: 60, filterQuality: FilterQuality.none),
                                  childWhenDragging: Container(),
                                  child: Tooltip(
                                    message: pokemon.nickname.toUpperCase(),
                                    child: Stack(alignment: Alignment.center, children: [
                                      Image.network(pokemon.imageUrl, fit: BoxFit.contain, filterQuality: FilterQuality.none),
                                      Positioned(right: 2, top: 2, child: InkWell(onTap: () => _showEditNicknameDialog(context, pokemon), child: const Icon(Icons.edit, color: Colors.white, size: 14))),
                                      Positioned(right: 2, bottom: 2, child: InkWell(onTap: () => provider.releasePokemon(absoluteIndex), child: const Icon(Icons.delete, color: Colors.redAccent, size: 14))),
                                    ]),
                                  ),
                                ),
                          );
                        },
                        onAccept: (data) {
                          final int oldAbsoluteIndex = data['index']!;
                          provider.reorderCapturedPokemon(oldAbsoluteIndex, absoluteIndex);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}