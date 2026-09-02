import 'dart:convert';

const inventorinatorKitPackageFormat = 'inventorinator-kit';
const inventorinatorKitPackageSchemaVersion = 1;
const inventorinatorKitPackageExtension = 'inventorinator-kit.json';

const supportedKitPackageTypes = <String>{
  'other',
  'fastener',
  'filament',
  'printedPart',
  'resin',
  'nozzle',
  'heatBreak',
  'heatBlock',
  'sock',
};

class KitPackageSource {
  const KitPackageSource({required this.url, this.title = ''});

  final String url;
  final String title;
}

class KitPackageSection {
  const KitPackageSection({
    required this.id,
    required this.name,
    this.description = '',
  });

  final String id;
  final String name;
  final String description;
}

class KitPackagePart {
  const KitPackagePart({
    required this.id,
    required this.name,
    required this.type,
    required this.sectionId,
    required this.quantity,
    this.material = '',
    this.brand = '',
    this.unitCost = 0,
    this.compatibility = const [],
    this.sources = const [],
  });

  final String id;
  final String name;
  final String type;
  final String sectionId;
  final double quantity;
  final String material;
  final String brand;
  final double unitCost;
  final List<String> compatibility;
  final List<KitPackageSource> sources;
}

class KitPackageMachine {
  const KitPackageMachine({
    required this.id,
    required this.name,
    required this.type,
    this.model = '',
    this.address = '',
    this.sources = const [],
  });

  final String id;
  final String name;
  final String type;
  final String model;
  final String address;
  final List<KitPackageSource> sources;
}

class InventorinatorKitPackage {
  const InventorinatorKitPackage({
    required this.id,
    required this.name,
    required this.description,
    required this.sources,
    required this.sections,
    required this.parts,
    required this.machines,
  });

  final String id;
  final String name;
  final String description;
  final List<KitPackageSource> sources;
  final List<KitPackageSection> sections;
  final List<KitPackagePart> parts;
  final List<KitPackageMachine> machines;
}

class KitPackageParseResult {
  const KitPackageParseResult({required this.package, required this.errors});

  final InventorinatorKitPackage? package;
  final List<String> errors;
  bool get isValid => package != null && errors.isEmpty;
}

KitPackageParseResult parseInventorinatorKitPackage(String source) {
  final errors = <String>[];
  Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException catch (error) {
    return KitPackageParseResult(
      package: null,
      errors: ['Invalid JSON: ${error.message}'],
    );
  }
  if (decoded is! Map<String, dynamic>) {
    return const KitPackageParseResult(
      package: null,
      errors: ['The package root must be a JSON object.'],
    );
  }
  final root = decoded;
  if (root['format'] != inventorinatorKitPackageFormat) {
    errors.add('format must be "$inventorinatorKitPackageFormat".');
  }
  if (root['schemaVersion'] != inventorinatorKitPackageSchemaVersion) {
    errors.add('schemaVersion must be $inventorinatorKitPackageSchemaVersion.');
  }
  final id = _requiredIdentifier(root, 'id', 'Package', errors);
  final name = _requiredString(root, 'name', 'Package', errors);
  final description = _optionalString(root, 'description', 'Package', errors);
  final sources = _readSources(root['sources'], 'Package', errors);
  final sections = <KitPackageSection>[];
  final sectionIds = <String>{};
  final rawSections = _objectList(root['sections'], 'sections', errors);
  for (var index = 0; index < rawSections.length; index++) {
    final value = rawSections[index];
    final label = 'Section ${index + 1}';
    final sectionId = _requiredIdentifier(value, 'id', label, errors);
    final sectionName = _requiredString(value, 'name', label, errors);
    final sectionDescription = _optionalString(
      value,
      'description',
      label,
      errors,
    );
    if (sectionId.isNotEmpty && !sectionIds.add(sectionId)) {
      errors.add('$label repeats section id "$sectionId".');
    }
    sections.add(
      KitPackageSection(
        id: sectionId,
        name: sectionName,
        description: sectionDescription,
      ),
    );
  }
  if (sections.isEmpty) errors.add('At least one section is required.');

  final parts = <KitPackagePart>[];
  final partIds = <String>{};
  final rawParts = _objectList(root['parts'], 'parts', errors);
  for (var index = 0; index < rawParts.length; index++) {
    final value = rawParts[index];
    final label = 'Part ${index + 1}';
    final partId = _requiredIdentifier(value, 'id', label, errors);
    final partName = _requiredString(value, 'name', label, errors);
    final type = _requiredString(value, 'type', label, errors);
    final sectionId = _requiredIdentifier(value, 'section', label, errors);
    final quantity = _positiveNumber(value, 'quantity', label, errors);
    final unitCost = _nonNegativeNumber(
      value,
      'unitCost',
      label,
      errors,
      fallback: 0,
    );
    if (partId.isNotEmpty && !partIds.add(partId)) {
      errors.add('$label repeats part id "$partId".');
    }
    if (type.isNotEmpty && !supportedKitPackageTypes.contains(type)) {
      errors.add('$label has unsupported type "$type".');
    }
    if (sectionId.isNotEmpty && !sectionIds.contains(sectionId)) {
      errors.add('$label references unknown section "$sectionId".');
    }
    parts.add(
      KitPackagePart(
        id: partId,
        name: partName,
        type: type,
        sectionId: sectionId,
        quantity: quantity,
        material: _optionalString(value, 'material', label, errors),
        brand: _optionalString(value, 'brand', label, errors),
        unitCost: unitCost,
        compatibility: _stringList(
          value['compatibility'],
          '$label compatibility',
          errors,
        ),
        sources: _readSources(value['sources'], label, errors),
      ),
    );
  }
  if (parts.isEmpty) errors.add('At least one part is required.');

  final machines = <KitPackageMachine>[];
  final machineIds = <String>{};
  final rawMachines = _objectList(
    root['machines'],
    'machines',
    errors,
    optional: true,
  );
  for (var index = 0; index < rawMachines.length; index++) {
    final value = rawMachines[index];
    final label = 'Machine ${index + 1}';
    final machineId = _requiredIdentifier(value, 'id', label, errors);
    if (machineId.isNotEmpty && !machineIds.add(machineId)) {
      errors.add('$label repeats machine id "$machineId".');
    }
    machines.add(
      KitPackageMachine(
        id: machineId,
        name: _requiredString(value, 'name', label, errors),
        type: _requiredString(value, 'type', label, errors),
        model: _optionalString(value, 'model', label, errors),
        address: _optionalString(value, 'address', label, errors),
        sources: _readSources(value['sources'], label, errors),
      ),
    );
  }

  if (errors.isNotEmpty) {
    return KitPackageParseResult(package: null, errors: errors);
  }
  return KitPackageParseResult(
    package: InventorinatorKitPackage(
      id: id,
      name: name,
      description: description,
      sources: sources,
      sections: sections,
      parts: parts,
      machines: machines,
    ),
    errors: const [],
  );
}

List<Map<String, dynamic>> _objectList(
  Object? value,
  String field,
  List<String> errors, {
  bool optional = false,
}) {
  if (value == null && optional) return const [];
  if (value is! List) {
    errors.add('$field must be an array.');
    return const [];
  }
  final result = <Map<String, dynamic>>[];
  for (var index = 0; index < value.length; index++) {
    final entry = value[index];
    if (entry is Map<String, dynamic>) {
      result.add(entry);
    } else {
      errors.add('$field entry ${index + 1} must be an object.');
    }
  }
  return result;
}

String _requiredIdentifier(
  Map<String, dynamic> object,
  String field,
  String label,
  List<String> errors,
) {
  final value = _requiredString(object, field, label, errors);
  if (value.isNotEmpty && !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value)) {
    errors.add('$label $field may only contain letters, numbers, ., _, and -.');
  }
  return value;
}

String _requiredString(
  Map<String, dynamic> object,
  String field,
  String label,
  List<String> errors,
) {
  final value = object[field];
  if (value is! String || value.trim().isEmpty) {
    errors.add('$label requires a non-empty $field.');
    return '';
  }
  return value.trim();
}

String _optionalString(
  Map<String, dynamic> object,
  String field,
  String label,
  List<String> errors,
) {
  final value = object[field];
  if (value == null) return '';
  if (value is! String) {
    errors.add('$label $field must be text.');
    return '';
  }
  return value.trim();
}

double _positiveNumber(
  Map<String, dynamic> object,
  String field,
  String label,
  List<String> errors,
) {
  final value = object[field];
  if (value is! num || !value.isFinite || value <= 0) {
    errors.add('$label $field must be greater than 0.');
    return 0;
  }
  return value.toDouble();
}

double _nonNegativeNumber(
  Map<String, dynamic> object,
  String field,
  String label,
  List<String> errors, {
  required double fallback,
}) {
  final value = object[field];
  if (value == null) return fallback;
  if (value is! num || !value.isFinite || value < 0) {
    errors.add('$label $field must be 0 or greater.');
    return fallback;
  }
  return value.toDouble();
}

List<String> _stringList(Object? value, String label, List<String> errors) {
  if (value == null) return const [];
  if (value is! List || value.any((entry) => entry is! String)) {
    errors.add('$label must be an array of text values.');
    return const [];
  }
  return value
      .cast<String>()
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toList();
}

List<KitPackageSource> _readSources(
  Object? value,
  String label,
  List<String> errors,
) {
  if (value == null) return const [];
  if (value is! List) {
    errors.add('$label sources must be an array.');
    return const [];
  }
  final result = <KitPackageSource>[];
  for (var index = 0; index < value.length; index++) {
    final entry = value[index];
    if (entry is! Map<String, dynamic>) {
      errors.add('$label source ${index + 1} must be an object.');
      continue;
    }
    final url = _requiredString(
      entry,
      'url',
      '$label source ${index + 1}',
      errors,
    );
    final uri = Uri.tryParse(url);
    if (url.isNotEmpty &&
        (uri == null ||
            !const {'http', 'https'}.contains(uri.scheme) ||
            uri.host.isEmpty)) {
      errors.add('$label source ${index + 1} must use a valid HTTP(S) URL.');
    }
    result.add(
      KitPackageSource(
        url: url,
        title: _optionalString(
          entry,
          'title',
          '$label source ${index + 1}',
          errors,
        ),
      ),
    );
  }
  return result;
}
