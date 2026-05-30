// lib/services/medicine_database.dart
// Layer 2 — Fuzzy DB lookup + Abbreviation decoder

/// Dosage abbreviation decoder (OD, BD, TDS, QDS, SOS, etc.)
class AbbreviationDecoder {
  static const Map<String, String> _dosageFreq = {
    'od': 'Once daily',
    'od1': 'Once daily',
    'bd': 'Twice daily',
    'bid': 'Twice daily',
    'tds': 'Three times daily',
    'tid': 'Three times daily',
    'qds': 'Four times daily',
    'qid': 'Four times daily',
    'sos': 'As needed (when required)',
    'prn': 'As needed',
    'stat': 'Immediately',
    'nocte': 'At night',
    'hs': 'At bedtime',
    'ac': 'Before meals',
    'pc': 'After meals',
    'mane': 'In the morning',
    'om': 'Every morning',
    'on': 'Every night',
    'q4h': 'Every 4 hours',
    'q6h': 'Every 6 hours',
    'q8h': 'Every 8 hours',
    'q12h': 'Every 12 hours',
    'qd': 'Once daily',
    'wkly': 'Weekly',
    'weekly': 'Weekly',
    'monthly': 'Monthly',
  };

  static const Map<String, String> _routeMap = {
    'po': 'By mouth (oral)',
    'sl': 'Under tongue (sublingual)',
    'pr': 'Rectally',
    'im': 'Intramuscular injection',
    'iv': 'Intravenous',
    'sc': 'Subcutaneous injection',
    'top': 'Topical (apply on skin)',
    'inh': 'Inhaled',
    'neb': 'Via nebulizer',
    'gtts': 'Drops',
    'oint': 'Ointment',
    'supp': 'Suppository',
  };

  static const Map<String, String> _doseUnits = {
    'mg': 'mg',
    'mcg': 'mcg',
    'g': 'g',
    'ml': 'mL',
    'iu': 'IU (International Units)',
    'units': 'Units',
    'tab': 'tablet(s)',
    'tabs': 'tablets',
    'cap': 'capsule(s)',
    'caps': 'capsules',
    'tsp': 'teaspoon (5 mL)',
    'tbsp': 'tablespoon (15 mL)',
    'sachet': 'sachet',
  };

  /// Decode a raw abbreviation token. Returns null if not recognized.
  static String? decode(String token) {
    final lower = token.toLowerCase().trim();
    return _dosageFreq[lower] ?? _routeMap[lower] ?? _doseUnits[lower];
  }

  /// Annotate a full dosage string with decoded abbreviations.
  static String annotateDosage(String raw) {
    final tokens = raw.split(RegExp(r'[\s/,]+'));
    final parts = <String>[];
    for (final t in tokens) {
      final decoded = decode(t);
      if (decoded != null && decoded != t) {
        parts.add('$t ($decoded)');
      } else {
        parts.add(t);
      }
    }
    return parts.join(' ');
  }
}

/// A known medicine entry in our local DB.
class MedicineEntry {
  final String canonical; // official name
  final List<String> aliases; // common misspellings, brand names, short forms
  final String category;
  final String? commonDose;

  const MedicineEntry({
    required this.canonical,
    required this.aliases,
    required this.category,
    this.commonDose,
  });
}

/// Lightweight fuzzy medicine lookup.
/// Returns the best canonical match and a confidence score 0–1.
class MedicineDatabase {
  static final List<MedicineEntry> _db = [
    // ── Antibiotics ──────────────────────────────────────────────────────
    MedicineEntry(canonical: 'Amoxicillin', aliases: [
      'amox', 'amoxil', 'amoxycillin', 'amoxcillin', 'amoxicilin',
      'amoxyclin', 'amox 500', 'amox500'
    ], category: 'Antibiotic', commonDose: '500 mg TDS x 5 days'),
    MedicineEntry(canonical: 'Azithromycin', aliases: [
      'azith', 'azithro', 'azee', 'zithromax', 'azimax', 'azithromycin',
      'azitro', 'azithro 500'
    ], category: 'Antibiotic', commonDose: '500 mg OD x 3 days'),
    MedicineEntry(canonical: 'Ciprofloxacin', aliases: [
      'cipro', 'cifran', 'ciprox', 'ciproflox', 'ciprobay',
      'ciprofloxasin', 'ciprofloxcin'
    ], category: 'Antibiotic', commonDose: '500 mg BD x 5 days'),
    MedicineEntry(canonical: 'Metronidazole', aliases: [
      'metro', 'flagyl', 'metrogyl', 'metronid', 'metronidazol',
      'metronidazle', 'metrodazole'
    ], category: 'Antibiotic', commonDose: '400 mg TDS x 5 days'),
    MedicineEntry(canonical: 'Doxycycline', aliases: [
      'doxy', 'doxycyclin', 'doxycline', 'vibramycin', 'doxt',
      'doxycycl'
    ], category: 'Antibiotic', commonDose: '100 mg BD'),
    MedicineEntry(canonical: 'Cephalexin', aliases: [
      'cefalexin', 'keflex', 'cephal', 'cephalex', 'cefalex',
      'cephalexin', 'cephlex'
    ], category: 'Antibiotic', commonDose: '500 mg QDS x 7 days'),
    MedicineEntry(canonical: 'Cloxacillin', aliases: [
      'clox', 'cloxapen', 'cloxacil', 'cloxacilin',
    ], category: 'Antibiotic', commonDose: '500 mg QDS x 5 days'),
    MedicineEntry(canonical: 'Co-Amoxiclav', aliases: [
      'augmentin', 'coamoxiclav', 'amoxiclav', 'co amoxiclav',
      'augmentin 625', 'co-amox'
    ], category: 'Antibiotic', commonDose: '625 mg TDS x 5 days'),

    // ── Analgesics / NSAIDs ──────────────────────────────────────────────
    MedicineEntry(canonical: 'Paracetamol', aliases: [
      'pcm', 'para', 'crocin', 'calpol', 'acetaminophen', 'tylenol',
      'paracet', 'paracetmol', 'parcetamol', 'paracetamole',
      'paracetamo', 'p500'
    ], category: 'Analgesic', commonDose: '500–1000 mg QDS'),
    MedicineEntry(canonical: 'Ibuprofen', aliases: [
      'ibuf', 'brufen', 'ibu', 'advil', 'nurofen', 'ibupro',
      'ibuprofen', 'ibuprofen 400', 'ibufren', 'ibuprof'
    ], category: 'NSAID', commonDose: '400 mg TDS after food'),
    MedicineEntry(canonical: 'Diclofenac', aliases: [
      'diclo', 'voveran', 'voltaren', 'diclofenac sodium', 'diclofen',
      'diclof', 'voltarol', 'diclofenac 50'
    ], category: 'NSAID', commonDose: '50 mg BD/TDS'),
    MedicineEntry(canonical: 'Naproxen', aliases: [
      'naprox', 'naprosyn', 'aleve', 'naproxin', 'napro',
    ], category: 'NSAID', commonDose: '250–500 mg BD'),
    MedicineEntry(canonical: 'Tramadol', aliases: [
      'trama', 'tramol', 'ultram', 'contramal', 'tramadol hcl',
      'tramahexal'
    ], category: 'Opioid Analgesic', commonDose: '50 mg BD/TDS'),
    MedicineEntry(canonical: 'Aspirin', aliases: [
      'asp', 'disprin', 'ecosprin', 'asprin', 'aspirin 75',
      'aspirin 150', 'ecosprin 75'
    ], category: 'Antiplatelet/Analgesic', commonDose: '75 mg OD'),

    // ── Antacids / GI ────────────────────────────────────────────────────
    MedicineEntry(canonical: 'Omeprazole', aliases: [
      'ome', 'omez', 'prilosec', 'losec', 'omeprazol', 'omeprazole 20',
      'omprazole', 'omeprazol 20'
    ], category: 'Proton Pump Inhibitor', commonDose: '20 mg OD before breakfast'),
    MedicineEntry(canonical: 'Pantoprazole', aliases: [
      'panto', 'pan', 'pantop', 'protonix', 'pantoprazol',
      'pantoprazole 40', 'pantoz'
    ], category: 'Proton Pump Inhibitor', commonDose: '40 mg OD'),
    MedicineEntry(canonical: 'Ranitidine', aliases: [
      'rani', 'zantac', 'ranit', 'ranitidine 150', 'ranitidin',
    ], category: 'H2 Blocker', commonDose: '150 mg BD'),
    MedicineEntry(canonical: 'Ondansetron', aliases: [
      'onda', 'zofran', 'emeset', 'ondan', 'ondansetron 4',
      'ondansetron 8', 'ondanst'
    ], category: 'Antiemetic', commonDose: '4–8 mg TDS'),
    MedicineEntry(canonical: 'Domperidone', aliases: [
      'domp', 'dom', 'motilium', 'domperidone 10', 'domperi',
      'domperidon'
    ], category: 'Prokinetic', commonDose: '10 mg TDS before meals'),
    MedicineEntry(canonical: 'Metoclopramide', aliases: [
      'metoclo', 'emex', 'maxolon', 'metoclop', 'metoclopramid',
    ], category: 'Antiemetic', commonDose: '10 mg TDS'),

    // ── Antihypertensives ─────────────────────────────────────────────────
    MedicineEntry(canonical: 'Amlodipine', aliases: [
      'amlo', 'norvasc', 'amlong', 'amlod', 'amlodipine 5',
      'amlodipine 10', 'amlodipin', 'amlodip'
    ], category: 'Calcium Channel Blocker', commonDose: '5–10 mg OD'),
    MedicineEntry(canonical: 'Atenolol', aliases: [
      'aten', 'tenormin', 'atenolol 50', 'atenolol 100',
      'atenolol 25', 'atenol'
    ], category: 'Beta Blocker', commonDose: '50 mg OD'),
    MedicineEntry(canonical: 'Losartan', aliases: [
      'losar', 'cozaar', 'losartan 50', 'losartan 25', 'losartan 100',
      'losartaan', 'losacar'
    ], category: 'ARB', commonDose: '50 mg OD'),
    MedicineEntry(canonical: 'Telmisartan', aliases: [
      'telmi', 'micardis', 'telma', 'telmis', 'telmisartan 40',
      'telmisartan 80'
    ], category: 'ARB', commonDose: '40 mg OD'),
    MedicineEntry(canonical: 'Ramipril', aliases: [
      'rami', 'altace', 'hopace', 'ramipr', 'ramipril 5',
      'ramipril 10', 'ramipril 2.5'
    ], category: 'ACE Inhibitor', commonDose: '5 mg OD'),
    MedicineEntry(canonical: 'Lisinopril', aliases: [
      'lisin', 'zestril', 'prinivil', 'lisinopril 10',
      'lisinopril 5', 'lisinopr'
    ], category: 'ACE Inhibitor', commonDose: '10 mg OD'),

    // ── Antidiabetics ─────────────────────────────────────────────────────
    MedicineEntry(canonical: 'Metformin', aliases: [
      'met', 'glucophage', 'glycomet', 'metformin 500', 'metformin 1000',
      'metformin sr', 'metformin xr', 'metformin 850', 'metfo',
      'metformine'
    ], category: 'Antidiabetic', commonDose: '500 mg BD with meals'),
    MedicineEntry(canonical: 'Glibenclamide', aliases: [
      'glib', 'daonil', 'glibenclam', 'glibenclamide 5', 'glyburide',
    ], category: 'Antidiabetic', commonDose: '5 mg OD before breakfast'),
    MedicineEntry(canonical: 'Glimepiride', aliases: [
      'glime', 'amaryl', 'glimp', 'glimepiride 1', 'glimepiride 2',
      'glimepiride 4', 'glimep'
    ], category: 'Antidiabetic', commonDose: '1–2 mg OD'),
    MedicineEntry(canonical: 'Sitagliptin', aliases: [
      'sita', 'januvia', 'sitag', 'sitagliptin 50', 'sitagliptin 100',
    ], category: 'Antidiabetic', commonDose: '100 mg OD'),

    // ── Lipid Lowering ────────────────────────────────────────────────────
    MedicineEntry(canonical: 'Atorvastatin', aliases: [
      'atorv', 'lipitor', 'atorva', 'atorvastatin 10', 'atorvastatin 20',
      'atorvastatin 40', 'atrovastat', 'atorvastat'
    ], category: 'Statin', commonDose: '10–40 mg OD at night'),
    MedicineEntry(canonical: 'Rosuvastatin', aliases: [
      'rosuv', 'crestor', 'rosuvast', 'rosuvastatin 10', 'rosuvastatin 20',
      'rosuvastatin 5'
    ], category: 'Statin', commonDose: '10–20 mg OD'),

    // ── Respiratory ───────────────────────────────────────────────────────
    MedicineEntry(canonical: 'Salbutamol', aliases: [
      'salb', 'ventolin', 'albuterol', 'salbutamol inhaler',
      'salbutamol 2mg', 'salbutamol 4mg', 'asthalin'
    ], category: 'Bronchodilator', commonDose: '2–4 mg TDS or inhaler PRN'),
    MedicineEntry(canonical: 'Prednisolone', aliases: [
      'pred', 'predniso', 'wysolone', 'prednisolone 5', 'prednisolone 10',
      'prednisolone 20', 'prednisolon', 'predn'
    ], category: 'Corticosteroid', commonDose: '5–40 mg OD'),
    MedicineEntry(canonical: 'Cetirizine', aliases: [
      'cetir', 'zyrtec', 'alerid', 'cetriz', 'cetirizin',
      'cetirizine 10', 'cetrizine'
    ], category: 'Antihistamine', commonDose: '10 mg OD at night'),
    MedicineEntry(canonical: 'Levocetirizine', aliases: [
      'levocet', 'xyzal', 'levo', 'levocetriz', 'levocetirizin',
      'levocetirizine 5'
    ], category: 'Antihistamine', commonDose: '5 mg OD at night'),
    MedicineEntry(canonical: 'Montelukast', aliases: [
      'monte', 'singulair', 'montek', 'montelukast 10', 'monteluk',
      'montelu'
    ], category: 'Leukotriene Antagonist', commonDose: '10 mg OD at night'),

    // ── Vitamins / Supplements ────────────────────────────────────────────
    MedicineEntry(canonical: 'Vitamin D3', aliases: [
      'vit d', 'vit d3', 'vitamin d', 'cholecalciferol', 'd3', 'calcirol',
      'uprise d3', 'vit-d'
    ], category: 'Supplement', commonDose: '60,000 IU weekly x 8 weeks'),
    MedicineEntry(canonical: 'Vitamin B12', aliases: [
      'vit b12', 'b12', 'mecobalamin', 'methylcobalamin', 'methycobal',
      'neurobion', 'mecob', 'mecobal'
    ], category: 'Supplement', commonDose: '500 mcg OD'),
    MedicineEntry(canonical: 'Folic Acid', aliases: [
      'folic', 'folate', 'fol', 'folic acid 5mg', 'folinas',
    ], category: 'Supplement', commonDose: '5 mg OD'),
    MedicineEntry(canonical: 'Iron Supplement', aliases: [
      'iron', 'ferrous sulphate', 'fesolate', 'ferrous sulfate',
      'iron tab', 'hemfer', 'ferrous', 'iron 150'
    ], category: 'Supplement', commonDose: '200 mg BD'),
    MedicineEntry(canonical: 'Calcium Carbonate', aliases: [
      'calci', 'calcium', 'caltrate', 'shelcal', 'calcium 500',
      'calcium carbonate', 'calcitab'
    ], category: 'Supplement', commonDose: '500 mg BD'),

    // ── Thyroid ───────────────────────────────────────────────────────────
    MedicineEntry(canonical: 'Levothyroxine', aliases: [
      'levo', 'synthroid', 'thyrox', 'levothyrox', 'eltroxin',
      'levothyroxine 25', 'levothyroxine 50', 'levothyroxine 75',
      'levothyroxine 100', 'thyroxine', 'thyronorm'
    ], category: 'Thyroid Hormone', commonDose: '25–100 mcg OD fasting'),

    // ── CNS / Neurological ────────────────────────────────────────────────
    MedicineEntry(canonical: 'Gabapentin', aliases: [
      'gaba', 'neurontin', 'gabapen', 'gabapentin 300', 'gabapentin 100',
      'gabapentin 400'
    ], category: 'Anticonvulsant/Neuropathic', commonDose: '300 mg TDS'),
    MedicineEntry(canonical: 'Pregabalin', aliases: [
      'pregab', 'lyrica', 'pregalin', 'pregabalin 75', 'pregabalin 150',
      'pregabalin 300'
    ], category: 'Anticonvulsant/Neuropathic', commonDose: '75 mg BD'),
    MedicineEntry(canonical: 'Alprazolam', aliases: [
      'alp', 'xanax', 'restyl', 'alpraz', 'alprax', 'alprazolam 0.25',
      'alprazolam 0.5'
    ], category: 'Benzodiazepine', commonDose: '0.25–0.5 mg BD/TDS'),
    MedicineEntry(canonical: 'Clonazepam', aliases: [
      'clona', 'rivotril', 'klonopin', 'clonazepm', 'clonazepam 0.5',
    ], category: 'Benzodiazepine', commonDose: '0.5 mg BD'),
  ];

  /// Find the best match for a raw medicine name token.
  /// Returns null if confidence is below threshold.
  static MedicineMatch? findBest(String rawToken, {double minScore = 0.45}) {
    if (rawToken.trim().isEmpty) return null;
    final lower = rawToken.toLowerCase().trim();

    MedicineEntry? bestEntry;
    double bestScore = 0.0;
    String? matchedAlias;

    for (final entry in _db) {
      // Check canonical name
      final cScore = _similarity(lower, entry.canonical.toLowerCase());
      if (cScore > bestScore) {
        bestScore = cScore;
        bestEntry = entry;
        matchedAlias = null;
      }
      // Check aliases
      for (final alias in entry.aliases) {
        final aScore = _similarity(lower, alias.toLowerCase());
        if (aScore > bestScore) {
          bestScore = aScore;
          bestEntry = entry;
          matchedAlias = alias;
        }
      }
    }

    if (bestEntry == null || bestScore < minScore) return null;
    return MedicineMatch(
      entry: bestEntry,
      rawInput: rawToken,
      confidence: bestScore,
      matchedAlias: matchedAlias,
    );
  }

  /// Normalized edit-distance similarity (0–1).
  static double _similarity(String a, String b) {
    // Exact match
    if (a == b) return 1.0;
    // Prefix bonus: if one starts with the other
    if (b.startsWith(a) || a.startsWith(b)) {
      final ratio = a.length < b.length ? a.length / b.length : b.length / a.length;
      return 0.7 + 0.3 * ratio;
    }
    // Contains bonus
    if (b.contains(a) || a.contains(b)) {
      final ratio = a.length < b.length ? a.length / b.length : b.length / a.length;
      return 0.55 + 0.25 * ratio;
    }
    // Levenshtein normalized
    final d = _levenshtein(a, b);
    final maxLen = a.length > b.length ? a.length : b.length;
    if (maxLen == 0) return 1.0;
    return 1.0 - (d / maxLen);
  }

  static int _levenshtein(String a, String b) {
    final m = a.length, n = b.length;
    if (m == 0) return n;
    if (n == 0) return m;
    final dp = List.generate(m + 1, (i) => List.filled(n + 1, 0));
    for (int i = 0; i <= m; i++) dp[i][0] = i;
    for (int j = 0; j <= n; j++) dp[0][j] = j;
    for (int i = 1; i <= m; i++) {
      for (int j = 1; j <= n; j++) {
        if (a[i - 1] == b[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1];
        } else {
          dp[i][j] = 1 +
              [dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]]
                  .reduce((x, y) => x < y ? x : y);
        }
      }
    }
    return dp[m][n];
  }
}

class MedicineMatch {
  final MedicineEntry entry;
  final String rawInput;
  final double confidence;
  final String? matchedAlias;

  MedicineMatch({
    required this.entry,
    required this.rawInput,
    required this.confidence,
    this.matchedAlias,
  });
}