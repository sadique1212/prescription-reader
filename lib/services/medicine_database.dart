// lib/services/medicine_database.dart
// Fixed: added common abbreviations (PCM, ASA, etc.) to aliases
// so local fuzzy pass catches them even without AI

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

    MedicineEntry(canonical: 'Cloxacillin', aliases: [
      'clox', 'cloxapen', 'cloxacil', 'cloxacilin', 'cloxacillin 500',
    ], category: 'Antibiotic', commonDose: '500mg Four times daily (QDS) x 5 days'),

    MedicineEntry(canonical: 'Co-Amoxiclav', aliases: [
      'augmentin', 'coamoxiclav', 'amoxiclav', 'co amoxiclav',
      'augmentin 625', 'augmentin 375', 'co-amox', 'coamox',
    ], category: 'Antibiotic', commonDose: '625mg Three times daily (TDS) x 5 days'),

    MedicineEntry(canonical: 'Levofloxacin', aliases: [
      'levo', 'levox', 'tavanic', 'levoflox', 'levofloxacin 500',
      'levofloxacin 750',
    ], category: 'Antibiotic', commonDose: '500mg Once daily (OD) x 5 days'),

    MedicineEntry(canonical: 'Clarithromycin', aliases: [
      'clarith', 'klaricid', 'biaxin', 'clarithromycin 500',
      'clarithromycin 250',
    ], category: 'Antibiotic', commonDose: '500mg Twice daily (BD) x 7 days'),

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

    MedicineEntry(canonical: 'Naproxen', aliases: [
      'naprox', 'naprosyn', 'aleve', 'naproxin', 'napro',
      'naproxen 250', 'naproxen 500',
    ], category: 'NSAID', commonDose: '250-500mg Twice daily (BD)'),

    MedicineEntry(canonical: 'Tramadol', aliases: [
      'trama', 'tramol', 'ultram', 'contramal', 'tramadol hcl',
      'tramahexal', 'tramadol 50',
    ], category: 'Opioid Analgesic', commonDose: '50mg Twice daily (BD)/Three times daily (TDS)'),

    MedicineEntry(canonical: 'Aspirin', aliases: [
      'asp', 'disprin', 'ecosprin', 'asprin', 'aspirin 75',
      'aspirin 150', 'ecosprin 75', 'asa', 'ecosprin75',
    ], category: 'Antiplatelet/Analgesic', commonDose: '75mg Once daily (OD)'),

    MedicineEntry(canonical: 'Aceclofenac', aliases: [
      'aceclo', 'aceclof', 'zerodol', 'hifenac', 'aceclofenac 100',
    ], category: 'NSAID', commonDose: '100mg Twice daily (BD) after food'),

    MedicineEntry(canonical: 'Mefenamic Acid', aliases: [
      'mefenamic', 'ponstan', 'meftal', 'mefenamic acid 500',
    ], category: 'NSAID', commonDose: '500mg Three times daily (TDS)'),

    // ── Antacids / GI ────────────────────────────────────────────────────
    MedicineEntry(canonical: 'Omeprazole', aliases: [
      'ome', 'omez', 'prilosec', 'losec', 'omeprazol',
      'omeprazole 20', 'omeprazole 40', 'omprazole', 'omeprazol 20',
    ], category: 'Proton Pump Inhibitor', commonDose: '20mg Once daily (OD) before breakfast'),

    MedicineEntry(canonical: 'Pantoprazole', aliases: [
      'panto', 'pan', 'pantop', 'protonix', 'pantoprazol',
      'pantoprazole 40', 'pantoz', 'pantoprazole 20',
    ], category: 'Proton Pump Inhibitor', commonDose: '40mg Once daily (OD) before breakfast'),

    MedicineEntry(canonical: 'Rabeprazole', aliases: [
      'rabe', 'rabep', 'rablet', 'pariet', 'rabeprazole 20',
    ], category: 'Proton Pump Inhibitor', commonDose: '20mg Once daily (OD)'),

    MedicineEntry(canonical: 'Ranitidine', aliases: [
      'rani', 'zantac', 'ranit', 'ranitidine 150', 'ranitidin',
    ], category: 'H2 Blocker', commonDose: '150mg Twice daily (BD)'),

    MedicineEntry(canonical: 'Ondansetron', aliases: [
      'onda', 'zofran', 'emeset', 'ondan', 'ondansetron 4',
      'ondansetron 8', 'ondanst',
    ], category: 'Antiemetic', commonDose: '4-8mg Three times daily (TDS)'),

    MedicineEntry(canonical: 'Domperidone', aliases: [
      'domp', 'dom', 'motilium', 'domperidone 10', 'domperi',
      'domperidon', 'domstal',
    ], category: 'Prokinetic', commonDose: '10mg Three times daily (TDS) before meals'),

    MedicineEntry(canonical: 'Metoclopramide', aliases: [
      'metoclo', 'emex', 'maxolon', 'metoclop', 'metoclopramid',
    ], category: 'Antiemetic', commonDose: '10mg Three times daily (TDS)'),

    // ── Antihypertensives ─────────────────────────────────────────────────
    MedicineEntry(canonical: 'Amlodipine', aliases: [
      'amlo', 'norvasc', 'amlong', 'amlod', 'amlodipine 5',
      'amlodipine 10', 'amlodipin', 'amlodip',
    ], category: 'Calcium Channel Blocker', commonDose: '5-10mg Once daily (OD)'),

    MedicineEntry(canonical: 'Atenolol', aliases: [
      'aten', 'tenormin', 'atenolol 50', 'atenolol 100',
      'atenolol 25', 'atenol',
    ], category: 'Beta Blocker', commonDose: '50mg Once daily (OD)'),

    MedicineEntry(canonical: 'Metoprolol', aliases: [
      'metop', 'lopressor', 'betaloc', 'metoprolol 25',
      'metoprolol 50', 'metoprolol 100',
    ], category: 'Beta Blocker', commonDose: '25-50mg Twice daily (BD)'),

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

    MedicineEntry(canonical: 'Lisinopril', aliases: [
      'lisin', 'zestril', 'prinivil', 'lisinopril 10',
      'lisinopril 5', 'lisinopr',
    ], category: 'ACE Inhibitor', commonDose: '10mg Once daily (OD)'),

    MedicineEntry(canonical: 'Hydrochlorothiazide', aliases: [
      'hctz', 'hydro', 'hydrochlorothia', 'hctz 25', 'hctz 12.5',
    ], category: 'Diuretic', commonDose: '25mg Once daily (OD) morning'),

    MedicineEntry(canonical: 'Furosemide', aliases: [
      'furo', 'lasix', 'frusemide', 'furosemide 40', 'frusemide 40',
    ], category: 'Loop Diuretic', commonDose: '40mg Once daily (OD) morning'),

    // ── Antidiabetics ─────────────────────────────────────────────────────
    MedicineEntry(canonical: 'Metformin', aliases: [
      'met', 'glucophage', 'glycomet', 'metformin 500', 'metformin 1000',
      'metformin sr', 'metformin xr', 'metformin 850', 'metfo',
      'metformine', 'metformin 1g',
    ], category: 'Antidiabetic', commonDose: '500mg Twice daily (BD) with meals'),

    MedicineEntry(canonical: 'Glibenclamide', aliases: [
      'glib', 'daonil', 'glibenclam', 'glibenclamide 5', 'glyburide',
    ], category: 'Antidiabetic', commonDose: '5mg Once daily (OD) before breakfast'),

    MedicineEntry(canonical: 'Glimepiride', aliases: [
      'glime', 'amaryl', 'glimp', 'glimepiride 1', 'glimepiride 2',
      'glimepiride 4', 'glimep',
    ], category: 'Antidiabetic', commonDose: '1-2mg Once daily (OD)'),

    MedicineEntry(canonical: 'Sitagliptin', aliases: [
      'sita', 'januvia', 'sitag', 'sitagliptin 50', 'sitagliptin 100',
    ], category: 'Antidiabetic', commonDose: '100mg Once daily (OD)'),

    MedicineEntry(canonical: 'Vildagliptin', aliases: [
      'vilda', 'galvus', 'vildag', 'vildagliptin 50',
    ], category: 'Antidiabetic', commonDose: '50mg Twice daily (BD)'),

    MedicineEntry(canonical: 'Insulin Glargine', aliases: [
      'lantus', 'basaglar', 'glargine', 'insulin glargine',
    ], category: 'Insulin', commonDose: 'As prescribed (subcutaneous) once at night'),

    // ── Lipid Lowering ────────────────────────────────────────────────────
    MedicineEntry(canonical: 'Atorvastatin', aliases: [
      'atorv', 'lipitor', 'atorva', 'atorvastatin 10', 'atorvastatin 20',
      'atorvastatin 40', 'atrovastat', 'atorvastat', 'storvas',
    ], category: 'Statin', commonDose: '10-40mg Once daily (OD) at night'),

    MedicineEntry(canonical: 'Rosuvastatin', aliases: [
      'rosuv', 'crestor', 'rosuvast', 'rosuvastatin 10', 'rosuvastatin 20',
      'rosuvastatin 5',
    ], category: 'Statin', commonDose: '10-20mg Once daily (OD)'),

    MedicineEntry(canonical: 'Fenofibrate', aliases: [
      'feno', 'tricor', 'fenofibrate 145', 'fenofibrate 160',
    ], category: 'Fibrate', commonDose: '145mg Once daily (OD) with food'),

    // ── Respiratory ───────────────────────────────────────────────────────
    MedicineEntry(canonical: 'Salbutamol', aliases: [
      'salb', 'ventolin', 'albuterol', 'salbutamol inhaler',
      'salbutamol 2mg', 'salbutamol 4mg', 'asthalin', 'asthalin inhaler',
    ], category: 'Bronchodilator', commonDose: '2-4mg Three times daily (TDS) or inhaler as needed'),

    MedicineEntry(canonical: 'Prednisolone', aliases: [
      'pred', 'predniso', 'wysolone', 'prednisolone 5', 'prednisolone 10',
      'prednisolone 20', 'prednisolon', 'predn', 'prednisolone 40',
    ], category: 'Corticosteroid', commonDose: '5-40mg Once daily (OD)'),

    MedicineEntry(canonical: 'Dexamethasone', aliases: [
      'dexa', 'dexona', 'decadron', 'dexamethasone 4', 'dexamethasone 8',
    ], category: 'Corticosteroid', commonDose: '4-8mg as prescribed'),

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

    MedicineEntry(canonical: 'Theophylline', aliases: [
      'theo', 'uniphyl', 'theophylline 200', 'theophylline 300',
      'deriphyllin',
    ], category: 'Bronchodilator', commonDose: '200mg Twice daily (BD)'),

    MedicineEntry(canonical: 'Budesonide', aliases: [
      'budes', 'pulmicort', 'budecort', 'budesonide inhaler',
    ], category: 'Inhaled Corticosteroid', commonDose: 'As prescribed (inhaler)'),

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

    MedicineEntry(canonical: 'Zinc Sulphate', aliases: [
      'zinc', 'zincovit', 'zinctab', 'zinc 20', 'zinc sulphate 20',
    ], category: 'Supplement', commonDose: '20mg Once daily (OD)'),

    // ── Thyroid ───────────────────────────────────────────────────────────
    MedicineEntry(canonical: 'Levothyroxine', aliases: [
      'synthroid', 'thyrox', 'levothyrox', 'eltroxin',
      'levothyroxine 25', 'levothyroxine 50', 'levothyroxine 75',
      'levothyroxine 100', 'thyroxine', 'thyronorm', 'levo25', 'levo50',
    ], category: 'Thyroid Hormone', commonDose: '25-100mcg Once daily (OD) fasting'),

    MedicineEntry(canonical: 'Carbimazole', aliases: [
      'carbi', 'neomercazole', 'carbimazole 5', 'carbimazole 10',
    ], category: 'Antithyroid', commonDose: '5-10mg Three times daily (TDS)'),

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

    MedicineEntry(canonical: 'Clonazepam', aliases: [
      'clona', 'rivotril', 'klonopin', 'clonazepm', 'clonazepam 0.5',
    ], category: 'Benzodiazepine', commonDose: '0.5mg Twice daily (BD)'),

    MedicineEntry(canonical: 'Sertraline', aliases: [
      'sert', 'zoloft', 'serta', 'sertraline 50', 'sertraline 100',
      'lustral',
    ], category: 'SSRI Antidepressant', commonDose: '50mg Once daily (OD)'),

    MedicineEntry(canonical: 'Escitalopram', aliases: [
      'escit', 'lexapro', 'nexito', 'escitalopram 10', 'escitalopram 20',
    ], category: 'SSRI Antidepressant', commonDose: '10mg Once daily (OD)'),

    MedicineEntry(canonical: 'Amitriptyline', aliases: [
      'amit', 'elavil', 'amitril', 'amitriptyline 10', 'amitriptyline 25',
      'tryptomer',
    ], category: 'Tricyclic Antidepressant', commonDose: '10-25mg At bedtime (HS)'),

    MedicineEntry(canonical: 'Phenytoin', aliases: [
      'pheny', 'dilantin', 'eptoin', 'phenytoin 100', 'phenytek',
    ], category: 'Anticonvulsant', commonDose: '100mg Three times daily (TDS)'),

    MedicineEntry(canonical: 'Carbamazepine', aliases: [
      'carba', 'tegretol', 'mazetol', 'carbamazepine 200',
      'carbamazepine 400',
    ], category: 'Anticonvulsant', commonDose: '200mg Twice daily (BD)/Three times daily (TDS)'),

    MedicineEntry(canonical: 'Levodopa + Carbidopa', aliases: [
      'sinemet', 'syndopa', 'levodopa', 'carbidopa', 'syndopa 110',
      'syndopa 275',
    ], category: 'Anti-Parkinsonian', commonDose: 'As prescribed'),

    // ── Cardiovascular ────────────────────────────────────────────────────
    MedicineEntry(canonical: 'Clopidogrel', aliases: [
      'clopi', 'plavix', 'deplatt', 'clopidogrel 75', 'clopilet',
    ], category: 'Antiplatelet', commonDose: '75mg Once daily (OD)'),

    MedicineEntry(canonical: 'Warfarin', aliases: [
      'warf', 'coumadin', 'warf 1', 'warf 2', 'warf 5', 'warfarin 5',
    ], category: 'Anticoagulant', commonDose: 'As per INR'),

    MedicineEntry(canonical: 'Digoxin', aliases: [
      'digo', 'lanoxin', 'digoxin 0.25', 'digoxin 0.125',
    ], category: 'Cardiac Glycoside', commonDose: '0.25mg Once daily (OD)'),

    MedicineEntry(canonical: 'Isosorbide Mononitrate', aliases: [
      'ismn', 'ismo', 'monosorb', 'isosorbide', 'imdur', 'ismn 20',
    ], category: 'Nitrate', commonDose: '20mg Twice daily (BD)'),

    // ── Antifungals ───────────────────────────────────────────────────────
    MedicineEntry(canonical: 'Fluconazole', aliases: [
      'fluco', 'diflucan', 'flucon', 'fluconazole 150', 'fluconazole 200',
    ], category: 'Antifungal', commonDose: '150mg Once weekly'),

    MedicineEntry(canonical: 'Itraconazole', aliases: [
      'itra', 'sporanox', 'canditral', 'itragen', 'itraconazole 100',
      'itraconazole 200',
    ], category: 'Antifungal', commonDose: '100-200mg Once daily (OD)'),

    // ── Antivirals ─────────────────────────────────────────────────────────
    MedicineEntry(canonical: 'Acyclovir', aliases: [
      'acyclo', 'zovirax', 'acivir', 'acyclovir 400', 'acyclovir 800',
      'aciclovir',
    ], category: 'Antiviral', commonDose: '400mg Three times daily (TDS) x 7 days'),

    MedicineEntry(canonical: 'Oseltamivir', aliases: [
      'tamiflu', 'oselti', 'oseltamivir 75',
    ], category: 'Antiviral', commonDose: '75mg Twice daily (BD) x 5 days'),

    // ── Muscle Relaxants ──────────────────────────────────────────────────
    MedicineEntry(canonical: 'Methocarbamol', aliases: [
      'robaxin', 'methocarbamol 750',
    ], category: 'Muscle Relaxant', commonDose: '750mg Three times daily (TDS)'),

    MedicineEntry(canonical: 'Thiocolchicoside', aliases: [
      'thioco', 'muscoril', 'thiocolchicoside 4', 'thiocolchicoside 8',
    ], category: 'Muscle Relaxant', commonDose: '4-8mg Twice daily (BD)'),

    MedicineEntry(canonical: 'Baclofen', aliases: [
      'baclo', 'lioresal', 'baclofen 10', 'baclofen 25',
    ], category: 'Muscle Relaxant', commonDose: '10mg Three times daily (TDS)'),

    // ── Urology ───────────────────────────────────────────────────────────
    MedicineEntry(canonical: 'Tamsulosin', aliases: [
      'tamsu', 'flomax', 'urimax', 'tamsulosin 0.4',
    ], category: 'Alpha Blocker', commonDose: '0.4mg Once daily (OD) after meal'),

    MedicineEntry(canonical: 'Sildenafil', aliases: [
      'viagra', 'silden', 'sildenafil 50', 'sildenafil 100', 'penegra',
    ], category: 'PDE5 Inhibitor', commonDose: '50mg as needed'),

    // ── Dermatology ───────────────────────────────────────────────────────
    MedicineEntry(canonical: 'Clotrimazole', aliases: [
      'clotrim', 'canesten', 'clotrimazole cream', 'candid cream',
    ], category: 'Antifungal (Topical)', commonDose: 'Apply twice daily'),

    MedicineEntry(canonical: 'Betamethasone', aliases: [
      'betam', 'diprosone', 'betnovate', 'betamethasone cream',
    ], category: 'Topical Corticosteroid', commonDose: 'Apply twice daily'),

    MedicineEntry(canonical: 'Hydrocortisone', aliases: [
      'hydrocort', 'cortisone', 'hc cream', 'hydrocortisone cream',
    ], category: 'Topical Corticosteroid', commonDose: 'Apply twice daily'),

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

    MedicineEntry(canonical: 'Zerodol SP', aliases: [
      'zerodol sp', 'zerodol-sp', 'zerodolsp', 'zerodol',
    ], category: 'NSAID Combo (Aceclofenac+Paracetamol+Serratiopeptidase)',
        commonDose: 'Twice daily (BD) after food'),

    MedicineEntry(canonical: 'Pan D', aliases: [
      'pan d', 'pan-d', 'pand', 'pan 40', 'pantodac',
    ], category: 'PPI Combo (Pantoprazole+Domperidone)',
        commonDose: 'Once daily (OD) before breakfast'),

    MedicineEntry(canonical: 'Sumo L', aliases: [
      'sumo l', 'sumo-l', 'sumol', 'sumo',
    ], category: 'NSAID Combo (Nimesulide+Paracetamol+Lornoxicam)',
        commonDose: 'Twice daily (BD) after food'),

    MedicineEntry(canonical: 'Montair LC', aliases: [
      'montair lc', 'montair-lc', 'montairlc', 'montair',
    ], category: 'Antiallergic Combo (Montelukast+Levocetirizine)',
        commonDose: 'Once daily (OD) at night'),

    MedicineEntry(canonical: 'Chymoral Forte', aliases: [
      'chymoral forte', 'chymoral', 'chymorol', 'chimoral forte',
    ], category: 'Enzyme (Trypsin+Chymotrypsin)',
        commonDose: 'Twice daily (BD) on empty stomach'),

    MedicineEntry(canonical: 'Becosules', aliases: [
      'becosules', 'becoules', 'becozymes', 'beco z',
    ], category: 'Vitamin B Complex',
        commonDose: 'Once daily (OD) after food'),

    MedicineEntry(canonical: 'Taxim O', aliases: [
      'taxim o', 'taxim-o', 'taxim', 'cefixime 200',
    ], category: 'Antibiotic (Cefixime 200mg)',
        commonDose: 'Twice daily (BD) x 5-7 days'),

    MedicineEntry(canonical: 'Mox 500', aliases: [
      'mox 500', 'mox500', 'mox', 'alec pro', 'alecpro',
      'alec bro', 'alec pro 500', 'alecbro',
    ], category: 'Antibiotic (Amoxicillin 500mg)',
        commonDose: 'Three times daily (TDS) x 5-7 days'),

    MedicineEntry(canonical: 'Nervijen', aliases: [
      'nervijen', 'nervizon', 'nervicon', 'nervigen',
    ], category: 'Nerve Vitamin (B1+B6+B12)',
        commonDose: 'Once daily (OD)'),

    MedicineEntry(canonical: 'Dolo 650', aliases: [
      'dolo 650', 'dolo650', 'dolo', 'dolo 500',
    ], category: 'Analgesic/Antipyretic (Paracetamol 650mg)',
        commonDose: 'Three times daily (TDS) as needed'),

    MedicineEntry(canonical: 'Sinarest', aliases: [
      'sinarest', 'sinarist', 'sinrest',
    ], category: 'Cold/Allergy Combo',
        commonDose: 'Twice daily (BD)'),

    MedicineEntry(canonical: 'GT 400', aliases: [
      'gt 400', 'gt400', 'bm gt 200', 'bm gt 400', 'bmgt',
      'bm gt200', 'brngt', 'brn gt', 'bm gt',
    ], category: 'Gabapentin/Pregabalin variant',
        commonDose: 'Twice daily (BD)'),
  ];

  static MedicineMatch? findBest(String rawToken, {double minScore = 0.42}) {
    if (rawToken.trim().isEmpty) return null;
    final lower = rawToken.toLowerCase().trim();

    // Skip pure dosage tokens
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

    // Exact prefix match
    if (b.startsWith(a) || a.startsWith(b)) {
      final ratio =
      a.length < b.length ? a.length / b.length : b.length / a.length;
      return 0.72 + 0.28 * ratio;
    }

    // Contains
    if (b.contains(a) || a.contains(b)) {
      final ratio =
      a.length < b.length ? a.length / b.length : b.length / a.length;
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
    final dp =
    List.generate(m + 1, (i) => List.filled(n + 1, 0));
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