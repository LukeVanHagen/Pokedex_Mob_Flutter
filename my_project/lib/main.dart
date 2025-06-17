import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';
import 'dart:math';

// ===================================================================
// 1. PONTO DE ENTRADA DA APLICAÇÃO (MAIN)
// ===================================================================

void main() {
  // Garante que os bindings do Flutter foram inicializados antes de rodar o app.
  // Essencial para o sqflite funcionar.
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    // O Provider vai "envolver" toda a aplicação, disponibilizando o PokemonProvider
    // para qualquer widget que precise dele.
    ChangeNotifierProvider(
      create: (context) => PokemonProvider(),
      child: const MyApp(),
    ),
  );
}

// ===================================================================
// 2. WIDGET RAIZ DA APLICAÇÃO (MyApp)
// ===================================================================

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pokédex App',
      theme: ThemeData(
        primarySwatch: Colors.red,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      home: const MainNavigator(),
    );
  }
}

// ===================================================================
// 3. MODELO DE DADOS (Pokemon)
// ===================================================================

class Pokemon {
  final int id;
  final String name;
  String nickname;
  final String imageUrl;

  Pokemon({
    required this.id,
    required this.name,
    this.nickname = '',
    required this.imageUrl,
  });

  // Converte um objeto Pokemon em um Map para o DB
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'nickname': nickname.isEmpty ? name : nickname,
      'imageUrl': imageUrl,
    };
  }

  // Converte um Map do DB em um objeto Pokemon
  factory Pokemon.fromMap(Map<String, dynamic> map) {
    return Pokemon(
      id: map['id'],
      name: map['name'],
      nickname: map['nickname'] ?? map['name'],
      imageUrl: map['imageUrl'],
    );
  }

  // Converte o JSON da PokeAPI em um objeto Pokemon
  factory Pokemon.fromJson(Map<String, dynamic> json) {
    // Tratamento para caso a imagem não exista
    final imageUrl = json['sprites']?['front_default'] ?? 'https://via.placeholder.com/150';
    return Pokemon(
      id: json['id'],
      name: json['name'],
      imageUrl: imageUrl,
    );
  }
}

// ===================================================================
// 4. HELPER DO BANCO DE DADOS (DatabaseHelper)
// ===================================================================

class DatabaseHelper {
  static const _databaseName = "Pokedex.db";
  static const _databaseVersion = 1;
  static const table = 'captured_pokemons';

  // Torna esta classe um singleton para garantir uma única instância
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // Abre o banco de dados e o cria se ele não existir
  _initDatabase() async {
    String path = join(await getDatabasesPath(), _databaseName);
    return await openDatabase(path,
        version: _databaseVersion, onCreate: _onCreate);
  }

  // Script SQL para criar a tabela
  Future _onCreate(Database db, int version) async {
    await db.execute('''
          CREATE TABLE $table (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            nickname TEXT NOT NULL,
            imageUrl TEXT NOT NULL
          )
          ''');
  }

  // Métodos CRUD
  Future<int> insert(Pokemon pokemon) async {
    Database db = await instance.database;
    return await db.insert(table, pokemon.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Pokemon>> queryAllPokemons() async {
    Database db = await instance.database;
    final maps = await db.query(table, orderBy: 'id ASC');
    return List.generate(maps.length, (i) {
      return Pokemon.fromMap(maps[i]);
    });
  }

  Future<int> update(Pokemon pokemon) async {
    Database db = await instance.database;
    return await db.update(table, pokemon.toMap(), where: 'id = ?', whereArgs: [pokemon.id]);
  }

  Future<int> delete(int id) async {
    Database db = await instance.database;
    return await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }
}

// ===================================================================
// 5. SERVIÇO DE API (ApiService)
// ===================================================================

class ApiService {
  final String _baseUrl = "https://pokeapi.co/api/v2/pokemon/";

  Future<Pokemon> fetchRandomPokemon() async {
    final randomId = Random().nextInt(898) + 1;
    final response = await http.get(Uri.parse('$_baseUrl$randomId'));

    if (response.statusCode == 200) {
      return Pokemon.fromJson(json.decode(response.body));
    } else {
      throw Exception('Falha ao carregar Pokémon.');
    }
  }
}

// ===================================================================
// 6. GERENCIADOR DE ESTADO (PokemonProvider)
// ===================================================================

class PokemonProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Pokemon? _currentPokemon;
  List<Pokemon> _capturedPokemons = [];
  bool _isLoading = true;

  Pokemon? get currentPokemon => _currentPokemon;
  List<Pokemon> get capturedPokemons => _capturedPokemons;
  bool get isLoading => _isLoading;

  PokemonProvider() {
    loadCapturedPokemons();
    fetchNewPokemon();
  }

  Future<void> fetchNewPokemon() async {
    _isLoading = true;
    notifyListeners();
    try {
      _currentPokemon = await _apiService.fetchRandomPokemon();
    } catch (e) {
      print(e); // No console, podemos ver se houve algum erro na API
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadCapturedPokemons() async {
    _capturedPokemons = await _dbHelper.queryAllPokemons();
    notifyListeners();
  }

  Future<void> captureCurrentPokemon() async {
    if (_currentPokemon != null) {
      await _dbHelper.insert(_currentPokemon!);
      await loadCapturedPokemons();
      await fetchNewPokemon();
    }
  }

  Future<void> updatePokemonNickname(int id, String newNickname) async {
    final pokemonIndex = _capturedPokemons.indexWhere((p) => p.id == id);
    if(pokemonIndex != -1) {
      Pokemon pokemonToUpdate = _capturedPokemons[pokemonIndex];
      pokemonToUpdate.nickname = newNickname.isEmpty ? pokemonToUpdate.name : newNickname;
      await _dbHelper.update(pokemonToUpdate);
      await loadCapturedPokemons();
    }
  }

  Future<void> releasePokemon(int id) async {
    await _dbHelper.delete(id);
    await loadCapturedPokemons();
  }
}

// ===================================================================
// 7. WIDGET DE NAVEGAÇÃO PRINCIPAL (MainNavigator)
// ===================================================================

class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key});

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> {
  int _selectedIndex = 0;

  static const List<Widget> _widgetOptions = <Widget>[
    HomeScreen(),
    PokedexScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _widgetOptions.elementAt(_selectedIndex),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: 'Encontrar',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.catching_pokemon_outlined),
            activeIcon: Icon(Icons.catching_pokemon),
            label: 'Pokédex',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.red[800],
        onTap: _onItemTapped,
      ),
    );
  }
}

// ===================================================================
// 8. TELA INICIAL (HomeScreen)
// ===================================================================

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PokemonProvider>(context);
    final pokemon = provider.currentPokemon;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Encontre um Pokémon!'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: provider.isLoading
            ? const CircularProgressIndicator()
            : pokemon == null
                ? const Text('Nenhum Pokémon encontrado.')
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.network(
                        pokemon.imageUrl,
                        height: 250,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(Icons.error, size: 100),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        pokemon.name.toUpperCase(),
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 40),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton.icon(
                            onPressed: provider.fetchNewPokemon,
                            icon: const Icon(Icons.arrow_forward),
                            label: const Text('Pular'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                          ),
                          ElevatedButton.icon(
                            onPressed: provider.captureCurrentPokemon,
                            icon: const Icon(Icons.catching_pokemon),
                            label: const Text('Capturar'),
                          ),
                        ],
                      ),
                    ],
                  ),
      ),
    );
  }
}

// ===================================================================
// 9. TELA DA POKEDEX (PokedexScreen)
// ===================================================================

class PokedexScreen extends StatelessWidget {
  const PokedexScreen({super.key});

  Future<void> _showEditNicknameDialog(
      BuildContext context, Pokemon pokemon) async {
    final provider = Provider.of<PokemonProvider>(context, listen: false);
    final controller = TextEditingController(text: pokemon.nickname == pokemon.name ? '' : pokemon.nickname);
    
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Editar Apelido de ${pokemon.name.toUpperCase()}'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: "Novo apelido"),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            TextButton(
              child: const Text('Salvar'),
              onPressed: () {
                provider.updatePokemonNickname(pokemon.id, controller.text);
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PokemonProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meus Pokémons'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: provider.capturedPokemons.isEmpty
          ? const Center(
              child: Text(
                'Você ainda não capturou nenhum Pokémon.',
                style: TextStyle(fontSize: 18),
                textAlign: TextAlign.center,
              ),
            )
          : ListView.builder(
              itemCount: provider.capturedPokemons.length,
              itemBuilder: (context, index) {
                final pokemon = provider.capturedPokemons[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: ListTile(
                    leading: Image.network(pokemon.imageUrl),
                    title: Text(
                      pokemon.nickname.toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text('Original: ${pokemon.name}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blueAccent),
                          onPressed: () => _showEditNicknameDialog(context, pokemon),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_forever, color: Colors.red),
                          onPressed: () => provider.releasePokemon(pokemon.id),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}