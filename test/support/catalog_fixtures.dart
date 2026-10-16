import 'package:vehicle_history/data/catalog/country_names.dart';
import 'package:vehicle_history/data/catalog/vehicle_catalog.dart';

/// A small make / model catalogue in the format of the real asset, so tests
/// exercise the same parsing as the app.
///
/// Popularity is chosen so the display order is easy to predict: Fiat is
/// the most popular car make, Škoda has no ranked model, and Honda exists
/// both as a car and as a motorcycle make.
const String vehicleCatalogFixtureJson = '''
{"source":"VehiclesDB","release":"v-test","license":"CC-BY-4.0","kinds":{
"car":[
{"slug":"alfa-romeo","name":"Alfa Romeo","popularity":50,"models":[["giulia","Giulia",3],["147","147",2]]},
{"slug":"fiat","name":"Fiat","popularity":300,"models":[["multipla","Multipla",6],["doblo","Doblò",4],["panda","Panda",3],["grande-punto","Grande Punto",4],["punto","Punto",2],["500","500"]]},
{"slug":"honda","name":"Honda","popularity":80,"models":[["civic","Civic",2],["jazz","Jazz",3]]},
{"slug":"skoda","name":"Škoda","models":[["octavia","Octavia"],["fabia","Fabia"]]}
],
"van":[
{"slug":"fiat","name":"Fiat","popularity":120,"models":[["ducato","Ducato",1],["doblo","Doblò",2]]}
],
"motorcycle":[
{"slug":"honda","name":"Honda","popularity":400,"models":[["sh125","SH125",5],["sh150","SH150",5],["cb500","CB500",3]]},
{"slug":"ducati","name":"Ducati","popularity":200,"models":[["monster","Monster",2]]}
],
"moped":[
{"slug":"piaggio","name":"Piaggio","popularity":90,"models":[["liberty","Liberty",2]]}
]
}}
''';

/// [vehicleCatalogFixtureJson], parsed.
VehicleCatalog vehicleCatalogFixture() =>
    VehicleCatalog.fromJson(vehicleCatalogFixtureJson);

/// A few countries in the three app languages, in the format of the asset.
const String countryNamesFixtureJson = '''
{"source":"Unicode CLDR","release":"test","names":{
"en":{"CU":"Cuba","ES":"Spain","IT":"Italy","TR":"Türkiye","CW":"Curaçao"},
"es":{"CU":"Cuba","ES":"España","IT":"Italia","TR":"Turquía","CW":"Curazao"},
"it":{"CU":"Cuba","ES":"Spagna","IT":"Italia","TR":"Turchia","CW":"Curaçao"}
}}
''';

/// [countryNamesFixtureJson], parsed.
CountryNames countryNamesFixture() =>
    CountryNames.fromJson(countryNamesFixtureJson);
