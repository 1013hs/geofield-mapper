class GeologicalPoint {
  final int? id;
  final double latitude;
  final double longitude;
  final double altitude;
  final String lithology;      
  final String structure;      
  final String mineralization; 
  final double strike;         
  final double dipDirection;   
  final double dip;            
  final String timestamp;      

  GeologicalPoint({
    this.id,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.lithology,
    required this.structure,
    required this.mineralization,
    required this.strike,
    required this.dipDirection,
    required this.dip,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'lithology': lithology,
      'structure': structure,
      'mineralization': mineralization,
      'strike': strike,
      'dipDirection': dipDirection,
      'dip': dip,
      'timestamp': timestamp,
    };
  }

  factory GeologicalPoint.fromMap(Map<String, dynamic> map) {
    return GeologicalPoint(
      id: map['id'],
      latitude: map['latitude'],
      longitude: map['longitude'],
      altitude: map['altitude'],
      lithology: map['lithology'],
      structure: map['structure'],
      mineralization: map['mineralization'],
      strike: map['strike'],
      dipDirection: map['dipDirection'],
      dip: map['dip'],
      timestamp: map['timestamp'],
    );
  }

  Map<String, dynamic> toGeoJsonFeature() {
    return {
      "type": "Feature",
      "geometry": {
        "type": "Point",
        "coordinates": [longitude, latitude, altitude]
      },
      "properties": {
        "id": id,
        "lithology": lithology,
        "structure": structure,
        "mineralization": mineralization,
        "strike": strike,
        "dipDirection": dipDirection,
        "dip": dip,
        "timestamp": timestamp,
      }
    };
  }
}
