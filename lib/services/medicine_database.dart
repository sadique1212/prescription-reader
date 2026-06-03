// lib/services/medicine_database.dart
// In-memory fuzzy medicine DB + SQLite DB service for the 2.5 lakh medicine asset

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

// ── Abbreviation decoder ─────────────────────────────────────────────────────

class AbbreviationDecoder {
  static const Map<String, String> _dosageFreq = {
    'od': 'Once daily',
    'od1': 'Once daily',
    'qd': 'Once daily',
    'bd': 'Twice daily',
    'bid': 'Twice daily',
    'tds': 'Three times daily',
    'tid': 'Three times daily',
    'qds': 'Four times daily',
    'qid': 'Four times daily',
    'sos': 'As needed (SOS)',
    'prn': 'As needed (PRN)',
    'stat': 'Immediately (STAT)',
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
    'wkly': 'Weekly',
    'weekly': 'Weekly',
    'monthly': 'Monthly',
    'fortnightly': 'Every 2 weeks',
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
    'patch': 'Transdermal patch',
  };

  static const Map<String, String> _doseUnits = {
    'mg': 'mg',
    'mcg': 'mcg',
    'g': 'g',
    'ml': 'mL',
    'iu': 'IU',
    'units': 'Units',
    'tab': 'tablet(s)',
    'tabs': 'tablets',
    'cap': 'capsule(s)',
    'caps': 'capsules',
    'tsp': 'teaspoon (5 mL)',
    'tbsp': 'tablespoon (15 mL)',
    'sachet': 'sachet',
    'puff': 'puff(s)',
    'drop': 'drop(s)',
    'drops': 'drops',
  };

  static String? decode(String token) {
    final lower = token.toLowerCase().trim();
    return _dosageFreq[lower] ?? _routeMap[lower] ?? _doseUnits[lower];
  }

  static String annotateDosage(String raw) {
    if (raw.isEmpty) return raw;
    final tokens = raw.split(RegExp(r'[\s/,]+'));
    final parts = <String>[];
    for (final t in tokens) {
      if (t.isEmpty) continue;
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

// ── In-memory fuzzy DB entry ──────────────────────────────────────────────────

class MedicineEntry {
  final String canonical;
  final List<String> aliases;
  final String category;
  final String? commonDose;

  const MedicineEntry({
    required this.canonical,
    required this.aliases,
    required this.category,
    this.commonDose,
  });
}

// ── In-memory fuzzy DB (common Indian medicines for fast local matching) ───────

class MedicineDatabase {
  static final List<MedicineEntry> _db = [
    // ── Antibiotics ──────────────────────────────────────────────────────
    MedicineEntry(canonical: 'Amoxicillin', aliases: [
      'amox', 'amoxil', 'amoxycillin', 'amoxcillin', 'amoxicilin',
      'amoxyclin', 'amox500', 'arnoxicillin', 'arnox', 'amoxicillin 500',
      'amoxicillin 250',
    ], category: 'Antibiotic', commonDose: '500mg Three times daily (TDS) x 5 days'),

    MedicineEntry(canonical: 'Azithromycin', aliases: [
      'azith', 'azithro', 'azee', 'zithromax', 'azimax', 'azitro',
      'azithro500', 'azithromycin 500', 'azithromycin 250',
    ], category: 'Antibiotic', commonDose: '500mg Once daily (OD) x 3 days'),

    MedicineEntry(canonical: 'Ciprofloxacin', aliases: [
      'cipro', 'cifran', 'ciprox', 'ciproflox', 'ciprobay',
      'ciprofloxasin', 'ciprofloxcin', 'ciprofloxacin 500',
    ], category: 'Antibiotic', commonDose: '500mg Twice daily (BD) x 5 days'),

    MedicineEntry(canonical: 'Metronidazole', aliases: [
      'metro', 'flagyl', 'metrogyl', 'metronid', 'metronidazol',
      'metronidazle', 'metrodazole', 'metronidazole 400',
    ], category: 'Antibiotic', commonDose: '400mg Three times daily (TDS) x 5 days'),

    MedicineEntry(canonical: 'Doxycycline', aliases: [
      'doxy', 'doxycyclin', 'doxycline', 'vibramycin', 'doxt',
      'doxycycl', 'doxycycline 100',
    ], category: 'Antibiotic', commonDose: '100mg Twice daily (BD)'),

    MedicineEntry(canonical: 'Cephalexin', aliases: [
      'cefalexin', 'keflex', 'cephal', 'cephalex', 'cefalex',
      'cephlex', 'cephalexin 500',
    ], category: 'Antibiotic', commonDose: '500mg Four times daily (QDS) x 7 days'),

    MedicineEntry(canonical: 'Co-Amoxiclav', aliases: [
      'augmentin', 'coamoxiclav', 'amoxiclav', 'co amoxiclav',
      'augmentin 625', 'augmentin 375', 'co-amox', 'coamox',
    ], category: 'Antibiotic', commonDose: '625mg Three times daily (TDS) x 5 days'),

    MedicineEntry(canonical: 'Levofloxacin', aliases: [
      'levo', 'levox', 'tavanic', 'levoflox', 'levofloxacin 500',
      'levofloxacin 750',
    ], category: 'Antibiotic', commonDose: '500mg Once daily (OD) x 5 days'),

    // ── Analgesics / NSAIDs ──────────────────────────────────────────────
    MedicineEntry(canonical: 'Paracetamol', aliases: [
      'pcm', 'para', 'crocin', 'calpol', 'acetaminophen', 'tylenol',
      'paracet', 'paracetmol', 'parcetamol', 'paracetamole',
      'paracetamo', 'p500', 'panadol', 'dolo', 'dolo650',
      'paracetamol 500', 'paracetamol 650', 'paracetamol 1000',
    ], category: 'Analgesic/Antipyretic', commonDose: '500mg Four times daily (QDS) as needed'),

    MedicineEntry(canonical: 'Ibuprofen', aliases: [
      'ibuf', 'brufen', 'ibu', 'advil', 'nurofen', 'ibupro',
      'ibuprofen 400', 'ibuprofen 200', 'ibuprofen 600', 'ibufren',
    ], category: 'NSAID', commonDose: '400mg Three times daily (TDS) after food'),

    MedicineEntry(canonical: 'Diclofenac', aliases: [
      'diclo', 'voveran', 'voltaren', 'diclofenac sodium',
      'diclofen', 'diclof', 'voltarol', 'diclofenac 50', 'diclofenac 75',
    ], category: 'NSAID', commonDose: '50mg Twice daily (BD)/Three times daily (TDS)'),

    MedicineEntry(canonical: 'Aspirin', aliases: [
      'asp', 'disprin', 'ecosprin', 'asprin', 'aspirin 75',
      'aspirin 150', 'ecosprin 75', 'asa', 'ecosprin75',
    ], category: 'Antiplatelet/Analgesic', commonDose: '75mg Once daily (OD)'),

    MedicineEntry(canonical: 'Aceclofenac', aliases: [
      'aceclo', 'aceclof', 'zerodol', 'hifenac', 'aceclofenac 100',
    ], category: 'NSAID', commonDose: '100mg Twice daily (BD) after food'),

    // ── Antacids / GI ────────────────────────────────────────────────────
    MedicineEntry(canonical: 'Omeprazole', aliases: [
      'ome', 'omez', 'prilosec', 'losec', 'omeprazol',
      'omeprazole 20', 'omeprazole 40', 'omprazole', 'omeprazol 20',
    ], category: 'Proton Pump Inhibitor', commonDose: '20mg Once daily (OD) before breakfast'),

    MedicineEntry(canonical: 'Pantoprazole', aliases: [
      'panto', 'pan', 'pantop', 'protonix', 'pantoprazol',
      'pantoprazole 40', 'pantoz', 'pantoprazole 20',
    ], category: 'Proton Pump Inhibitor', commonDose: '40mg Once daily (OD) before breakfast'),

    MedicineEntry(canonical: 'Ondansetron', aliases: [
      'onda', 'zofran', 'emeset', 'ondan', 'ondansetron 4',
      'ondansetron 8', 'ondanst',
    ], category: 'Antiemetic', commonDose: '4-8mg Three times daily (TDS)'),

    MedicineEntry(canonical: 'Domperidone', aliases: [
      'domp', 'dom', 'motilium', 'domperidone 10', 'domperi',
      'domperidon', 'domstal',
    ], category: 'Prokinetic', commonDose: '10mg Three times daily (TDS) before meals'),

    // ── Antihypertensives ─────────────────────────────────────────────────
    MedicineEntry(canonical: 'Amlodipine', aliases: [
      'amlo', 'norvasc', 'amlong', 'amlod', 'amlodipine 5',
      'amlodipine 10', 'amlodipin', 'amlodip',
    ], category: 'Calcium Channel Blocker', commonDose: '5-10mg Once daily (OD)'),

    MedicineEntry(canonical: 'Atenolol', aliases: [
      'aten', 'tenormin', 'atenolol 50', 'atenolol 100',
      'atenolol 25', 'atenol',
    ], category: 'Beta Blocker', commonDose: '50mg Once daily (OD)'),

    MedicineEntry(canonical: 'Losartan', aliases: [
      'losar', 'cozaar', 'losartan 50', 'losartan 25', 'losartan 100',
      'losartaan', 'losacar',
    ], category: 'ARB', commonDose: '50mg Once daily (OD)'),

    MedicineEntry(canonical: 'Telmisartan', aliases: [
      'telmi', 'micardis', 'telma', 'telmis', 'telmisartan 40',
      'telmisartan 80',
    ], category: 'ARB', commonDose: '40mg Once daily (OD)'),

    MedicineEntry(canonical: 'Ramipril', aliases: [
      'rami', 'altace', 'hopace', 'ramipr', 'ramipril 5',
      'ramipril 10', 'ramipril 2.5',
    ], category: 'ACE Inhibitor', commonDose: '5mg Once daily (OD)'),

    MedicineEntry(canonical: 'Furosemide', aliases: [
      'furo', 'lasix', 'frusemide', 'furosemide 40', 'frusemide 40',
    ], category: 'Loop Diuretic', commonDose: '40mg Once daily (OD) morning'),

    // ── Antidiabetics ─────────────────────────────────────────────────────
    MedicineEntry(canonical: 'Metformin', aliases: [
      'met', 'glucophage', 'glycomet', 'metformin 500', 'metformin 1000',
      'metformin sr', 'metformin xr', 'metformin 850', 'metfo',
      'metformine', 'metformin 1g',
    ], category: 'Antidiabetic', commonDose: '500mg Twice daily (BD) with meals'),

    MedicineEntry(canonical: 'Glimepiride', aliases: [
      'glime', 'amaryl', 'glimp', 'glimepiride 1', 'glimepiride 2',
      'glimepiride 4', 'glimep',
    ], category: 'Antidiabetic', commonDose: '1-2mg Once daily (OD)'),

    // ── Lipid Lowering ────────────────────────────────────────────────────
    MedicineEntry(canonical: 'Atorvastatin', aliases: [
      'atorv', 'lipitor', 'atorva', 'atorvastatin 10', 'atorvastatin 20',
      'atorvastatin 40', 'atrovastat', 'atorvastat', 'storvas',
    ], category: 'Statin', commonDose: '10-40mg Once daily (OD) at night'),

    MedicineEntry(canonical: 'Rosuvastatin', aliases: [
      'rosuv', 'crestor', 'rosuvast', 'rosuvastatin 10', 'rosuvastatin 20',
      'rosuvastatin 5',
    ], category: 'Statin', commonDose: '10-20mg Once daily (OD)'),

    // ── Respiratory ───────────────────────────────────────────────────────
    MedicineEntry(canonical: 'Salbutamol', aliases: [
      'salb', 'ventolin', 'albuterol', 'salbutamol inhaler',
      'salbutamol 2mg', 'salbutamol 4mg', 'asthalin', 'asthalin inhaler',
    ], category: 'Bronchodilator', commonDose: '2-4mg Three times daily (TDS) or inhaler as needed'),

    MedicineEntry(canonical: 'Prednisolone', aliases: [
      'pred', 'predniso', 'wysolone', 'prednisolone 5', 'prednisolone 10',
      'prednisolone 20', 'prednisolon', 'predn', 'prednisolone 40',
    ], category: 'Corticosteroid', commonDose: '5-40mg Once daily (OD)'),

    MedicineEntry(canonical: 'Cetirizine', aliases: [
      'cetir', 'zyrtec', 'alerid', 'cetriz', 'cetirizin',
      'cetirizine 10', 'cetrizine', 'okacet',
    ], category: 'Antihistamine', commonDose: '10mg Once daily (OD) at night'),

    MedicineEntry(canonical: 'Levocetirizine', aliases: [
      'levocet', 'xyzal', 'levocetriz', 'levocetirizin',
      'levocetirizine 5', 'levo5',
    ], category: 'Antihistamine', commonDose: '5mg Once daily (OD) at night'),

    MedicineEntry(canonical: 'Montelukast', aliases: [
      'monte', 'singulair', 'montek', 'montelukast 10', 'monteluk',
      'montelu',
    ], category: 'Leukotriene Antagonist', commonDose: '10mg Once daily (OD) at night'),

    // ── Vitamins / Supplements ────────────────────────────────────────────
    MedicineEntry(canonical: 'Vitamin D3', aliases: [
      'vit d', 'vit d3', 'vitamin d', 'cholecalciferol', 'd3', 'calcirol',
      'uprise d3', 'vit-d', 'vitamin d3 60000', 'arachitol', 'd3 60000',
    ], category: 'Supplement', commonDose: '60,000 IU weekly x 8 weeks'),

    MedicineEntry(canonical: 'Vitamin B12', aliases: [
      'vit b12', 'b12', 'mecobalamin', 'methylcobalamin', 'methycobal',
      'neurobion', 'mecob', 'mecobal', 'cobamamide',
    ], category: 'Supplement', commonDose: '500mcg Once daily (OD)'),

    MedicineEntry(canonical: 'Folic Acid', aliases: [
      'folic', 'folate', 'fol', 'folic acid 5mg', 'folinas',
      'folvite', 'folic 5',
    ], category: 'Supplement', commonDose: '5mg Once daily (OD)'),

    MedicineEntry(canonical: 'Ferrous Sulphate', aliases: [
      'iron', 'ferrous sulphate', 'fesolate', 'ferrous sulfate',
      'iron tab', 'hemfer', 'ferrous', 'iron 150', 'fefol',
      'ferrous ascorbate',
    ], category: 'Iron Supplement', commonDose: '200mg Twice daily (BD)'),

    MedicineEntry(canonical: 'Calcium Carbonate', aliases: [
      'calci', 'calcium', 'caltrate', 'shelcal', 'calcium 500',
      'calcium carbonate', 'calcitab', 'calcium 1000', 'shelcal 500',
    ], category: 'Calcium Supplement', commonDose: '500mg Twice daily (BD)'),

    // ── Thyroid ───────────────────────────────────────────────────────────
    MedicineEntry(canonical: 'Levothyroxine', aliases: [
      'synthroid', 'thyrox', 'levothyrox', 'eltroxin',
      'levothyroxine 25', 'levothyroxine 50', 'levothyroxine 75',
      'levothyroxine 100', 'thyroxine', 'thyronorm', 'levo25', 'levo50',
    ], category: 'Thyroid Hormone', commonDose: '25-100mcg Once daily (OD) fasting'),

    // ── CNS / Neurological ────────────────────────────────────────────────
    MedicineEntry(canonical: 'Gabapentin', aliases: [
      'gaba', 'neurontin', 'gabapen', 'gabapentin 300', 'gabapentin 100',
      'gabapentin 400',
    ], category: 'Anticonvulsant/Neuropathic', commonDose: '300mg Three times daily (TDS)'),

    MedicineEntry(canonical: 'Pregabalin', aliases: [
      'pregab', 'lyrica', 'pregalin', 'pregabalin 75', 'pregabalin 150',
      'pregabalin 300',
    ], category: 'Anticonvulsant/Neuropathic', commonDose: '75mg Twice daily (BD)'),

    MedicineEntry(canonical: 'Alprazolam', aliases: [
      'alp', 'xanax', 'restyl', 'alpraz', 'alprax', 'alprazolam 0.25',
      'alprazolam 0.5',
    ], category: 'Benzodiazepine', commonDose: '0.25-0.5mg Twice daily (BD)/Three times daily (TDS)'),

    MedicineEntry(canonical: 'Sertraline', aliases: [
      'sert', 'zoloft', 'serta', 'sertraline 50', 'sertraline 100',
      'lustral',
    ], category: 'SSRI Antidepressant', commonDose: '50mg Once daily (OD)'),

    MedicineEntry(canonical: 'Amitriptyline', aliases: [
      'amit', 'elavil', 'amitril', 'amitriptyline 10', 'amitriptyline 25',
      'tryptomer',
    ], category: 'Tricyclic Antidepressant', commonDose: '10-25mg At bedtime (HS)'),

    // ── Common Indian Combos ──────────────────────────────────────────────
    MedicineEntry(canonical: 'Oxalgin DP', aliases: [
      'oxalgin dp', 'oxalgin-dp', 'oxalgindp', 'oxalgin',
      'ox algin dp', 'oxalgin d', 'oxalgln dp',
    ], category: 'NSAID Combo (Diclofenac+Paracetamol+Serratiopeptidase)',
        commonDose: 'Twice daily (BD) after food'),

    MedicineEntry(canonical: 'Neuforce', aliases: [
      'neuforce', 'neuroforce', 'nuerforce', 'neutroforce',
      'neuforece', 'neuforce 300', 'neufonce',
    ], category: 'Nerve Supplement (Methylcobalamin+Alpha Lipoic Acid)',
        commonDose: 'Once daily (OD)'),

    MedicineEntry(canonical: 'Aristozyme', aliases: [
      'aristozyme', 'aristozyke', 'aritrozyme', 'aristozym',
      'aristoyme', 'ariloryee', 'ariloryce gold', 'aristozyme gold',
    ], category: 'Digestive Enzyme Syrup',
        commonDose: '10ml Three times daily (TDS) after food'),

    MedicineEntry(canonical: 'Pan D', aliases: [
      'pan d', 'pan-d', 'pand', 'pan 40', 'pantodac',
    ], category: 'PPI Combo (Pantoprazole+Domperidone)',
        commonDose: 'Once daily (OD) before breakfast'),

    MedicineEntry(canonical: 'Montair LC', aliases: [
      'montair lc', 'montair-lc', 'montairlc', 'montair',
    ], category: 'Antiallergic Combo (Montelukast+Levocetirizine)',
        commonDose: 'Once daily (OD) at night'),

    MedicineEntry(canonical: 'Taxim O', aliases: [
      'taxim o', 'taxim-o', 'taxim', 'cefixime 200',
    ], category: 'Antibiotic (Cefixime 200mg)',
        commonDose: 'Twice daily (BD) x 5-7 days'),

    MedicineEntry(canonical: 'Mox 500', aliases: [
      'mox 500', 'mox500', 'mox', 'alec pro', 'alecpro',
      'alec bro', 'alec pro 500', 'alecbro',
    ], category: 'Antibiotic (Amoxicillin 500mg)',
        commonDose: 'Three times daily (TDS) x 5-7 days'),

    MedicineEntry(canonical: 'Dolo 650', aliases: [
      'dolo 650', 'dolo650', 'dolo', 'dolo 500',
    ], category: 'Analgesic/Antipyretic (Paracetamol 650mg)',
        commonDose: 'Three times daily (TDS) as needed'),

    MedicineEntry(canonical: 'Zerodol SP', aliases: [
      'zerodol sp', 'zerodol-sp', 'zerodolsp', 'zerodol',
    ], category: 'NSAID Combo (Aceclofenac+Paracetamol+Serratiopeptidase)',
        commonDose: 'Twice daily (BD) after food'),

    MedicineEntry(canonical: 'Chymoral Forte', aliases: [
      'chymoral forte', 'chymoral', 'chymorol', 'chimoral forte',
    ], category: 'Enzyme (Trypsin+Chymotrypsin)',
        commonDose: 'Twice daily (BD) on empty stomach'),

    MedicineEntry(canonical: 'Becosules', aliases: [
      'becosules', 'becoules', 'becozymes', 'beco z',
    ], category: 'Vitamin B Complex',
        commonDose: 'Once daily (OD) after food'),
  ];

  /// Fast fuzzy match against the in-memory list.
  static MedicineMatch? findBest(String rawToken, {double minScore = 0.42}) {
    if (rawToken.trim().isEmpty) return null;
    final lower = rawToken.toLowerCase().trim();

    if (RegExp(r'^\d+(?:mg|mcg|ml|g|iu|tab|cap)$').hasMatch(lower)) {
      return null;
    }

    MedicineEntry? bestEntry;
    double bestScore = 0.0;
    String? matchedAlias;

    for (final entry in _db) {
      final cScore = _similarity(lower, entry.canonical.toLowerCase());
      if (cScore > bestScore) {
        bestScore = cScore;
        bestEntry = entry;
        matchedAlias = null;
      }
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

  static double _similarity(String a, String b) {
    if (a == b) return 1.0;
    if (b.startsWith(a) || a.startsWith(b)) {
      final ratio = a.length < b.length ? a.length / b.length : b.length / a.length;
      return 0.72 + 0.28 * ratio;
    }
    if (b.contains(a) || a.contains(b)) {
      final ratio = a.length < b.length ? a.length / b.length : b.length / a.length;
      return 0.55 + 0.25 * ratio;
    }
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

// ── SQLite DB service for the full 2.5 lakh medicine asset ───────────────────
//
// The database is bundled at assets/db/medicines.db.
// On first launch it is copied from the asset bundle to the app's documents
// directory, where sqflite can open it read/write.
//
// Expected table structure (matches your CSV-converted DB):
//   CREATE TABLE medicines (
//     id INTEGER PRIMARY KEY,
//     name TEXT,
//     manufacturer_name TEXT,
//     type TEXT,
//     short_composition1 TEXT,
//     short_composition2 TEXT
//   );

class MedicineDatabaseService {
  static Database? _database;
  static const String _assetPath = 'assets/db/medicines.db';
  static const String _dbFileName = 'medicines.db';

  /// Returns the opened database, copying from assets on first run.
  static Future<Database> get database async {
    if (_database != null) return _database!;

    final dir = await getApplicationDocumentsDirectory();
    final dbPath = join(dir.path, _dbFileName);

    // Copy from asset bundle if not already on disk
    if (!await File(dbPath).exists()) {
      final ByteData data = await rootBundle.load(_assetPath);
      final List<int> bytes = data.buffer.asUint8List();
      await File(dbPath).writeAsBytes(bytes, flush: true);
    }

    _database = await openDatabase(dbPath, readOnly: true);
    return _database!;
  }

  /// Search by medicine name (partial, case-insensitive).
  /// Returns up to [limit] results.
  static Future<List<Map<String, dynamic>>> searchByName(
      String query, {
        int limit = 10,
      }) async {
    if (query.trim().isEmpty) return [];
    final db = await database;
    return db.query(
      'medicines',
      where: 'name LIKE ?',
      whereArgs: ['%${query.trim()}%'],
      limit: limit,
    );
  }

  /// Search by composition (ingredient), e.g. "Paracetamol".
  static Future<List<Map<String, dynamic>>> searchByComposition(
      String composition, {
        int limit = 10,
      }) async {
    if (composition.trim().isEmpty) return [];
    final db = await database;
    final q = '%${composition.trim()}%';
    return db.rawQuery(
      '''
      SELECT * FROM medicines
      WHERE short_composition1 LIKE ?
         OR short_composition2 LIKE ?
      LIMIT ?
      ''',
      [q, q, limit],
    );
  }

  /// Fuzzy-style search: tries exact name match first, then LIKE, then
  /// composition. Returns the best [limit] candidates merged together.
  static Future<List<Map<String, dynamic>>> smartSearch(
      String query, {
        int limit = 10,
      }) async {
    if (query.trim().isEmpty) return [];
    final db = await database;
    final q = query.trim();

    // 1. Exact name match (highest priority)
    final exact = await db.query(
      'medicines',
      where: 'LOWER(name) = ?',
      whereArgs: [q.toLowerCase()],
      limit: limit,
    );
    if (exact.length >= limit) return exact;

    // 2. LIKE name match
    final like = await db.query(
      'medicines',
      where: 'name LIKE ?',
      whereArgs: ['%$q%'],
      limit: limit - exact.length,
    );

    final seen = <dynamic>{};
    final results = <Map<String, dynamic>>[];
    for (final row in [...exact, ...like]) {
      final id = row['id'];
      if (seen.add(id)) results.add(row);
    }

    if (results.length >= limit) return results;

    // 3. Composition fallback
    final comp = await searchByComposition(q, limit: limit - results.length);
    for (final row in comp) {
      final id = row['id'];
      if (seen.add(id)) results.add(row);
    }

    return results;
  }

  /// Close the database connection (call on app dispose if needed).
  static Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}